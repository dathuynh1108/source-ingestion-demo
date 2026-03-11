USE inventory_demo;
GO

SELECT TOP 50
    stream_seq,
    warehouse_id,
    sku_id,
    event_type,
    qty_change,
    event_time
FROM dbo.inventory_transactions
ORDER BY event_time DESC, stream_seq DESC;
