SET NOCOUNT ON;
GO

IF DB_ID(N'$(DB_NAME)') IS NULL
BEGIN
    EXEC('CREATE DATABASE [$(DB_NAME)]');
END;
GO

USE [$(DB_NAME)];
GO

IF OBJECT_ID(N'dbo.warehouses', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.warehouses (
        warehouse_id VARCHAR(10) NOT NULL PRIMARY KEY,
        warehouse_name NVARCHAR(100) NOT NULL,
        city NVARCHAR(100) NOT NULL,
        region NVARCHAR(100) NOT NULL,
        created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()
    );
END;
GO

IF OBJECT_ID(N'dbo.skus', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.skus (
        sku_id VARCHAR(20) NOT NULL PRIMARY KEY,
        sku_name NVARCHAR(200) NOT NULL,
        category NVARCHAR(50) NOT NULL,
        unit_cost DECIMAL(18,2) NOT NULL,
        created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()
    );
END;
GO

IF OBJECT_ID(N'dbo.inventory_transactions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.inventory_transactions (
        stream_seq BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        transaction_id VARCHAR(64) NOT NULL UNIQUE,
        warehouse_id VARCHAR(10) NOT NULL,
        sku_id VARCHAR(20) NOT NULL,
        event_type VARCHAR(20) NOT NULL,
        qty_change INT NOT NULL,
        event_time DATETIME2(0) NOT NULL,
        created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        updated_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT FK_inventory_transactions_warehouse FOREIGN KEY (warehouse_id) REFERENCES dbo.warehouses(warehouse_id),
        CONSTRAINT FK_inventory_transactions_sku FOREIGN KEY (sku_id) REFERENCES dbo.skus(sku_id),
        CONSTRAINT CK_inventory_transactions_event_type CHECK (event_type IN ('RECEIPT', 'SHIPMENT', 'RETURN', 'ADJUSTMENT')),
        CONSTRAINT CK_inventory_transactions_qty_nonzero CHECK (qty_change <> 0)
    );
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_inventory_transactions_event_time'
      AND object_id = OBJECT_ID(N'dbo.inventory_transactions')
)
BEGIN
    CREATE INDEX IX_inventory_transactions_event_time
        ON dbo.inventory_transactions (event_time DESC);
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_inventory_transactions_wh_sku_event'
      AND object_id = OBJECT_ID(N'dbo.inventory_transactions')
)
BEGIN
    CREATE INDEX IX_inventory_transactions_wh_sku_event
        ON dbo.inventory_transactions (warehouse_id, sku_id, event_time DESC);
END;
GO

IF NOT EXISTS (SELECT 1 FROM dbo.warehouses)
BEGIN
    INSERT INTO dbo.warehouses (warehouse_id, warehouse_name, city, region)
    VALUES
        ('WH01', N'Warehouse 01', N'Ho Chi Minh City', N'South'),
        ('WH02', N'Warehouse 02', N'Ha Noi', N'North'),
        ('WH03', N'Warehouse 03', N'Da Nang', N'Central'),
        ('WH04', N'Warehouse 04', N'Can Tho', N'Mekong'),
        ('WH05', N'Warehouse 05', N'Hai Phong', N'Coastal');
END;
GO

IF NOT EXISTS (SELECT 1 FROM dbo.skus)
BEGIN
    ;WITH numbers AS (
        SELECT TOP (300)
            ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.all_objects
    )
    INSERT INTO dbo.skus (sku_id, sku_name, category, unit_cost)
    SELECT
        CONCAT('SKU_', RIGHT('000' + CAST(n AS VARCHAR(3)), 3)) AS sku_id,
        CONCAT(N'Product ', RIGHT('000' + CAST(n AS VARCHAR(3)), 3)) AS sku_name,
        CASE
            WHEN n % 6 = 0 THEN N'Electronics'
            WHEN n % 6 = 1 THEN N'Groceries'
            WHEN n % 6 = 2 THEN N'Fashion'
            WHEN n % 6 = 3 THEN N'Home'
            WHEN n % 6 = 4 THEN N'Health'
            ELSE N'Office'
        END AS category,
        CAST(10 + (n % 90) + ((n % 7) * 0.25) AS DECIMAL(18,2)) AS unit_cost
    FROM numbers;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_seed_inventory_transactions
    @rows INT = 180000,
    @start_days_back INT = 45
