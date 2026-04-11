# Source Ingestion Demo - Run Steps

1. Create environment file:

```bash
cp .env.example .env
```

PowerShell:

```powershell
Copy-Item .env.example .env
```

2. Start the full stack:

```bash
docker compose -f docker-compose.yml up -d --build
```

3. Start the full stack with live source generator:

```bash
docker compose -f docker-compose.yml --profile live-gen up -d --build
```

4. Check status and logs:

```bash
docker compose -f docker-compose.yml ps
docker compose -f docker-compose.yml logs -f
docker compose -f docker-compose.yml logs -f sqlserver-live-generator logstash --tail=200
```

5. Stop:

```bash
docker compose -f docker-compose.yml down
```

6. Stop and remove volumes:

```bash
docker compose -f docker-compose.yml down -v
```

7. Open Grafana:

```text
http://localhost:3000
```

Default credentials:

```text
admin / admin123
```

Grafana provisions the dashboard automatically from `grafana/dashboards/warehouse_inventory_dashboard.json`.
