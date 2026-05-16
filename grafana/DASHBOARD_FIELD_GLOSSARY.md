# Grafana Dashboard Field Glossary

This file explains the main dashboard fields, KPI names, and operational terms used by the provisioned Grafana inventory dashboards in this repo.

Scope:

- dashboards under [grafana/dashboards](/Users/huynhthanhdat/Workspace/source-ingestion-demo/grafana/dashboards)
- datasource provisioning in [grafana/provisioning/datasources/clickhouse.yml](/Users/huynhthanhdat/Workspace/source-ingestion-demo/grafana/provisioning/datasources/clickhouse.yml)
- current SQL logic embedded in the dashboard JSON

Important:

- This glossary reflects the current implementation, not an abstract BI ideal.
- If the SQL in dashboard JSON changes, this glossary may need updates.
- Several metrics appear in more than one dashboard. Their meaning is the same unless stated otherwise.

## Core data terms

### `snapshot_date`

- Meaning: the business date of a daily inventory snapshot.
- Source: `inventory_mart.fact_inventory_snapshot_daily`.
- Typical use: identify the latest inventory state, trend inventory value over time, and filter stock health metrics.

### `on_hand_qty`

- Meaning: physical quantity currently in stock.
- Source: `inventory_mart.fact_inventory_snapshot_daily`.
- Difference from `available_qty`: `on_hand_qty` can include quantities that are reserved, damaged, or otherwise not available for sale/use.

### `available_qty`

- Meaning: stock that is currently usable or sellable.
- Source: `inventory_mart.fact_inventory_snapshot_daily`.
- Used heavily in low-stock, reorder, and negative-stock logic.

### `inventory_value`

- Meaning: monetary value of current inventory.
- Source: `inventory_mart.fact_inventory_snapshot_daily`.
- In dashboards it is usually aggregated with `sum(inventory_value)` and rounded to 2 decimals.

### `damaged_qty`

- Meaning: stock marked damaged in the latest snapshot.
- Source: `inventory_mart.fact_inventory_snapshot_daily`.
- Used as an exception/quality-of-stock signal.

### `in_transit_qty`

- Meaning: stock moving between locations or inbound but not yet fully received into available stock.
- Source: `inventory_mart.fact_inventory_snapshot_daily`.
- Useful for explaining why supply exists operationally but not yet in `available_qty`.

### `reorder_point`

- Meaning: the minimum desired stock threshold before replenishment action is needed.
- Source: `inventory_mart.dim_product`.
- Main low-stock rule:

```text
available_qty < reorder_point
```

### `max_stock`

- Meaning: upper stock target for a SKU.
- Source: `inventory_mart.dim_product`.
- Main overstock rule:

```text
available_qty > max_stock
```

### `qty_in`

- Meaning: inbound movement quantity into stock.
- Source: `inventory_mart.fact_inventory_movement`.
- Used for receiving, replenishment, and inbound trend charts.

### `qty_out`

- Meaning: outbound movement quantity out of stock.
- Source: `inventory_mart.fact_inventory_movement`.
- Used for dispatch and outbound trend charts.

### `qty_change`

- Meaning: signed stock movement amount.
- Source: `inventory_mart.fact_inventory_movement`.
- In dashboards, `abs(qty_change)` is often used to measure movement volume regardless of direction.

### `qty_open`

- Meaning: open quantity on purchase orders that has not been received yet.
- Source: `inventory_mart.fact_purchase_order_lines`.
- Used for open PO dashboards and replenishment planning.

### `qty_received`

- Meaning: quantity already received against purchase orders.
- Source: `inventory_mart.fact_purchase_order_lines`.
- Used together with `qty_open` to compare demand coverage and receiving progress.

### `sales_amount`

- Meaning: commercial value of sales order lines.
- Source: `inventory_mart.fact_sales_order_lines`.
- Used for sales trends and SKU demand context.

### `variance_qty`

- Meaning: difference between physical counted stock and system stock during stock count.
- Source: `inventory_mart.fact_stock_counts`.
- Interpretation:
  - `0`: system and physical count match exactly
  - positive: counted quantity higher than system quantity
  - negative: counted quantity lower than system quantity
- This is the base field behind `accuracy` and `variance` metrics.

### `ingestion_time`

- Meaning: timestamp when data landed into the mart layer.
- Source: multiple mart fact tables.
- Used for freshness and lag metrics.

## KPI and dashboard term glossary

## `Inventory Accuracy %`

- Meaning: share of stock count events where the variance is exactly zero.
- Current formula:

```text
100 * countIf(variance_qty = 0) / count()
```

