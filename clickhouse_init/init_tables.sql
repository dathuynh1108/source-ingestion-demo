-- ---------------------------------------------------------------------------
-- Inventory demo: layered databases (raw → staging → mart)
--
-- NOTE: ClickHouse does not have "schemas" like Postgres; using databases
-- to represent layers makes it explicit and Power BI-friendly.
-- ---------------------------------------------------------------------------

CREATE DATABASE IF NOT EXISTS inventory_raw;
CREATE DATABASE IF NOT EXISTS inventory_stg;
CREATE DATABASE IF NOT EXISTS inventory_mart;

-- ---------------------------------------------------------------------------
-- RAW: landing tables and Kafka consumers
-- ---------------------------------------------------------------------------

-- 1) Raw landing table (append-only)
CREATE TABLE IF NOT EXISTS inventory_raw.raw_inventory_transactions (
    warehouse_id String,
    sku_id String,
    qty_change Int32,
    event_time DateTime,
    ingestion_time DateTime DEFAULT now()
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (warehouse_id, event_time, sku_id);

-- 2) Kafka engine table (consumer)
CREATE TABLE IF NOT EXISTS inventory_raw.kafka_inventory_consumer (
    warehouse_id String,
    sku_id String,
    qty_change Int32,
    event_time DateTime
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka_broker:9092',
    kafka_topic_list = 'inventory_topic',
    kafka_group_name = 'clickhouse_group_inventory_txn',
    kafka_format = 'JSONEachRow',
    kafka_skip_broken_messages = 1,
    kafka_max_block_size = 1000,
    kafka_poll_timeout_ms = 1000;

-- 3) Materialized view: Kafka → raw landing
CREATE MATERIALIZED VIEW IF NOT EXISTS inventory_raw.inventory_mv
TO inventory_raw.raw_inventory_transactions AS
SELECT
    warehouse_id,
    sku_id,
    qty_change,
    event_time,
    now() AS ingestion_time
FROM inventory_raw.kafka_inventory_consumer;

-- ---------------------------------------------------------------------------
-- Additional RAW sources for Power BI marts
-- ---------------------------------------------------------------------------

