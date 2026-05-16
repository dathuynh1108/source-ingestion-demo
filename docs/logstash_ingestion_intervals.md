# Logstash Source Ingestion Intervals

This file summarizes the near-CDC polling setup used by the source-ingestion demo.

## Runtime Cadence

| Component | Env var | Default | Purpose |
|---|---:|---:|---|
| SQL Server live generator | `LIVE_BATCH_INTERVAL_SECONDS` | `5` seconds | Inserts new demo source rows for live movement/reporting simulation. |
| Logstash JDBC polling | `LOGSTASH_POLL_INTERVAL` | `5s` | Polls SQL Server source tables and publishes incremental rows to Kafka. |
| ClickHouse mart refresher | `MART_REFRESH_INTERVAL_SECONDS` | `5` seconds | Refreshes `inventory_mart.fact_*` from ClickHouse raw tables when the `mart-sync` profile is enabled. |

All Logstash JDBC inputs currently use the same interval expression:

```conf
interval => "${LOGSTASH_POLL_INTERVAL:5s}"
```

## Source Table Mapping

| Source table in SQL Server | Logstash SQL file | Tracking column | Tracking type | Poll interval | Kafka topic | ClickHouse raw table | ClickHouse mart table |
|---|---|---|---|---:|---|---|---|
| `dbo.inventory_transactions` | `inventory_incremental.sql` | `stream_seq` | numeric | `LOGSTASH_POLL_INTERVAL`, default `5s` | `inventory_topic` | `inventory_raw.raw_inventory_transactions` | `inventory_mart.fact_inventory_movement` |
| `dbo.purchase_order_lines` | `purchase_order_lines_incremental.sql` | `created_at` | timestamp | `LOGSTASH_POLL_INTERVAL`, default `5s` | `po_lines_topic` | `inventory_raw.raw_purchase_order_lines` | `inventory_mart.fact_purchase_order_lines` |
| `dbo.sales_order_lines` | `sales_order_lines_incremental.sql` | `created_at` | timestamp | `LOGSTASH_POLL_INTERVAL`, default `5s` | `sales_lines_topic` | `inventory_raw.raw_sales_order_lines` | `inventory_mart.fact_sales_order_lines` |
| `dbo.inventory_snapshot_daily` | `inventory_snapshot_daily_incremental.sql` | `created_at` | timestamp | `LOGSTASH_POLL_INTERVAL`, default `5s` | `snapshot_topic` | `inventory_raw.raw_inventory_snapshot_daily` | `inventory_mart.fact_inventory_snapshot_daily` |
| `dbo.stock_counts` | `stock_counts_incremental.sql` | `created_at` | timestamp | `LOGSTASH_POLL_INTERVAL`, default `5s` | `stock_counts_topic` | `inventory_raw.raw_stock_counts` | `inventory_mart.fact_stock_counts` |
| `dbo.skus` | `dim_skus_incremental.sql` | `created_at` | timestamp | `LOGSTASH_POLL_INTERVAL`, default `5s` | `dim_skus_topic` | `inventory_raw.raw_dim_skus` | `inventory_mart.dim_product` |
| `dbo.warehouses` | `dim_warehouses_incremental.sql` | `created_at` | timestamp | `LOGSTASH_POLL_INTERVAL`, default `5s` | `dim_warehouses_topic` | `inventory_raw.raw_dim_warehouses` | `inventory_mart.dim_warehouse` |
| `dbo.suppliers` | `dim_suppliers_incremental.sql` | `created_at` | timestamp | `LOGSTASH_POLL_INTERVAL`, default `5s` | `dim_suppliers_topic` | `inventory_raw.raw_dim_suppliers` | `inventory_mart.dim_supplier` |
| `dbo.customers` | `dim_customers_incremental.sql` | `created_at` | timestamp | `LOGSTASH_POLL_INTERVAL`, default `5s` | `dim_customers_topic` | `inventory_raw.raw_dim_customers` | `inventory_mart.dim_customer` |

## Notes For Report

- `dbo.inventory_transactions` is the strongest near-CDC example because it tracks the append-only `stream_seq` column.
- The reporting and dimension tables use `created_at` timestamp tracking, so late updates to old rows are not captured unless they also advance `created_at` or the query is changed to use an update timestamp.
- Logstash lands data into Kafka first; ClickHouse Kafka engine tables and materialized views then persist rows into `inventory_raw.raw_*`.
- Grafana dashboards read from `inventory_mart`, so the end-to-end freshness depends on both Logstash polling and mart refresh cadence.
