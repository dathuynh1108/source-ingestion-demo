#!/usr/bin/env python3
from __future__ import annotations

import json
from copy import deepcopy
from pathlib import Path
from textwrap import dedent


ROOT = Path(__file__).resolve().parent.parent
DASHBOARD_DIR = ROOT / "grafana" / "dashboards" / "inventory"
DATASOURCE = {"type": "grafana-clickhouse-datasource", "uid": "clickhouse-inventory"}
SCHEMA_VERSION = 39


def target(sql: str, ref_id: str = "A") -> dict:
    return {
        "datasource": DATASOURCE,
        "editorType": "sql",
        "format": 1,
        "queryType": "table",
        "rawSql": dedent(sql).strip(),
        "refId": ref_id,
    }


def base_dashboard(uid: str, title: str, tags: list[str]) -> dict:
    return {
        "annotations": {"list": []},
        "editable": True,
        "fiscalYearStartMonth": 0,
        "graphTooltip": 0,
        "id": None,
        "links": [],
        "panels": [],
        "refresh": "10m",
        "schemaVersion": SCHEMA_VERSION,
        "style": "dark",
        "tags": tags,
        "templating": {"list": []},
        "time": {"from": "now-45d", "to": "now"},
        "timepicker": {},
        "timezone": "browser",
        "title": title,
        "uid": uid,
        "version": 1,
        "weekStart": "",
    }


def panel_common(panel_id: int, title: str, panel_type: str, x: int, y: int, w: int, h: int) -> dict:
    return {
        "id": panel_id,
        "title": title,
        "type": panel_type,
        "datasource": DATASOURCE,
        "gridPos": {"h": h, "w": w, "x": x, "y": y},
        "fieldConfig": {"defaults": {}, "overrides": []},
        "targets": [],
        "transparent": False,
    }


def stat_panel(
    panel_id: int,
    title: str,
    sql: str,
    x: int,
    y: int,
    w: int = 4,
    h: int = 4,
    unit: str | None = None,
) -> dict:
    panel = panel_common(panel_id, title, "stat", x, y, w, h)
    panel["options"] = {
        "colorMode": "value",
        "graphMode": "none",
        "justifyMode": "auto",
        "orientation": "auto",
        "percentChangeColorMode": "standard",
        "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
        "showPercentChange": False,
        "textMode": "auto",
        "wideLayout": True,
    }
    if unit:
        panel["fieldConfig"]["defaults"]["unit"] = unit
    panel["targets"] = [target(sql)]
    return panel


def timeseries_panel(panel_id: int, title: str, sql: str, x: int, y: int, w: int = 12, h: int = 8) -> dict:
    panel = panel_common(panel_id, title, "timeseries", x, y, w, h)
    panel["options"] = {
        "legend": {"calcs": [], "displayMode": "table", "placement": "bottom", "showLegend": True},
        "tooltip": {"mode": "multi", "sort": "desc"},
    }
    panel["targets"] = [target(sql)]
    return panel


def bar_panel(panel_id: int, title: str, sql: str, x: int, y: int, w: int = 12, h: int = 8) -> dict:
    panel = panel_common(panel_id, title, "barchart", x, y, w, h)
    panel["options"] = {
        "legend": {"displayMode": "list", "placement": "bottom", "showLegend": False},
        "orientation": "auto",
        "showValue": "auto",
        "tooltip": {"mode": "single", "sort": "none"},
        "xTickLabelRotation": 0,
        "xTickLabelSpacing": 0,
    }
    panel["targets"] = [target(sql)]
    return panel


def table_panel(panel_id: int, title: str, sql: str, x: int, y: int, w: int = 12, h: int = 9) -> dict:
    panel = panel_common(panel_id, title, "table", x, y, w, h)
    panel["options"] = {"cellHeight": "sm", "footer": {"show": False}, "showHeader": True}
    panel["targets"] = [target(sql)]
    return panel


