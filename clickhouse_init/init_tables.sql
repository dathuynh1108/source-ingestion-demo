-- 1. Raw data table
CREATE TABLE IF NOT EXISTS raw_inventory_transactions (
    warehouse_id String,
    sku_id String,
    qty_change Int32,
    event_time DateTime,
    ingestion_time DateTime DEFAULT now()
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (warehouse_id, event_time);

-- 2. Kafka engine table (member 3 contract)
CREATE TABLE IF NOT EXISTS kafka_inventory_consumer (
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

-- 3. Materialized view to ingest from Kafka to raw table
CREATE MATERIALIZED VIEW IF NOT EXISTS inventory_mv
TO raw_inventory_transactions AS
SELECT
    warehouse_id,
    sku_id,
    qty_change,
    event_time,
    now() AS ingestion_time
FROM kafka_inventory_consumer;
