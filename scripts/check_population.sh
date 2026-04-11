#!/usr/bin/env bash
set -euo pipefail

echo "== SQL Server counts =="
docker exec sqlserver_source /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "YourStrong!Passw0rd" -No -d inventory_demo -W -s"|" -Q "
SET NOCOUNT ON;
SELECT 'inventory_transactions' AS tbl, COUNT(*) AS cnt FROM dbo.inventory_transactions
UNION ALL SELECT 'purchase_order_lines', COUNT(*) FROM dbo.purchase_order_lines
UNION ALL SELECT 'sales_order_lines', COUNT(*) FROM dbo.sales_order_lines
UNION ALL SELECT 'inventory_snapshot_daily', COUNT(*) FROM dbo.inventory_snapshot_daily
UNION ALL SELECT 'stock_counts', COUNT(*) FROM dbo.stock_counts
ORDER BY tbl;
"

echo ""
echo "== ClickHouse RAW counts =="
docker exec clickhouse_db clickhouse-client --user password --password admin --query "
SELECT
  (SELECT count() FROM inventory_raw.raw_inventory_transactions) AS raw_inventory_transactions,
  (SELECT count() FROM inventory_raw.raw_purchase_order_lines) AS raw_purchase_order_lines,
  (SELECT count() FROM inventory_raw.raw_sales_order_lines) AS raw_sales_order_lines,
  (SELECT count() FROM inventory_raw.raw_inventory_snapshot_daily) AS raw_inventory_snapshot_daily,
  (SELECT count() FROM inventory_raw.raw_stock_counts) AS raw_stock_counts
"

echo ""
echo "== ClickHouse MART counts =="
docker exec clickhouse_db clickhouse-client --user password --password admin --query "
SELECT
  (SELECT count() FROM inventory_mart.fact_inventory_movement) AS fact_inventory_movement,
  (SELECT count() FROM inventory_mart.fact_purchase_order_lines) AS fact_purchase_order_lines,
  (SELECT count() FROM inventory_mart.fact_sales_order_lines) AS fact_sales_order_lines,
  (SELECT count() FROM inventory_mart.fact_inventory_snapshot_daily) AS fact_inventory_snapshot_daily,
  (SELECT count() FROM inventory_mart.fact_stock_counts) AS fact_stock_counts
"

echo ""
echo "== ClickHouse MART dim counts =="
docker exec clickhouse_db clickhouse-client --user password --password admin --query "
SELECT
  (SELECT count() FROM inventory_mart.dim_product) AS dim_product,
  (SELECT count() FROM inventory_mart.dim_warehouse) AS dim_warehouse,
  (SELECT count() FROM inventory_mart.dim_supplier) AS dim_supplier,
  (SELECT count() FROM inventory_mart.dim_customer) AS dim_customer,
  (SELECT count() FROM inventory_mart.dim_date) AS dim_date
"