-- Purchase order lines (procurement)
CREATE TABLE IF NOT EXISTS inventory_raw.raw_purchase_order_lines (
    po_line_id Int64,
    po_id Int64,
    line_no Int32,
    sku_id String,
    qty_ordered Int32,
    qty_received Int32,
    unit_cost Decimal(18, 2),
    line_status String,
    created_at DateTime,
    ingestion_time DateTime DEFAULT now()
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(created_at)
ORDER BY (created_at, po_line_id);

CREATE TABLE IF NOT EXISTS inventory_raw.kafka_po_lines_consumer (
    po_line_id Int64,
    po_id Int64,
    line_no Int32,
    sku_id String,
    qty_ordered Int32,
    qty_received Int32,
    unit_cost Float64,
    line_status String,
    created_at String
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka_broker:9092',
    kafka_topic_list = 'po_lines_topic',
    kafka_group_name = 'clickhouse_group_po_lines',
    kafka_format = 'JSONEachRow',
    kafka_skip_broken_messages = 1,
    kafka_max_block_size = 1000,
    kafka_poll_timeout_ms = 1000;

CREATE MATERIALIZED VIEW IF NOT EXISTS inventory_raw.po_lines_mv
TO inventory_raw.raw_purchase_order_lines AS
WITH parseDateTimeBestEffortOrNull(inventory_raw.kafka_po_lines_consumer.created_at) AS created_at_dt
SELECT
    po_line_id,
    po_id,
    line_no,
    sku_id,
    qty_ordered,
    qty_received,
    toDecimal64(unit_cost, 2) AS unit_cost,
    line_status,
    created_at_dt AS created_at,
    now() AS ingestion_time
FROM inventory_raw.kafka_po_lines_consumer
WHERE created_at_dt IS NOT NULL;

-- Sales order lines (demand)
CREATE TABLE IF NOT EXISTS inventory_raw.raw_sales_order_lines (
    so_line_id Int64,
    order_id Int64,
    line_no Int32,
    sku_id String,
    qty Int32,
    unit_price Decimal(18, 2),
    created_at DateTime,
    ingestion_time DateTime DEFAULT now()
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(created_at)
ORDER BY (created_at, so_line_id);

CREATE TABLE IF NOT EXISTS inventory_raw.kafka_sales_lines_consumer (
    so_line_id Int64,
    order_id Int64,
    line_no Int32,
    sku_id String,
    qty Int32,
    unit_price Float64,
    created_at String
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka_broker:9092',
    kafka_topic_list = 'sales_lines_topic',
    kafka_group_name = 'clickhouse_group_sales_lines',
    kafka_format = 'JSONEachRow',
    kafka_skip_broken_messages = 1,
    kafka_max_block_size = 1000,
    kafka_poll_timeout_ms = 1000;

CREATE MATERIALIZED VIEW IF NOT EXISTS inventory_raw.sales_lines_mv
TO inventory_raw.raw_sales_order_lines AS
WITH parseDateTimeBestEffortOrNull(inventory_raw.kafka_sales_lines_consumer.created_at) AS created_at_dt
SELECT
    so_line_id,
    order_id,
    line_no,
    sku_id,
    qty,
    toDecimal64(unit_price, 2) AS unit_price,
    created_at_dt AS created_at,
    now() AS ingestion_time
FROM inventory_raw.kafka_sales_lines_consumer
WHERE created_at_dt IS NOT NULL;

-- Daily inventory snapshot (on-hand / available)
CREATE TABLE IF NOT EXISTS inventory_raw.raw_inventory_snapshot_daily (
    snapshot_date Date,
    warehouse_id String,
    sku_id String,
    on_hand_qty Int32,
    reserved_qty Int32,
    damaged_qty Int32,
    in_transit_qty Int32,
    available_qty Int32,
    unit_cost Decimal(18, 2),
    inventory_value Decimal(18, 2),
    created_at DateTime,
    ingestion_time DateTime DEFAULT now()
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(snapshot_date)
ORDER BY (snapshot_date, warehouse_id, sku_id);

CREATE TABLE IF NOT EXISTS inventory_raw.kafka_snapshot_consumer (
    snapshot_date String,
    warehouse_id String,
    sku_id String,
    on_hand_qty Int32,
    reserved_qty Int32,
    damaged_qty Int32,
    in_transit_qty Int32,
    available_qty Int32,
    unit_cost Float64,
    inventory_value Float64,
    created_at String
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka_broker:9092',
    kafka_topic_list = 'snapshot_topic',
    kafka_group_name = 'clickhouse_group_snapshot',
    kafka_format = 'JSONEachRow',
    kafka_skip_broken_messages = 1,
    kafka_max_block_size = 2000,
    kafka_poll_timeout_ms = 1000;

CREATE MATERIALIZED VIEW IF NOT EXISTS inventory_raw.snapshot_mv
TO inventory_raw.raw_inventory_snapshot_daily AS
SELECT
    toDate(parseDateTimeBestEffortOrNull(inventory_raw.kafka_snapshot_consumer.snapshot_date)) AS snapshot_date,
    warehouse_id,
    sku_id,
    on_hand_qty,
    reserved_qty,
    damaged_qty,
    in_transit_qty,
    available_qty,
    toDecimal64(unit_cost, 2) AS unit_cost,
    toDecimal64(inventory_value, 2) AS inventory_value,
    parseDateTimeBestEffortOrNull(inventory_raw.kafka_snapshot_consumer.created_at) AS created_at,
    now() AS ingestion_time
FROM inventory_raw.kafka_snapshot_consumer
WHERE parseDateTimeBestEffortOrNull(inventory_raw.kafka_snapshot_consumer.snapshot_date) IS NOT NULL
  AND parseDateTimeBestEffortOrNull(inventory_raw.kafka_snapshot_consumer.created_at) IS NOT NULL;

-- Stock counts (accuracy)
CREATE TABLE IF NOT EXISTS inventory_raw.raw_stock_counts (
    count_id Int64,
    count_date Date,
    warehouse_id String,
    sku_id String,
    system_qty Int32,
    counted_qty Int32,
    variance_qty Int32,
    created_at DateTime,
    ingestion_time DateTime DEFAULT now()
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(count_date)
ORDER BY (count_date, count_id);

CREATE TABLE IF NOT EXISTS inventory_raw.kafka_stock_counts_consumer (
    count_id Int64,
    count_date String,
    warehouse_id String,
    sku_id String,
    system_qty Int32,
    counted_qty Int32,
    variance_qty Int32,
    created_at String
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka_broker:9092',
    kafka_topic_list = 'stock_counts_topic',
    kafka_group_name = 'clickhouse_group_stock_counts',
    kafka_format = 'JSONEachRow',
    kafka_skip_broken_messages = 1,
    kafka_max_block_size = 2000,
    kafka_poll_timeout_ms = 1000;

CREATE MATERIALIZED VIEW IF NOT EXISTS inventory_raw.stock_counts_mv
TO inventory_raw.raw_stock_counts AS
SELECT
    count_id,
    toDate(parseDateTimeBestEffortOrNull(inventory_raw.kafka_stock_counts_consumer.count_date)) AS count_date,
    warehouse_id,
    sku_id,
    system_qty,
    counted_qty,
    variance_qty,
    parseDateTimeBestEffortOrNull(inventory_raw.kafka_stock_counts_consumer.created_at) AS created_at,
    now() AS ingestion_time
FROM inventory_raw.kafka_stock_counts_consumer
WHERE parseDateTimeBestEffortOrNull(inventory_raw.kafka_stock_counts_consumer.count_date) IS NOT NULL
  AND parseDateTimeBestEffortOrNull(inventory_raw.kafka_stock_counts_consumer.created_at) IS NOT NULL;

-- ---------------------------------------------------------------------------
-- RAW dimensions: land master data for marts
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS inventory_raw.raw_dim_skus (
    sku_id String,
    sku_name String,
    category String,
    subcategory String,
    brand String,
    uom String,
    unit_cost Float64,
    selling_price Float64,
    status String,
    reorder_point Int32,
    safety_stock Int32,
    max_stock Int32,
    shelf_life_days Int32,
    abc_class String,
    created_at String,
    ingestion_time DateTime DEFAULT now()
)
ENGINE = MergeTree()
ORDER BY (sku_id);

CREATE TABLE IF NOT EXISTS inventory_raw.kafka_dim_skus_consumer (
    sku_id String,
    sku_name String,
    category String,
    subcategory String,
    brand String,
    uom String,
    unit_cost Float64,
    selling_price Float64,
    status String,
    reorder_point Int32,
    safety_stock Int32,
    max_stock Int32,
    shelf_life_days Int32,
    abc_class String,
    created_at String
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka_broker:9092',
    kafka_topic_list = 'dim_skus_topic',
    kafka_group_name = 'clickhouse_group_dim_skus_v1',
    kafka_format = 'JSONEachRow',
    kafka_skip_broken_messages = 1,
    kafka_max_block_size = 2000,
    kafka_poll_timeout_ms = 1000;

CREATE MATERIALIZED VIEW IF NOT EXISTS inventory_raw.dim_skus_mv
TO inventory_raw.raw_dim_skus AS
SELECT
    sku_id, sku_name, category, subcategory, brand, uom,
    unit_cost, selling_price, status,
    reorder_point, safety_stock, max_stock, shelf_life_days, abc_class,
    created_at,
    now() AS ingestion_time
FROM inventory_raw.kafka_dim_skus_consumer;

CREATE TABLE IF NOT EXISTS inventory_raw.raw_dim_warehouses (
    warehouse_id String,
    warehouse_name String,
    city String,
    region String,
    created_at String,
    ingestion_time DateTime DEFAULT now()
)
ENGINE = MergeTree()
ORDER BY (warehouse_id);

CREATE TABLE IF NOT EXISTS inventory_raw.kafka_dim_warehouses_consumer (
    warehouse_id String,
    warehouse_name String,
    city String,
    region String,
    created_at String
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka_broker:9092',
    kafka_topic_list = 'dim_warehouses_topic',
    kafka_group_name = 'clickhouse_group_dim_warehouses_v1',
    kafka_format = 'JSONEachRow',
    kafka_skip_broken_messages = 1,
    kafka_max_block_size = 1000,
    kafka_poll_timeout_ms = 1000;

CREATE MATERIALIZED VIEW IF NOT EXISTS inventory_raw.dim_warehouses_mv
TO inventory_raw.raw_dim_warehouses AS
SELECT
    warehouse_id, warehouse_name, city, region, created_at, now() AS ingestion_time
FROM inventory_raw.kafka_dim_warehouses_consumer;

CREATE TABLE IF NOT EXISTS inventory_raw.raw_dim_suppliers (
    supplier_id String,
    supplier_name String,
    country String,
    lead_time_days Int32,
    rating Float64,
    payment_terms_days Int32,
    created_at String,
    ingestion_time DateTime DEFAULT now()
)
ENGINE = MergeTree()
ORDER BY (supplier_id);

CREATE TABLE IF NOT EXISTS inventory_raw.kafka_dim_suppliers_consumer (
    supplier_id String,
    supplier_name String,
    country String,
    lead_time_days Int32,
    rating Float64,
    payment_terms_days Int32,
    created_at String
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka_broker:9092',
    kafka_topic_list = 'dim_suppliers_topic',
    kafka_group_name = 'clickhouse_group_dim_suppliers_v1',
    kafka_format = 'JSONEachRow',
    kafka_skip_broken_messages = 1,
    kafka_max_block_size = 1000,
    kafka_poll_timeout_ms = 1000;

CREATE MATERIALIZED VIEW IF NOT EXISTS inventory_raw.dim_suppliers_mv
TO inventory_raw.raw_dim_suppliers AS
SELECT
    supplier_id, supplier_name, country, lead_time_days, rating, payment_terms_days,
    created_at, now() AS ingestion_time
FROM inventory_raw.kafka_dim_suppliers_consumer;

CREATE TABLE IF NOT EXISTS inventory_raw.raw_dim_customers (
    customer_id String,
    customer_name String,
    segment String,
    city String,
    region String,
    created_at String,
    ingestion_time DateTime DEFAULT now()
)
ENGINE = MergeTree()
ORDER BY (customer_id);

CREATE TABLE IF NOT EXISTS inventory_raw.kafka_dim_customers_consumer (
    customer_id String,
    customer_name String,
    segment String,
    city String,
    region String,
    created_at String
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka_broker:9092',
    kafka_topic_list = 'dim_customers_topic',
    kafka_group_name = 'clickhouse_group_dim_customers_v1',
    kafka_format = 'JSONEachRow',
    kafka_skip_broken_messages = 1,
    kafka_max_block_size = 1000,
    kafka_poll_timeout_ms = 1000;

CREATE MATERIALIZED VIEW IF NOT EXISTS inventory_raw.dim_customers_mv
TO inventory_raw.raw_dim_customers AS
SELECT
    customer_id, customer_name, segment, city, region, created_at, now() AS ingestion_time
FROM inventory_raw.kafka_dim_customers_consumer;

-- ---------------------------------------------------------------------------
-- STAGING: normalized and latest-state tables between raw and mart
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS inventory_stg.stg_inventory_transactions_clean (
    event_date Date,
    event_time DateTime,
    warehouse_id String,
    sku_id String,
    qty_change Int32,
    event_type String,
    qty_in Int32,
    qty_out Int32,
    ingestion_time DateTime
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_date)
ORDER BY (event_date, warehouse_id, sku_id, event_time);

CREATE TABLE IF NOT EXISTS inventory_stg.stg_inventory_snapshot_daily_clean (
    snapshot_date Date,
    warehouse_id String,
    sku_id String,
    on_hand_qty Int32,
    reserved_qty Int32,
    damaged_qty Int32,
    in_transit_qty Int32,
    available_qty Int32,
    inventory_value Decimal(18,2),
    unit_cost Decimal(18,2),
    created_at DateTime,
    ingestion_time DateTime
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(snapshot_date)
ORDER BY (snapshot_date, warehouse_id, sku_id);

CREATE TABLE IF NOT EXISTS inventory_stg.stg_purchase_order_lines_clean (
    created_date Date,
    po_id Int64,
    po_line_id Int64,
    line_no Int32,
    sku_id String,
    qty_ordered Int32,
    qty_received Int32,
    qty_open Int32,
    unit_cost Decimal(18,2),
    line_status String,
    created_at DateTime,
    ingestion_time DateTime
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(created_date)
ORDER BY (created_date, po_id, po_line_id);

CREATE TABLE IF NOT EXISTS inventory_stg.stg_sales_order_lines_clean (
    created_date Date,
    order_id Int64,
    so_line_id Int64,
    line_no Int32,
    sku_id String,
    qty Int32,
    unit_price Decimal(18,2),
    sales_amount Decimal(18,2),
    created_at DateTime,
    ingestion_time DateTime
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(created_date)
ORDER BY (created_date, order_id, so_line_id);

CREATE TABLE IF NOT EXISTS inventory_stg.stg_stock_counts_clean (
    count_date Date,
    warehouse_id String,
    sku_id String,
    system_qty Int32,
    counted_qty Int32,
    variance_qty Int32,
    created_at DateTime,
    ingestion_time DateTime
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(count_date)
ORDER BY (count_date, warehouse_id, sku_id);

CREATE TABLE IF NOT EXISTS inventory_stg.stg_dim_product_latest (
    sku_id String,
    sku_name String,
    category String,
    subcategory String,
    brand String,
    uom String,
    unit_cost Decimal(18,2),
    selling_price Decimal(18,2),
    status String,
    reorder_point Int32,
    safety_stock Int32,
    max_stock Int32,
    shelf_life_days Int32,
    abc_class String,
    created_at DateTime
)
ENGINE = MergeTree
ORDER BY (sku_id);

CREATE TABLE IF NOT EXISTS inventory_stg.stg_dim_warehouse_latest (
    warehouse_id String,
    warehouse_name String,
    city String,
    region String,
    created_at DateTime
)
ENGINE = MergeTree
ORDER BY (warehouse_id);

CREATE TABLE IF NOT EXISTS inventory_stg.stg_dim_supplier_latest (
    supplier_id String,
    supplier_name String,
    country String,
    lead_time_days Int32,
    rating Decimal(4,2),
    payment_terms_days Int32,
    created_at DateTime
)
ENGINE = MergeTree
ORDER BY (supplier_id);

CREATE TABLE IF NOT EXISTS inventory_stg.stg_dim_customer_latest (
    customer_id String,
    customer_name String,
    segment String,
    city String,
    region String,
    created_at DateTime
)
ENGINE = MergeTree
ORDER BY (customer_id);

CREATE TABLE IF NOT EXISTS inventory_stg.stg_dim_date (
    date_key UInt32,
    full_date Date,
    calendar_year UInt16,
    calendar_quarter UInt8,
    calendar_month UInt8,
    month_name String,
    day_of_month UInt8,
    day_of_week UInt8,
    day_name String,
    is_weekend UInt8
)
ENGINE = MergeTree
ORDER BY (full_date);

-- ---------------------------------------------------------------------------
-- MART: star schema tables (Power BI connects here)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS inventory_mart.dim_date (
    date_key UInt32,
    full_date Date,
    calendar_year UInt16,
    calendar_quarter UInt8,
    calendar_month UInt8,
    month_name String,
    day_of_month UInt8,
    day_of_week UInt8,
    day_name String,
    is_weekend UInt8
)
ENGINE = MergeTree
ORDER BY (full_date);

CREATE TABLE IF NOT EXISTS inventory_mart.dim_warehouse (
    warehouse_id String,
    warehouse_name String,
    city String,
    region String,
    created_at DateTime
)
ENGINE = MergeTree
ORDER BY (warehouse_id);

CREATE TABLE IF NOT EXISTS inventory_mart.dim_product (
    sku_id String,
    sku_name String,
    category String,
    subcategory String,
    brand String,
    uom String,
    unit_cost Decimal(18,2),
    selling_price Decimal(18,2),
    status String,
    reorder_point Int32,
    safety_stock Int32,
    max_stock Int32,
    shelf_life_days Int32,
    abc_class String,
    created_at DateTime
)
ENGINE = MergeTree
ORDER BY (sku_id);

CREATE TABLE IF NOT EXISTS inventory_mart.dim_supplier (
    supplier_id String,
    supplier_name String,
    country String,
    lead_time_days Int32,
    rating Decimal(4,2),
    payment_terms_days Int32,
    created_at DateTime
)
ENGINE = MergeTree
ORDER BY (supplier_id);

CREATE TABLE IF NOT EXISTS inventory_mart.dim_customer (
    customer_id String,
    customer_name String,
    segment String,
    city String,
    region String,
    created_at DateTime
)
ENGINE = MergeTree
ORDER BY (customer_id);

CREATE TABLE IF NOT EXISTS inventory_mart.fact_inventory_movement (
    event_date Date,
    event_time DateTime,
    warehouse_id String,
    sku_id String,
    event_type String,
    qty_change Int32,
    qty_in Int32,
    qty_out Int32,
    ingestion_time DateTime
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_date)
ORDER BY (event_date, warehouse_id, sku_id, event_time);

CREATE TABLE IF NOT EXISTS inventory_mart.fact_inventory_snapshot_daily (
    snapshot_date Date,
    warehouse_id String,
    sku_id String,
    on_hand_qty Int32,
    reserved_qty Int32,
    damaged_qty Int32,
    in_transit_qty Int32,
    available_qty Int32,
    inventory_value Decimal(18,2),
    unit_cost Decimal(18,2),
    created_at DateTime,
    ingestion_time DateTime
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(snapshot_date)
ORDER BY (snapshot_date, warehouse_id, sku_id);

CREATE TABLE IF NOT EXISTS inventory_mart.fact_purchase_order_lines (
    created_date Date,
    po_id Int64,
    po_line_id Int64,
    line_no Int32,
    sku_id String,
    qty_ordered Int32,
    qty_received Int32,
    qty_open Int32,
    unit_cost Decimal(18,2),
    line_status String,
    created_at DateTime,
    ingestion_time DateTime
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(created_date)
ORDER BY (created_date, po_id, po_line_id);

CREATE TABLE IF NOT EXISTS inventory_mart.fact_sales_order_lines (
    created_date Date,
    order_id Int64,
    so_line_id Int64,
    line_no Int32,
    sku_id String,
    qty Int32,
    unit_price Decimal(18,2),
    sales_amount Decimal(18,2),
    created_at DateTime,
    ingestion_time DateTime
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(created_date)
ORDER BY (created_date, order_id, so_line_id);

CREATE TABLE IF NOT EXISTS inventory_mart.fact_stock_counts (
    count_date Date,
    warehouse_id String,
    sku_id String,
    system_qty Int32,
    counted_qty Int32,
    variance_qty Int32,
    created_at DateTime,
    ingestion_time DateTime
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(count_date)
ORDER BY (count_date, warehouse_id, sku_id);
