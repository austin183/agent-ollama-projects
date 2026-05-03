# MariaDB Replication (Primary + Replica)

## Overview

This experiment sets up MariaDB 10.11 master-replica replication with a primary write server, a read-only replica, and Adminer for database management.

## Quick Start

```bash
cd ~/homelab/databases/mariadb-replication
# Copy .env.example to .env and set your own passwords
cp .env.example .env
podman compose up -d
```

**Note**: First startup takes 1-2 minutes for both databases to initialize and the init container to configure replication.

## Services

| Service | Host Port | Container Port | Purpose |
|---------|-----------|----------------|---------|
| primary | 13307 | 3306 | MariaDB primary (read/write) |
| replica | 13308 | 3306 | MariaDB replica (read-only) |
| adminer | 18083 | 8080 | Adminer web UI |
| replication-init | - | - | One-shot init container (configures replication) |
| test-client | - | - | Connectivity testing |

## How It Works

```
┌─────────────────┐         ┌─────────────────┐
│   Primary       │  Binlog │   Replica       │
│   (Master)      │────────▶│   (Slave)       │
│   Read/Write    │  Stream │   Read-Only     │
│   Host:13307    │         │   Host:13308    │
└─────────────────┘         └─────────────────┘
```

1. Primary accepts all writes and ships binlog (binary log) events to replica
2. Replica continuously applies binlog events to stay in sync
3. Replica is read-only but can handle SELECT queries (load balancing)
4. Replication is **asynchronous** (primary doesn't wait for replica confirmation)

## Automatic Replication Setup

Replication is configured automatically by the `replication-init` container on startup. It:

1. Waits for both primary and replica to be healthy
2. Creates the replication user on primary
3. Syncs data from primary to replica via `mariadb-dump`
4. Configures the replica to follow the primary's binlog
5. Verifies replication is running

The init container is idempotent — if replication is already configured, it skips setup.

**Re-running setup manually:**
```bash
podman compose run --rm replication-init
```

## Access

### Adminer Web UI
- URL: http://localhost:18083
- System: MariaDB
- Server: `primary` or `replica` (service name)
- Username: `replicator`
- Password: (from `.env` → `REPLICATOR_PASSWORD`)
- Database: `homelab_db`

### Direct Database Connections

**Primary (Read/Write):**
- Host: localhost
- Port: 13307
- Database: homelab_db
- User: replicator
- Password: (from `.env` → `REPLICATOR_PASSWORD`)

**Replica (Read-Only):**
- Host: localhost
- Port: 13308
- Database: homelab_db
- User: replicator
- Password: (from `.env` → `REPLICATOR_PASSWORD`)

## Verification Commands

### Check container status
```bash
podman ps | grep homelab-mariadb
```

### View replication logs
```bash
podman logs -f homelab-mariadb-replica
```

### Check replication status
```bash
export ROOT_PASS=$(grep MARIADB_ROOT_PASSWORD .env | cut -d= -f2)
podman exec homelab-mariadb-replica mariadb -u root -p"${ROOT_PASS}" -e "SHOW SLAVE STATUS\G"
```

**Expected output:**
```
Slave_IO_Running: Yes
Slave_SQL_Running: Yes
Last_Error: 
Seconds_Behind_Master: 0
```

### Check if replica is read-only
```bash
export REPL_PASS=$(grep REPLICATOR_PASSWORD .env | cut -d= -f2)
podman exec homelab-mariadb-replica mariadb -u replicator -p"${REPL_PASS}" \
  -e "SELECT @@global.read_only;"
```

**Expected output:**
```
+----------------------+
| @@global.read_only   |
+----------------------+
|                    1 |
+----------------------+
```

### Check primary master status
```bash
export ROOT_PASS=$(grep MARIADB_ROOT_PASSWORD .env | cut -d= -f2)
podman exec homelab-mariadb-primary mariadb -u root -p"${ROOT_PASS}" \
  -e "SHOW MASTER STATUS\G"
```

**Expected output:**
```
File: mariadb-bin.00000X
Position: XXXXX
```

## Testing Replication

### 1. Insert guest registration on primary
```bash
export REPL_PASS=$(grep REPLICATOR_PASSWORD .env | cut -d= -f2)
podman exec homelab-mariadb-primary mariadb -u replicator -p"${REPL_PASS}" homelab_db \
  -e "INSERT INTO guest_registration (first_name, last_name, email) VALUES ('Alice', 'Johnson', 'alice.johnson@test.com');"
```

### 2. Query on replica (data should appear within seconds)
```bash
podman exec homelab-mariadb-replica mariadb -u replicator -p"${REPL_PASS}" homelab_db \
  -e "SELECT * FROM guest_registration ORDER BY registered_at DESC LIMIT 5;"
```

### 3. Try to write to replica (should fail)
```bash
podman exec homelab-mariadb-replica mariadb -u replicator -p"${REPL_PASS}" homelab_db \
  -e "INSERT INTO guest_registration (first_name, last_name, email) VALUES ('Should', 'Fail', 'fail@test.com');"
```

**Expected error:**
```
ERROR 1290 (HY000): The MariaDB server is running with the --read-only option so it cannot execute this statement
```

## Adding Servers in Adminer

### Primary Server
1. Open Adminer at http://localhost:18083
2. Select **MariaDB** as system
3. Connection:
   - Server: `primary`
   - Username: `replicator`
   - Password: (from `.env` → `REPLICATOR_PASSWORD`)
   - Database: `homelab_db`
4. Click **Log in**

### Replica Server
1. Same as above, but use:
   - Server: `replica`

## Troubleshooting

### Replica won't start
```bash
# Check for config errors
podman logs homelab-mariadb-replica | grep ERROR

# Common error: unknown variable 'replica-do-db'
# Fix: Use 'replicate-do-db' instead in configs/replica.cnf

# Common error: Database is uninitialized and password option is not specified
# Fix: Ensure MARIADB_ROOT_PASSWORD is set in .env
```

### Replication not working
```bash
# Check if replica has the data
export ROOT_PASS=$(grep MARIADB_ROOT_PASSWORD .env | cut -d= -f2)
podman exec homelab-mariadb-replica mariadb -u root -p"${ROOT_PASS}" homelab_db -e "SHOW TABLES;"

# If tables are missing, re-sync data:
podman exec homelab-mariadb-primary mariadb-dump -u root -p"${ROOT_PASS}" \
  --single-transaction homelab_db \
  | podman exec -i homelab-mariadb-replica mariadb -u root -p"${ROOT_PASS}" homelab_db

# Get new master position and reconfigure
MASTER_INFO=$(podman exec homelab-mariadb-primary mariadb -u root -p"${ROOT_PASS}" -N -e "SHOW MASTER STATUS;")
podman exec homelab-mariadb-replica mariadb -u root -p"${ROOT_PASS}" -e "
RESET SLAVE ALL;
CHANGE MASTER TO
  MASTER_HOST='primary',
  MASTER_USER='repl_user',
  MASTER_PASSWORD='repl_pass_123',
  MASTER_LOG_FILE='$(echo $MASTER_INFO | awk '{print $1}')',
  MASTER_LOG_POS=$(echo $MASTER_INFO | awk '{print $2}'),
  MASTER_PORT=3306;
START SLAVE;
"
```

### Replication stopped on replica
```bash
export ROOT_PASS=$(grep MARIADB_ROOT_PASSWORD .env | cut -d= -f2)
# Check error
podman exec homelab-mariadb-replica mariadb -u root -p"${ROOT_PASS}" \
  -e "SHOW SLAVE STATUS\G" | grep -A 2 "Last_Error"

# Try to restart replication
podman exec homelab-mariadb-replica mariadb -u root -p"${ROOT_PASS}" \
  -e "STOP SLAVE; START SLAVE;"
```

### Port conflicts
If ports 13307 or 13308 are in use, change them in `docker-compose.yml`:
```yaml
ports:
  - "13309:3306/tcp"  # Primary on 13309
  - "13310:3306/tcp"  # Replica on 13310
```

## Failover (Manual Promotion)

If primary fails, promote replica to primary:

```bash
# 1. Stop old primary (if still running)
podman stop homelab-mariadb-primary

export ROOT_PASS=$(grep MARIADB_ROOT_PASSWORD .env | cut -d= -f2)
# 2. Disable read-only on replica
podman exec homelab-mariadb-replica mariadb -u root -p"${ROOT_PASS}" \
  -e "SET GLOBAL read_only = 0;"

# 3. Stop replication
podman exec homelab-mariadb-replica mariadb -u root -p"${ROOT_PASS}" \
  -e "STOP SLAVE;"

# 4. Update application connections to use port 13308
```

**Note**: After promotion, you'll need to set up a new replica if you want replication again.

## Cleanup

```bash
# Stop containers (preserve data)
podman compose down

# Stop and remove volumes (WARNING: deletes all data!)
podman compose down -v
```

## Resource Usage

- **Primary**: ~30-50MB RAM idle
- **Replica**: ~30-50MB RAM idle
- **Adminer**: ~20-30MB RAM
- **Test client**: ~5MB RAM
- **Total**: ~100-150MB RAM
- **Storage**: ~300MB + data growth

## Next Steps

1. Test read load balancing (direct SELECT queries to replica)
2. Monitor replication lag with `Seconds_Behind_Master`
3. Practice failover procedures
4. Consider adding automatic failover (MHA, Orchestrator, etc.)
