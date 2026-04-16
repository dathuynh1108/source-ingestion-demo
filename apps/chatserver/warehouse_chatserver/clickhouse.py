from __future__ import annotations

import re
import unicodedata
from datetime import date, datetime
from decimal import Decimal
from functools import lru_cache
from typing import Any

import clickhouse_connect

from .config import Settings, get_settings

PRODUCT_DIM_CTE = """
product_dim AS (
    SELECT
        sku_id,
        argMax(sku_name, parseDateTimeBestEffortOrZero(created_at)) AS sku_name,
        argMax(category, parseDateTimeBestEffortOrZero(created_at)) AS category,
        argMax(subcategory, parseDateTimeBestEffortOrZero(created_at)) AS subcategory,
        argMax(brand, parseDateTimeBestEffortOrZero(created_at)) AS brand,
        argMax(reorder_point, parseDateTimeBestEffortOrZero(created_at)) AS reorder_point,
        argMax(safety_stock, parseDateTimeBestEffortOrZero(created_at)) AS safety_stock,
        argMax(max_stock, parseDateTimeBestEffortOrZero(created_at)) AS max_stock,
        argMax(unit_cost, parseDateTimeBestEffortOrZero(created_at)) AS unit_cost,
        argMax(selling_price, parseDateTimeBestEffortOrZero(created_at)) AS selling_price,
        argMax(status, parseDateTimeBestEffortOrZero(created_at)) AS status,
        argMax(abc_class, parseDateTimeBestEffortOrZero(created_at)) AS abc_class
    FROM inventory_raw.raw_dim_skus
    GROUP BY sku_id
)
"""

WAREHOUSE_DIM_CTE = """
warehouse_dim AS (
    SELECT
        warehouse_id,
        argMax(warehouse_name, parseDateTimeBestEffortOrZero(created_at)) AS warehouse_name,
        argMax(city, parseDateTimeBestEffortOrZero(created_at)) AS city,
        argMax(region, parseDateTimeBestEffortOrZero(created_at)) AS region
    FROM inventory_raw.raw_dim_warehouses
    GROUP BY warehouse_id
)
"""

LATEST_SNAPSHOT_CTE = """
latest_snapshot AS (
    SELECT max(snapshot_date) AS snapshot_date
    FROM inventory_raw.raw_inventory_snapshot_daily
)
"""

INVENTORY_DATABASE_DESCRIPTIONS = {
    "inventory_raw": "Raw layer with data ingested directly from source systems and Kafka.",
    "inventory_stg": "Staging layer for cleanup and intermediate standardization.",
    "inventory_mart": "Mart layer for analytics, BI, and business-level summaries.",
}

INVENTORY_TABLE_CATALOG = {
    "inventory_raw.raw_inventory_snapshot_daily": {
        "purpose": "Daily inventory snapshot by date, warehouse, and SKU.",
        "grain": "snapshot_date + warehouse_id + sku_id",
    },
    "inventory_raw.raw_inventory_transactions": {
        "purpose": "Inventory movement events over time.",
        "grain": "event_time + warehouse_id + sku_id",
    },
    "inventory_raw.raw_purchase_order_lines": {
        "purpose": "Purchase order lines for replenishment and inbound pipeline tracking.",
        "grain": "purchase order line",
    },
    "inventory_raw.raw_stock_counts": {
        "purpose": "Stock count results and inventory discrepancies.",
        "grain": "count_date + warehouse_id + sku_id",
    },
    "inventory_raw.raw_dim_skus": {
        "purpose": "SKU master data with category, brand, and reorder policy.",
        "grain": "sku_id",
    },
    "inventory_raw.raw_dim_warehouses": {
        "purpose": "Warehouse master data with warehouse name, city, and region.",
        "grain": "warehouse_id",
    },
    "inventory_mart.fact_inventory_snapshot_daily": {
        "purpose": "Daily inventory snapshot fact table in the mart layer.",
        "grain": "snapshot_date + warehouse_id + sku_id",
    },
    "inventory_mart.fact_inventory_movement": {
        "purpose": "Inventory movement fact table in the mart layer.",
        "grain": "movement_date + warehouse_id + sku_id",
    },
    "inventory_mart.fact_purchase_order_lines": {
        "purpose": "Purchase order fact table in the mart layer.",
        "grain": "purchase order line",
    },
    "inventory_mart.fact_sales_order_lines": {
        "purpose": "Sales order fact table in the mart layer.",
        "grain": "sales order line",
    },
    "inventory_mart.fact_stock_counts": {
        "purpose": "Stock count fact table in the mart layer.",
        "grain": "count_date + warehouse_id + sku_id",
    },
    "inventory_mart.dim_product": {
        "purpose": "Product dimension in the mart layer.",
        "grain": "sku_id",
    },
    "inventory_mart.dim_warehouse": {
        "purpose": "Warehouse dimension in the mart layer.",
        "grain": "warehouse_id",
    },
    "inventory_mart.dim_supplier": {
        "purpose": "Supplier dimension.",
        "grain": "supplier_id",
    },
    "inventory_mart.dim_customer": {
        "purpose": "Customer dimension.",
        "grain": "customer_id",
    },
    "inventory_mart.dim_date": {
        "purpose": "Date dimension for BI use cases.",
        "grain": "date_key",
    },
}

