#!/bin/bash
set -e

PRIMARY="primary"
REPLICA="replica"
ROOT_PASS="${MARIADB_ROOT_PASSWORD}"
REPL_USER="repl_user"
REPL_PASS="${REPLICATOR_PASSWORD}"

echo "=== MariaDB Replication Setup ==="

# Wait for primary to be ready
echo "Waiting for primary..."
for i in $(seq 1 60); do
  if mariadb -h "$PRIMARY" -u root -p"$ROOT_PASS" -e "SELECT 1" > /dev/null 2>&1; then
    echo "  Primary is ready!"
    break
  fi
  echo "  Waiting... ($i/60)"
  sleep 2
done

# Wait for replica to be ready
echo "Waiting for replica..."
for i in $(seq 1 60); do
  if mariadb -h "$REPLICA" -u root -p"$ROOT_PASS" -e "SELECT 1" > /dev/null 2>&1; then
    echo "  Replica is ready!"
    break
  fi
  echo "  Waiting... ($i/60)"
  sleep 2
done

# Check if replication is already configured
ALREADY_RUNNING=$(mariadb -h "$REPLICA" -u root -p"$ROOT_PASS" -e "SHOW SLAVE STATUS\G" 2>/dev/null | grep -c "Slave_IO_Running: Yes" || true)
if [ "$ALREADY_RUNNING" -gt 0 ]; then
  echo "Replication already configured. Skipping."
  exit 0
fi

# Step 1: Create replication user on primary
echo "Creating replication user..."
mariadb -h "$PRIMARY" -u root -p"$ROOT_PASS" -e "
CREATE USER IF NOT EXISTS '$REPL_USER'@'%' IDENTIFIED BY '$REPL_PASS';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO '$REPL_USER'@'%';
FLUSH PRIVILEGES;
"

# Step 2: Sync data
echo "Syncing data..."
mariadb-dump -h "$PRIMARY" -u root -p"$ROOT_PASS" --single-transaction --routines --triggers homelab_db \
  | mariadb -h "$REPLICA" -u root -p"$ROOT_PASS" homelab_db

# Step 3: Get master status
MASTER_INFO=$(mariadb -h "$PRIMARY" -u root -p"$ROOT_PASS" -N -e "SHOW MASTER STATUS;")
MASTER_LOG_FILE=$(echo "$MASTER_INFO" | awk '{print $1}')
MASTER_LOG_POS=$(echo "$MASTER_INFO" | awk '{print $2}')
echo "  Master log file: $MASTER_LOG_FILE"
echo "  Master log position: $MASTER_LOG_POS"

# Step 4: Configure replica
mariadb -h "$REPLICA" -u root -p"$ROOT_PASS" -e "
RESET SLAVE ALL;
CHANGE MASTER TO
  MASTER_HOST='$PRIMARY',
  MASTER_USER='$REPL_USER',
  MASTER_PASSWORD='$REPL_PASS',
  MASTER_LOG_FILE='$MASTER_LOG_FILE',
  MASTER_LOG_POS=$MASTER_LOG_POS,
  MASTER_PORT=3306,
  MASTER_CONNECT_RETRY=10;
START SLAVE;
"

# Step 5: Verify
sleep 2
echo "Replication status:"
mariadb -h "$REPLICA" -u root -p"$ROOT_PASS" -e "SHOW SLAVE STATUS\G" | \
  grep -E "Slave_IO_Running|Slave_SQL_Running|Last_Error|Seconds_Behind"

echo "=== Replication Setup Complete ==="
