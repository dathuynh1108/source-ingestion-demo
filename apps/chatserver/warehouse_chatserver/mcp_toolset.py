import json
from logging import getLogger
from typing import Any, TypeVar

from fastmcp import Client
from pydantic_ai import RunContext as PydanticRunContext
from pydantic_ai.tools import ToolDefinition
from pydantic_ai.toolsets import AbstractToolset, ToolsetTool
from pydantic_core import SchemaValidator, core_schema

logger = getLogger(__name__)

TDeps = TypeVar("TDeps")


def _serialize_tool_result(result: Any) -> str:
    if hasattr(result, "content") and getattr(result, "content"):
        aggregated = []
        for content_item in result.content:
            text_part = getattr(content_item, "text", None)
            aggregated.append(text_part if text_part is not None else str(content_item))
        return "".join(aggregated)

    payload = None
    if hasattr(result, "model_dump") and callable(getattr(result, "model_dump")):
        try:
            payload = result.model_dump()
        except Exception:
            payload = None

    if payload is None:
        if isinstance(result, (dict, list, str, int, float, bool)) or result is None:
            payload = result
        else:
            payload = str(result)

    try:
        return json.dumps(payload, ensure_ascii=False)
    except Exception:
        return str(payload)


class FastMCPToolset(AbstractToolset[TDeps]):
    def __init__(
        self,
        mcp_clients: list[tuple[str, Client]],
        toolset_id: str = "fastmcp",
    ):
        self.mcp_clients = mcp_clients
        self._id = toolset_id
        self._args_validator = SchemaValidator(core_schema.any_schema())
        self._tool_bindings: dict[str, tuple[Client, str]] = {}

    @property
    def id(self) -> str | None:
        return self._id

    async def get_tools(
        self,
        ctx: PydanticRunContext[TDeps],
    ) -> dict[str, ToolsetTool[TDeps]]:
        _ = ctx
        self._tool_bindings.clear()
        definitions: dict[str, ToolsetTool[TDeps]] = {}

        for server_alias, client in self.mcp_clients:
            try:
                async with client:
                    tools = await client.list_tools()
            except Exception as exc:
                logger.error("Failed to list MCP tools from %s: %s", server_alias, exc)
                continue

            for tool in tools:
                public_name = tool.name
                if public_name in definitions:
                    logger.warning(
                        "Duplicate MCP tool name '%s' detected. Skipping server '%s'.",
                        public_name,
                        server_alias,
                    )
                    continue

                self._tool_bindings[public_name] = (client, tool.name)
                definitions[public_name] = ToolsetTool(
                    toolset=self,
                    tool_def=ToolDefinition(
                        name=public_name,
                        description=tool.description,
                        parameters_json_schema=tool.inputSchema,
                    ),
                    max_retries=1,
                    args_validator=self._args_validator,
                )

        return definitions

    async def call_tool(
        self,
        name: str,
        tool_args: dict[str, Any],
        ctx: PydanticRunContext[TDeps],
        tool: ToolsetTool[TDeps],
    ) -> Any:
        _ = (ctx, tool)
        binding = self._tool_bindings.get(name)
        if binding is None:
            raise ValueError(f"MCP tool not found: {name}")

        client, original_name = binding
        try:
            async with client:
                result = await client.call_tool(original_name, arguments=tool_args)
            return _serialize_tool_result(result)
        except Exception as exc:
            logger.error("Error calling MCP tool %s: %s", name, exc)
            return f"Error executing tool: {exc}"