- Source: `inventory_mart.fact_stock_counts`.
- Usage:
  - `Inventory Accuracy % (60 days)`
  - `Count Variance by Warehouse`
- Caveat: this is a strict exact-match definition. A warehouse with many tiny non-zero variances may still look worse than expected.

## `Variance`

- Meaning: the mismatch between counted stock and system stock.
- Base field: `variance_qty`.
- Practical interpretation:
  - larger absolute variance means poorer inventory control
  - signed variance tells direction
  - absolute variance tells magnitude only

## `Avg Absolute Count Variance`

- Meaning: average size of stock-count mismatches, ignoring direction.
- Current formula:

```text
avg(abs(variance_qty))
```

- Source: `inventory_mart.fact_stock_counts`.
- Why it matters: accuracy alone only says how often counts are exact; absolute variance says how bad mismatches are when they happen.

## `Count Variance Trend`

- Meaning: how average variance changes over time.
- Current logic: trend line over stock-count dates, using average absolute variance and accuracy percentage.
- Source: `inventory_mart.fact_stock_counts`.

## `Count Variance by Warehouse`

- Meaning: warehouse-by-warehouse summary of count quality.
- Current fields usually include:
  - number of count events
  - average absolute variance
  - total absolute variance
  - exact-match accuracy percentage
- Source: `inventory_mart.fact_stock_counts` joined to `dim_warehouse`.

## `Dead Stock`

- Meaning: stock with no movement for 90 days or more.
- Current logic: based on days since last movement and current stock value.
- Main dashboard metric:

```text
Dead Stock Value (90+ days)
```

- Source: derived from latest stock snapshot plus movement history.
- Caveat: with recently seeded demo data, dead-stock values may stay low unless older inactivity is present.

## `Slow-moving`

- Meaning: stock with weak turnover, but not yet in dead-stock territory.
- Current bucket in this repo:
  - `31-90 days` since last movement
- Main dashboard metric:

```text
Slow-moving Value (31-90 days)
```

## `Aging`

- Meaning: classifying inventory by how long it has sat without movement.
- Dashboard example:
  - `Aging Value by Bucket`
- Typical bucket meaning:
  - fresh / recently moved
  - slow-moving
  - dead stock
- Source: latest stock snapshot plus latest movement date logic.

## `Snapshot Lag (hours)`

- Meaning: how stale the latest mart snapshot is relative to current wall-clock time.
- Current formula:

```text
(now() - max(ingestion_time)) / 3600
```

- Source: `inventory_mart.fact_inventory_snapshot_daily`.
- Interpretation:
  - low number: data is fresh
  - high number: pipeline or refresh process may be delayed

## `Last Mart Ingestion Time`

- Meaning: most recent ingestion timestamp found across mart fact tables.
- Source: union of mart facts in the dashboard SQL.
- Use: sanity-check that pipelines are still landing data.

## `Latest Snapshot Date`

- Meaning: latest `snapshot_date` available in daily inventory facts.
- Source: `inventory_mart.fact_inventory_snapshot_daily`.
- Use: quick freshness indicator for business-date data, separate from technical ingestion time.

## `Low-stock SKU` / `Items Below Reorder Point`

- Meaning: SKU currently below its reorder threshold.
- For this KPI, stockout rows are included if they are also below the reorder threshold.
- Current rule:

```text
reorder_point > 0 AND available_qty < reorder_point
```

- Sources:
  - `inventory_mart.fact_inventory_snapshot_daily`
  - `inventory_mart.dim_product`
- Important:
  - `Items Below Reorder Point` is a threshold KPI.
  - `Stockout` and `Low stock` in `stock_status` are mutually exclusive status labels.
  - So this KPI can include rows classified as `Stockout`.

## `Overstock SKU`

- Meaning: SKU currently above its configured maximum desired level.
- Current rule:

```text
max_stock > 0 AND available_qty > max_stock
```

- Sources:
  - `inventory_mart.fact_inventory_snapshot_daily`
  - `inventory_mart.dim_product`

## `Negative Available Stock`

- Meaning: rows where `available_qty < 0`.
- This is usually a data/process exception, not a healthy operating state.
- Source: `inventory_mart.fact_inventory_snapshot_daily`.

## `Current Stock Exception Matrix`

- Meaning: detailed table of current warehouse + SKU exceptions.
- Typical exception classes include:
  - low stock
  - overstock
  - negative stock
  - zero stock with recent demand
- Use: operational drilldown after KPI cards show a problem.

## `Zero Stock with Recent Demand`

- Meaning: SKU with current zero stock but recent sales or demand signal.
- Current time window in dashboard: `30 days`.
- Use: identify likely service risk or missed replenishment.

