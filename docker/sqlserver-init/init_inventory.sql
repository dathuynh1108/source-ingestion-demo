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

-- Enrich product master for Power BI star schema (safe to re-run)
IF COL_LENGTH('dbo.skus', 'subcategory') IS NULL
    ALTER TABLE dbo.skus ADD subcategory NVARCHAR(80) NULL;
IF COL_LENGTH('dbo.skus', 'brand') IS NULL
    ALTER TABLE dbo.skus ADD brand NVARCHAR(80) NULL;
IF COL_LENGTH('dbo.skus', 'uom') IS NULL
    ALTER TABLE dbo.skus ADD uom NVARCHAR(20) NOT NULL CONSTRAINT DF_skus_uom DEFAULT N'EA';
IF COL_LENGTH('dbo.skus', 'selling_price') IS NULL
    ALTER TABLE dbo.skus ADD selling_price DECIMAL(18,2) NULL;
IF COL_LENGTH('dbo.skus', 'status') IS NULL
    ALTER TABLE dbo.skus ADD status VARCHAR(20) NOT NULL CONSTRAINT DF_skus_status DEFAULT 'ACTIVE';
IF COL_LENGTH('dbo.skus', 'reorder_point') IS NULL
    ALTER TABLE dbo.skus ADD reorder_point INT NULL;
IF COL_LENGTH('dbo.skus', 'safety_stock') IS NULL
    ALTER TABLE dbo.skus ADD safety_stock INT NULL;
IF COL_LENGTH('dbo.skus', 'max_stock') IS NULL
    ALTER TABLE dbo.skus ADD max_stock INT NULL;
IF COL_LENGTH('dbo.skus', 'shelf_life_days') IS NULL
    ALTER TABLE dbo.skus ADD shelf_life_days INT NULL;
IF COL_LENGTH('dbo.skus', 'abc_class') IS NULL
    ALTER TABLE dbo.skus ADD abc_class CHAR(1) NULL;
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

-- Populate enriched SKU attributes when missing
UPDATE s
SET
    subcategory = ISNULL(s.subcategory,
        CASE
            WHEN s.category = N'Electronics' THEN N'Accessories'
            WHEN s.category = N'Groceries' THEN N'Packaged'
            WHEN s.category = N'Fashion' THEN N'Basics'
            WHEN s.category = N'Home' THEN N'Kitchen'
            WHEN s.category = N'Health' THEN N'Personal Care'
            ELSE N'Stationery'
        END
    ),
    brand = ISNULL(s.brand,
        CASE ABS(CHECKSUM(s.sku_id)) % 6
            WHEN 0 THEN N'Nova'
            WHEN 1 THEN N'Aurora'
            WHEN 2 THEN N'Pioneer'
            WHEN 3 THEN N'Zenith'
            WHEN 4 THEN N'Lotus'
            ELSE N'Atlas'
        END
    ),
    selling_price = ISNULL(s.selling_price, CAST(s.unit_cost * (1.25 + (ABS(CHECKSUM(CONCAT('m', s.sku_id))) % 50) / 100.0) AS DECIMAL(18,2))),
    reorder_point = ISNULL(s.reorder_point, 25 + (ABS(CHECKSUM(CONCAT('rp', s.sku_id))) % 80)),
    safety_stock = ISNULL(s.safety_stock, 10 + (ABS(CHECKSUM(CONCAT('ss', s.sku_id))) % 40)),
    max_stock = ISNULL(s.max_stock, 150 + (ABS(CHECKSUM(CONCAT('mx', s.sku_id))) % 600)),
    shelf_life_days = ISNULL(s.shelf_life_days,
        CASE
            WHEN s.category = N'Groceries' THEN 180
            WHEN s.category = N'Health' THEN 365
            ELSE 0
        END
    ),
    abc_class = ISNULL(s.abc_class,
        CASE ABS(CHECKSUM(CONCAT('abc', s.sku_id))) % 10
            WHEN 0 THEN 'A'
            WHEN 1 THEN 'A'
            WHEN 2 THEN 'B'
            WHEN 3 THEN 'B'
            WHEN 4 THEN 'B'
            ELSE 'C'
        END
    )
FROM dbo.skus s
WHERE
    s.subcategory IS NULL OR s.brand IS NULL OR s.selling_price IS NULL OR
    s.reorder_point IS NULL OR s.safety_stock IS NULL OR s.max_stock IS NULL OR
    s.shelf_life_days IS NULL OR s.abc_class IS NULL;
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

-- ---------------------------------------------------------------------------
-- Reporting / Power BI: dimensions & facts (beyond Kafka stream)
-- ---------------------------------------------------------------------------

