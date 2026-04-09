# Source Ingestion Demo - Run Steps (SQL Server → Logstash → Kafka → ClickHouse)

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
- run row-count checks (`scripts/check_population.sh`)

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

### 4) Refresh mart dimensions (for Power BI)

```bash
bash scripts/refresh_mart_dims.sh
```

### 5) Verify population (SQL Server + ClickHouse raw/mart)

```bash
bash scripts/check_population.sh
```

### 6) Check status and logs

```bash
docker compose -f docker-compose.yml ps
docker compose -f docker-compose.yml logs -f
```

### 7) Stop

```bash
docker compose -f docker-compose.yml down
```

### 8) Stop and remove volumes (reset everything)

```bash
docker compose -f docker-compose.yml down -v
```

## Where to query in ClickHouse

- **Raw layer**: `inventory_raw`
- **Mart layer (Power BI connects here)**: `inventory_mart`