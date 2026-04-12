#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
ENV_EXAMPLE="${ROOT_DIR}/.env.example"
ENV_FILE="${ROOT_DIR}/.env"

log() { printf '%s\n' "$*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log "Missing required command: $1"
    exit 1
  }
}

wait_for() {
  local desc="$1"
  local cmd="$2"
  local timeout_s="${3:-180}"
  local start
  start="$(date +%s)"

  while true; do
    if eval "$cmd" >/dev/null 2>&1; then
      log "OK: ${desc}"
      return 0
    fi

    local now elapsed
    now="$(date +%s)"
    elapsed=$((now - start))
    if (( elapsed >= timeout_s )); then
      log "TIMEOUT after ${timeout_s}s: ${desc}"
      return 1
    fi
    sleep 3
  done
}

wait_for_optional() {
  local desc="$1"
  local cmd="$2"
  local timeout_s="${3:-180}"
  if ! wait_for "$desc" "$cmd" "$timeout_s"; then
    log "WARN: ${desc} not ready yet, continuing bootstrap."
  fi
}

verify_population_ready() {
  local counts
  counts="$(
    docker exec clickhouse_db clickhouse-client --user password --password admin --query "
SELECT
  (SELECT count() FROM inventory_raw.raw_inventory_transactions) AS raw_inventory_transactions,
  (SELECT count() FROM inventory_raw.raw_purchase_order_lines) AS raw_purchase_order_lines,
  (SELECT count() FROM inventory_raw.raw_sales_order_lines) AS raw_sales_order_lines,
  (SELECT count() FROM inventory_raw.raw_inventory_snapshot_daily) AS raw_inventory_snapshot_daily,
  (SELECT count() FROM inventory_raw.raw_stock_counts) AS raw_stock_counts,
  (SELECT count() FROM inventory_mart.dim_product) AS dim_product,
  (SELECT count() FROM inventory_mart.dim_warehouse) AS dim_warehouse,
  (SELECT count() FROM inventory_mart.dim_supplier) AS dim_supplier,
  (SELECT count() FROM inventory_mart.dim_customer) AS dim_customer,
  (SELECT count() FROM inventory_mart.dim_date) AS dim_date,
  (SELECT count() FROM inventory_mart.fact_inventory_movement) AS fact_inventory_movement,
  (SELECT count() FROM inventory_mart.fact_purchase_order_lines) AS fact_purchase_order_lines,
  (SELECT count() FROM inventory_mart.fact_sales_order_lines) AS fact_sales_order_lines,
  (SELECT count() FROM inventory_mart.fact_inventory_snapshot_daily) AS fact_inventory_snapshot_daily,
  (SELECT count() FROM inventory_mart.fact_stock_counts) AS fact_stock_counts
"
  )"

  log ""
  log "Population counts:"
  printf '%s\n' "$counts"

  set -- $counts
  if [ "$#" -ne 15 ]; then
    log "Population verification returned unexpected output."
    exit 1
  fi

  if [ "$1" -le 0 ] || [ "$2" -le 0 ] || [ "$3" -le 0 ] || [ "$4" -le 0 ] || [ "$5" -le 0 ] || \
     [ "$6" -le 0 ] || [ "$7" -le 0 ] || [ "$8" -le 0 ] || [ "$9" -le 0 ] || [ "${10}" -le 0 ] || \
     [ "${11}" -le 0 ] || [ "${12}" -le 0 ] || [ "${13}" -le 0 ] || [ "${14}" -le 0 ] || [ "${15}" -le 0 ]; then
    log "Population verification failed: one or more raw/mart tables are still empty."
    exit 1
  fi

  log "OK: ClickHouse raw and mart data are ready for Grafana."
}

require_cmd docker
require_cmd curl

if ! docker info >/dev/null 2>&1; then
  log "Docker daemon is not running. Start Docker Desktop and retry."
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  log "Missing docker compose plugin. Install Docker Desktop or docker-compose."
  exit 1
fi

cd "${ROOT_DIR}"

if [[ ! -f "${ENV_FILE}" ]]; then
  if [[ ! -f "${ENV_EXAMPLE}" ]]; then
    log "Missing .env.example at ${ENV_EXAMPLE}"
    exit 1
  fi
  cp "${ENV_EXAMPLE}" "${ENV_FILE}"
  log "Created .env from .env.example"
else
  log "Found existing .env"
fi

log ""
log "Starting stack (build + up)..."
docker compose -f "${COMPOSE_FILE}" up -d --build

log ""
log "Waiting for services to be ready..."

wait_for "kafka_broker healthy" \
  "docker inspect -f '{{.State.Health.Status}}' kafka_broker 2>/dev/null | grep -q '^healthy$'" \
  240

wait_for "sqlserver_source healthy" \
  "docker inspect -f '{{.State.Health.Status}}' sqlserver_source 2>/dev/null | grep -q '^healthy$'" \
  360

wait_for "clickhouse_db healthy" \
  "docker inspect -f '{{.State.Health.Status}}' clickhouse_db 2>/dev/null | grep -q '^healthy$'" \
  240

wait_for "kafka_init exited 0" \
  "docker inspect -f '{{.State.Status}} {{.State.ExitCode}}' kafka_init 2>/dev/null | grep -q '^exited 0$'" \
  240

wait_for "sqlserver_init exited 0" \
  "docker inspect -f '{{.State.Status}} {{.State.ExitCode}}' sqlserver_init 2>/dev/null | grep -q '^exited 0$'" \
  600

log ""
log "Refreshing mart dimensions..."
bash "${ROOT_DIR}/scripts/refresh_mart_dims.sh"

log ""
log "Refreshing mart facts..."
bash "${ROOT_DIR}/scripts/refresh_mart_facts.sh"

log ""
log "Running population checks (SQL Server + ClickHouse raw/mart)..."
bash "${ROOT_DIR}/scripts/check_population.sh"

log ""
log "Verifying Grafana data readiness..."
verify_population_ready

log ""
log "Checking application endpoints (non-blocking)..."

wait_for_optional "inventory_chatserver healthy" \
  "docker inspect -f '{{.State.Health.Status}}' inventory_chatserver 2>/dev/null | grep -q '^healthy$'" \
  240

wait_for_optional "inventory_chatui healthy" \
  "docker inspect -f '{{.State.Health.Status}}' inventory_chatui 2>/dev/null | grep -q '^healthy$'" \
  240

wait_for_optional "inventory_grafana ready" \
  "curl -fsS http://localhost:3002/api/health | grep -Eq '\"database\"[[:space:]]*:[[:space:]]*\"ok\"'" \
  300

log ""
log "Done."
log "Chat UI: http://localhost:3000"
log "Chat server docs: http://localhost:8001/docs"
log "Grafana: http://localhost:3002 (admin/admin123 by default)"