IF OBJECT_ID(N'dbo.suppliers', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.suppliers (
        supplier_id VARCHAR(12) NOT NULL PRIMARY KEY,
        supplier_name NVARCHAR(200) NOT NULL,
        country NVARCHAR(100) NOT NULL,
        lead_time_days INT NOT NULL,
        rating DECIMAL(4,2) NOT NULL,
        payment_terms_days INT NOT NULL DEFAULT 30,
        created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT CK_suppliers_rating CHECK (rating >= 0 AND rating <= 5),
        CONSTRAINT CK_suppliers_lead CHECK (lead_time_days >= 0)
    );
END;
GO

IF OBJECT_ID(N'dbo.customers', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.customers (
        customer_id VARCHAR(12) NOT NULL PRIMARY KEY,
        customer_name NVARCHAR(200) NOT NULL,
        segment NVARCHAR(50) NOT NULL,
        city NVARCHAR(100) NOT NULL,
        region NVARCHAR(100) NOT NULL,
        created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()
    );
END;
GO

-- Sales / demand facts (for turnover, days of supply, forecasting demos)
IF OBJECT_ID(N'dbo.sales_orders', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.sales_orders (
        order_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        order_number VARCHAR(40) NOT NULL,
        customer_id VARCHAR(12) NOT NULL,
        warehouse_id VARCHAR(10) NOT NULL,
        order_date DATE NOT NULL,
        status VARCHAR(20) NOT NULL,
        created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_sales_orders_order_number UNIQUE (order_number),
        CONSTRAINT FK_so_customer FOREIGN KEY (customer_id) REFERENCES dbo.customers (customer_id),
        CONSTRAINT FK_so_warehouse FOREIGN KEY (warehouse_id) REFERENCES dbo.warehouses (warehouse_id),
        CONSTRAINT CK_so_status CHECK (status IN ('OPEN', 'SHIPPED', 'CANCELLED'))
    );
END;
GO

IF OBJECT_ID(N'dbo.sales_order_lines', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.sales_order_lines (
        so_line_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        order_id BIGINT NOT NULL,
        line_no INT NOT NULL,
        sku_id VARCHAR(20) NOT NULL,
        qty INT NOT NULL,
        unit_price DECIMAL(18,2) NOT NULL,
        line_amount AS (CAST(qty AS DECIMAL(18,2)) * unit_price) PERSISTED,
        created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT FK_sol_order FOREIGN KEY (order_id) REFERENCES dbo.sales_orders (order_id) ON DELETE CASCADE,
        CONSTRAINT FK_sol_sku FOREIGN KEY (sku_id) REFERENCES dbo.skus (sku_id),
        CONSTRAINT CK_sol_qty CHECK (qty > 0),
        CONSTRAINT UQ_sol_order_line UNIQUE (order_id, line_no)
    );
END;
GO

-- Stock count / cycle count (for inventory accuracy KPIs)
IF OBJECT_ID(N'dbo.stock_counts', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.stock_counts (
        count_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        count_date DATE NOT NULL,
        warehouse_id VARCHAR(10) NOT NULL,
        sku_id VARCHAR(20) NOT NULL,
        system_qty INT NOT NULL,
        counted_qty INT NOT NULL,
        variance_qty INT NOT NULL,
        created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT FK_sc_wh FOREIGN KEY (warehouse_id) REFERENCES dbo.warehouses (warehouse_id),
        CONSTRAINT FK_sc_sku FOREIGN KEY (sku_id) REFERENCES dbo.skus (sku_id)
    );
END;
GO

-- Daily inventory snapshot (for on-hand/available, stock status, aging base)
IF OBJECT_ID(N'dbo.inventory_snapshot_daily', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.inventory_snapshot_daily (
        snapshot_date DATE NOT NULL,
        warehouse_id VARCHAR(10) NOT NULL,
        sku_id VARCHAR(20) NOT NULL,
        on_hand_qty INT NOT NULL,
        reserved_qty INT NOT NULL,
        damaged_qty INT NOT NULL,
        in_transit_qty INT NOT NULL,
        available_qty INT NOT NULL,
        inventory_value DECIMAL(18,2) NOT NULL,
        created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_inventory_snapshot_daily PRIMARY KEY (snapshot_date, warehouse_id, sku_id),
        CONSTRAINT FK_isd_wh FOREIGN KEY (warehouse_id) REFERENCES dbo.warehouses (warehouse_id),
        CONSTRAINT FK_isd_sku FOREIGN KEY (sku_id) REFERENCES dbo.skus (sku_id),
        CONSTRAINT CK_isd_nonneg CHECK (on_hand_qty >= 0 AND reserved_qty >= 0 AND damaged_qty >= 0 AND in_transit_qty >= 0 AND available_qty >= 0)
    );
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_sales_orders_order_date' AND object_id = OBJECT_ID(N'dbo.sales_orders')
)
    CREATE INDEX IX_sales_orders_order_date ON dbo.sales_orders (order_date DESC, warehouse_id);

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_sales_order_lines_sku' AND object_id = OBJECT_ID(N'dbo.sales_order_lines')
)
    CREATE INDEX IX_sales_order_lines_sku ON dbo.sales_order_lines (sku_id);

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_stock_counts_date_wh' AND object_id = OBJECT_ID(N'dbo.stock_counts')
)
    CREATE INDEX IX_stock_counts_date_wh ON dbo.stock_counts (count_date DESC, warehouse_id);
GO

CREATE OR ALTER PROCEDURE dbo.sp_seed_sales_orders
    @order_count INT = 24000,
    @lines_min INT = 1,
    @lines_max INT = 5,
    @days_back INT = 180
AS
BEGIN
    SET NOCOUNT ON;

    IF @order_count IS NULL OR @order_count < 1 SET @order_count = 1;
    IF @lines_min IS NULL OR @lines_min < 1 SET @lines_min = 1;
    IF @lines_max IS NULL OR @lines_max < @lines_min SET @lines_max = @lines_min;
    IF @days_back IS NULL OR @days_back < 1 SET @days_back = 180;

    IF EXISTS (SELECT 1 FROM dbo.sales_orders)
        RETURN;

    DECLARE @wh_count INT = 5;
    DECLARE @sku_count INT = 300;

    ;WITH c AS (
        SELECT customer_id, ROW_NUMBER() OVER (ORDER BY customer_id) AS rn
        FROM dbo.customers
    ),
    n AS (
        SELECT TOP (@order_count)
            ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS k
        FROM sys.all_objects a
        CROSS JOIN sys.all_objects b
    )
    INSERT INTO dbo.sales_orders (order_number, customer_id, warehouse_id, order_date, status)
    SELECT
        CONCAT('SO-SEED-', RIGHT('000000' + CAST(n.k AS VARCHAR(12)), 6)) AS order_number,
        c.customer_id,
        CONCAT('WH', RIGHT('00' + CAST(((n.k - 1) % @wh_count) + 1 AS VARCHAR(2)), 2)) AS warehouse_id,
        DATEADD(DAY, -1 * (ABS(CHECKSUM(CONCAT('sod', n.k))) % @days_back), CAST(SYSUTCDATETIME() AS DATE)) AS order_date,
        CASE (n.k % 20)
            WHEN 0 THEN 'CANCELLED'
            WHEN 1 THEN 'OPEN'
            ELSE 'SHIPPED'
        END AS status
    FROM n
    INNER JOIN c ON c.rn = ((n.k - 1) % (SELECT COUNT(*) FROM dbo.customers)) + 1;

    ;WITH o AS (
        SELECT order_id, order_number,
            ABS(CHECKSUM(CONCAT('sol', order_id))) % (@lines_max - @lines_min + 1) + @lines_min AS line_cnt
        FROM dbo.sales_orders
        WHERE order_number LIKE 'SO-SEED-%'
    ),
    lines AS (
        SELECT o.order_id, v.n AS line_no, o.line_cnt
        FROM o
        INNER JOIN (SELECT TOP (20) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects) v
            ON v.n <= o.line_cnt
    )
    INSERT INTO dbo.sales_order_lines (order_id, line_no, sku_id, qty, unit_price)
    SELECT
        l.order_id,
        l.line_no,
        CONCAT('SKU_', RIGHT('000' + CAST((ABS(CHECKSUM(CONCAT(l.order_id, '-', l.line_no))) % @sku_count) + 1 AS VARCHAR(3)), 3)) AS sku_id,
        1 + ABS(CHECKSUM(CONCAT('sq', l.order_id, l.line_no))) % 12 AS qty,
        ISNULL(s.selling_price, s.unit_cost) AS unit_price
    FROM lines l
    INNER JOIN dbo.skus s ON s.sku_id = CONCAT('SKU_', RIGHT('000' + CAST((ABS(CHECKSUM(CONCAT(l.order_id, '-', l.line_no))) % @sku_count) + 1 AS VARCHAR(3)), 3));
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_refresh_inventory_snapshot_daily
    @days_back INT = 120
AS
BEGIN
    SET NOCOUNT ON;

    IF @days_back IS NULL OR @days_back < 7 SET @days_back = 120;

    DECLARE @d0 DATE = DATEADD(DAY, -1 * @days_back, CAST(SYSUTCDATETIME() AS DATE));
    DECLARE @d1 DATE = CAST(SYSUTCDATETIME() AS DATE);

    -- Refresh only recent window to keep runtime bounded
    DELETE FROM dbo.inventory_snapshot_daily
    WHERE snapshot_date BETWEEN @d0 AND @d1;

    ;WITH daily_net AS (
        SELECT
            CAST(t.event_time AS DATE) AS d,
            t.warehouse_id,
            t.sku_id,
            SUM(t.qty_change) AS net_qty
        FROM dbo.inventory_transactions t
        WHERE CAST(t.event_time AS DATE) BETWEEN @d0 AND @d1
        GROUP BY CAST(t.event_time AS DATE), t.warehouse_id, t.sku_id
    ),
    wh_sku AS (
        SELECT DISTINCT warehouse_id, sku_id FROM daily_net
    ),
    dates AS (
        SELECT full_date
        FROM dbo.dim_date
        WHERE full_date BETWEEN @d0 AND @d1
    ),
    grid AS (
        SELECT d.full_date AS snapshot_date, ws.warehouse_id, ws.sku_id
        FROM dates d
        CROSS JOIN wh_sku ws
    ),
    joined AS (
        SELECT
            g.snapshot_date,
            g.warehouse_id,
            g.sku_id,
            ISNULL(dn.net_qty, 0) AS net_qty
        FROM grid g
        LEFT JOIN daily_net dn
            ON dn.d = g.snapshot_date
           AND dn.warehouse_id = g.warehouse_id
           AND dn.sku_id = g.sku_id
    ),
    running AS (
        SELECT
            snapshot_date,
            warehouse_id,
            sku_id,
            SUM(net_qty) OVER (PARTITION BY warehouse_id, sku_id ORDER BY snapshot_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS on_hand_qty_raw
        FROM joined
    )
    INSERT INTO dbo.inventory_snapshot_daily (
        snapshot_date, warehouse_id, sku_id,
        on_hand_qty, reserved_qty, damaged_qty, in_transit_qty, available_qty,
        inventory_value
    )
    SELECT
        r.snapshot_date,
        r.warehouse_id,
        r.sku_id,
        CASE WHEN r.on_hand_qty_raw < 0 THEN 0 ELSE CAST(r.on_hand_qty_raw AS INT) END AS on_hand_qty,
        CASE
            WHEN r.on_hand_qty_raw <= 0 THEN 0
            ELSE (ABS(CHECKSUM(CONCAT('res', r.snapshot_date, r.warehouse_id, r.sku_id))) % 8)
        END AS reserved_qty,
        CASE
            WHEN r.on_hand_qty_raw <= 0 THEN 0
            ELSE (ABS(CHECKSUM(CONCAT('dam', r.snapshot_date, r.warehouse_id, r.sku_id))) % 3)
        END AS damaged_qty,
        (ABS(CHECKSUM(CONCAT('trn', r.snapshot_date, r.warehouse_id, r.sku_id))) % 12) AS in_transit_qty,
        CASE
            WHEN r.on_hand_qty_raw <= 0 THEN 0
            ELSE
                CASE
                    WHEN (r.on_hand_qty_raw
                          - (ABS(CHECKSUM(CONCAT('res', r.snapshot_date, r.warehouse_id, r.sku_id))) % 8)
                          - (ABS(CHECKSUM(CONCAT('dam', r.snapshot_date, r.warehouse_id, r.sku_id))) % 3)) < 0
                        THEN 0
                    ELSE CAST(r.on_hand_qty_raw AS INT)
                         - (ABS(CHECKSUM(CONCAT('res', r.snapshot_date, r.warehouse_id, r.sku_id))) % 8)
                         - (ABS(CHECKSUM(CONCAT('dam', r.snapshot_date, r.warehouse_id, r.sku_id))) % 3)
                END
        END AS available_qty,
        CAST(
            (CASE WHEN r.on_hand_qty_raw < 0 THEN 0 ELSE r.on_hand_qty_raw END) * ISNULL(s.unit_cost, 0)
            AS DECIMAL(18,2)
        ) AS inventory_value
    FROM running r
    INNER JOIN dbo.skus s ON s.sku_id = r.sku_id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_seed_stock_counts
    @days_back INT = 120,
    @rows_per_day INT = 250
AS
BEGIN
    SET NOCOUNT ON;

    IF @days_back IS NULL OR @days_back < 7 SET @days_back = 120;
    IF @rows_per_day IS NULL OR @rows_per_day < 1 SET @rows_per_day = 250;

    IF EXISTS (SELECT 1 FROM dbo.stock_counts)
        RETURN;

    DECLARE @d0 DATE = DATEADD(DAY, -1 * @days_back, CAST(SYSUTCDATETIME() AS DATE));
    DECLARE @d1 DATE = CAST(SYSUTCDATETIME() AS DATE);

    ;WITH dates AS (
        SELECT full_date
        FROM dbo.dim_date
        WHERE full_date BETWEEN @d0 AND @d1
    ),
    nums AS (
        SELECT TOP (@rows_per_day)
            ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.all_objects
    )
    INSERT INTO dbo.stock_counts (count_date, warehouse_id, sku_id, system_qty, counted_qty, variance_qty)
    SELECT
        d.full_date AS count_date,
        CONCAT('WH', RIGHT('00' + CAST(((ABS(CHECKSUM(CONCAT(d.full_date, '-', nums.n))) % 5) + 1) AS VARCHAR(2)), 2)) AS warehouse_id,
        CONCAT('SKU_', RIGHT('000' + CAST(((ABS(CHECKSUM(CONCAT('sku', d.full_date, '-', nums.n))) % 300) + 1) AS VARCHAR(3)), 3)) AS sku_id,
        sys_qty.system_qty,
        sys_qty.system_qty + ((ABS(CHECKSUM(CONCAT('var', d.full_date, '-', nums.n))) % 7) - 3) AS counted_qty,
        ((sys_qty.system_qty + ((ABS(CHECKSUM(CONCAT('var', d.full_date, '-', nums.n))) % 7) - 3)) - sys_qty.system_qty) AS variance_qty
    FROM dates d
    CROSS JOIN nums
    CROSS APPLY (
        SELECT 10 + (ABS(CHECKSUM(CONCAT('sys', d.full_date, '-', nums.n))) % 220) AS system_qty
    ) sys_qty;
END;
GO

IF OBJECT_ID(N'dbo.purchase_orders', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.purchase_orders (
        po_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        po_number VARCHAR(40) NOT NULL,
        supplier_id VARCHAR(12) NOT NULL,
        warehouse_id VARCHAR(10) NOT NULL,
        order_date DATE NOT NULL,
        status VARCHAR(20) NOT NULL,
        expected_delivery_date DATE NULL,
        currency CHAR(3) NOT NULL DEFAULT 'VND',
        total_amount DECIMAL(18,2) NULL,
        created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_purchase_orders_po_number UNIQUE (po_number),
        CONSTRAINT FK_po_supplier FOREIGN KEY (supplier_id) REFERENCES dbo.suppliers (supplier_id),
        CONSTRAINT FK_po_warehouse FOREIGN KEY (warehouse_id) REFERENCES dbo.warehouses (warehouse_id),
        CONSTRAINT CK_po_status CHECK (status IN ('DRAFT', 'OPEN', 'PARTIAL', 'RECEIVED', 'CLOSED', 'CANCELLED'))
    );
END;
GO

IF OBJECT_ID(N'dbo.purchase_order_lines', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.purchase_order_lines (
        po_line_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        po_id BIGINT NOT NULL,
        line_no INT NOT NULL,
        sku_id VARCHAR(20) NOT NULL,
        qty_ordered INT NOT NULL,
        qty_received INT NOT NULL DEFAULT 0,
        unit_cost DECIMAL(18,2) NOT NULL,
        line_amount AS (CAST(qty_ordered AS DECIMAL(18,2)) * unit_cost) PERSISTED,
        line_status VARCHAR(20) NOT NULL DEFAULT 'OPEN',
        created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT FK_pol_po FOREIGN KEY (po_id) REFERENCES dbo.purchase_orders (po_id) ON DELETE CASCADE,
        CONSTRAINT FK_pol_sku FOREIGN KEY (sku_id) REFERENCES dbo.skus (sku_id),
        CONSTRAINT CK_pol_qty CHECK (qty_ordered > 0),
        CONSTRAINT CK_pol_received CHECK (qty_received >= 0 AND qty_received <= qty_ordered),
        CONSTRAINT CK_pol_line_status CHECK (line_status IN ('OPEN', 'PARTIAL', 'CLOSED', 'CANCELLED')),
        CONSTRAINT UQ_pol_po_line UNIQUE (po_id, line_no)
    );
END;
GO

IF OBJECT_ID(N'dbo.inventory_transfers', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.inventory_transfers (
        transfer_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        transfer_ref VARCHAR(40) NOT NULL,
        from_warehouse_id VARCHAR(10) NOT NULL,
        to_warehouse_id VARCHAR(10) NOT NULL,
        status VARCHAR(20) NOT NULL,
        requested_at DATETIME2(0) NOT NULL,
        completed_at DATETIME2(0) NULL,
        created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_inventory_transfers_ref UNIQUE (transfer_ref),
        CONSTRAINT FK_it_from_wh FOREIGN KEY (from_warehouse_id) REFERENCES dbo.warehouses (warehouse_id),
        CONSTRAINT FK_it_to_wh FOREIGN KEY (to_warehouse_id) REFERENCES dbo.warehouses (warehouse_id),
        CONSTRAINT CK_it_wh_diff CHECK (from_warehouse_id <> to_warehouse_id),
        CONSTRAINT CK_it_status CHECK (status IN ('REQUESTED', 'PICKING', 'IN_TRANSIT', 'RECEIVED', 'CANCELLED'))
    );
END;
GO

IF OBJECT_ID(N'dbo.inventory_transfer_lines', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.inventory_transfer_lines (
        transfer_line_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        transfer_id BIGINT NOT NULL,
        sku_id VARCHAR(20) NOT NULL,
        qty INT NOT NULL,
        CONSTRAINT FK_itl_transfer FOREIGN KEY (transfer_id) REFERENCES dbo.inventory_transfers (transfer_id) ON DELETE CASCADE,
        CONSTRAINT FK_itl_sku FOREIGN KEY (sku_id) REFERENCES dbo.skus (sku_id),
        CONSTRAINT CK_itl_qty CHECK (qty > 0)
    );
END;
GO

IF OBJECT_ID(N'dbo.dim_date', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.dim_date (
        date_key INT NOT NULL PRIMARY KEY,
        full_date DATE NOT NULL,
        calendar_year SMALLINT NOT NULL,
        calendar_quarter TINYINT NOT NULL,
        calendar_month TINYINT NOT NULL,
        month_name NVARCHAR(20) NOT NULL,
        day_of_month TINYINT NOT NULL,
        day_of_week TINYINT NOT NULL,
        day_name NVARCHAR(20) NOT NULL,
        is_weekend BIT NOT NULL,
        CONSTRAINT UQ_dim_date_full UNIQUE (full_date)
    );
END;
GO

IF OBJECT_ID(N'dbo.fact_daily_inventory_movements', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.fact_daily_inventory_movements (
        movement_date DATE NOT NULL,
        warehouse_id VARCHAR(10) NOT NULL,
        sku_id VARCHAR(20) NOT NULL,
        gross_receipt_qty INT NOT NULL DEFAULT 0,
        shipment_qty INT NOT NULL DEFAULT 0,
        return_qty INT NOT NULL DEFAULT 0,
        adjustment_net_qty INT NOT NULL DEFAULT 0,
        net_qty_change INT NOT NULL,
        transaction_rows INT NOT NULL,
        CONSTRAINT PK_fact_daily_inv PRIMARY KEY (movement_date, warehouse_id, sku_id),
        CONSTRAINT FK_fdim_wh FOREIGN KEY (warehouse_id) REFERENCES dbo.warehouses (warehouse_id),
        CONSTRAINT FK_fdim_sku FOREIGN KEY (sku_id) REFERENCES dbo.skus (sku_id)
    );
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_purchase_orders_order_date' AND object_id = OBJECT_ID(N'dbo.purchase_orders')
)
    CREATE INDEX IX_purchase_orders_order_date ON dbo.purchase_orders (order_date DESC, warehouse_id);

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_purchase_orders_supplier' AND object_id = OBJECT_ID(N'dbo.purchase_orders')
)
    CREATE INDEX IX_purchase_orders_supplier ON dbo.purchase_orders (supplier_id, status);

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_pol_sku' AND object_id = OBJECT_ID(N'dbo.purchase_order_lines')
)
    CREATE INDEX IX_pol_sku ON dbo.purchase_order_lines (sku_id);

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_inventory_transfers_requested' AND object_id = OBJECT_ID(N'dbo.inventory_transfers')
)
    CREATE INDEX IX_inventory_transfers_requested ON dbo.inventory_transfers (requested_at DESC, status);

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_fact_daily_wh_date' AND object_id = OBJECT_ID(N'dbo.fact_daily_inventory_movements')
)
    CREATE INDEX IX_fact_daily_wh_date ON dbo.fact_daily_inventory_movements (warehouse_id, movement_date DESC);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.suppliers)
BEGIN
    INSERT INTO dbo.suppliers (supplier_id, supplier_name, country, lead_time_days, rating, payment_terms_days)
    VALUES
        ('SUP-VN-01', N'Alpha Components VN', N'Vietnam', 5, 4.20, 30),
        ('SUP-VN-02', N'Beta Foods Supply', N'Vietnam', 3, 4.50, 15),
        ('SUP-VN-03', N'Gamma Electronics Asia', N'Vietnam', 7, 3.90, 45),
        ('SUP-CN-01', N'Delta Manufacturing CN', N'China', 14, 4.00, 60),
        ('SUP-CN-02', N'Epsilon Textiles', N'China', 10, 3.70, 45),
        ('SUP-SG-01', N'Zeta Logistics Hub', N'Singapore', 4, 4.60, 30),
        ('SUP-JP-01', N'Eta Precision Parts', N'Japan', 12, 4.80, 45),
        ('SUP-KR-01', N'Theta Consumer Goods', N'Korea', 8, 4.10, 30),
        ('SUP-TH-01', N'Iota Agri Wholesale', N'Thailand', 6, 3.85, 30),
        ('SUP-MY-01', N'Kappa Packaging MY', N'Malaysia', 5, 4.30, 30),
        ('SUP-ID-01', N'Lambda Spices ID', N'Indonesia', 9, 3.95, 45),
        ('SUP-AU-01', N'Mu Oceania Imports', N'Australia', 18, 4.40, 60);
END;
GO

IF NOT EXISTS (SELECT 1 FROM dbo.customers)
BEGIN
    INSERT INTO dbo.customers (customer_id, customer_name, segment, city, region)
    VALUES
        ('CUS-RET-001', N'Phuong Retail Chain', N'Retail', N'Ho Chi Minh City', N'South'),
        ('CUS-RET-002', N'Minh Mart Group', N'Retail', N'Ha Noi', N'North'),
        ('CUS-RET-003', N'Lan Convenience', N'Retail', N'Da Nang', N'Central'),
        ('CUS-WHL-001', N'Thai Wholesale Co', N'Wholesale', N'Can Tho', N'Mekong'),
        ('CUS-WHL-002', N'Hung Distribution', N'Wholesale', N'Hai Phong', N'Coastal'),
        ('CUS-ECO-001', N'QuickCart Ecommerce', N'Ecommerce', N'Ho Chi Minh City', N'South'),
        ('CUS-ECO-002', N'RiverShop Online', N'Ecommerce', N'Ha Noi', N'North'),
        ('CUS-B2B-001', N'Industrial Parts Ltd', N'B2B', N'Binh Duong', N'South'),
        ('CUS-B2B-002', N'Cafe Equipment VN', N'B2B', N'Ho Chi Minh City', N'South'),
        ('CUS-B2B-003', N'Hotel Supply North', N'B2B', N'Ha Noi', N'North'),
        ('CUS-RET-004', N'Song Department Store', N'Retail', N'Hue', N'Central'),
        ('CUS-RET-005', N'Bien Pharma Retail', N'Retail', N'Vung Tau', N'South'),
        ('CUS-WHL-003', N'Dong Mekong Traders', N'Wholesale', N'Long Xuyen', N'Mekong'),
        ('CUS-ECO-003', N'FlashSale Marketplace', N'Ecommerce', N'Da Nang', N'Central'),
        ('CUS-B2B-004', N'Clinic Network VN', N'B2B', N'Ho Chi Minh City', N'South');
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_seed_dim_date
    @start_date DATE,
    @end_date DATE
AS
BEGIN
    SET NOCOUNT ON;

    IF @start_date IS NULL OR @end_date IS NULL OR @start_date > @end_date
        RETURN;

    ;WITH seq AS (
        SELECT @start_date AS d
        UNION ALL
        SELECT DATEADD(DAY, 1, d) FROM seq WHERE d < @end_date
    )
    INSERT INTO dbo.dim_date (
        date_key, full_date, calendar_year, calendar_quarter, calendar_month,
        month_name, day_of_month, day_of_week, day_name, is_weekend
    )
    SELECT
        YEAR(d) * 10000 + MONTH(d) * 100 + DAY(d) AS date_key,
        d AS full_date,
        CAST(YEAR(d) AS SMALLINT) AS calendar_year,
        CAST(DATEPART(QUARTER, d) AS TINYINT) AS calendar_quarter,
        CAST(MONTH(d) AS TINYINT) AS calendar_month,
        DATENAME(MONTH, d) AS month_name,
        CAST(DAY(d) AS TINYINT) AS day_of_month,
        CAST(((DATEPART(WEEKDAY, d) + @@DATEFIRST - 2) % 7 + 1) AS TINYINT) AS day_of_week,
        DATENAME(WEEKDAY, d) AS day_name,
        CASE
            WHEN UPPER(LEFT(DATENAME(WEEKDAY, d), 3)) IN (N'SAT', N'SUN') THEN 1
            ELSE 0
        END AS is_weekend
    FROM seq
    WHERE NOT EXISTS (SELECT 1 FROM dbo.dim_date dd WHERE dd.full_date = seq.d)
    OPTION (MAXRECURSION 32767);
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_seed_purchase_orders_and_transfers
    @po_count INT = 3200,
    @lines_per_po_min INT = 1,
    @lines_per_po_max INT = 5,
    @transfer_count INT = 900
AS
BEGIN
    SET NOCOUNT ON;

    IF @po_count IS NULL OR @po_count < 1 SET @po_count = 1;
    IF @lines_per_po_min IS NULL OR @lines_per_po_min < 1 SET @lines_per_po_min = 1;
    IF @lines_per_po_max IS NULL OR @lines_per_po_max < @lines_per_po_min SET @lines_per_po_max = @lines_per_po_min;
    IF @transfer_count IS NULL OR @transfer_count < 0 SET @transfer_count = 0;

    IF EXISTS (SELECT 1 FROM dbo.purchase_orders)
        RETURN;

    DECLARE @supplier_count INT = (SELECT COUNT(*) FROM dbo.suppliers);
    DECLARE @wh_count INT = 5;
    DECLARE @sku_count INT = 300;

    ;WITH sup_ranked AS (
        SELECT supplier_id, ROW_NUMBER() OVER (ORDER BY supplier_id) AS rn
        FROM dbo.suppliers
    ),
    n AS (
        SELECT TOP (@po_count)
            ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS k
        FROM sys.all_objects a
        CROSS JOIN sys.all_objects b
    )
    INSERT INTO dbo.purchase_orders (po_number, supplier_id, warehouse_id, order_date, status, expected_delivery_date, total_amount)
    SELECT
        CONCAT('PO-SEED-', RIGHT('000000' + CAST(n.k AS VARCHAR(12)), 6)) AS po_number,
        sr.supplier_id,
        CONCAT('WH', RIGHT('00' + CAST(((n.k - 1) % @wh_count) + 1 AS VARCHAR(2)), 2)) AS warehouse_id,
        DATEADD(DAY, -1 * (ABS(CHECKSUM(CONCAT('pod', n.k))) % 400), CAST(SYSUTCDATETIME() AS DATE)) AS order_date,
        CASE (n.k % 7)
            WHEN 0 THEN 'CLOSED'
            WHEN 1 THEN 'PARTIAL'
            WHEN 2 THEN 'OPEN'
            WHEN 3 THEN 'RECEIVED'
            ELSE 'OPEN'
        END AS status,
        DATEADD(DAY, 3 + (n.k % 10), DATEADD(DAY, -1 * (ABS(CHECKSUM(CONCAT('pod', n.k))) % 400), CAST(SYSUTCDATETIME() AS DATE))) AS expected_delivery_date,
        CAST(500 + ABS(CHECKSUM(CONCAT('poa', n.k))) % 500000 AS DECIMAL(18,2)) AS total_amount
    FROM n
    INNER JOIN sup_ranked sr ON sr.rn = ((n.k - 1) % NULLIF(@supplier_count, 0)) + 1;

    ;WITH po_ids AS (
        SELECT po_id, po_number,
            ABS(CHECKSUM(CONCAT('ln', po_id))) % (@lines_per_po_max - @lines_per_po_min + 1) + @lines_per_po_min AS line_cnt
        FROM dbo.purchase_orders
        WHERE po_number LIKE 'PO-SEED-%'
    ),
    lines AS (
        SELECT p.po_id, p.po_number, v.n AS line_no, p.line_cnt
        FROM po_ids p
        INNER JOIN (
            SELECT TOP (20) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects
        ) v ON v.n <= p.line_cnt
    )
    INSERT INTO dbo.purchase_order_lines (po_id, line_no, sku_id, qty_ordered, qty_received, unit_cost, line_status)
    SELECT
        l.po_id,
        l.line_no,
        CONCAT('SKU_', RIGHT('000' + CAST((ABS(CHECKSUM(CONCAT(l.po_id, '-', l.line_no))) % @sku_count) + 1 AS VARCHAR(3)), 3)) AS sku_id,
        10 + ABS(CHECKSUM(CONCAT('qty', l.po_id, l.line_no))) % 500 AS qty_ordered,
        CASE
            WHEN po.status IN ('RECEIVED', 'CLOSED') THEN 10 + ABS(CHECKSUM(CONCAT('qty', l.po_id, l.line_no))) % 500
            WHEN po.status = 'PARTIAL' THEN (10 + ABS(CHECKSUM(CONCAT('qty', l.po_id, l.line_no))) % 500) / 2
            ELSE 0
        END AS qty_received,
        s.unit_cost,
        CASE
            WHEN po.status IN ('RECEIVED', 'CLOSED') THEN 'CLOSED'
            WHEN po.status = 'PARTIAL' THEN 'PARTIAL'
            ELSE 'OPEN'
        END AS line_status
    FROM lines l
    INNER JOIN dbo.purchase_orders po ON po.po_id = l.po_id
    INNER JOIN dbo.skus s ON s.sku_id = CONCAT('SKU_', RIGHT('000' + CAST((ABS(CHECKSUM(CONCAT(l.po_id, '-', l.line_no))) % @sku_count) + 1 AS VARCHAR(3)), 3));

    UPDATE po
    SET total_amount = agg.line_sum
    FROM dbo.purchase_orders po
    INNER JOIN (
        SELECT pol.po_id, SUM(pol.line_amount) AS line_sum
        FROM dbo.purchase_order_lines pol
        GROUP BY pol.po_id
    ) agg ON agg.po_id = po.po_id
    WHERE po.po_number LIKE 'PO-SEED-%';

    IF @transfer_count > 0
    BEGIN
        ;WITH t AS (
            SELECT TOP (@transfer_count)
                ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS k
            FROM sys.all_objects a
            CROSS JOIN sys.all_objects b
        )
        INSERT INTO dbo.inventory_transfers (transfer_ref, from_warehouse_id, to_warehouse_id, status, requested_at, completed_at)
        SELECT
            CONCAT('TRF-SEED-', RIGHT('000000' + CAST(k AS VARCHAR(12)), 6)) AS transfer_ref,
            CONCAT('WH', RIGHT('00' + CAST(((k - 1) % @wh_count) + 1 AS VARCHAR(2)), 2)) AS from_warehouse_id,
            CONCAT('WH', RIGHT('00' + CAST(((k + 1) % @wh_count) + 1 AS VARCHAR(2)), 2)) AS to_warehouse_id,
            CASE (k % 5)
                WHEN 0 THEN 'RECEIVED'
                WHEN 1 THEN 'IN_TRANSIT'
                WHEN 2 THEN 'PICKING'
                ELSE 'REQUESTED'
            END AS status,
            DATEADD(HOUR, -1 * (k % 720), SYSUTCDATETIME()) AS requested_at,
            CASE WHEN (k % 5) = 0 THEN DATEADD(HOUR, -1 * (k % 48), SYSUTCDATETIME()) ELSE NULL END AS completed_at
        FROM t
        WHERE CONCAT('WH', RIGHT('00' + CAST(((k - 1) % @wh_count) + 1 AS VARCHAR(2)), 2))
           <> CONCAT('WH', RIGHT('00' + CAST(((k + 1) % @wh_count) + 1 AS VARCHAR(2)), 2));

        ;WITH tid AS (
            SELECT transfer_id, transfer_ref,
                ABS(CHECKSUM(CONCAT('tl', transfer_id))) % 4 + 1 AS line_cnt
            FROM dbo.inventory_transfers
            WHERE transfer_ref LIKE 'TRF-SEED-%'
        ),
        tl AS (
            SELECT t.transfer_id, v.n AS line_no, t.line_cnt
            FROM tid t
            INNER JOIN (SELECT TOP (8) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects) v
                ON v.n <= t.line_cnt
        )
        INSERT INTO dbo.inventory_transfer_lines (transfer_id, sku_id, qty)
        SELECT
            tl.transfer_id,
            CONCAT('SKU_', RIGHT('000' + CAST((ABS(CHECKSUM(CONCAT(tl.transfer_id, '-', tl.line_no))) % @sku_count) + 1 AS VARCHAR(3)), 3)),
            5 + ABS(CHECKSUM(CONCAT('tq', tl.transfer_id, tl.line_no))) % 120
        FROM tl;
    END
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_refresh_fact_daily_inventory_movements
AS
BEGIN
    SET NOCOUNT ON;

    TRUNCATE TABLE dbo.fact_daily_inventory_movements;

    INSERT INTO dbo.fact_daily_inventory_movements (
        movement_date, warehouse_id, sku_id,
        gross_receipt_qty, shipment_qty, return_qty, adjustment_net_qty,
        net_qty_change, transaction_rows
    )
    SELECT
        CAST(t.event_time AS DATE) AS movement_date,
        t.warehouse_id,
        t.sku_id,
        SUM(CASE WHEN t.event_type IN ('RECEIPT') AND t.qty_change > 0 THEN t.qty_change ELSE 0 END) AS gross_receipt_qty,
        SUM(CASE WHEN t.event_type = 'SHIPMENT' THEN ABS(t.qty_change) ELSE 0 END) AS shipment_qty,
        SUM(CASE WHEN t.event_type = 'RETURN' AND t.qty_change > 0 THEN t.qty_change ELSE 0 END) AS return_qty,
        SUM(CASE WHEN t.event_type = 'ADJUSTMENT' THEN t.qty_change ELSE 0 END) AS adjustment_net_qty,
        SUM(t.qty_change) AS net_qty_change,
        COUNT(*) AS transaction_rows
    FROM dbo.inventory_transactions t
    GROUP BY
        CAST(t.event_time AS DATE),
        t.warehouse_id,
        t.sku_id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_seed_reporting_layer
    @dim_start_days_back INT = 800,
    @dim_end_days_forward INT = 60
AS
BEGIN
    SET NOCOUNT ON;

    IF @dim_start_days_back IS NULL OR @dim_start_days_back < 30 SET @dim_start_days_back = 800;
    IF @dim_end_days_forward IS NULL SET @dim_end_days_forward = 60;

    IF NOT EXISTS (SELECT 1 FROM dbo.dim_date)
    BEGIN
        DECLARE @d0 DATE = DATEADD(DAY, -1 * @dim_start_days_back, CAST(SYSUTCDATETIME() AS DATE));
        DECLARE @d1 DATE = DATEADD(DAY, @dim_end_days_forward, CAST(SYSUTCDATETIME() AS DATE));
        EXEC dbo.sp_seed_dim_date @start_date = @d0, @end_date = @d1;
    END;

    EXEC dbo.sp_seed_purchase_orders_and_transfers
        @po_count = 3200,
        @lines_per_po_min = 1,
        @lines_per_po_max = 5,
        @transfer_count = 900;

    EXEC dbo.sp_seed_sales_orders
        @order_count = 24000,
        @lines_min = 1,
        @lines_max = 5,
        @days_back = 180;

    EXEC dbo.sp_refresh_inventory_snapshot_daily
        @days_back = 120;

    EXEC dbo.sp_seed_stock_counts
        @days_back = 120,
        @rows_per_day = 250;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_insert_live_reporting_batch
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @r INT;
    DECLARE @wh_from VARCHAR(10);
    DECLARE @wh_to VARCHAR(10);
    DECLARE @sup VARCHAR(12);
    DECLARE @wh_po VARCHAR(10);
    DECLARE @po_id BIGINT;
    DECLARE @tid BIGINT;
    DECLARE @line_cnt INT;
    DECLARE @n INT;
    DECLARE @sku VARCHAR(20);
    DECLARE @qty INT;
    DECLARE @cost DECIMAL(18,2);

    IF NOT EXISTS (SELECT 1 FROM dbo.suppliers)
        RETURN;

    SET @r = ABS(CHECKSUM(NEWID())) % 100;
    SET @wh_from = CONCAT('WH', RIGHT('00' + CAST((ABS(CHECKSUM(NEWID())) % 5) + 1 AS VARCHAR(2)), 2));
    SET @wh_to = CONCAT('WH', RIGHT('00' + CAST(((ABS(CHECKSUM(NEWID())) % 4) + CASE WHEN RIGHT(@wh_from, 1) = '1' THEN 2 ELSE 1 END) % 5 + 1 AS VARCHAR(2)), 2));
    IF @wh_to = @wh_from
        SET @wh_to = CASE @wh_from WHEN 'WH01' THEN 'WH02' WHEN 'WH02' THEN 'WH03' ELSE 'WH01' END;

    SET @sup = (SELECT TOP 1 supplier_id FROM dbo.suppliers ORDER BY NEWID());
    SET @wh_po = CONCAT('WH', RIGHT('00' + CAST((ABS(CHECKSUM(NEWID())) % 5) + 1 AS VARCHAR(2)), 2));
    SET @line_cnt = 1 + ABS(CHECKSUM(NEWID())) % 4;
    SET @n = 1;

    IF @r < 55
    BEGIN
        INSERT INTO dbo.purchase_orders (po_number, supplier_id, warehouse_id, order_date, status, expected_delivery_date, total_amount)
        VALUES (
            CONCAT('PO-LIVE-', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', '')),
            @sup,
            @wh_po,
            CAST(SYSUTCDATETIME() AS DATE),
            'OPEN',
            DATEADD(DAY, 3 + ABS(CHECKSUM(NEWID())) % 10, CAST(SYSUTCDATETIME() AS DATE)),
            NULL
        );
        SET @po_id = SCOPE_IDENTITY();

        WHILE @n <= @line_cnt
        BEGIN
            SET @sku = CONCAT('SKU_', RIGHT('000' + CAST((ABS(CHECKSUM(NEWID())) % 300) + 1 AS VARCHAR(3)), 3));
            SET @qty = 10 + ABS(CHECKSUM(NEWID())) % 180;
            SET @cost = ISNULL((SELECT unit_cost FROM dbo.skus WHERE sku_id = @sku), CAST(0 AS DECIMAL(18,2)));
            INSERT INTO dbo.purchase_order_lines (po_id, line_no, sku_id, qty_ordered, qty_received, unit_cost, line_status)
            VALUES (@po_id, @n, @sku, @qty, 0, @cost, 'OPEN');
            SET @n = @n + 1;
        END;

        UPDATE dbo.purchase_orders
        SET total_amount = (SELECT SUM(line_amount) FROM dbo.purchase_order_lines WHERE po_id = @po_id)
        WHERE po_id = @po_id;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.inventory_transfers (transfer_ref, from_warehouse_id, to_warehouse_id, status, requested_at, completed_at)
        VALUES (
            CONCAT('TRF-LIVE-', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', '')),
            @wh_from,
            @wh_to,
            CASE ABS(CHECKSUM(NEWID())) % 3 WHEN 0 THEN 'REQUESTED' WHEN 1 THEN 'IN_TRANSIT' ELSE 'PICKING' END,
            DATEADD(MINUTE, -1 * (ABS(CHECKSUM(NEWID())) % 120), SYSUTCDATETIME()),
            NULL
        );
        SET @tid = SCOPE_IDENTITY();
        SET @n = 1;
        SET @line_cnt = 1 + ABS(CHECKSUM(NEWID())) % 3;
        WHILE @n <= @line_cnt
        BEGIN
            SET @sku = CONCAT('SKU_', RIGHT('000' + CAST((ABS(CHECKSUM(NEWID())) % 300) + 1 AS VARCHAR(3)), 3));
            SET @qty = 5 + ABS(CHECKSUM(NEWID())) % 90;
            INSERT INTO dbo.inventory_transfer_lines (transfer_id, sku_id, qty) VALUES (@tid, @sku, @qty);
            SET @n = @n + 1;
        END
    END
END;
GO

CREATE OR ALTER VIEW dbo.vw_inventory_transactions_for_bi AS
SELECT
    t.stream_seq,
    t.transaction_id,
    t.event_time,
    CAST(t.event_time AS DATE) AS event_date,
    dd.date_key,
    t.warehouse_id,
    w.warehouse_name,
    w.city AS warehouse_city,
    w.region AS warehouse_region,
    t.sku_id,
    s.sku_name,
    s.category AS sku_category,
    s.unit_cost AS sku_unit_cost,
    t.event_type,
    t.qty_change,
    CASE WHEN t.qty_change > 0 THEN t.qty_change ELSE 0 END AS qty_in,
    CASE WHEN t.qty_change < 0 THEN ABS(t.qty_change) ELSE 0 END AS qty_out_abs,
    CAST(t.qty_change AS DECIMAL(18,4)) * s.unit_cost AS value_change_estimated
FROM dbo.inventory_transactions t
INNER JOIN dbo.warehouses w ON w.warehouse_id = t.warehouse_id
INNER JOIN dbo.skus s ON s.sku_id = t.sku_id
LEFT JOIN dbo.dim_date dd ON dd.full_date = CAST(t.event_time AS DATE);
GO

CREATE OR ALTER VIEW dbo.vw_purchase_order_lines_for_bi AS
SELECT
    pol.po_line_id,
    pol.po_id,
    po.po_number,
    po.order_date,
    po.status AS po_status,
    po.expected_delivery_date,
    po.currency,
    po.total_amount AS po_total_amount,
    sup.supplier_id,
    sup.supplier_name,
    sup.country AS supplier_country,
    sup.rating AS supplier_rating,
    sup.lead_time_days,
    w.warehouse_id,
    w.warehouse_name,
    w.region AS warehouse_region,
    pol.line_no,
    pol.sku_id,
    sk.sku_name,
    sk.category AS sku_category,
    pol.qty_ordered,
    pol.qty_received,
    pol.unit_cost,
    pol.line_amount,
    pol.line_status,
    pol.qty_ordered - pol.qty_received AS qty_open
FROM dbo.purchase_order_lines pol
INNER JOIN dbo.purchase_orders po ON po.po_id = pol.po_id
INNER JOIN dbo.suppliers sup ON sup.supplier_id = po.supplier_id
INNER JOIN dbo.warehouses w ON w.warehouse_id = po.warehouse_id
INNER JOIN dbo.skus sk ON sk.sku_id = pol.sku_id;
GO

CREATE OR ALTER VIEW dbo.vw_inventory_transfers_for_bi AS
SELECT
    it.transfer_id,
    it.transfer_ref,
    it.status AS transfer_status,
    it.requested_at,
    it.completed_at,
    wf.warehouse_id AS from_warehouse_id,
    wf.warehouse_name AS from_warehouse_name,
    wf.region AS from_region,
    wt.warehouse_id AS to_warehouse_id,
    wt.warehouse_name AS to_warehouse_name,
    wt.region AS to_region,
    itl.transfer_line_id,
    itl.sku_id,
    sk.sku_name,
    sk.category AS sku_category,
    itl.qty AS transfer_qty
FROM dbo.inventory_transfers it
INNER JOIN dbo.warehouses wf ON wf.warehouse_id = it.from_warehouse_id
INNER JOIN dbo.warehouses wt ON wt.warehouse_id = it.to_warehouse_id
INNER JOIN dbo.inventory_transfer_lines itl ON itl.transfer_id = it.transfer_id
INNER JOIN dbo.skus sk ON sk.sku_id = itl.sku_id;
GO

CREATE OR ALTER VIEW dbo.vw_daily_inventory_metrics AS
SELECT
    CAST(t.event_time AS DATE) AS movement_date,
    dd.date_key,
    t.warehouse_id,
    w.warehouse_name,
    w.region AS warehouse_region,
    t.sku_id,
    s.sku_name,
    s.category AS sku_category,
    SUM(CASE WHEN t.event_type IN ('RECEIPT') AND t.qty_change > 0 THEN t.qty_change ELSE 0 END) AS gross_receipt_qty,
    SUM(CASE WHEN t.event_type = 'SHIPMENT' THEN ABS(t.qty_change) ELSE 0 END) AS shipment_qty,
    SUM(CASE WHEN t.event_type = 'RETURN' AND t.qty_change > 0 THEN t.qty_change ELSE 0 END) AS return_qty,
    SUM(CASE WHEN t.event_type = 'ADJUSTMENT' THEN t.qty_change ELSE 0 END) AS adjustment_net_qty,
    SUM(t.qty_change) AS net_qty_change,
    COUNT(*) AS transaction_rows
FROM dbo.inventory_transactions t
INNER JOIN dbo.warehouses w ON w.warehouse_id = t.warehouse_id
INNER JOIN dbo.skus s ON s.sku_id = t.sku_id
LEFT JOIN dbo.dim_date dd ON dd.full_date = CAST(t.event_time AS DATE)
GROUP BY
    CAST(t.event_time AS DATE),
    dd.date_key,
    t.warehouse_id,
    w.warehouse_name,
    w.region,
    t.sku_id,
    s.sku_name,
    s.category;
GO

CREATE OR ALTER VIEW dbo.vw_fact_daily_inventory_for_bi AS
SELECT
    f.movement_date,
    dd.date_key,
    f.warehouse_id,
    w.warehouse_name,
    w.region AS warehouse_region,
    f.sku_id,
    s.sku_name,
    s.category AS sku_category,
    f.gross_receipt_qty,
    f.shipment_qty,
    f.return_qty,
    f.adjustment_net_qty,
    f.net_qty_change,
    f.transaction_rows
FROM dbo.fact_daily_inventory_movements f
INNER JOIN dbo.warehouses w ON w.warehouse_id = f.warehouse_id
INNER JOIN dbo.skus s ON s.sku_id = f.sku_id
LEFT JOIN dbo.dim_date dd ON dd.full_date = f.movement_date;
GO

CREATE OR ALTER VIEW dbo.vw_customers_for_bi AS
SELECT
    customer_id,
    customer_name,
    segment,
    city,
    region
FROM dbo.customers;
GO

CREATE OR ALTER VIEW dbo.vw_sales_order_lines_for_bi AS
SELECT
    so.order_id,
    so.order_number,
    so.order_date,
    dd.date_key,
    so.status AS order_status,
    so.customer_id,
    c.customer_name,
    c.segment AS customer_segment,
    c.region AS customer_region,
    so.warehouse_id,
    w.warehouse_name,
    w.region AS warehouse_region,
    sol.so_line_id,
    sol.line_no,
    sol.sku_id,
    s.sku_name,
    s.category AS sku_category,
    s.subcategory AS sku_subcategory,
    s.brand AS sku_brand,
    sol.qty,
    sol.unit_price,
    sol.line_amount
FROM dbo.sales_orders so
INNER JOIN dbo.sales_order_lines sol ON sol.order_id = so.order_id
INNER JOIN dbo.customers c ON c.customer_id = so.customer_id
INNER JOIN dbo.warehouses w ON w.warehouse_id = so.warehouse_id
INNER JOIN dbo.skus s ON s.sku_id = sol.sku_id
LEFT JOIN dbo.dim_date dd ON dd.full_date = so.order_date;
GO

CREATE OR ALTER VIEW dbo.vw_stock_counts_for_bi AS
SELECT
    sc.count_id,
    sc.count_date,
    dd.date_key,
    sc.warehouse_id,
    w.warehouse_name,
    w.region AS warehouse_region,
    sc.sku_id,
    s.sku_name,
    s.category AS sku_category,
    s.subcategory AS sku_subcategory,
    s.brand AS sku_brand,
    sc.system_qty,
    sc.counted_qty,
    sc.variance_qty,
    CAST(sc.variance_qty AS DECIMAL(18,4)) * s.unit_cost AS variance_value_estimated
FROM dbo.stock_counts sc
INNER JOIN dbo.warehouses w ON w.warehouse_id = sc.warehouse_id
INNER JOIN dbo.skus s ON s.sku_id = sc.sku_id
LEFT JOIN dbo.dim_date dd ON dd.full_date = sc.count_date;
GO

CREATE OR ALTER VIEW dbo.vw_inventory_snapshot_daily_for_bi AS
SELECT
    isd.snapshot_date,
    dd.date_key,
    isd.warehouse_id,
    w.warehouse_name,
    w.region AS warehouse_region,
    isd.sku_id,
    s.sku_name,
    s.category AS sku_category,
    s.subcategory AS sku_subcategory,
    s.brand AS sku_brand,
    s.uom,
    s.reorder_point,
    s.safety_stock,
    s.max_stock,
    isd.on_hand_qty,
    isd.reserved_qty,
    isd.available_qty,
    isd.damaged_qty,
    isd.in_transit_qty,
    isd.inventory_value
FROM dbo.inventory_snapshot_daily isd
INNER JOIN dbo.warehouses w ON w.warehouse_id = isd.warehouse_id
INNER JOIN dbo.skus s ON s.sku_id = isd.sku_id
LEFT JOIN dbo.dim_date dd ON dd.full_date = isd.snapshot_date;
GO