## `Inventory Value Over Time`

- Meaning: trend of total inventory valuation by snapshot date.
- Current formula:

```text
sum(inventory_value) grouped by snapshot_date
```

- Source: `inventory_mart.fact_inventory_snapshot_daily`.

## `Inbound vs Outbound Trend`

- Meaning: compares incoming stock and outgoing stock over time.
- Source: `inventory_mart.fact_inventory_movement`.
- Business use:
  - detect demand spikes
  - detect replenishment lag
  - see whether stock build-up is demand-driven or supply-driven

## `Receiving vs Dispatch by Warehouse`

- Meaning: warehouse-level comparison between quantity received and quantity dispatched.
- Source: `inventory_mart.fact_inventory_movement` joined to `dim_warehouse`.
- Use: identify net senders, net receivers, or imbalanced flow.

## `Top Moving SKUs`

- Meaning: SKUs with the largest movement volume during the selected period.
- Current logic uses both inbound and outbound quantities and often total absolute movement.
- Source: `inventory_mart.fact_inventory_movement`.

## `Slow-moving SKUs (no movement in 30 days)`

- Meaning: SKUs with stock but no recorded movement in the last 30 days.
- Use: identify aging risk before stock becomes fully dead.

## `Replenishment Recommendation`

- Meaning: a computed suggestion for how much to reorder.
- Current logic approximates reorder need using the gap between `max_stock` and current `available_qty`.
- Typical formula shape:

```text
greatest(max_stock - available_qty, 0)
```

- Caveat: this is a simple stock-gap method, not a full demand forecast.

## `Suggested Reorder Qty`

- Meaning: aggregate reorder suggestion across items.
- Same logic basis as the replenishment recommendation table.

## `Open PO Quantity`

- Meaning: total outstanding purchase order quantity not yet received.
- Source: `inventory_mart.fact_purchase_order_lines`.
- Use: estimate inbound pipeline already committed.

## `Open PO Lines`

- Meaning: count of purchase order lines with remaining open quantity.
- Source: `inventory_mart.fact_purchase_order_lines`.
- Use: complexity/workload indicator, not just quantity.

## `PO Open vs Received Trend`

- Meaning: trend comparison between open quantity and received quantity.
- Source: `inventory_mart.fact_purchase_order_lines`.
- Use: tell whether purchase orders are converting into received stock on time.

## `Average Supplier Lead Time`

- Meaning: average `lead_time_days` across suppliers.
- Source: `inventory_mart.dim_supplier`.
- Caveat: current dashboard uses supplier master data, not PO-event actual lead time.

## `Supplier SLA On-time Rate`

- Meaning: simplified supplier punctuality score.
- Current implementation is not based on actual PO due-date performance.
- Current formula classifies suppliers with `lead_time_days <= 7` as on-time for the purpose of the demo.
- Source: `inventory_mart.dim_supplier`.
- Caveat: this is a model simplification. It is not a true realized on-time delivery KPI.

## `Average Daily Sold Qty (30 days)`

- Meaning: average quantity sold per day over the last 30 days.
- Current formula:

```text
sum(qty) / 30
```

- Source: `inventory_mart.fact_sales_order_lines`.
- Use: demand intensity proxy for replenishment and stockout risk.

## `Inventory Value by Warehouse`

- Meaning: total stock value by warehouse at the latest snapshot.
- Source: `inventory_mart.fact_inventory_snapshot_daily` joined to `dim_warehouse`.

## `Inventory Value by Category`

- Meaning: total stock value grouped by product category.
- Source: latest stock snapshot joined to `dim_product`.
- Caveat: rows with missing category are usually mapped to `Unknown`.

## Low-stock Rows in `Current Stock Exception Matrix`

- Meaning: detailed list of the most severe low-stock positions.
- Usually includes warehouse, SKU, product name, available quantity, reorder point, and shortage severity.

## Overstock Rows in `Current Stock Exception Matrix`

- Meaning: detailed list of the most severe overstock positions.
- Usually includes warehouse, SKU, product name, available quantity, and max stock gap.

## `Damaged Qty (Latest Snapshot)`

- Meaning: total quantity marked damaged in the most recent snapshot.
- Source: `inventory_mart.fact_inventory_snapshot_daily`.
- Use: stock quality and write-off risk.

## `In-transit Qty (Latest Snapshot)`

- Meaning: total quantity in transit in the most recent snapshot.
- Use: supply visibility and reconciliation of incoming stock.

## `Top Dead / Slow-moving SKUs`

