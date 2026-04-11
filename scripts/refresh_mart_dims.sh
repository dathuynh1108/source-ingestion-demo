#!/usr/bin/env bash
set -euo pipefail

docker exec clickhouse_db clickhouse-client --user password --password admin --multiquery --query "
TRUNCATE TABLE inventory_mart.dim_product;
INSERT INTO inventory_mart.dim_product
SELECT
  sku_id,
  sku_name,
  category,
  subcategory,
  brand,
  uom,
  toDecimal64(unit_cost, 2) AS unit_cost,
  toDecimal64(selling_price, 2) AS selling_price,
  status,
  reorder_point,
  safety_stock,
  max_stock,
  shelf_life_days,
  abc_class,
  parseDateTimeBestEffortOrNull(created_at) AS created_at
FROM inventory_raw.raw_dim_skus;

TRUNCATE TABLE inventory_mart.dim_warehouse;
INSERT INTO inventory_mart.dim_warehouse
SELECT
  warehouse_id,
  warehouse_name,
  city,
  region,
  parseDateTimeBestEffortOrNull(created_at) AS created_at
FROM inventory_raw.raw_dim_warehouses;

TRUNCATE TABLE inventory_mart.dim_supplier;
INSERT INTO inventory_mart.dim_supplier
SELECT
  supplier_id,
  supplier_name,
  country,
  lead_time_days,
  toDecimal64(rating, 2) AS rating,
  payment_terms_days,
  parseDateTimeBestEffortOrNull(created_at) AS created_at
FROM inventory_raw.raw_dim_suppliers;

TRUNCATE TABLE inventory_mart.dim_customer;
INSERT INTO inventory_mart.dim_customer
SELECT
  customer_id,
  customer_name,
  segment,
  city,
  region,
  parseDateTimeBestEffortOrNull(created_at) AS created_at
FROM inventory_raw.raw_dim_customers;

-- Generate dim_date directly in ClickHouse (rolling window)
TRUNCATE TABLE inventory_mart.dim_date;
INSERT INTO inventory_mart.dim_date
WITH
  toDate(today() - 800) AS d0,
  toUInt32(861) AS days
SELECT
  toUInt32(toYYYYMMDD(d)) AS date_key,
  d AS full_date,
  toUInt16(toYear(d)) AS calendar_year,
  toUInt8(toQuarter(d)) AS calendar_quarter,
  toUInt8(toMonth(d)) AS calendar_month,
  monthName(d) AS month_name,
  toUInt8(toDayOfMonth(d)) AS day_of_month,
  toUInt8(toDayOfWeek(d)) AS day_of_week,
  multiIf(
    toDayOfWeek(d) = 1, 'Mon',
    toDayOfWeek(d) = 2, 'Tue',
    toDayOfWeek(d) = 3, 'Wed',
    toDayOfWeek(d) = 4, 'Thu',
    toDayOfWeek(d) = 5, 'Fri',
    toDayOfWeek(d) = 6, 'Sat',
    'Sun'
  ) AS day_name,
  toUInt8(if(toDayOfWeek(d) IN (6,7), 1, 0)) AS is_weekend
FROM
(
  SELECT addDays(d0, number) AS d
  FROM numbers(days)
);

SELECT
  (SELECT count() FROM inventory_mart.dim_product) AS dim_product,
  (SELECT count() FROM inventory_mart.dim_warehouse) AS dim_warehouse,
  (SELECT count() FROM inventory_mart.dim_supplier) AS dim_supplier,
  (SELECT count() FROM inventory_mart.dim_customer) AS dim_customer,
  (SELECT count() FROM inventory_mart.dim_date) AS dim_date;
"

