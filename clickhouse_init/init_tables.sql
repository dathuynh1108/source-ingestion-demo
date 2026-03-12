-- 0. Database (explicit để chạy ổn trong mọi môi trường)
CREATE DATABASE IF NOT EXISTS inventory_db;

-- 1. Raw Data Table
CREATE TABLE IF NOT EXISTS inventory_db.raw_inventory_transactions (
    warehouse_id String,
    sku_id String,
    qty_change Int32,
    event_time DateTime,
    ingestion_time DateTime DEFAULT now()
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (warehouse_id, sku_id, event_time);

-- 2. Kafka Engine (Consumer)
CREATE TABLE IF NOT EXISTS inventory_db.kafka_inventory_consumer (
    warehouse_id String,
    sku_id String,
    qty_change Int32,
    event_time DateTime
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka_broker:9092',
    kafka_topic_list = 'inventory_topic',
    kafka_group_name = 'clickhouse_group_1',
    kafka_format = 'JSONEachRow',
    kafka_skip_broken_messages = 1,
    kafka_max_block_size = 1000,
    kafka_poll_timeout_ms = 1000;        

-- 3. Automation: Materialized View to ingest data from Kafka to Raw Table
CREATE MATERIALIZED VIEW IF NOT EXISTS inventory_db.inventory_mv
TO inventory_db.raw_inventory_transactions AS
SELECT
    warehouse_id,
    sku_id,
    qty_change,
    event_time,
    now() AS ingestion_time
FROM inventory_db.kafka_inventory_consumer;
