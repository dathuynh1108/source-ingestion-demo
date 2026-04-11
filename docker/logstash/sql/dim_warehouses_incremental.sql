SELECT
    warehouse_id,
    warehouse_name,
    city,
    region,
    CONVERT(VARCHAR(19), created_at, 120) AS created_at
FROM dbo.warehouses
WHERE created_at > :sql_last_value
ORDER BY created_at ASC, warehouse_id ASC;

