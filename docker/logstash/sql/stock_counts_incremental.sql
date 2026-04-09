SELECT
    count_id,
    CONVERT(VARCHAR(10), count_date, 120) AS count_date,
    warehouse_id,
    sku_id,
    system_qty,
    counted_qty,
    variance_qty,
    CONVERT(VARCHAR(19), created_at, 120) AS created_at
FROM dbo.stock_counts
WHERE created_at > :sql_last_value
ORDER BY created_at ASC, count_id ASC;

