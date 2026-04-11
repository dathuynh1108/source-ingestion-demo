# Copilot instructions for `source-ingestion-demo`

## Big picture (read this first)
- This repo is an **inventory data pipeline + warehouse chat app** in one stack.
- Data flow is: **SQL Server -> Logstash JDBC -> Kafka topics -> ClickHouse raw -> ClickHouse mart -> Grafana + chatserver APIs**.
- Service wiring and ports are defined in `docker-compose.yml`.
- ClickHouse uses **databases as layers** (not schemas): `inventory_raw`, `inventory_stg`, `inventory_mart` (`clickhouse_init/init_tables.sql`).

## Core service boundaries
- `docker/logstash/pipeline/logstash.conf`: Extracts SQL Server tables incrementally via `statement_filepath` SQLs and publishes to specific Kafka topics.
- `clickhouse_init/init_tables.sql`: Creates Kafka-engine consumers + MVs into raw tables, plus mart facts/dims.
- `scripts/refresh_mart_dims.sh`: Rebuilds mart dimensions from raw master tables; run after bootstrap or source changes.
- `apps/chatserver`: FastAPI + Socket.IO + internal MCP server for ClickHouse queries.
- `apps/chatui`: Next.js chat UI consuming REST + Socket.IO events from chatserver.

## Chatserver patterns (do not break)
- Entry is `apps/chatserver/main.py` -> `warehouse_chatserver.app:create_app`.
- Socket protocol is event-based (`client_message`, `server_message`, `session`) and supports streaming chunks (`event: "chunk"`) then final `event: "message"` and `event: "response"` (`warehouse_chatserver/realtime.py`, `message_handler.py`).
- Conversation state/history is persisted in SQLite via `ConversationStore` (`warehouse_chatserver/db.py`), default path from `CHATSERVER_DATABASE_PATH`.
- LLM is optional: if no Azure/OpenAI config, agent falls back to deterministic warehouse responses (`warehouse_chatserver/warehouse_agent.py`).
- MCP HTTP mount is `/clickhouse/mcp`; tool wrappers live in `warehouse_chatserver/warehouse_mcp.py`.

## ClickHouse + SQL conventions
- Prefer querying **latest snapshot** context for inventory answers (see service methods in `warehouse_chatserver/clickhouse.py`).
- Keep SQL read-only in agent-facing paths; `run_readonly_sql` blocks mutating statements via forbidden-keyword guard in `clickhouse.py`.
- Validate DB/table identifiers (existing helper `_validate_identifier`) before dynamic SQL.
- Preserve raw/mart naming conventions like `raw_*`, `fact_*`, `dim_*`.

## Developer workflows that matter
- Recommended full startup: `bash scripts/bootstrap_pipeline.sh` (creates `.env`, builds stack, waits for health, refreshes dims, runs population checks).
- Verification: `bash scripts/check_population.sh` and `docker compose -f docker-compose.yml ps`.
- Rebuild mart dims only: `bash scripts/refresh_mart_dims.sh`.
- On Windows, run repo bash scripts through WSL/Git Bash (example already used: `wsl bash .\\scripts\\bootstrap_pipeline.sh`).

## Environment and config rules
- Chatserver settings come from `CHATSERVER_` env vars with aliases in `warehouse_chatserver/config.py`.
- UI->server integration depends on `NEXT_PUBLIC_CHATSERVER_URL`, `NEXT_PUBLIC_CHATSERVER_SOCKET_PATH`, `NEXT_PUBLIC_CHAT_NAMESPACE`.
- Keep defaults aligned with compose (`http://localhost:8001`, `/socket.io`, `warehouse`).

## When editing this repo
- Keep warehouse scope: inventory, stock health, replenishment, movement; avoid reintroducing document-upload/support workflows.
- If changing socket payload shapes, update both `apps/chatserver/warehouse_chatserver/models.py` and `apps/chatui/app/page.tsx` together.
- If changing ingestion fields, update all three layers: Logstash SQL/pipeline, ClickHouse raw/MV DDL, and mart refresh/consumers.
