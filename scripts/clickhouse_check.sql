SELECT
    warehouse_id,
    sku_id,
    qty_change,
    event_time,
    ingestion_time
FROM raw_inventory_transactions
ORDER BY ingestion_time DESC
LIMIT 20;