AS
BEGIN
    SET NOCOUNT ON;

    IF @rows IS NULL OR @rows < 1
        SET @rows = 1;

    IF @start_days_back IS NULL OR @start_days_back < 1
        SET @start_days_back = 1;

    ;WITH numbers AS (
        SELECT TOP (@rows)
            ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.all_objects a
        CROSS JOIN sys.all_objects b
    )
    INSERT INTO dbo.inventory_transactions (
        transaction_id,
        warehouse_id,
        sku_id,
        event_type,
        qty_change,
        event_time
    )
    SELECT
        CONCAT(
            'TX_SEED_',
            RIGHT(REPLICATE('0', 9) + CAST(n AS VARCHAR(9)), 9),
            '_',
            ABS(CHECKSUM(CONCAT('seed-', n)))
        ) AS transaction_id,
        CONCAT('WH', RIGHT('00' + CAST(((n - 1) % 5) + 1 AS VARCHAR(2)), 2)) AS warehouse_id,
        CONCAT('SKU_', RIGHT('000' + CAST(((n - 1) % 300) + 1 AS VARCHAR(3)), 3)) AS sku_id,
        CASE
            WHEN n % 20 BETWEEN 0 AND 8 THEN 'SHIPMENT'
            WHEN n % 20 BETWEEN 9 AND 16 THEN 'RECEIPT'
            WHEN n % 20 = 17 THEN 'RETURN'
            ELSE 'ADJUSTMENT'
        END AS event_type,
        CASE
            WHEN n % 20 BETWEEN 0 AND 8 THEN -1 * (5 + ABS(CHECKSUM(CONCAT('ship-', n))) % 41)
            WHEN n % 20 BETWEEN 9 AND 16 THEN 10 + ABS(CHECKSUM(CONCAT('recv-', n))) % 91
            WHEN n % 20 = 17 THEN 1 + ABS(CHECKSUM(CONCAT('ret-', n))) % 12
            ELSE
                CASE
                    WHEN n % 2 = 0 THEN 1 + ABS(CHECKSUM(CONCAT('adjp-', n))) % 10
                    ELSE -1 * (1 + ABS(CHECKSUM(CONCAT('adjn-', n))) % 10)
                END
        END AS qty_change,
        DATEADD(
            SECOND,
            ABS(CHECKSUM(CONCAT('sec-', n))) % 86400,
            DATEADD(
                DAY,
                -1 * (ABS(CHECKSUM(CONCAT('day-', n))) % @start_days_back),
                CAST(CAST(SYSUTCDATETIME() AS DATE) AS DATETIME2(0))
            )
        ) AS event_time
    FROM numbers;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_insert_live_batch
    @rows INT = 250
AS
BEGIN
    SET NOCOUNT ON;

    IF @rows IS NULL OR @rows < 1
        SET @rows = 1;

    ;WITH numbers AS (
        SELECT TOP (@rows)
            ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.all_objects
    )
    INSERT INTO dbo.inventory_transactions (
        transaction_id,
        warehouse_id,
        sku_id,
        event_type,
        qty_change,
        event_time
    )
    SELECT
        CONCAT('TX_LIVE_', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), '_', RIGHT('000000' + CAST(n AS VARCHAR(6)), 6)) AS transaction_id,
        CONCAT('WH', RIGHT('00' + CAST((random_values.rand_wh % 5) + 1 AS VARCHAR(2)), 2)) AS warehouse_id,
        CONCAT('SKU_', RIGHT('000' + CAST((random_values.rand_sku % 300) + 1 AS VARCHAR(3)), 3)) AS sku_id,
        CASE
            WHEN random_values.rand_event < 45 THEN 'SHIPMENT'
            WHEN random_values.rand_event < 85 THEN 'RECEIPT'
            WHEN random_values.rand_event < 92 THEN 'RETURN'
            ELSE 'ADJUSTMENT'
        END AS event_type,
        CASE
            WHEN random_values.rand_event < 45 THEN -1 * (5 + (random_values.rand_qty % 41))
            WHEN random_values.rand_event < 85 THEN 10 + (random_values.rand_qty % 91)
            WHEN random_values.rand_event < 92 THEN 1 + (random_values.rand_qty % 12)
            ELSE
                CASE
                    WHEN random_values.rand_sign % 2 = 0 THEN 1 + (random_values.rand_qty % 10)
                    ELSE -1 * (1 + (random_values.rand_qty % 10))
                END
        END AS qty_change,
        DATEADD(SECOND, -1 * (random_values.rand_lag % 45), SYSUTCDATETIME()) AS event_time
    FROM numbers
    CROSS APPLY (
        SELECT
            ABS(CHECKSUM(NEWID())) AS rand_wh,
            ABS(CHECKSUM(NEWID())) AS rand_sku,
            ABS(CHECKSUM(NEWID())) % 100 AS rand_event,
            ABS(CHECKSUM(NEWID())) AS rand_qty,
            ABS(CHECKSUM(NEWID())) AS rand_sign,
            ABS(CHECKSUM(NEWID())) AS rand_lag
    ) AS random_values;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_insert_demo_transaction
    @warehouse_id VARCHAR(10),
    @sku_id VARCHAR(20),
    @event_type VARCHAR(20),
    @qty_change INT,
    @event_time DATETIME2(0) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @event_time IS NULL
        SET @event_time = SYSUTCDATETIME();

    INSERT INTO dbo.inventory_transactions (
        transaction_id,
        warehouse_id,
        sku_id,
        event_type,
        qty_change,
        event_time
    )
    VALUES (
        CONCAT('TX_DEMO_', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', '')),
        @warehouse_id,
        @sku_id,
        UPPER(@event_type),
        @qty_change,
        @event_time
    );
END;
GO
