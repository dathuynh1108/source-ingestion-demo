CREATE DATABASE IF NOT EXISTS inventory_db;

USE inventory_db;

-- 1. Raw data table
CREATE TABLE IF NOT EXISTS raw_inventory_transactions (
    warehouse_id String,
    sku_id String,
    qty_change Int32,
    event_time DateTime,
    ingestion_time DateTime DEFAULT now()
) ENGINE = MergeTree ()
PARTITION BY
    toYYYYMM (event_time)
ORDER BY (warehouse_id, event_time);

-- 2. Kafka engine table (member 3 contract)
CREATE TABLE IF NOT EXISTS kafka_inventory_consumer (
    warehouse_id String,
    sku_id String,
    qty_change Int32,
    event_time DateTime
) ENGINE = Kafka SETTINGS kafka_broker_list = 'kafka_broker:9092',
kafka_topic_list = 'inventory_topic',
kafka_group_name = 'clickhouse_group_1',
kafka_format = 'JSONEachRow',
kafka_skip_broken_messages = 1,
kafka_max_block_size = 1000,
kafka_poll_timeout_ms = 1000;

-- 3. Materialized view to ingest from Kafka to raw table
CREATE MATERIALIZED VIEW IF NOT EXISTS inventory_mv TO raw_inventory_transactions AS
SELECT
    warehouse_id,
    sku_id,
    qty_change,
    event_time,
    now() AS ingestion_time
FROM kafka_inventory_consumer;

-- 4. Demo dashboard data for Grafana
DROP TABLE IF EXISTS demo_inventory_snapshot;

CREATE TABLE IF NOT EXISTS demo_inventory_snapshot (
    warehouse_id LowCardinality (String),
    sku_id LowCardinality (String),
    category LowCardinality (String),
    onhand_qty UInt32,
    reserved_qty UInt32,
    reorder_point UInt32,
    last_movement_time DateTime
) ENGINE = MergeTree ()
ORDER BY (warehouse_id, sku_id);

INSERT INTO
    demo_inventory_snapshot
WITH
    [
        'WH01',
        'WH02',
        'WH03',
        'WH04',
        'WH05'
    ] AS warehouses,
    [
        'SKU_001',
        'SKU_002',
        'SKU_003',
        'SKU_004',
        'SKU_005',
        'SKU_006',
        'SKU_007',
        'SKU_008',
        'SKU_009',
        'SKU_010',
        'SKU_011',
        'SKU_012',
        'SKU_013',
        'SKU_014',
        'SKU_015',
        'SKU_016',
        'SKU_017',
        'SKU_018',
        'SKU_019',
        'SKU_020'
    ] AS skus,
    [
        'Raw Material',
        'Packaging',
        'Finished Goods',
        'Fast Moving'
    ] AS categories
SELECT
    arrayElement (
        warehouses,
        intDiv (number, 20) + 1
    ) AS warehouse_id,
    arrayElement (skus, (number % 20) + 1) AS sku_id,
    arrayElement (categories, (number % 4) + 1) AS category,
    toUInt32 (90 + (number * 37 % 460)) AS onhand_qty,
    toUInt32 (10 + (number * 11 % 90)) AS reserved_qty,
    toUInt32 (70 + (number * 13 % 140)) AS reorder_point,
    now() - toIntervalDay (number % 14) - toIntervalMinute (number % 180) AS last_movement_time
FROM numbers (100);

DROP TABLE IF EXISTS demo_inventory_movements;

CREATE TABLE IF NOT EXISTS demo_inventory_movements (
    event_time DateTime,
    warehouse_id LowCardinality (String),
    movement_type LowCardinality (String),
    qty_change Int32
) ENGINE = MergeTree ()
ORDER BY (event_time, warehouse_id);

INSERT INTO
    demo_inventory_movements
WITH
    [
        'WH01',
        'WH02',
        'WH03',
        'WH04',
        'WH05'
    ] AS warehouses,
    [
        'RECEIPT',
        'SHIPMENT',
        'ADJUSTMENT'
    ] AS movement_types
SELECT
    now() - toIntervalDay (number % 30) - toIntervalHour (number % 24) AS event_time,
    arrayElement (warehouses, (number % 5) + 1) AS warehouse_id,
    arrayElement (
        movement_types,
        (number % 3) + 1
    ) AS movement_type,
    multiIf (
        number % 5 = 0,
        -1 * (10 + (number % 40)),
        number % 2 = 0,
        15 + (number % 60),
        5 + (number % 30)
    ) AS qty_change
FROM numbers (360);