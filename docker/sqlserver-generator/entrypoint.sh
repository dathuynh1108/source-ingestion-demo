#!/usr/bin/env bash
set -euo pipefail

SQLCMD="/opt/mssql-tools18/bin/sqlcmd"
HOST="${MSSQL_HOST:-sqlserver}"
PORT="${MSSQL_PORT:-1433}"
USER_NAME="${MSSQL_USER:-sa}"
PASSWORD="${MSSQL_SA_PASSWORD:?MSSQL_SA_PASSWORD is required}"
DATABASE="${MSSQL_DATABASE:-inventory_demo}"
LIVE_BATCH_ROWS="${LIVE_BATCH_ROWS:-250}"
LIVE_BATCH_INTERVAL_SECONDS="${LIVE_BATCH_INTERVAL_SECONDS:-15}"

echo "[sqlserver-generator] Waiting for SQL Server on ${HOST}:${PORT}..."

ready=0
for attempt in $(seq 1 90); do
  if "${SQLCMD}" -S "${HOST},${PORT}" -U "${USER_NAME}" -P "${PASSWORD}" -No -Q "SELECT 1" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
done

if [[ "${ready}" -ne 1 ]]; then
  echo "[sqlserver-generator] SQL Server is not ready in time."
  exit 1
fi

echo "[sqlserver-generator] Starting live source generator: ${LIVE_BATCH_ROWS} rows every ${LIVE_BATCH_INTERVAL_SECONDS}s"
while true; do
  "${SQLCMD}" -S "${HOST},${PORT}" -U "${USER_NAME}" -P "${PASSWORD}" -No -Q "
  EXEC ${DATABASE}.dbo.sp_insert_live_batch @rows = ${LIVE_BATCH_ROWS};
  EXEC ${DATABASE}.dbo.sp_insert_live_reporting_batch;
  "
  sleep "${LIVE_BATCH_INTERVAL_SECONDS}"
done
