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

require_cmd docker

if ! command -v "docker" >/dev/null 2>&1; then
  log "Docker is not installed."
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  log "Docker daemon is not running. Start Docker Desktop and retry."
  exit 1
fi

if ! command -v "docker" >/dev/null 2>&1; then
  log "Missing docker CLI."
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

wait_for "inventory_chatserver healthy" \
  "docker inspect -f '{{.State.Health.Status}}' inventory_chatserver 2>/dev/null | grep -q '^healthy$'" \
  240

wait_for "inventory_chatui healthy" \
  "docker inspect -f '{{.State.Health.Status}}' inventory_chatui 2>/dev/null | grep -q '^healthy$'" \
  240

log ""
log "Refreshing mart dimensions..."
bash "${ROOT_DIR}/scripts/refresh_mart_dims.sh"

log ""
log "Running population checks (SQL Server + ClickHouse raw/mart)..."
bash "${ROOT_DIR}/scripts/check_population.sh"

log ""
log "Done."
log "Chat UI: http://localhost:3000"
log "Chat server docs: http://localhost:8001/docs"