- Meaning: detailed list of SKUs that have been inactive for long periods.
- Use: markdown, liquidation, or replenishment policy review.

## `SKU Stock Trend`

- Meaning: time series of stock quantities for a selected SKU.
- Current series usually include:
  - `available_qty`
  - `on_hand_qty`
- Source: `inventory_mart.fact_inventory_snapshot_daily`.

## `SKU Sales Trend`

- Meaning: time series of sold quantity and sales amount for a selected SKU.
- Source: `inventory_mart.fact_sales_order_lines`.

## `SKU Detail (Latest Snapshot)`

- Meaning: one-row-per-warehouse-or-SKU latest stock detail table.
- Typical fields:
  - warehouse
  - SKU
  - name/category/brand
  - on-hand
  - available
  - reorder point
  - max stock
  - value

## `Negative Stock Rows (Latest)`

- Meaning: number of latest snapshot rows where available stock is negative.
- Use: strong data/process exception KPI.

## `Data Quality Summary (Latest Snapshot)`

- Meaning: quick checks on reporting data quality at latest snapshot.
- Current checks include examples like:
  - total rows
  - missing category rows
  - missing brand rows
  - other master-data completeness conditions
- Use: explain why breakdown charts may have `Unknown` buckets or suspicious totals.

## Common interpretation guide

### What does `accuracy` mean here?

- In this repo, `accuracy` is not forecast accuracy or planning accuracy.
- It means stock count agreement between system and physical count.
- Exact zero variance is treated as accurate.

### What does `variance` mean here?

- It is inventory count mismatch, not statistical variance.
- If the system says 100 and the count says 96, the variance is `-4`.
- If the system says 100 and the count says 103, the variance is `+3`.

### Why use `absolute variance`?

- Signed variance can cancel out when aggregated.
- Absolute variance measures error size without letting positive and negative errors offset each other.

### Why can `accuracy` look good while `variance` still looks bad?

- If many rows are exact but a few rows have very large mismatches, exact-match accuracy can still look reasonable.
- `Avg Absolute Count Variance` catches the size of those misses.

### Why can `dead stock` stay low in demo data?

- The seeded dataset is often recent.
- If there are not enough old idle records, age-based buckets will not produce large dead-stock values.

### Why is supplier SLA a weak metric in the current demo?

- Current logic uses supplier master `lead_time_days`, not actual PO promised date vs received date.
- So it behaves more like a supplier-risk proxy than a true delivery SLA KPI.

## Dashboard-to-source mapping

### `Executive Overview`

- Main source:
  - `inventory_mart.fact_inventory_snapshot_daily`
  - `inventory_mart.fact_inventory_movement`
  - `inventory_mart.dim_product`
  - `inventory_mart.dim_warehouse`

### `Warehouse Operations - Stock Exceptions`

- Main source:
  - `inventory_mart.fact_inventory_snapshot_daily`
  - `inventory_mart.fact_sales_order_lines`
  - `inventory_mart.dim_product`
  - `inventory_mart.dim_warehouse`

### `Warehouse Operations - Movement Flow`

- Main source:
  - `inventory_mart.fact_inventory_movement`
  - `inventory_mart.fact_inventory_snapshot_daily`
  - `inventory_mart.fact_sales_order_lines`
  - `inventory_mart.dim_product`
  - `inventory_mart.dim_warehouse`

### `Procurement Planner - Replenishment`

- Main source:
  - `inventory_mart.fact_purchase_order_lines`
  - `inventory_mart.fact_sales_order_lines`
  - `inventory_mart.dim_product`
  - `inventory_mart.dim_supplier`
  - `inventory_mart.dim_warehouse`

### `Inventory Control - Aging & Accuracy`

- Main source:
  - `inventory_mart.fact_inventory_snapshot_daily`
  - `inventory_mart.fact_inventory_movement`
  - `inventory_mart.fact_stock_counts`
  - `inventory_mart.dim_product`
  - `inventory_mart.dim_warehouse`

### `Data Reliability & SKU Drilldown`

- Main source:
  - `inventory_mart.fact_inventory_snapshot_daily`
  - `inventory_mart.fact_sales_order_lines`
  - `inventory_mart.dim_product`
  - `inventory_mart.dim_warehouse`

## Known limitations in the current model

- `Supplier SLA On-time Rate` is a simplified proxy, not actual supplier delivery performance.
- Aging/dead-stock metrics depend on enough historical movement depth.
- Metrics rely on mart refresh health; stale mart data will distort interpretation.
- `inventory_mart` is the reporting layer; if raw ingestion is ahead of mart refresh, Grafana may lag behind source ingestion.