LATEST_SNAPSHOT = """
WITH latest_snapshot AS (
  SELECT max(snapshot_date) AS snapshot_date
  FROM inventory_mart.fact_inventory_snapshot_daily
)
"""


def executive_summary_dashboard() -> dict:
    dashboard = base_dashboard(
        uid="inventory-executive-summary",
        title="Inventory Executive Summary",
        tags=["inventory", "executive", "guideline-summary"],
    )
    panels = [
        stat_panel(
            1,
            "Latest Snapshot Date",
            """
            SELECT toUnixTimestamp64Milli(toDateTime64(max(snapshot_date), 3)) AS value
            FROM inventory_mart.fact_inventory_snapshot_daily
            """,
            0,
            0,
            unit="dateTimeAsIso",
        ),
        stat_panel(
            2,
            "On-hand Quantity",
            f"""
            {LATEST_SNAPSHOT}
            SELECT sum(on_hand_qty) AS value
            FROM inventory_mart.fact_inventory_snapshot_daily
            WHERE snapshot_date = (SELECT snapshot_date FROM latest_snapshot)
            """,
            4,
            0,
        ),
        stat_panel(
            3,
            "Available Quantity",
            f"""
            {LATEST_SNAPSHOT}
            SELECT sum(available_qty) AS value
            FROM inventory_mart.fact_inventory_snapshot_daily
            WHERE snapshot_date = (SELECT snapshot_date FROM latest_snapshot)
            """,
            8,
            0,
        ),
        stat_panel(
            4,
            "Inventory Value",
            f"""
            {LATEST_SNAPSHOT}
            SELECT round(sum(inventory_value), 2) AS value
            FROM inventory_mart.fact_inventory_snapshot_daily
            WHERE snapshot_date = (SELECT snapshot_date FROM latest_snapshot)
            """,
            12,
            0,
        ),
        stat_panel(
            5,
            "Low-stock SKUs",
            f"""
            {LATEST_SNAPSHOT}
            SELECT countIf(p.reorder_point > 0 AND s.available_qty < p.reorder_point) AS value
            FROM inventory_mart.fact_inventory_snapshot_daily s
            LEFT JOIN inventory_mart.dim_product p ON p.sku_id = s.sku_id
            WHERE s.snapshot_date = (SELECT snapshot_date FROM latest_snapshot)
            """,
            16,
            0,
        ),
        stat_panel(
            6,
            "Overstock SKUs",
            f"""
            {LATEST_SNAPSHOT}
            SELECT countIf(p.max_stock > 0 AND s.available_qty > p.max_stock) AS value
            FROM inventory_mart.fact_inventory_snapshot_daily s
            LEFT JOIN inventory_mart.dim_product p ON p.sku_id = s.sku_id
            WHERE s.snapshot_date = (SELECT snapshot_date FROM latest_snapshot)
            """,
            20,
            0,
        ),
        timeseries_panel(
            7,
            "Inventory Value Over Time",
            """
            SELECT
              snapshot_date AS time,
              round(sum(inventory_value), 2) AS inventory_value
            FROM inventory_mart.fact_inventory_snapshot_daily
            GROUP BY snapshot_date
            ORDER BY snapshot_date
            """,
            0,
            4,
        ),
        timeseries_panel(
            8,
            "Inbound vs Outbound Trend (90 days)",
            """
            SELECT
              event_date AS time,
              sum(qty_in) AS inbound_qty,
              sum(qty_out) AS outbound_qty
            FROM inventory_mart.fact_inventory_movement
            WHERE event_date >= today() - 90
            GROUP BY event_date
            ORDER BY event_date
            """,
            12,
            4,
        ),
        bar_panel(
            9,
            "Inventory Value by Warehouse",
            f"""
            {LATEST_SNAPSHOT}
            SELECT
              coalesce(w.warehouse_name, s.warehouse_id) AS warehouse,
              round(sum(s.inventory_value), 2) AS inventory_value
            FROM inventory_mart.fact_inventory_snapshot_daily s
            LEFT JOIN inventory_mart.dim_warehouse w ON w.warehouse_id = s.warehouse_id
            WHERE s.snapshot_date = (SELECT snapshot_date FROM latest_snapshot)
            GROUP BY warehouse
            ORDER BY inventory_value DESC
            """,
            0,
            12,
        ),
        bar_panel(
            10,
            "Inventory Value by Category",
            f"""
            {LATEST_SNAPSHOT}
            SELECT
              coalesce(p.category, 'Unknown') AS category,
              round(sum(s.inventory_value), 2) AS inventory_value
            FROM inventory_mart.fact_inventory_snapshot_daily s
            LEFT JOIN inventory_mart.dim_product p ON p.sku_id = s.sku_id
            WHERE s.snapshot_date = (SELECT snapshot_date FROM latest_snapshot)
            GROUP BY category
            ORDER BY inventory_value DESC
            """,
            12,
            12,
        ),
        table_panel(
            11,
            "Top Low-stock Items",
            f"""
            {LATEST_SNAPSHOT}
            SELECT
              coalesce(w.warehouse_name, s.warehouse_id) AS warehouse,
              s.sku_id AS sku_id,
              coalesce(p.sku_name, s.sku_id) AS sku_name,
              coalesce(p.category, 'Unknown') AS category,
              s.available_qty AS available_qty,
              p.reorder_point AS reorder_point,
              greatest(p.reorder_point - s.available_qty, 0) AS gap_qty,
              round(s.inventory_value, 2) AS inventory_value
            FROM inventory_mart.fact_inventory_snapshot_daily s
            LEFT JOIN inventory_mart.dim_product p ON p.sku_id = s.sku_id
            LEFT JOIN inventory_mart.dim_warehouse w ON w.warehouse_id = s.warehouse_id
            WHERE
              s.snapshot_date = (SELECT snapshot_date FROM latest_snapshot)
              AND p.reorder_point > 0
              AND s.available_qty < p.reorder_point
            ORDER BY gap_qty DESC, inventory_value DESC
            LIMIT 10
            """,
            0,
            20,
        ),
        table_panel(
            12,
            "Top Overstock Items",
            f"""
            {LATEST_SNAPSHOT}
            SELECT
              coalesce(w.warehouse_name, s.warehouse_id) AS warehouse,
              s.sku_id AS sku_id,
              coalesce(p.sku_name, s.sku_id) AS sku_name,
              coalesce(p.category, 'Unknown') AS category,
              s.available_qty AS available_qty,
              p.max_stock AS max_stock,
              greatest(s.available_qty - p.max_stock, 0) AS excess_qty,
              round(s.inventory_value, 2) AS inventory_value
            FROM inventory_mart.fact_inventory_snapshot_daily s
            LEFT JOIN inventory_mart.dim_product p ON p.sku_id = s.sku_id
            LEFT JOIN inventory_mart.dim_warehouse w ON w.warehouse_id = s.warehouse_id
            WHERE
              s.snapshot_date = (SELECT snapshot_date FROM latest_snapshot)
              AND p.max_stock > 0
              AND s.available_qty > p.max_stock
            ORDER BY excess_qty DESC, inventory_value DESC
            LIMIT 10
            """,
            12,
            20,
        ),
    ]
    dashboard["panels"] = panels
    return dashboard


