SELECT
    supplier_id,
    supplier_name,
    country,
    lead_time_days,
    rating,
    payment_terms_days,
    CONVERT(VARCHAR(19), created_at, 120) AS created_at
FROM dbo.suppliers
WHERE created_at > :sql_last_value
ORDER BY created_at ASC, supplier_id ASC;

