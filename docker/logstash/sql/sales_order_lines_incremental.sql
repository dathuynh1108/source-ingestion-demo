SELECT
    so_line_id,
    order_id,
    line_no,
    sku_id,
    qty,
    unit_price,
    CONVERT(VARCHAR(19), created_at, 120) AS created_at
FROM dbo.sales_order_lines
WHERE created_at > :sql_last_value
ORDER BY created_at ASC, so_line_id ASC;