def stock_monitoring_dashboard() -> dict:
    dashboard = base_dashboard(
        uid="inventory-stock-monitoring",
        title="Inventory Stock Monitoring",
        tags=["inventory", "operations", "stock-health"],
    )
    status_cte = f"""
    {LATEST_SNAPSHOT},
    stock_status AS (
      SELECT
        s.warehouse_id,
        s.sku_id,
        coalesce(w.warehouse_name, s.warehouse_id) AS warehouse,
        coalesce(p.sku_name, s.sku_id) AS sku_name,
        coalesce(p.category, 'Unknown') AS category,
        coalesce(p.brand, 'Unknown') AS brand,
        s.on_hand_qty,
        s.available_qty,
        s.reserved_qty,
        p.reorder_point,
        p.max_stock,
        round(s.inventory_value, 2) AS inventory_value,
        multiIf(
          s.available_qty <= 0, 'Stockout',
          p.reorder_point > 0 AND s.available_qty < p.reorder_point, 'Low stock',
          p.max_stock > 0 AND s.available_qty > p.max_stock, 'Overstock',
          'Healthy'
        ) AS stock_status
      FROM inventory_mart.fact_inventory_snapshot_daily s
      LEFT JOIN inventory_mart.dim_product p ON p.sku_id = s.sku_id
      LEFT JOIN inventory_mart.dim_warehouse w ON w.warehouse_id = s.warehouse_id
      WHERE s.snapshot_date = (SELECT snapshot_date FROM latest_snapshot)
    )
    """
    panels = [
        bar_panel(
            1,
            "Stock Status Distribution",
            f"""
            {status_cte}
            SELECT stock_status, count() AS sku_count
            FROM stock_status
            GROUP BY stock_status
            ORDER BY sku_count DESC
            """,
            0,
            0,
            8,
            7,
        ),
        bar_panel(
            2,
            "Low-stock Items by Warehouse",
            f"""
            {status_cte}
            SELECT warehouse, count() AS low_stock_items
            FROM stock_status
            WHERE stock_status = 'Low stock'
            GROUP BY warehouse
            ORDER BY low_stock_items DESC
            """,
            8,
            0,
            8,
            7,
        ),
        stat_panel(
            3,
            "Items Below Reorder Point",
            f"""
            {status_cte}
            SELECT count() AS value
            FROM stock_status
            WHERE reorder_point > 0
              AND available_qty < reorder_point
            """,
            16,
            0,
            4,
            4,
        ),
        stat_panel(
            4,
            "Negative Available Stock",
            f"""
            {status_cte}
            SELECT countIf(available_qty < 0) AS value
            FROM stock_status
            """,
            20,
            0,
            4,
            4,
        ),
        table_panel(
            5,
            "Current Stock Exception Matrix",
            f"""
            {status_cte}
            SELECT
              warehouse,
              sku_id,
              sku_name,
              category,
              brand,
              on_hand_qty,
              available_qty,
              reserved_qty,
              reorder_point,
              max_stock,
              stock_status,
              inventory_value
            FROM stock_status
            WHERE stock_status != 'Healthy'
            ORDER BY
              multiIf(stock_status = 'Stockout', 0, stock_status = 'Low stock', 1, stock_status = 'Overstock', 2, 3),
              inventory_value DESC
            LIMIT 200
            """,
            0,
            7,
            24,
            10,
        ),
        table_panel(
            6,
            "Zero Stock with Recent Demand (30 days)",
            f"""
            {status_cte},
            recent_demand AS (
              SELECT
                sku_id,
                sum(qty) AS sold_qty_30d
              FROM inventory_mart.fact_sales_order_lines
              WHERE created_date >= today() - 30
              GROUP BY sku_id
            )
            SELECT
              s.warehouse,
              s.sku_id,
              s.sku_name,
              s.category,
              s.available_qty,
              d.sold_qty_30d
            FROM stock_status s
            INNER JOIN recent_demand d ON d.sku_id = s.sku_id
            WHERE s.available_qty <= 0
            ORDER BY d.sold_qty_30d DESC
            LIMIT 30
            """,
            0,
            17,
        ),
        table_panel(
            7,
            "Largest Overstock Positions",
            f"""
            {status_cte}
            SELECT
              warehouse,
              sku_id,
              sku_name,
              category,
              available_qty,
              max_stock,
              greatest(available_qty - max_stock, 0) AS excess_qty,
              inventory_value
            FROM stock_status
            WHERE stock_status = 'Overstock'
            ORDER BY excess_qty DESC, inventory_value DESC
            LIMIT 30
            """,
            12,
            17,
        ),
    ]
    dashboard["panels"] = panels
    return dashboard


