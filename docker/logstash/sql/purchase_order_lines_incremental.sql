SELECT
    po_line_id,
    po_id,
    line_no,
    sku_id,
    qty_ordered,
    qty_received,
    unit_cost,
    line_status,
    CONVERT(VARCHAR(19), created_at, 120) AS created_at
FROM dbo.purchase_order_lines
WHERE created_at > :sql_last_value
ORDER BY created_at ASC, po_line_id ASC;

