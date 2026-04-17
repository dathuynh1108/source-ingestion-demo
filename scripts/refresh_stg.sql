TRUNCATE TABLE inventory_stg.stg_inventory_transactions_clean;

INSERT INTO inventory_stg.stg_inventory_transactions_clean
SELECT
    toDate(event_time) AS event_date,
    event_time,
    upperUTF8(trim(BOTH ' ' FROM warehouse_id)) AS warehouse_id,
    upperUTF8(trim(BOTH ' ' FROM sku_id)) AS sku_id,
    qty_change,
    if(
        qty_change > 0,
        'inbound',
        if(qty_change < 0, 'outbound', 'adjustment')
    ) AS event_type,
    if(qty_change > 0, qty_change, 0) AS qty_in,
    if(qty_change < 0, abs(qty_change), 0) AS qty_out,
    ingestion_time
FROM inventory_raw.raw_inventory_transactions
WHERE trim(BOTH ' ' FROM warehouse_id) != ''
  AND trim(BOTH ' ' FROM sku_id) != '';

TRUNCATE TABLE inventory_stg.stg_inventory_snapshot_daily_clean;

INSERT INTO inventory_stg.stg_inventory_snapshot_daily_clean
SELECT
    snapshot_date,
    upperUTF8(trim(BOTH ' ' FROM warehouse_id)) AS warehouse_id,
    upperUTF8(trim(BOTH ' ' FROM sku_id)) AS sku_id,
    greatest(on_hand_qty, 0) AS on_hand_qty,
    greatest(reserved_qty, 0) AS reserved_qty,
    greatest(damaged_qty, 0) AS damaged_qty,
    greatest(in_transit_qty, 0) AS in_transit_qty,
    greatest(available_qty, 0) AS available_qty,
    toDecimal64(greatest(toFloat64(inventory_value), 0.), 2) AS inventory_value,
    toDecimal64(greatest(toFloat64(unit_cost), 0.), 2) AS unit_cost,
    created_at,
    ingestion_time
FROM inventory_raw.raw_inventory_snapshot_daily
WHERE trim(BOTH ' ' FROM warehouse_id) != ''
  AND trim(BOTH ' ' FROM sku_id) != '';

TRUNCATE TABLE inventory_stg.stg_purchase_order_lines_clean;

INSERT INTO inventory_stg.stg_purchase_order_lines_clean
SELECT
    toDate(created_at) AS created_date,
    po_id,
    po_line_id,
    line_no,
    upperUTF8(trim(BOTH ' ' FROM sku_id)) AS sku_id,
    greatest(qty_ordered, 0) AS qty_ordered,
    greatest(qty_received, 0) AS qty_received,
    greatest(qty_ordered - qty_received, 0) AS qty_open,
    toDecimal64(greatest(toFloat64(unit_cost), 0.), 2) AS unit_cost,
    if(trim(BOTH ' ' FROM line_status) = '', 'unknown', trim(BOTH ' ' FROM line_status)) AS line_status,
    created_at,
    ingestion_time
FROM inventory_raw.raw_purchase_order_lines
WHERE trim(BOTH ' ' FROM sku_id) != '';

TRUNCATE TABLE inventory_stg.stg_sales_order_lines_clean;

INSERT INTO inventory_stg.stg_sales_order_lines_clean
SELECT
    toDate(created_at) AS created_date,
    order_id,
    so_line_id,
    line_no,
    upperUTF8(trim(BOTH ' ' FROM sku_id)) AS sku_id,
    greatest(qty, 0) AS qty,
    toDecimal64(greatest(toFloat64(unit_price), 0.), 2) AS unit_price,
    toDecimal64(greatest(qty, 0) * greatest(toFloat64(unit_price), 0.), 2) AS sales_amount,
    created_at,
    ingestion_time
FROM inventory_raw.raw_sales_order_lines
WHERE trim(BOTH ' ' FROM sku_id) != '';

TRUNCATE TABLE inventory_stg.stg_stock_counts_clean;

INSERT INTO inventory_stg.stg_stock_counts_clean
SELECT
    count_date,
    upperUTF8(trim(BOTH ' ' FROM warehouse_id)) AS warehouse_id,
    upperUTF8(trim(BOTH ' ' FROM sku_id)) AS sku_id,
    system_qty,
    counted_qty,
    counted_qty - system_qty AS variance_qty,
    created_at,
    ingestion_time
FROM inventory_raw.raw_stock_counts
WHERE trim(BOTH ' ' FROM warehouse_id) != ''
  AND trim(BOTH ' ' FROM sku_id) != '';

TRUNCATE TABLE inventory_stg.stg_dim_product_latest;

INSERT INTO inventory_stg.stg_dim_product_latest
SELECT
    normalized_sku_id AS sku_id,
    argMax(trim(BOTH ' ' FROM sku_name), parsed_created_at) AS sku_name,
    argMax(trim(BOTH ' ' FROM category), parsed_created_at) AS category,
    argMax(trim(BOTH ' ' FROM subcategory), parsed_created_at) AS subcategory,
    argMax(trim(BOTH ' ' FROM brand), parsed_created_at) AS brand,
    argMax(trim(BOTH ' ' FROM uom), parsed_created_at) AS uom,
    toDecimal64(argMax(greatest(unit_cost, 0.), parsed_created_at), 2) AS unit_cost,
    toDecimal64(argMax(greatest(selling_price, 0.), parsed_created_at), 2) AS selling_price,
    argMax(trim(BOTH ' ' FROM status), parsed_created_at) AS status,
    argMax(greatest(reorder_point, 0), parsed_created_at) AS reorder_point,
    argMax(greatest(safety_stock, 0), parsed_created_at) AS safety_stock,
    argMax(greatest(max_stock, 0), parsed_created_at) AS max_stock,
    argMax(greatest(shelf_life_days, 0), parsed_created_at) AS shelf_life_days,
    argMax(trim(BOTH ' ' FROM abc_class), parsed_created_at) AS abc_class,
    max(parsed_created_at) AS created_at
