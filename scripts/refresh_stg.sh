#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

docker exec -i clickhouse_db clickhouse-client --user password --password admin --multiquery < "${ROOT_DIR}/scripts/refresh_stg.sql"
