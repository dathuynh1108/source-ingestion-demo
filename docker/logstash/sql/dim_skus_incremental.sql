SELECT
    sku_id,
    sku_name,
    category,
    subcategory,
    brand,
    uom,
    unit_cost,
    selling_price,
    status,
    reorder_point,
    safety_stock,
    max_stock,
    shelf_life_days,
    abc_class,
    CONVERT(VARCHAR(19), created_at, 120) AS created_at
FROM dbo.skus
WHERE created_at > :sql_last_value
ORDER BY created_at ASC, sku_id ASC;

