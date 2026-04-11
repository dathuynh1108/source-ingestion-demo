# Source Ingestion Demo - Run Steps (SQL Server -> Logstash -> Kafka -> ClickHouse)

This repo now includes a warehouse chat app in the same workspace:

- `apps/chatui`: Next.js UI for warehouse Q&A
- `apps/chatserver`: FastAPI + Socket.IO backend
- `apps/chatserver/warehouse_chatserver/warehouse_mcp.py`: internal MCP server for ClickHouse access

Warehouse chat app scope:

- casual Q&A over the current warehouse dataset
- inventory, low stock, overstock, replenishment, and stock movement
- no document upload flow
- no citation or customer-support workflow from the previous use case

## Quick start (recommended)

After cloning the repo and starting Docker Desktop, run:

```bash
bash scripts/bootstrap_pipeline.sh
```

This will:
- bring up the full stack (`docker-compose.yml`)
- wait for services to be ready
- populate ClickHouse **raw** (`inventory_raw.*`)
- populate ClickHouse **mart dims** (`inventory_mart.dim_*`)
- populate ClickHouse **mart facts** (`inventory_mart.fact_*`)
- start the warehouse chat backend and UI
- start Grafana with provisioned inventory dashboards
- run row-count checks (`scripts/check_population.sh`)

When bootstrap finishes:

- Chat UI: `http://localhost:3000`
- Chat server docs: `http://localhost:8001/docs`
- MCP endpoint: `http://localhost:8001/clickhouse/mcp`
- Grafana: `http://localhost:3002` (`admin` / `admin` by default)

## Manual run

### 1) Create environment file

```bash
cp .env.example .env
```

PowerShell:

```powershell
Copy-Item .env.example .env
```

### 2) Start the full stack

```bash
docker compose -f docker-compose.yml up -d --build
```

### 3) (Optional) Start live source generator

```bash
docker compose -f docker-compose.yml --profile live-gen up -d --build
```

### 4) Refresh mart dimensions (for Power BI / Grafana)

```bash
bash scripts/refresh_mart_dims.sh
```

### 5) Refresh mart facts

```bash
bash scripts/refresh_mart_facts.sh
```

### 6) Verify population (SQL Server + ClickHouse raw/mart)

```bash
bash scripts/check_population.sh
```

### 7) Open the warehouse chat app and Grafana

- UI: `http://localhost:3000`
- Backend docs: `http://localhost:8001/docs`
- Grafana: `http://localhost:3002`

If neither Azure OpenAI nor the OpenAI-compatible fallback is configured, the chat server still runs in fallback mode with warehouse-specific canned reasoning on top of ClickHouse queries.

### 8) Check status and logs

```bash
docker compose -f docker-compose.yml ps
docker compose -f docker-compose.yml logs -f
```

### 9) Stop

```bash
docker compose -f docker-compose.yml down
```

### 10) Stop and remove volumes (reset everything)

```bash
docker compose -f docker-compose.yml down -v
```

## Where to query in ClickHouse

- **Raw layer**: `inventory_raw`
- **Mart layer (Power BI connects here)**: `inventory_mart`

## Table guide

`inventory_raw` is the landing layer. Data arrives here first from Kafka with minimal reshaping.

### `inventory_raw` tables

- `raw_inventory_transactions`: inventory movement events; one row per warehouse + SKU + event time.
- `raw_purchase_order_lines`: purchase order line data for inbound and replenishment tracking; one row per PO line.
- `raw_sales_order_lines`: sales order line data for outbound demand tracking; one row per sales order line.
- `raw_inventory_snapshot_daily`: end-of-day inventory balances and valuation; one row per snapshot date + warehouse + SKU.
- `raw_stock_counts`: physical stock count results and discrepancies; one row per count event.
- `raw_dim_skus`: SKU master data such as product name, category, brand, reorder policy, and pricing; one row per SKU version landed from source.
- `raw_dim_warehouses`: warehouse master data such as warehouse name, city, and region; one row per warehouse version landed from source.
- `raw_dim_suppliers`: supplier master data such as supplier name, country, lead time, rating, and payment terms; one row per supplier version landed from source.
- `raw_dim_customers`: customer master data such as customer name, segment, city, and region; one row per customer version landed from source.

### `inventory_mart` dimension tables

- `dim_date`: calendar dimension for BI filtering and grouping by day, month, quarter, and year; one row per calendar date.
- `dim_product`: conformed product dimension built from the latest SKU master data; one row per SKU.
- `dim_warehouse`: conformed warehouse dimension built from the latest warehouse master data; one row per warehouse.
- `dim_supplier`: conformed supplier dimension built from the latest supplier master data; one row per supplier.
- `dim_customer`: conformed customer dimension built from the latest customer master data; one row per customer.

### `inventory_mart` fact tables

- `fact_inventory_movement`: inventory movement fact for inbound/outbound activity over time; one row per warehouse + SKU + event time.
- `fact_inventory_snapshot_daily`: daily inventory balance fact for stock on hand, reserved, damaged, in transit, available quantity, and value; one row per snapshot date + warehouse + SKU.
- `fact_purchase_order_lines`: procurement fact for ordered, received, and open quantities; one row per PO line.
- `fact_sales_order_lines`: demand fact for sold quantity and sales amount; one row per sales order line.
- `fact_stock_counts`: inventory accuracy fact for system quantity vs counted quantity and variance; one row per count date + warehouse + SKU.

### Notes on naming

- `dim_*` means dimension tables: descriptive or master data used to slice and label metrics.
- `fact_*` means fact tables: measurable business events such as movements, snapshots, purchases, sales, and stock counts.
- Power BI should connect to `inventory_mart`; `inventory_raw` is useful for debugging ingestion and validating landed source data.

## Grafana dashboards

Grafana is provisioned automatically at `http://localhost:3002` with the ClickHouse datasource and four inventory dashboards:

- `Inventory Executive Summary`: KPI cards, inventory value trend, inbound vs outbound trend, warehouse/category breakdowns, top low-stock and overstock items.
- `Inventory Stock Monitoring`: stock status distribution, low-stock by warehouse, current stock exception matrix, zero-stock items with recent demand, largest overstock positions.
- `Inventory Movement & Replenishment`: inbound/outbound movement, receiving vs dispatch by warehouse, top moving SKUs, slow-moving SKUs, open PO metrics, replenishment recommendations.
- `Inventory Aging & Warehouse Performance`: aging buckets, dead/slow-moving value, inventory accuracy, count variance trend, warehouse-level performance tables.

These dashboards are aligned to the main use cases in [guideline.md](/Users/huynhthanhdat/Workspace/source-ingestion-demo/guideline.md:13): executive overview, stock monitoring, movement analysis, replenishment planning, and warehouse performance.

Current data-model limits:

- Supplier lead time is available from `dim_supplier`, but supplier-linked PO performance is not, because the current purchase-order fact does not carry `supplier_id`.
- Aging and dead-stock visuals are based on days since last movement from the current mart facts. With the seeded demo data, those values may stay low unless you extend the inactivity window or seed older snapshots.
