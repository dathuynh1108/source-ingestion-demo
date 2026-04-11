TRUNCATE TABLE inventory_mart.fact_inventory_movement;

INSERT INTO
    inventory_mart.fact_inventory_movement
SELECT
    toDate (event_time) AS event_date,
    event_time,
    warehouse_id,
    sku_id,
    if (
        qty_change > 0,
        'inbound',
        if (
            qty_change < 0,
            'outbound',
            'adjustment'
        )
    ) AS event_type,
    qty_change,
    if (qty_change > 0, qty_change, 0) AS qty_in,
    if (
        qty_change < 0,
        abs(qty_change),
        0
    ) AS qty_out,
    ingestion_time
FROM inventory_raw.raw_inventory_transactions;

TRUNCATE TABLE inventory_mart.fact_inventory_snapshot_daily;

INSERT INTO
    inventory_mart.fact_inventory_snapshot_daily
SELECT
    snapshot_date,
    warehouse_id,
    sku_id,
    on_hand_qty,
    reserved_qty,
    damaged_qty,
    in_transit_qty,
    available_qty,
    toDecimal64 (inventory_value, 2) AS inventory_value,
    toDecimal64 (unit_cost, 2) AS unit_cost,
    created_at,
    ingestion_time
FROM inventory_raw.raw_inventory_snapshot_daily;

TRUNCATE TABLE inventory_mart.fact_purchase_order_lines;

INSERT INTO
    inventory_mart.fact_purchase_order_lines
SELECT
    toDate (created_at) AS created_date,
    po_id,
    po_line_id,
    line_no,
    sku_id,
    qty_ordered,
    qty_received,
    greatest(qty_ordered - qty_received, 0) AS qty_open,
    toDecimal64 (unit_cost, 2) AS unit_cost,
    line_status,
    created_at,
    ingestion_time
FROM inventory_raw.raw_purchase_order_lines;

TRUNCATE TABLE inventory_mart.fact_sales_order_lines;

INSERT INTO
    inventory_mart.fact_sales_order_lines
SELECT
    toDate (created_at) AS created_date,
    order_id,
    so_line_id,
    line_no,
    sku_id,
    qty,
    toDecimal64 (unit_price, 2) AS unit_price,
    toDecimal64 (qty * unit_price, 2) AS sales_amount,
    created_at,
    ingestion_time
FROM inventory_raw.raw_sales_order_lines;

TRUNCATE TABLE inventory_mart.fact_stock_counts;

INSERT INTO
    inventory_mart.fact_stock_counts
SELECT
    count_date,
    warehouse_id,
    sku_id,
    system_qty,
    counted_qty,
    variance_qty,
    created_at,
    ingestion_time
FROM inventory_raw.raw_stock_counts;

SELECT (
        SELECT count()
        FROM inventory_mart.fact_inventory_movement
    ) AS fact_inventory_movement,
    (
        SELECT count()
        FROM inventory_mart.fact_inventory_snapshot_daily
    ) AS fact_inventory_snapshot_daily,
    (
        SELECT count()
        FROM inventory_mart.fact_purchase_order_lines
    ) AS fact_purchase_order_lines,
    (
        SELECT count()
        FROM inventory_mart.fact_sales_order_lines
    ) AS fact_sales_order_lines,
    (
        SELECT count()
        FROM inventory_mart.fact_stock_counts
    ) AS fact_stock_counts;