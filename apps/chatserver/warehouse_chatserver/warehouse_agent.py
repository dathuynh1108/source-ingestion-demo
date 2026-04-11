from __future__ import annotations

import asyncio
import re
import textwrap
import unicodedata
from datetime import UTC, datetime
from logging import getLogger
from typing import AsyncGenerator

from fastmcp import Client
from openai import AsyncAzureOpenAI, AsyncOpenAI
from pydantic_ai import Agent as PydanticAgent
from pydantic_ai import AgentRunResultEvent, PartDeltaEvent, PartStartEvent
from pydantic_ai.messages import (
    ModelMessage,
    ModelRequest,
    ModelResponse,
    TextPart,
    TextPartDelta,
    UserPromptPart,
)
from pydantic_ai.models.openai import OpenAIChatModel, OpenAIChatModelSettings
from pydantic_ai.providers.azure import AzureProvider
from pydantic_ai.providers.openai import OpenAIProvider

from .clickhouse import get_clickhouse_service
from .config import get_settings
from .mcp_toolset import FastMCPToolset
from .models import ChatMessage, ChatMessageChunk, Conversation, MessageLink
from .warehouse_mcp import mcp

logger = getLogger(__name__)

SKU_PATTERN = re.compile(r"\bSKU[_-]?(\d{3})\b", re.IGNORECASE)
WAREHOUSE_PATTERN = re.compile(r"\bWH(\d{2})\b", re.IGNORECASE)


def _now_iso() -> str:
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")


def _markdown_table(rows: list[dict], columns: list[tuple[str, str]]) -> str:
    if not rows:
        return "_No matching data found._"

    header = "| " + " | ".join(label for _, label in columns) + " |"
    divider = "| " + " | ".join(["---"] * len(columns)) + " |"
    body = []
    for row in rows:
        values = []
        for key, _ in columns:
            value = row.get(key, "")
            values.append(str(value) if value is not None else "")
        body.append("| " + " | ".join(values) + " |")
    return "\n".join([header, divider, *body])


def _normalize_text_for_match(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value or "")
    without_accents = "".join(
        char for char in normalized if not unicodedata.combining(char)
    )
    return without_accents.lower()


def _contains_any(text: str, tokens: list[str]) -> bool:
    return any(token in text for token in tokens)


