SELECT
    CONVERT(VARCHAR(10), snapshot_date, 120) AS snapshot_date,
    warehouse_id,
    sku_id,
    on_hand_qty,
    reserved_qty,
    damaged_qty,
    in_transit_qty,
    available_qty,
    unit_cost = (SELECT unit_cost FROM dbo.skus s WHERE s.sku_id = isd.sku_id),
    inventory_value,
    CONVERT(VARCHAR(19), created_at, 120) AS created_at
FROM dbo.inventory_snapshot_daily isd
WHERE created_at > :sql_last_value
ORDER BY created_at ASC, snapshot_date ASC, warehouse_id ASC, sku_id ASC;