FROM
(
    SELECT
        *,
        upperUTF8(trim(BOTH ' ' FROM sku_id)) AS normalized_sku_id,
        parseDateTimeBestEffortOrZero(created_at) AS parsed_created_at
    FROM inventory_raw.raw_dim_skus
)
WHERE trim(BOTH ' ' FROM sku_id) != ''
GROUP BY normalized_sku_id;

TRUNCATE TABLE inventory_stg.stg_dim_warehouse_latest;

INSERT INTO inventory_stg.stg_dim_warehouse_latest
SELECT
    normalized_warehouse_id AS warehouse_id,
    argMax(trim(BOTH ' ' FROM warehouse_name), parsed_created_at) AS warehouse_name,
    argMax(trim(BOTH ' ' FROM city), parsed_created_at) AS city,
    argMax(trim(BOTH ' ' FROM region), parsed_created_at) AS region,
    max(parsed_created_at) AS created_at
FROM
(
    SELECT
        *,
        upperUTF8(trim(BOTH ' ' FROM warehouse_id)) AS normalized_warehouse_id,
        parseDateTimeBestEffortOrZero(created_at) AS parsed_created_at
    FROM inventory_raw.raw_dim_warehouses
)
WHERE trim(BOTH ' ' FROM warehouse_id) != ''
GROUP BY normalized_warehouse_id;

TRUNCATE TABLE inventory_stg.stg_dim_supplier_latest;

INSERT INTO inventory_stg.stg_dim_supplier_latest
SELECT
    normalized_supplier_id AS supplier_id,
    argMax(trim(BOTH ' ' FROM supplier_name), parsed_created_at) AS supplier_name,
    argMax(trim(BOTH ' ' FROM country), parsed_created_at) AS country,
    argMax(greatest(lead_time_days, 0), parsed_created_at) AS lead_time_days,
    toDecimal64(argMax(greatest(rating, 0.), parsed_created_at), 2) AS rating,
    argMax(greatest(payment_terms_days, 0), parsed_created_at) AS payment_terms_days,
    max(parsed_created_at) AS created_at
FROM
(
    SELECT
        *,
        upperUTF8(trim(BOTH ' ' FROM supplier_id)) AS normalized_supplier_id,
        parseDateTimeBestEffortOrZero(created_at) AS parsed_created_at
    FROM inventory_raw.raw_dim_suppliers
)
WHERE trim(BOTH ' ' FROM supplier_id) != ''
GROUP BY normalized_supplier_id;

TRUNCATE TABLE inventory_stg.stg_dim_customer_latest;

INSERT INTO inventory_stg.stg_dim_customer_latest
SELECT
    normalized_customer_id AS customer_id,
    argMax(trim(BOTH ' ' FROM customer_name), parsed_created_at) AS customer_name,
    argMax(trim(BOTH ' ' FROM segment), parsed_created_at) AS segment,
    argMax(trim(BOTH ' ' FROM city), parsed_created_at) AS city,
    argMax(trim(BOTH ' ' FROM region), parsed_created_at) AS region,
    max(parsed_created_at) AS created_at
FROM
(
    SELECT
        *,
        upperUTF8(trim(BOTH ' ' FROM customer_id)) AS normalized_customer_id,
        parseDateTimeBestEffortOrZero(created_at) AS parsed_created_at
    FROM inventory_raw.raw_dim_customers
)
WHERE trim(BOTH ' ' FROM customer_id) != ''
GROUP BY normalized_customer_id;

TRUNCATE TABLE inventory_stg.stg_dim_date;

INSERT INTO inventory_stg.stg_dim_date
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
    toUInt8(if(toDayOfWeek(d) IN (6, 7), 1, 0)) AS is_weekend
FROM
(
    SELECT addDays(d0, number) AS d
    FROM numbers(days)
);

SELECT
    (SELECT count() FROM inventory_stg.stg_inventory_transactions_clean) AS stg_inventory_transactions_clean,
    (SELECT count() FROM inventory_stg.stg_inventory_snapshot_daily_clean) AS stg_inventory_snapshot_daily_clean,
    (SELECT count() FROM inventory_stg.stg_purchase_order_lines_clean) AS stg_purchase_order_lines_clean,
    (SELECT count() FROM inventory_stg.stg_sales_order_lines_clean) AS stg_sales_order_lines_clean,
    (SELECT count() FROM inventory_stg.stg_stock_counts_clean) AS stg_stock_counts_clean,
    (SELECT count() FROM inventory_stg.stg_dim_product_latest) AS stg_dim_product_latest,
    (SELECT count() FROM inventory_stg.stg_dim_warehouse_latest) AS stg_dim_warehouse_latest,
    (SELECT count() FROM inventory_stg.stg_dim_supplier_latest) AS stg_dim_supplier_latest,
    (SELECT count() FROM inventory_stg.stg_dim_customer_latest) AS stg_dim_customer_latest,
    (SELECT count() FROM inventory_stg.stg_dim_date) AS stg_dim_date;