class WarehouseAgent:
    def __init__(self, namespace: str):
        self.namespace = namespace
        self.settings = get_settings()
        self.service = get_clickhouse_service()
        self.stop_requested = False
        self.pydantic_agent: PydanticAgent[None, str] | None = None
        self._model_init_error: str | None = None

        if self.settings.llm_enabled():
            try:
                base_url = self.settings.openai_base_url.strip()
                if base_url:
                    provider = OpenAIProvider(
                        openai_client=AsyncOpenAI(
                            api_key=self.settings.openai_api_key,
                            base_url=base_url.rstrip("/"),
                            max_retries=self.settings.azure_openai_max_retries,
                            timeout=self.settings.openai_timeout_seconds,
                        )
                    )
                    model_name = self.settings.openai_model
                else:
                    provider = AzureProvider(
                        openai_client=AsyncAzureOpenAI(
                            azure_endpoint=self.settings.azure_openai_endpoint,
                            api_key=self.settings.azure_openai_api_key,
                            api_version=self.settings.azure_openai_api_version,
                            azure_deployment=self.settings.azure_openai_deployment
                            or None,
                            max_retries=self.settings.azure_openai_max_retries,
                            timeout=self.settings.openai_timeout_seconds,
                        )
                    )
                    model_name = (
                        self.settings.azure_openai_deployment
                        or self.settings.openai_model
                    )
                model = OpenAIChatModel(
                    model_name=model_name,
                    provider=provider,
                )
                mcp_toolset = FastMCPToolset(
                    mcp_clients=[("warehouse_mcp", Client(mcp, name="warehouse_mcp"))],
                    toolset_id="warehouse_clickhouse_tools",
                )
                self.pydantic_agent = PydanticAgent[None, str](
                    model=model,
                    output_type=str,
                    model_settings=OpenAIChatModelSettings(parallel_tool_calls=False),
                    toolsets=[mcp_toolset],
                )
            except Exception as exc:
                self._model_init_error = str(exc)
                logger.exception("Failed to initialize LLM agent")

    def _build_system_prompt(self) -> str:
        return textwrap.dedent(
            f"""
            You are the warehouse operations assistant for this inventory demo.

            Working rules:
            - Focus on warehouses, SKUs, stock levels, replenishment, inventory movement, inventory value, and stock-count discrepancies.
            - Stay out of sales-support, prospecting, and customer-use-case answers unless the user explicitly asks for them.
            - Business tools such as `get_inventory_overview` and `get_low_stock_alerts` are shortcuts, not your limit.
            - When the wrapper tools are not enough, inspect schema in this order: `list_databases` -> `list_tables` -> `describe_table` -> `sample_table_rows`, then use `query_clickhouse` or `run_readonly_sql`.
            - In this repo, ClickHouse databases act as schema or data layers. Prioritize `inventory_raw`, `inventory_stg`, and `inventory_mart`.
            - When answering inventory questions, always mention the latest snapshot_date you used.
            - Keep answers concise, explicit, and action-oriented.
            - Respond in English, even if the user writes in another language.
            - Use Markdown tables for rankings or row-based outputs.
            - Do not invent data, SQL results, or schema details you have not verified.

            Current UTC time: {_now_iso()}
            Active namespace: {self.namespace}
            """
        ).strip()

    def _build_message_history(self, history: list[ChatMessage]) -> list[ModelMessage]:
        messages: list[ModelMessage] = []
        for item in history[-12:]:
            content = (item.message or "").strip()
            if not content:
                continue
            sender = item.sender.lower()
            if sender == "user":
                messages.append(ModelRequest(parts=[UserPromptPart(content=content)]))
            elif sender in {"assistant", "bot"}:
                messages.append(ModelResponse(parts=[TextPart(content=content)]))
        return messages

    def _extract_ids(self, message: str) -> tuple[str | None, str | None]:
        sku_match = SKU_PATTERN.search(message or "")
        warehouse_match = WAREHOUSE_PATTERN.search(message or "")
        sku_id = f"SKU_{sku_match.group(1)}" if sku_match else None
        warehouse_id = f"WH{warehouse_match.group(1)}" if warehouse_match else None
        return sku_id, warehouse_id

    def _fallback_response(self, message: str) -> str:
        lowered = _normalize_text_for_match(message or "")
        sku_id, warehouse_id = self._extract_ids(message)

        if _contains_any(
            lowered,
            [
                "tong quan",
                "overview",
                "hien tai",
                "current inventory",
                "gia tri ton kho",
            ],
        ):
            overview = self.service.get_inventory_overview()
            return textwrap.dedent(
                f"""
                ## Inventory overview

                - Latest snapshot date: `{overview.get("snapshot_date", "N/A")}`
                - Total on-hand quantity: `{overview.get("total_on_hand_qty", 0)}`
                - Total available quantity: `{overview.get("total_available_qty", 0)}`
                - Inventory value: `{overview.get("total_inventory_value", 0)}`
                - SKUs below reorder point: `{overview.get("low_stock_sku_count", 0)}`
                - SKUs above max stock: `{overview.get("overstock_sku_count", 0)}`
                """
            ).strip()

        if _contains_any(
            lowered,
            ["sap het", "thieu hang", "low stock", "stockout", "reorder"],
        ):
            rows = self.service.get_low_stock_alerts(limit=8)
            return "## SKUs at risk of stockout\n\n" + _markdown_table(
                rows,
                [
                    ("warehouse_name", "Warehouse"),
                    ("sku_id", "SKU"),
                    ("sku_name", "SKU name"),
                    ("available_qty", "Available"),
                    ("reorder_point", "Reorder point"),
                    ("coverage_ratio", "Coverage ratio"),
                ],
            )

        if _contains_any(
            lowered,
            ["overstock", "vuot max", "ton qua muc", "du hang"],
        ):
            rows = self.service.get_overstock_alerts(limit=8)
            return "## SKUs above max stock\n\n" + _markdown_table(
                rows,
                [
                    ("warehouse_name", "Warehouse"),
                    ("sku_id", "SKU"),
                    ("sku_name", "SKU name"),
                    ("available_qty", "Available"),
                    ("max_stock", "Max stock"),
                    ("stock_ratio", "Stock ratio"),
                ],
            )

        if _contains_any(
            lowered,
            ["warehouse", "kho nao", "theo kho", "tung kho"],
        ):
            rows = self.service.get_warehouse_summary(limit=6)
            return "## Warehouse summary\n\n" + _markdown_table(
                rows,
                [
                    ("warehouse_name", "Warehouse"),
                    ("city", "City"),
                    ("available_qty", "Available"),
                    ("inventory_value", "Inventory value"),
                    ("low_stock_sku_count", "Low-stock SKUs"),
                ],
            )

        if _contains_any(
            lowered,
            ["movement", "nhap xuat", "bien dong", "xuat nhap", "giao dich kho"],
        ):
            rows = self.service.get_recent_movements(
                days=7,
                warehouse_id=warehouse_id,
                sku_id=sku_id,
                limit=12,
            )
            title = "## Inventory movement in the last 7 days"
            if warehouse_id or sku_id:
                filters = ", ".join(value for value in [warehouse_id, sku_id] if value)
                title += f" ({filters})"
            return title + "\n\n" + _markdown_table(
                rows,
                [
                    ("event_date", "Date"),
                    ("warehouse_id", "Warehouse"),
                    ("sku_id", "SKU"),
                    ("qty_in", "Inbound"),
                    ("qty_out", "Outbound"),
                    ("net_qty_change", "Net"),
                ],
            )

        if _contains_any(
            lowered,
            ["po", "mua hang", "replenishment", "inbound", "don mua"],
        ):
            rows = self.service.get_purchase_replenishment(limit=8)
            return "## Open replenishment demand\n\n" + _markdown_table(
                rows,
                [
                    ("sku_id", "SKU"),
                    ("sku_name", "SKU name"),
                    ("qty_open", "Open qty"),
                    ("open_value", "Open value"),
                    ("open_po_count", "Open PO count"),
                ],
            )

        overview = self.service.get_inventory_overview()
        return textwrap.dedent(
            f"""
            No LLM is configured, so the agent is running in fallback mode.

            The latest available snapshot is `{overview.get("snapshot_date", "N/A")}`.

            Try prompts like:
            - Which warehouse is most at risk of stockout today?
            - What is the current inventory value by warehouse?
            - What happened in WH01 over the last 7 days of inventory movement?
            - Which SKUs are furthest above max stock?
            - Which open purchase orders still drive replenishment demand?
            """
        ).strip()

    async def process_message(
        self,
        user_message: ChatMessage,
        conversation: Conversation,
        history: list[ChatMessage],
    ) -> AsyncGenerator[ChatMessageChunk | ChatMessage, None]:
        self.stop_requested = False

        if self.pydantic_agent is None:
            response_text = await asyncio.to_thread(
                self._fallback_response,
                user_message.message,
            )
            if self.stop_requested:
                return
            yield ChatMessage(
                sender="assistant",
                message=response_text,
                links=[
                        MessageLink(
                            title="Warehouse MCP",
                            link="/clickhouse/mcp",
                            format="mcp",
                        )
                ],
            )
            return

        final_chunks: list[str] = []
        final_text = ""
        try:
            async for event in self.pydantic_agent.run_stream_events(
                user_prompt=user_message.message,
                message_history=self._build_message_history(history),
                instructions=self._build_system_prompt(),
            ):
                if self.stop_requested:
                    return

                if isinstance(event, PartStartEvent) and isinstance(event.part, TextPart):
                    if event.part.content:
                        final_chunks.append(event.part.content)
                        yield ChatMessageChunk(text=event.part.content)
                    continue

                if isinstance(event, PartDeltaEvent) and isinstance(
                    event.delta, TextPartDelta
                ):
                    if event.delta.content_delta:
                        final_chunks.append(event.delta.content_delta)
                        yield ChatMessageChunk(text=event.delta.content_delta)
                    continue

                if isinstance(event, AgentRunResultEvent):
                    output = getattr(event.result, "output", "")
                    final_text = str(output).strip() if output is not None else ""

            if not final_text:
                final_text = "".join(final_chunks).strip()

            if not final_text:
                final_text = "No response content."

            yield ChatMessage(
                sender="assistant",
                message=final_text,
                links=[
                    MessageLink(
                        title="Warehouse MCP",
                        link="/clickhouse/mcp",
                        format="mcp",
                    )
                ],
            )
        except Exception as exc:
            logger.exception("Warehouse agent failed")
            fallback_prefix = (
                f"The LLM agent failed: {exc}. Returning fallback output.\n\n"
                if self._model_init_error is None
                else ""
            )
            yield ChatMessage(
                sender="assistant",
                message=fallback_prefix + self._fallback_response(user_message.message),
            )

    def stop_processing(self) -> None:
        self.stop_requested = True
