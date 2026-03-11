USE inventory_demo;
GO

EXEC dbo.sp_insert_demo_transaction
    @warehouse_id = 'WH03',
    @sku_id = 'SKU_001',
    @event_type = 'SHIPMENT',
    @qty_change = -50,
    @event_time = SYSUTCDATETIME();