def movement_replenishment_dashboard() -> dict:
    dashboard = base_dashboard(
        uid="inventory-movement-replenishment",
        title="Inventory Movement & Replenishment",
        tags=["inventory", "movement", "replenishment"],
    )
    panels = [
        stat_panel(
            1,
            "Open PO Quantity",
            """
            SELECT sum(qty_open) AS value
            FROM inventory_mart.fact_purchase_order_lines
            WHERE qty_open > 0
            """,
            0,
            0,
        ),
        stat_panel(
            2,
            "Open PO Lines",
            """
            SELECT count() AS value
            FROM inventory_mart.fact_purchase_order_lines
            WHERE qty_open > 0
            """,
            4,
            0,
        ),
        stat_panel(
            3,
            "Average Supplier Lead Time",
            """
            SELECT round(avg(lead_time_days), 2) AS value
            FROM inventory_mart.dim_supplier
            """,
            8,
            0,
        ),
        stat_panel(
            4,
            "Average Daily Sold Qty (30 days)",
            """
            SELECT round(sum(qty) / 30, 2) AS value
            FROM inventory_mart.fact_sales_order_lines
            WHERE created_date >= today() - 30
            """,
            12,
            0,
        ),
        stat_panel(
            5,
            "Items Below Reorder Point",
            f"""
            {LATEST_SNAPSHOT}
            SELECT countIf(p.reorder_point > 0 AND s.available_qty < p.reorder_point) AS value
            FROM inventory_mart.fact_inventory_snapshot_daily s
            LEFT JOIN inventory_mart.dim_product p ON p.sku_id = s.sku_id
            WHERE s.snapshot_date = (SELECT snapshot_date FROM latest_snapshot)
            """,
            16,
            0,
        ),
        stat_panel(
            6,
            "Suggested Reorder Qty",
            f"""
            {LATEST_SNAPSHOT}
            SELECT round(sum(greatest(p.max_stock - s.available_qty, 0)), 0) AS value
            FROM inventory_mart.fact_inventory_snapshot_daily s
            LEFT JOIN inventory_mart.dim_product p ON p.sku_id = s.sku_id
            WHERE
              s.snapshot_date = (SELECT snapshot_date FROM latest_snapshot)
              AND p.reorder_point > 0
              AND s.available_qty < p.reorder_point
            """,
            20,
            0,
        ),
        timeseries_panel(
            7,
            "Inbound vs Outbound (90 days)",
            """
            SELECT
              event_date AS time,
              sum(qty_in) AS inbound_qty,
              sum(qty_out) AS outbound_qty
            FROM inventory_mart.fact_inventory_movement
            WHERE event_date >= today() - 90
            GROUP BY event_date
            ORDER BY event_date
            """,
            0,
            4,
        ),
        bar_panel(
            8,
            "Receiving vs Dispatch by Warehouse (30 days)",
            """
            SELECT
              coalesce(w.warehouse_name, m.warehouse_id) AS warehouse,
              sum(m.qty_in) AS received_qty,
              sum(m.qty_out) AS dispatched_qty
            FROM inventory_mart.fact_inventory_movement m
            LEFT JOIN inventory_mart.dim_warehouse w ON w.warehouse_id = m.warehouse_id
            WHERE m.event_date >= today() - 30
            GROUP BY warehouse
            ORDER BY received_qty DESC
            """,
            12,
            4,
        ),
        table_panel(
            9,
            "Top Moving SKUs (30 days)",
            """
            SELECT
              m.sku_id AS sku_id,
              coalesce(p.sku_name, m.sku_id) AS sku_name,
              coalesce(p.category, 'Unknown') AS category,
              sum(m.qty_in) AS qty_in,
              sum(m.qty_out) AS qty_out,
              sum(abs(m.qty_change)) AS movement_volume,
              round(sum(abs(m.qty_change) * toFloat64(dp.unit_cost)), 2) AS movement_value_proxy
            FROM inventory_mart.fact_inventory_movement m
            LEFT JOIN inventory_mart.dim_product p ON p.sku_id = m.sku_id
            LEFT JOIN inventory_mart.dim_product dp ON dp.sku_id = m.sku_id
            WHERE m.event_date >= today() - 30
            GROUP BY m.sku_id, sku_name, category
            ORDER BY movement_volume DESC
            LIMIT 20
            """,
            0,
            12,
        ),
        table_panel(
            10,
            "Slow-moving SKUs (no movement in 30 days)",
            f"""
            {LATEST_SNAPSHOT},
            latest_stock AS (
              SELECT
                s.sku_id,
                round(sum(s.available_qty), 2) AS available_qty,
                round(sum(s.inventory_value), 2) AS inventory_value
              FROM inventory_mart.fact_inventory_snapshot_daily s
              WHERE s.snapshot_date = (SELECT snapshot_date FROM latest_snapshot)
              GROUP BY s.sku_id
            ),
            recent_moves AS (
              SELECT
                sku_id,
                max(event_date) AS last_event_date
              FROM inventory_mart.fact_inventory_movement
              GROUP BY sku_id
            )
            SELECT
              ls.sku_id AS sku_id,
              coalesce(p.sku_name, ls.sku_id) AS sku_name,
              coalesce(p.category, 'Unknown') AS category,
              ls.available_qty,
              ls.inventory_value,
              rm.last_event_date
            FROM latest_stock ls
            LEFT JOIN recent_moves rm ON rm.sku_id = ls.sku_id
            LEFT JOIN inventory_mart.dim_product p ON p.sku_id = ls.sku_id
            WHERE ls.available_qty > 0 AND (rm.last_event_date IS NULL OR rm.last_event_date < today() - 30)
            ORDER BY ls.inventory_value DESC, ls.available_qty DESC
            LIMIT 20
            """,
            12,
            12,
        ),
        table_panel(
            11,
            "Replenishment Recommendation",
            f"""
            {LATEST_SNAPSHOT},
            current_stock AS (
              SELECT
                sku_id,
                sum(available_qty) AS available_qty
              FROM inventory_mart.fact_inventory_snapshot_daily
              WHERE snapshot_date = (SELECT snapshot_date FROM latest_snapshot)
              GROUP BY sku_id
            ),
            daily_demand AS (
              SELECT
                sku_id,
                round(sum(qty) / 30, 2) AS avg_daily_demand
              FROM inventory_mart.fact_sales_order_lines
              WHERE created_date >= today() - 30
              GROUP BY sku_id
            )
            SELECT
              cs.sku_id AS sku_id,
              coalesce(p.sku_name, cs.sku_id) AS sku_name,
              coalesce(p.category, 'Unknown') AS category,
              cs.available_qty,
              p.reorder_point,
              p.max_stock,
              coalesce(dd.avg_daily_demand, 0) AS avg_daily_demand,
              greatest(p.max_stock - cs.available_qty, 0) AS recommended_reorder_qty
            FROM current_stock cs
            LEFT JOIN inventory_mart.dim_product p ON p.sku_id = cs.sku_id
            LEFT JOIN daily_demand dd ON dd.sku_id = cs.sku_id
            WHERE p.reorder_point > 0 AND cs.available_qty < p.reorder_point
            ORDER BY recommended_reorder_qty DESC, avg_daily_demand DESC
            LIMIT 50
            """,
            0,
            21,
            24,
            11,
        ),
    ]
    dashboard["panels"] = panels
    return dashboard


