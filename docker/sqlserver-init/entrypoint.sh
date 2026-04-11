#!/usr/bin/env sh
set -eu

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
attempt=1
while [ "$attempt" -le 90 ]; do
  if "${SQLCMD}" -S "${HOST},${PORT}" -U "${USER_NAME}" -P "${PASSWORD}" -No -Q "SELECT 1" >/dev/null 2>&1; then
    ready=1
    break
  fi
  attempt=$((attempt + 1))
  sleep 2
done

if [ "${ready}" -ne 1 ]; then
  echo "[sqlserver-init] SQL Server is not ready in time."
  exit 1
fi

echo "[sqlserver-init] Applying schema and stored procedures..."
"${SQLCMD}" -S "${HOST},${PORT}" -U "${USER_NAME}" -P "${PASSWORD}" -No -v DB_NAME="${DATABASE}" -i /opt/bootstrap/init_inventory.sql

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

echo "[sqlserver-init] Done."
