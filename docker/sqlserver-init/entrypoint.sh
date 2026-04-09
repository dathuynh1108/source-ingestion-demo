#!/usr/bin/env bash
set -euo pipefail

SQLCMD="/opt/mssql-tools18/bin/sqlcmd"
HOST="${MSSQL_HOST:-sqlserver}"
PORT="${MSSQL_PORT:-1433}"
USER_NAME="${MSSQL_USER:-sa}"
PASSWORD="${MSSQL_SA_PASSWORD:?MSSQL_SA_PASSWORD is required}"
DATABASE="${MSSQL_DATABASE:-inventory_demo}"
SEED_ROWS="${SEED_ROWS:-180000}"
SEED_DAYS_BACK="${SEED_DAYS_BACK:-45}"

echo "[sqlserver-init] Waiting for SQL Server on ${HOST}:${PORT}..."

ready=0
for attempt in $(seq 1 90); do
  if "${SQLCMD}" -S "${HOST},${PORT}" -U "${USER_NAME}" -P "${PASSWORD}" -No -Q "SELECT 1" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
done

if [[ "${ready}" -ne 1 ]]; then
  echo "[sqlserver-init] SQL Server is not ready in time."
  exit 1
fi

echo "[sqlserver-init] Applying schema and stored procedures..."
# -I: QUOTED_IDENTIFIER ON (required for PERSISTED computed columns, e.g. purchase_order_lines.line_amount)
"${SQLCMD}" -S "${HOST},${PORT}" -U "${USER_NAME}" -P "${PASSWORD}" -No -I -v DB_NAME="${DATABASE}" -i /opt/bootstrap/init_inventory.sql

echo "[sqlserver-init] Seeding historical transactions if table is empty..."
"${SQLCMD}" -S "${HOST},${PORT}" -U "${USER_NAME}" -P "${PASSWORD}" -No -Q "
IF NOT EXISTS (SELECT 1 FROM ${DATABASE}.dbo.inventory_transactions)
BEGIN
    EXEC ${DATABASE}.dbo.sp_seed_inventory_transactions
        @rows = ${SEED_ROWS},
        @start_days_back = ${SEED_DAYS_BACK};
END
"

echo "[sqlserver-init] Current source volume:"
"${SQLCMD}" -S "${HOST},${PORT}" -U "${USER_NAME}" -P "${PASSWORD}" -No -Q "
SELECT COUNT(*) AS total_transactions
FROM ${DATABASE}.dbo.inventory_transactions;
"

echo "[sqlserver-init] Reporting layer (dim_date, PO, transfers) and daily fact snapshot for BI..."
"${SQLCMD}" -S "${HOST},${PORT}" -U "${USER_NAME}" -P "${PASSWORD}" -No -Q "
EXEC ${DATABASE}.dbo.sp_seed_reporting_layer;
EXEC ${DATABASE}.dbo.sp_refresh_fact_daily_inventory_movements;
EXEC ${DATABASE}.dbo.sp_refresh_inventory_snapshot_daily;
"

echo "[sqlserver-init] Done."
