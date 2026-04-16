from __future__ import annotations

import asyncio
from typing import Any

from fastmcp import FastMCP

from .clickhouse import get_clickhouse_service

mcp = FastMCP(name="warehouse_clickhouse_mcp")


async def _run_sync(method_name: str, *args, **kwargs) -> Any:
    service = get_clickhouse_service()
    method = getattr(service, method_name)
    return await asyncio.to_thread(method, *args, **kwargs)


@mcp.tool(
    description="Describe the warehouse business model and the main entities used to answer inventory questions.",
)
async def get_semantic_model() -> dict[str, Any]:
    return await _run_sync("get_semantic_model")


@mcp.tool(
    description="Return the inventory overview for the latest available snapshot.",
)
async def get_inventory_overview() -> dict[str, Any]:
    return await _run_sync("get_inventory_overview")


@mcp.tool(
    description="Summarize the latest inventory snapshot by warehouse. Useful for questions like which warehouse has the highest inventory value or the most low-stock SKUs.",
)
async def get_warehouse_summary(limit: int = 5) -> list[dict[str, Any]]:
    return await _run_sync("get_warehouse_summary", limit=limit)


@mcp.tool(
    description="List SKUs below their reorder point in the latest snapshot. Useful for low stock, stockout risk, and replenishment questions.",
)
async def get_low_stock_alerts(limit: int = 10) -> list[dict[str, Any]]:
    return await _run_sync("get_low_stock_alerts", limit=limit)


@mcp.tool(
    description="List SKUs above their max-stock threshold in the latest snapshot. Useful for overstock and excess inventory questions.",
)
async def get_overstock_alerts(limit: int = 10) -> list[dict[str, Any]]:
    return await _run_sync("get_overstock_alerts", limit=limit)


@mcp.tool(
    description="Summarize inbound and outbound inventory movement over the last N days. Can be filtered by warehouse_id and sku_id.",
)
async def get_recent_movements(
    days: int = 7,
    warehouse_id: str | None = None,
    sku_id: str | None = None,
    limit: int = 20,
) -> list[dict[str, Any]]:
    return await _run_sync(
        "get_recent_movements",
        days=days,
        warehouse_id=warehouse_id,
        sku_id=sku_id,
        limit=limit,
    )


@mcp.tool(
    description="Summarize replenishment demand by SKU from open purchase orders. Useful for replenishment backlog and inbound pipeline questions.",
)
async def get_purchase_replenishment(limit: int = 10) -> list[dict[str, Any]]:
    return await _run_sync("get_purchase_replenishment", limit=limit)


@mcp.tool(
    description="List available ClickHouse databases. In this repo, databases act as schema or data layers.",
)
async def list_databases(include_system: bool = False) -> list[dict[str, Any]]:
    return await _run_sync("list_databases", include_system=include_system)


@mcp.tool(
    description="List ClickHouse tables. Use this when the agent needs to inspect schema instead of relying only on business wrapper tools.",
)
async def list_tables(
    database: str | None = None,
    include_system: bool = False,
    search: str | None = None,
    limit: int = 200,
) -> list[dict[str, Any]]:
    return await _run_sync(
        "list_tables",
        database=database,
        include_system=include_system,
        search=search,
        limit=limit,
    )


@mcp.tool(
    description="Describe a table schema in detail, including columns, data types, grain, engine, and a suggested starter query.",
)
async def describe_table(database: str, table_name: str) -> dict[str, Any]:
    return await _run_sync(
        "describe_table",
        database=database,
        table_name=table_name,
    )


@mcp.tool(
    description="Return a small read-only sample of rows from a ClickHouse table.",
)
async def sample_table_rows(
    database: str,
    table_name: str,
    limit: int = 5,
) -> dict[str, Any]:
    return await _run_sync(
        "sample_table_rows",
        database=database,
        table_name=table_name,
        limit=limit,
    )


@mcp.tool(
    description="Run a read-only SQL query on ClickHouse. Only use this after verifying the exact table names and columns with list_tables and describe_table in the current conversation. Do not guess schema objects or columns.",
)
async def query_clickhouse(sql: str) -> dict[str, Any]:
    return await _run_sync("run_readonly_sql", sql=sql)


@mcp.tool(
    description="Backward-compatible alias for running a read-only SQL query on ClickHouse.",
)
async def run_readonly_sql(sql: str) -> dict[str, Any]:
    return await _run_sync("run_readonly_sql", sql=sql)
