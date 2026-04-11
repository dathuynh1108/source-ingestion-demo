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
- run row-count checks (`scripts/check_population.sh`)

When bootstrap finishes:

- Chat UI: `http://localhost:3000`
- Chat server docs: `http://localhost:8001/docs`
- MCP endpoint: `http://localhost:8001/clickhouse/mcp`

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

### 4) Refresh mart dimensions (for Grafana/BI reports)

```bash
bash scripts/refresh_mart_dims.sh
```

### 5) Refresh mart facts (for Grafana/BI reports)

```bash
bash scripts/refresh_mart_facts.sh
```

### 6) Verify population (SQL Server + ClickHouse raw/mart)

```bash
bash scripts/check_population.sh
```

### 7) Open the warehouse chat app

- UI: `http://localhost:3000`
- Backend docs: `http://localhost:8001/docs`

If neither Azure OpenAI nor the OpenAI-compatible fallback is configured, the chat server still runs in fallback mode with warehouse-specific canned reasoning on top of ClickHouse queries.

### 8) Check status and logs

```bash
docker compose -f docker-compose.yml ps
docker compose -f docker-compose.yml logs -f
docker compose -f docker-compose.yml logs -f sqlserver-live-generator logstash --tail=200
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

### 10). Open Grafana:

```text
http://localhost:3001
```

Default credentials:

```text
admin / admin123
```

Grafana provisions the dashboard automatically from `grafana/dashboards/warehouse_inventory_dashboard.json`.