def aging_performance_dashboard() -> dict:
    dashboard = base_dashboard(
        uid="inventory-aging-performance",
        title="Inventory Aging & Warehouse Performance",
        tags=["inventory", "aging", "warehouse-performance"],
    )
    aging_cte = f"""
    {LATEST_SNAPSHOT},
    latest_stock AS (
      SELECT
        s.snapshot_date,
        s.warehouse_id,
        s.sku_id,
        s.available_qty,
        s.damaged_qty,
        s.in_transit_qty,
        round(s.inventory_value, 2) AS inventory_value
      FROM inventory_mart.fact_inventory_snapshot_daily s
      WHERE s.snapshot_date = (SELECT snapshot_date FROM latest_snapshot)
    ),
    last_movement AS (
      SELECT
        warehouse_id,
        sku_id,
        max(event_date) AS last_movement_date
      FROM inventory_mart.fact_inventory_movement
      GROUP BY warehouse_id, sku_id
    ),
    aging_base AS (
      SELECT
        ls.warehouse_id,
        ls.sku_id,
        ls.available_qty,
        ls.damaged_qty,
        ls.in_transit_qty,
        ls.inventory_value,
        coalesce(lm.last_movement_date, ls.snapshot_date) AS last_movement_date,
        dateDiff('day', coalesce(lm.last_movement_date, ls.snapshot_date), ls.snapshot_date) AS days_since_movement
      FROM latest_stock ls
      LEFT JOIN last_movement lm ON lm.warehouse_id = ls.warehouse_id AND lm.sku_id = ls.sku_id
      WHERE ls.available_qty > 0
    )
    """
    panels = [
        stat_panel(
            1,
            "Inventory Accuracy % (60 days)",
            """
            SELECT round(100.0 * countIf(variance_qty = 0) / nullIf(count(), 0), 2) AS value
            FROM inventory_mart.fact_stock_counts
            WHERE count_date >= today() - 60
            """,
            0,
            0,
        ),
        stat_panel(
            2,
            "Avg Absolute Count Variance",
            """
            SELECT round(avg(abs(variance_qty)), 2) AS value
            FROM inventory_mart.fact_stock_counts
            WHERE count_date >= today() - 60
            """,
            4,
            0,
        ),
        stat_panel(
            3,
            "Dead Stock Value (90+ days)",
            f"""
            {aging_cte}
            SELECT round(sumIf(inventory_value, days_since_movement > 90), 2) AS value
            FROM aging_base
            """,
            8,
            0,
        ),
        stat_panel(
            4,
            "Slow-moving Value (31-90 days)",
            f"""
            {aging_cte}
            SELECT round(sumIf(inventory_value, days_since_movement BETWEEN 31 AND 90), 2) AS value
            FROM aging_base
            """,
            12,
            0,
        ),
        stat_panel(
            5,
            "Damaged Qty (Latest Snapshot)",
            f"""
            {LATEST_SNAPSHOT}
            SELECT sum(damaged_qty) AS value
            FROM inventory_mart.fact_inventory_snapshot_daily
            WHERE snapshot_date = (SELECT snapshot_date FROM latest_snapshot)
            """,
            16,
            0,
        ),
        stat_panel(
            6,
            "In-transit Qty (Latest Snapshot)",
            f"""
            {LATEST_SNAPSHOT}
            SELECT sum(in_transit_qty) AS value
            FROM inventory_mart.fact_inventory_snapshot_daily
            WHERE snapshot_date = (SELECT snapshot_date FROM latest_snapshot)
            """,
            20,
            0,
        ),
        bar_panel(
            7,
            "Aging Value by Bucket",
            f"""
            {aging_cte}
            SELECT
              multiIf(
                days_since_movement <= 30, '0-30 days',
                days_since_movement <= 60, '31-60 days',
                days_since_movement <= 90, '61-90 days',
                '90+ days'
              ) AS aging_bucket,
              round(sum(inventory_value), 2) AS aging_value
            FROM aging_base
            GROUP BY aging_bucket
            ORDER BY min(days_since_movement)
            """,
            0,
            4,
        ),
        bar_panel(
            8,
            "Inventory Accuracy by Warehouse",
            """
            SELECT
              coalesce(w.warehouse_name, sc.warehouse_id) AS warehouse,
              round(100.0 * countIf(sc.variance_qty = 0) / nullIf(count(), 0), 2) AS accuracy_pct
            FROM inventory_mart.fact_stock_counts sc
            LEFT JOIN inventory_mart.dim_warehouse w ON w.warehouse_id = sc.warehouse_id
            WHERE sc.count_date >= today() - 60
            GROUP BY warehouse
            ORDER BY accuracy_pct ASC
            """,
            12,
            4,
        ),
        timeseries_panel(
            9,
            "Count Variance Trend (60 days)",
            """
            SELECT
              count_date AS time,
              round(avg(abs(variance_qty)), 2) AS avg_abs_variance,
              round(100.0 * countIf(variance_qty = 0) / nullIf(count(), 0), 2) AS accuracy_pct
            FROM inventory_mart.fact_stock_counts
            WHERE count_date >= today() - 60
            GROUP BY count_date
            ORDER BY count_date
            """,
            0,
            12,
        ),
        bar_panel(
            10,
            "Latest Inventory Value by Warehouse",
            f"""
            {LATEST_SNAPSHOT}
            SELECT
              coalesce(w.warehouse_name, s.warehouse_id) AS warehouse,
              round(sum(s.inventory_value), 2) AS inventory_value
            FROM inventory_mart.fact_inventory_snapshot_daily s
            LEFT JOIN inventory_mart.dim_warehouse w ON w.warehouse_id = s.warehouse_id
            WHERE s.snapshot_date = (SELECT snapshot_date FROM latest_snapshot)
            GROUP BY warehouse
            ORDER BY inventory_value DESC
            """,
            12,
            12,
        ),
        table_panel(
            11,
            "Top Dead / Slow-moving SKUs",
            f"""
            {aging_cte}
            SELECT
              coalesce(w.warehouse_name, a.warehouse_id) AS warehouse,
              a.sku_id AS sku_id,
              coalesce(p.sku_name, a.sku_id) AS sku_name,
              coalesce(p.category, 'Unknown') AS category,
              a.available_qty,
              a.inventory_value,
              a.last_movement_date,
              a.days_since_movement
            FROM aging_base a
            LEFT JOIN inventory_mart.dim_product p ON p.sku_id = a.sku_id
            LEFT JOIN inventory_mart.dim_warehouse w ON w.warehouse_id = a.warehouse_id
            WHERE a.days_since_movement >= 30
            ORDER BY a.days_since_movement DESC, a.inventory_value DESC
            LIMIT 25
            """,
            0,
            20,
        ),
        table_panel(
            12,
            "Count Variance by Warehouse",
            """
            SELECT
              coalesce(w.warehouse_name, sc.warehouse_id) AS warehouse,
              count() AS count_events,
              round(avg(abs(sc.variance_qty)), 2) AS avg_abs_variance,
              round(sum(abs(sc.variance_qty)), 2) AS total_abs_variance,
              round(100.0 * countIf(sc.variance_qty = 0) / nullIf(count(), 0), 2) AS accuracy_pct
            FROM inventory_mart.fact_stock_counts sc
            LEFT JOIN inventory_mart.dim_warehouse w ON w.warehouse_id = sc.warehouse_id
            WHERE sc.count_date >= today() - 60
            GROUP BY warehouse
            ORDER BY accuracy_pct ASC, total_abs_variance DESC
            """,
            12,
            20,
        ),
    ]
    dashboard["panels"] = panels
    return dashboard


DASHBOARDS = {
    "inventory-executive-summary.json": executive_summary_dashboard,
    "inventory-stock-monitoring.json": stock_monitoring_dashboard,
    "inventory-movement-replenishment.json": movement_replenishment_dashboard,
    "inventory-aging-performance.json": aging_performance_dashboard,
}


def main() -> None:
    DASHBOARD_DIR.mkdir(parents=True, exist_ok=True)
    for filename, builder in DASHBOARDS.items():
        payload = builder()
        path = DASHBOARD_DIR / filename
        with path.open("w", encoding="ascii") as handle:
            json.dump(payload, handle, indent=2)
            handle.write("\n")


if __name__ == "__main__":
    main()
