SELECT
    customer_id,
    customer_name,
    segment,
    city,
    region,
    CONVERT(VARCHAR(19), created_at, 120) AS created_at
FROM dbo.customers
WHERE created_at > :sql_last_value
ORDER BY created_at ASC, customer_id ASC;

