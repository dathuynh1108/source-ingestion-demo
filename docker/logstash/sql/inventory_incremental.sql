SELECT
    warehouse_id,
    sku_id,
    CAST(qty_change AS INT) AS qty_change,
    CONVERT(VARCHAR(19), event_time, 120) AS event_time,
    stream_seq
FROM dbo.inventory_transactions
WHERE stream_seq > :sql_last_value
ORDER BY stream_seq ASC;