FORBIDDEN_SQL_PATTERN = re.compile(
    r"\b(insert|update|delete|drop|alter|create|truncate|optimize|grant|revoke|system|kill|attach|detach|rename)\b",
    re.IGNORECASE,
)
IDENTIFIER_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def _fold_text(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    return "".join(ch for ch in normalized if not unicodedata.combining(ch)).lower()


def _normalize_value(value: Any) -> Any:
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, list):
        return [_normalize_value(item) for item in value]
    if isinstance(value, tuple):
        return [_normalize_value(item) for item in value]
    if isinstance(value, dict):
        return {key: _normalize_value(item) for key, item in value.items()}
    return value


class ClickHouseService:
    def __init__(self, settings: Settings):
        self.settings = settings
        self._client = None

    @property
    def client(self):
        if self._client is None:
            self._client = clickhouse_connect.get_client(
                host=self.settings.clickhouse_host,
                port=self.settings.clickhouse_port,
                username=self.settings.clickhouse_username,
                password=self.settings.clickhouse_password,
                database=self.settings.clickhouse_database,
                secure=self.settings.clickhouse_secure,
                connect_timeout=self.settings.clickhouse_connect_timeout,
                send_receive_timeout=self.settings.clickhouse_send_receive_timeout,
                # The service reuses one HTTP client across FastAPI requests, so
                # per-client ClickHouse sessions cause false concurrent-query
                # failures when health checks overlap with user traffic.
                autogenerate_session_id=False,
            )
        return self._client

    def _query_rows(
        self,
        sql: str,
        parameters: dict[str, Any] | None = None,
        settings: dict[str, Any] | None = None,
    ) -> list[dict[str, Any]]:
        query_result = self.client.query(
            sql,
            parameters=parameters or {},
            settings=settings or {},
        )
        columns = query_result.column_names
        return [
            {column: _normalize_value(value) for column, value in zip(columns, row)}
            for row in query_result.result_rows
        ]

    def _run_query(
        self,
        sql: str,
        parameters: dict[str, Any] | None = None,
        settings: dict[str, Any] | None = None,
    ):
        return self.client.query(
            sql,
            parameters=parameters or {},
            settings=settings or {},
        )

    def _query_one(
        self,
        sql: str,
        parameters: dict[str, Any] | None = None,
        settings: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        rows = self._query_rows(sql, parameters=parameters, settings=settings)
        return rows[0] if rows else {}

    def health(self) -> dict[str, Any]:
        return self._query_one(
            f"""
            SELECT
                1 AS ok,
                (SELECT max(snapshot_date) FROM {self.settings.clickhouse_raw_database}.raw_inventory_snapshot_daily) AS latest_snapshot_date,
                (SELECT count() FROM {self.settings.clickhouse_raw_database}.raw_inventory_snapshot_daily) AS snapshot_rows,
                (SELECT count() FROM {self.settings.clickhouse_raw_database}.raw_inventory_transactions) AS movement_rows
            """
        )

    def _validate_identifier(self, value: str, label: str) -> str:
        normalized = (value or "").strip()
        if not normalized:
            raise ValueError(f"Missing {label}.")
        if not IDENTIFIER_PATTERN.fullmatch(normalized):
            raise ValueError(f"Invalid {label}: `{value}`.")
        return normalized

    def _table_catalog_entry(self, database: str, table_name: str) -> dict[str, Any]:
        return INVENTORY_TABLE_CATALOG.get(f"{database}.{table_name}", {})

    def list_databases(self, include_system: bool = False) -> list[dict[str, Any]]:
        conditions = []
        if not include_system:
            conditions.append(
                "name NOT IN ('system', 'INFORMATION_SCHEMA', 'information_schema', 'default')"
            )

        sql = """
            SELECT
                name AS database,
                engine
            FROM system.databases
        """
        if conditions:
            sql += f"\nWHERE {' AND '.join(conditions)}"
        sql += """
            ORDER BY
                multiIf(
                    name = 'inventory_raw', 0,
                    name = 'inventory_stg', 1,
                    name = 'inventory_mart', 2,
                    10
                ),
                name
        """

        rows = self._query_rows(sql)
        for row in rows:
            row["description"] = INVENTORY_DATABASE_DESCRIPTIONS.get(row["database"])
        return rows

    def list_tables(
        self,
        database: str | None = None,
        include_system: bool = False,
        search: str | None = None,
        limit: int = 200,
    ) -> list[dict[str, Any]]:
        conditions = []
        parameters: dict[str, Any] = {"limit": max(1, min(limit, 500))}

        if database:
            parameters["database"] = self._validate_identifier(database, "database")
            conditions.append("database = {database:String}")
        elif not include_system:
            conditions.append(
                "database IN ('inventory_raw', 'inventory_stg', 'inventory_mart')"
            )

        if search:
            parameters["search"] = _fold_text(search.strip())
            conditions.append(
                "positionCaseInsensitiveUTF8(lower(concat(database, '.', name)), {search:String}) > 0"
            )

        sql = """
            SELECT
                database,
                name AS table,
                engine,
                total_rows,
                total_bytes,
                metadata_modification_time
            FROM system.tables
        """
        if conditions:
            sql += f"\nWHERE {' AND '.join(conditions)}"
        sql += """
            ORDER BY
                multiIf(
                    database = 'inventory_raw', 0,
                    database = 'inventory_stg', 1,
                    database = 'inventory_mart', 2,
                    10
                ),
                database,
                table
            LIMIT {limit:UInt32}
        """

        rows = self._query_rows(sql, parameters=parameters)
        for row in rows:
            row.update(self._table_catalog_entry(row["database"], row["table"]))
        return rows

    def describe_table(self, database: str, table_name: str) -> dict[str, Any]:
        normalized_database = self._validate_identifier(database, "database")
        normalized_table = self._validate_identifier(table_name, "table name")

        table_info = self._query_one(
            """
            SELECT
                database,
                name AS table,
                engine,
                total_rows,
                total_bytes,
                metadata_modification_time,
                create_table_query
            FROM system.tables
            WHERE database = {database:String}
              AND name = {table:String}
            LIMIT 1
            """,
            parameters={
                "database": normalized_database,
                "table": normalized_table,
            },
        )
        if not table_info:
            raise ValueError(
                f"Table `{normalized_database}.{normalized_table}` was not found."
            )

        columns = self._query_rows(
            """
            SELECT
                position,
                name,
                type,
                default_kind,
                default_expression,
                is_in_primary_key,
                is_in_sorting_key,
                is_in_partition_key
            FROM system.columns
            WHERE database = {database:String}
              AND table = {table:String}
            ORDER BY position
            """,
            parameters={
                "database": normalized_database,
                "table": normalized_table,
            },
        )

        catalog_entry = self._table_catalog_entry(normalized_database, normalized_table)
        return {
            **table_info,
            **catalog_entry,
            "database_description": INVENTORY_DATABASE_DESCRIPTIONS.get(
                normalized_database
            ),
            "column_count": len(columns),
            "columns": columns,
            "suggested_query": (
                f"SELECT * FROM {normalized_database}.{normalized_table} LIMIT 20"
            ),
        }

    def sample_table_rows(
        self,
        database: str,
        table_name: str,
        limit: int = 5,
    ) -> dict[str, Any]:
        normalized_database = self._validate_identifier(database, "database")
        normalized_table = self._validate_identifier(table_name, "table name")
        safe_limit = max(1, min(limit, 20))
        sql = (
            f"SELECT * FROM {normalized_database}.{normalized_table} "
            f"LIMIT {{limit:UInt32}}"
        )
        query_result = self._run_query(
            sql,
            parameters={"limit": safe_limit},
            settings={
                "readonly": 1,
                "max_result_rows": 20,
                "result_overflow_mode": "break",
            },
        )
        rows = [
            {
                column: _normalize_value(value)
                for column, value in zip(query_result.column_names, row)
            }
            for row in query_result.result_rows
        ]
        return {
            "database": normalized_database,
            "table": normalized_table,
            "columns": list(query_result.column_names),
            "row_count": len(rows),
            "rows": rows,
        }

    def get_semantic_model(self) -> dict[str, Any]:
        return {
            "assistant_scope": "warehouse-operations",
            "default_language": "en",
            "layer_note": "In this ClickHouse setup, databases act as schema or data layers.",
            "priority_entities": [
                "warehouse",
                "sku",
                "inventory snapshot",
                "inventory movement",
                "purchase order lines",
                "stock count discrepancy",
            ],
            "tables": [
                {
                    "name": "inventory_raw.raw_inventory_snapshot_daily",
                    "purpose": "latest inventory snapshot by date, warehouse, and sku, including on-hand, available, damaged, and in-transit quantities",
                    "grain": "snapshot_date + warehouse_id + sku_id",
                },
                {
                    "name": "inventory_raw.raw_inventory_transactions",
                    "purpose": "inventory movement event stream",
                    "grain": "event_time + warehouse_id + sku_id",
                },
                {
                    "name": "inventory_raw.raw_purchase_order_lines",
                    "purpose": "replenishment status and open purchase order quantities",
                    "grain": "purchase order line",
                },
                {
                    "name": "inventory_raw.raw_stock_counts",
                    "purpose": "stock count results and inventory discrepancies",
                    "grain": "count_date + warehouse_id + sku_id",
                },
                {
                    "name": "inventory_raw.raw_dim_skus",
                    "purpose": "product master data with category, brand, and reorder policy",
                    "grain": "sku_id",
                },
                {
                    "name": "inventory_raw.raw_dim_warehouses",
                    "purpose": "warehouse master data with city and region",
                    "grain": "warehouse_id",
                },
            ],
            "starter_questions": [
                "Which warehouse is most at risk of stockout today?",
                "Which SKUs are furthest above max stock?",
                "What is the current inventory value by warehouse?",
                "What looks unusual in the last 7 days of movement for WH01?",
            ],
            "notes": [
                "Prioritize warehouse, SKU, replenishment, and movement insights.",
                "Stay within the warehouse-operations use case unless the user explicitly asks for something else.",
                "When wrapper business tools are not enough, inspect schema with list_databases, list_tables, and describe_table before writing SQL.",
                "Always mention the latest snapshot_date when answering inventory questions.",
            ],
        }

    def get_inventory_overview(self) -> dict[str, Any]:
        return self._query_one(
            f"""
            WITH
                {LATEST_SNAPSHOT_CTE},
                {PRODUCT_DIM_CTE}
            SELECT
                latest_snapshot.snapshot_date AS snapshot_date,
                sum(s.on_hand_qty) AS total_on_hand_qty,
                sum(s.available_qty) AS total_available_qty,
                sum(s.damaged_qty) AS total_damaged_qty,
                sum(s.in_transit_qty) AS total_in_transit_qty,
                round(sum(s.inventory_value), 2) AS total_inventory_value,
                uniqExact(s.warehouse_id) AS warehouse_count,
                uniqExact(s.sku_id) AS sku_count,
                countIf(coalesce(p.reorder_point, 0) > 0 AND s.available_qty < p.reorder_point) AS low_stock_sku_count,
                countIf(coalesce(p.max_stock, 0) > 0 AND s.available_qty > p.max_stock) AS overstock_sku_count
            FROM {self.settings.clickhouse_raw_database}.raw_inventory_snapshot_daily s
            CROSS JOIN latest_snapshot
            LEFT JOIN product_dim p ON p.sku_id = s.sku_id
            WHERE s.snapshot_date = latest_snapshot.snapshot_date
            GROUP BY latest_snapshot.snapshot_date
            """
        )

    def get_warehouse_summary(self, limit: int = 5) -> list[dict[str, Any]]:
        return self._query_rows(
            f"""
            WITH
                {LATEST_SNAPSHOT_CTE},
                {PRODUCT_DIM_CTE},
                {WAREHOUSE_DIM_CTE}
            SELECT
                s.warehouse_id,
                coalesce(w.warehouse_name, s.warehouse_id) AS warehouse_name,
                w.city,
                w.region,
                sum(s.on_hand_qty) AS on_hand_qty,
                sum(s.available_qty) AS available_qty,
                round(sum(s.inventory_value), 2) AS inventory_value,
                sum(s.damaged_qty) AS damaged_qty,
                sum(s.in_transit_qty) AS in_transit_qty,
                countIf(coalesce(p.reorder_point, 0) > 0 AND s.available_qty < p.reorder_point) AS low_stock_sku_count
            FROM {self.settings.clickhouse_raw_database}.raw_inventory_snapshot_daily s
            CROSS JOIN latest_snapshot
            LEFT JOIN warehouse_dim w ON w.warehouse_id = s.warehouse_id
            LEFT JOIN product_dim p ON p.sku_id = s.sku_id
            WHERE s.snapshot_date = latest_snapshot.snapshot_date
            GROUP BY s.warehouse_id, warehouse_name, w.city, w.region
            ORDER BY inventory_value DESC, available_qty DESC
            LIMIT {{limit:UInt32}}
            """,
            parameters={"limit": max(1, min(limit, 20))},
        )

    def get_low_stock_alerts(self, limit: int = 10) -> list[dict[str, Any]]:
        return self._query_rows(
            f"""
            WITH
                {LATEST_SNAPSHOT_CTE},
                {PRODUCT_DIM_CTE},
                {WAREHOUSE_DIM_CTE}
            SELECT
                s.warehouse_id,
                coalesce(w.warehouse_name, s.warehouse_id) AS warehouse_name,
                s.sku_id,
                coalesce(p.sku_name, s.sku_id) AS sku_name,
                p.category,
                p.brand,
                s.available_qty,
                coalesce(p.reorder_point, 0) AS reorder_point,
                coalesce(p.safety_stock, 0) AS safety_stock,
                round(if(coalesce(p.reorder_point, 0) > 0, s.available_qty / p.reorder_point, 0), 2) AS coverage_ratio,
                round(s.inventory_value, 2) AS inventory_value
            FROM {self.settings.clickhouse_raw_database}.raw_inventory_snapshot_daily s
            CROSS JOIN latest_snapshot
            LEFT JOIN product_dim p ON p.sku_id = s.sku_id
            LEFT JOIN warehouse_dim w ON w.warehouse_id = s.warehouse_id
            WHERE
                s.snapshot_date = latest_snapshot.snapshot_date
                AND coalesce(p.reorder_point, 0) > 0
                AND s.available_qty < p.reorder_point
            ORDER BY (p.reorder_point - s.available_qty) DESC, inventory_value DESC
            LIMIT {{limit:UInt32}}
            """,
            parameters={"limit": max(1, min(limit, 30))},
        )

    def get_overstock_alerts(self, limit: int = 10) -> list[dict[str, Any]]:
        return self._query_rows(
            f"""
            WITH
                {LATEST_SNAPSHOT_CTE},
                {PRODUCT_DIM_CTE},
                {WAREHOUSE_DIM_CTE}
            SELECT
                s.warehouse_id,
                coalesce(w.warehouse_name, s.warehouse_id) AS warehouse_name,
                s.sku_id,
                coalesce(p.sku_name, s.sku_id) AS sku_name,
                p.category,
                p.brand,
                s.available_qty,
                coalesce(p.max_stock, 0) AS max_stock,
                round(if(coalesce(p.max_stock, 0) > 0, s.available_qty / p.max_stock, 0), 2) AS stock_ratio,
                round(s.inventory_value, 2) AS inventory_value
            FROM {self.settings.clickhouse_raw_database}.raw_inventory_snapshot_daily s
            CROSS JOIN latest_snapshot
            LEFT JOIN product_dim p ON p.sku_id = s.sku_id
            LEFT JOIN warehouse_dim w ON w.warehouse_id = s.warehouse_id
            WHERE
                s.snapshot_date = latest_snapshot.snapshot_date
                AND coalesce(p.max_stock, 0) > 0
                AND s.available_qty > p.max_stock
            ORDER BY (s.available_qty - p.max_stock) DESC, inventory_value DESC
            LIMIT {{limit:UInt32}}
            """,
            parameters={"limit": max(1, min(limit, 30))},
        )

    def get_recent_movements(
        self,
        days: int = 7,
        warehouse_id: str | None = None,
        sku_id: str | None = None,
        limit: int = 20,
    ) -> list[dict[str, Any]]:
        filters = [
            "event_time >= now() - INTERVAL {days:UInt32} DAY",
        ]
        parameters: dict[str, Any] = {
            "days": max(1, min(days, 90)),
            "limit": max(1, min(limit, 50)),
        }
        if warehouse_id:
            filters.append("warehouse_id = {warehouse_id:String}")
            parameters["warehouse_id"] = warehouse_id.upper()
        if sku_id:
            filters.append("sku_id = {sku_id:String}")
            parameters["sku_id"] = sku_id.upper()

        return self._query_rows(
            f"""
            SELECT
                toDate(event_time) AS event_date,
                warehouse_id,
                sku_id,
                count() AS movement_count,
                sum(if(qty_change > 0, qty_change, 0)) AS qty_in,
                sum(abs(if(qty_change < 0, qty_change, 0))) AS qty_out,
                sum(qty_change) AS net_qty_change,
                min(event_time) AS first_event_time,
                max(event_time) AS last_event_time
            FROM {self.settings.clickhouse_raw_database}.raw_inventory_transactions
            WHERE {" AND ".join(filters)}
            GROUP BY event_date, warehouse_id, sku_id
            ORDER BY event_date DESC, abs(net_qty_change) DESC, movement_count DESC
            LIMIT {{limit:UInt32}}
            """,
            parameters=parameters,
        )

    def get_purchase_replenishment(self, limit: int = 10) -> list[dict[str, Any]]:
        return self._query_rows(
            f"""
            WITH {PRODUCT_DIM_CTE}
            SELECT
                p.sku_id,
                coalesce(d.sku_name, p.sku_id) AS sku_name,
                d.category,
                d.brand,
                sum(p.qty_ordered) AS qty_ordered,
                sum(p.qty_received) AS qty_received,
                sum(greatest(p.qty_ordered - p.qty_received, 0)) AS qty_open,
                round(sum(greatest(p.qty_ordered - p.qty_received, 0) * toFloat64(p.unit_cost)), 2) AS open_value,
                countDistinct(p.po_id) AS open_po_count,
                min(p.created_at) AS oldest_open_created_at
            FROM {self.settings.clickhouse_raw_database}.raw_purchase_order_lines p
            LEFT JOIN product_dim d ON d.sku_id = p.sku_id
            WHERE greatest(p.qty_ordered - p.qty_received, 0) > 0
            GROUP BY p.sku_id, sku_name, d.category, d.brand
            ORDER BY qty_open DESC, open_value DESC
            LIMIT {{limit:UInt32}}
            """,
            parameters={"limit": max(1, min(limit, 30))},
        )

    def get_dashboard_summary(self) -> dict[str, Any]:
        return {
            "agent_mode": "llm" if self.settings.llm_enabled() else "fallback",
            "summary": self.get_inventory_overview(),
            "warehouse_summary": self.get_warehouse_summary(limit=5),
            "low_stock_alerts": self.get_low_stock_alerts(limit=5),
            "overstock_alerts": self.get_overstock_alerts(limit=5),
            "replenishment": self.get_purchase_replenishment(limit=5),
        }

    def run_readonly_sql(self, sql: str) -> dict[str, Any]:
        sql_text = (sql or "").strip()
        sql_to_run = sql_text.rstrip(";").strip()
        lowered = sql_to_run.lower()

        if not sql_text:
            raise ValueError("SQL input is required.")
        if ";" in sql_text.rstrip(";"):
            raise ValueError("Only one SQL statement is allowed per call.")
        if FORBIDDEN_SQL_PATTERN.search(sql_text):
            raise ValueError("Only read-only SQL is allowed.")
        if not (
            lowered.startswith("select")
            or lowered.startswith("with")
            or lowered.startswith("show")
            or lowered.startswith("describe")
            or lowered.startswith("explain")
        ):
            raise ValueError(
                "Only SELECT, WITH, SHOW, DESCRIBE, or EXPLAIN statements are allowed."
            )

        query_result = self._run_query(
            sql_to_run,
            settings={
                "readonly": 1,
                "max_result_rows": 200,
                "result_overflow_mode": "break",
            },
        )
        rows = [
            {
                column: _normalize_value(value)
                for column, value in zip(query_result.column_names, row)
            }
            for row in query_result.result_rows
        ]
        return {
            "sql": sql_to_run,
            "columns": list(query_result.column_names),
            "row_count": len(rows),
            "rows": rows,
        }


@lru_cache(maxsize=1)
def get_clickhouse_service() -> ClickHouseService:
    return ClickHouseService(get_settings())
