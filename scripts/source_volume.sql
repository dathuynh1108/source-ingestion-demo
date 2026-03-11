USE inventory_demo;
GO

SELECT
    COUNT(*) AS total_transactions,
    COUNT(DISTINCT warehouse_id) AS warehouse_count,
    COUNT(DISTINCT sku_id) AS sku_count,
    MIN(event_time) AS min_event_time,
    MAX(event_time) AS max_event_time
FROM dbo.inventory_transactions;

SELECT
    warehouse_id,
    COUNT(*) AS txn_count
FROM dbo.inventory_transactions
GROUP BY warehouse_id
ORDER BY warehouse_id;
