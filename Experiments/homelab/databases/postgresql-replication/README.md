# PostgreSQL Replication (Primary + Standby)

## Overview

This experiment sets up PostgreSQL streaming replication with a read/write primary and a read-only standby replica, managed via pgAdmin web UI.

## Quick Start

```bash
cd ~/homelab/databases/postgresql-replication
cp .env.example .env  # Edit .env with your own passwords
podman compose up -d
```

**Note:** First startup takes 1-2 minutes for standby to initialize via `pg_basebackup`.

## Services

| Service | Host Port | Purpose |
|---------|-----------|---------|
| primary | 15434 | PostgreSQL primary (read/write) |
| standby | 15435 | PostgreSQL standby (read-only replica) |
| pgadmin | 18082 | pgAdmin web UI |
| test-client | — | Connectivity testing container |

## How It Works

```
┌─────────────────┐         ┌─────────────────┐
│   Primary       │────────▶│   Standby       │
│   (Read/Write)  │  WAL    │   (Read-Only)   │
│   Port 5432     │  Stream │   Port 5432     │
└─────────────────┘         └─────────────────┘
```

1. Primary accepts all writes and ships WAL (Write-Ahead Log) records to standby
2. Standby continuously applies WAL records to stay in sync
3. Standby is read-only but can handle SELECT queries (load balancing)
4. Replication is **asynchronous** (primary doesn't wait for standby confirmation)

## Access

### pgAdmin Web UI
- URL: http://localhost:18082
- Email: admin@homelab.local
- Password: set in `.env` as `PGADMIN_PASSWORD`

### Direct Database Connections

**Primary (Read/Write):**
- Host: localhost
- Port: 15434
- Database: homelab_db
- User: replicator
- Password: set in `.env` as `REPLICATION_PASSWORD`

**Standby (Read-Only):**
- Host: localhost
- Port: 15435
- Database: homelab_db
- User: replicator
- Password: set in `.env` as `REPLICATION_PASSWORD`

## Testing

```bash
# Check container status
podman ps | grep homelab-pg

# View standby initialization logs
podman logs -f homelab-pg-standby | grep -i "init"

# Test primary connectivity
PGPASSWORD=$(grep ^REPLICATION_PASSWORD .env | cut -d= -f2)
podman exec homelab-postgresql-replication-test sh -c "PGPASSWORD=$PGPASSWORD psql -h primary -U replicator -d homelab_db -c 'SELECT count(*) FROM users;'"

# Test standby connectivity
PGPASSWORD=$(grep ^REPLICATION_PASSWORD .env | cut -d= -f2)
podman exec homelab-postgresql-replication-test sh -c "PGPASSWORD=$PGPASSWORD psql -h standby -U replicator -d homelab_db -c 'SELECT count(*) FROM users;'"

# Check replication status on primary
PGPASSWORD=$(grep ^REPLICATION_PASSWORD .env | cut -d= -f2)
podman exec homelab-pg-primary sh -c "PGPASSWORD=$PGPASSWORD psql -U replicator -d homelab_db -c 'SELECT * FROM pg_stat_replication;'"
```

**Expected replication output:**
```
 pid | usesysid | usename    | application_name | client_addr | client_port | backend_start | state   | sent_lsn | write_lsn | flush_lsn | replay_lsn | sync_state | sync_priority
-----+----------+------------+------------------+-------------+-------------+---------------+---------+----------+-----------+-----------+------------+------------+---------------
 123 |    16384 | replicator | walreceiver      | <CONTAINER_IP>   |       50123 | 2026-04-17... | streaming| 0/1234567| 0/1234567 | 0/1234567 | 0/1234567  | async      |           0
(1 row)
```

### Test Replication

```bash
# 1. Insert data on primary
PGPASSWORD=$(grep ^REPLICATION_PASSWORD .env | cut -d= -f2)
podman exec homelab-postgresql-replication-test sh -c "PGPASSWORD=$PGPASSWORD psql -h primary -U replicator -d homelab_db -c \"INSERT INTO replication_test (data) VALUES ('Test replication ' || clock_timestamp());\""

# 2. Query on standby (data should appear within seconds)
PGPASSWORD=$(grep ^REPLICATION_PASSWORD .env | cut -d= -f2)
podman exec homelab-postgresql-replication-test sh -c "PGPASSWORD=$PGPASSWORD psql -h standby -U replicator -d homelab_db -c 'SELECT * FROM replication_test ORDER BY created_at DESC LIMIT 5;'"

# 3. Try to write to standby (should fail)
PGPASSWORD=$(grep ^REPLICATION_PASSWORD .env | cut -d= -f2)
podman exec homelab-postgresql-replication-test sh -c "PGPASSWORD=$PGPASSWORD psql -h standby -U replicator -d homelab_db -c \"INSERT INTO replication_test (data) VALUES ('Should fail');\""
```

**Expected error:**
```
ERROR:  cannot execute INSERT in a read-only transaction
HINT:  Disable synchronous_replication or start as primary.
```

## Adding Servers in pgAdmin

1. Open pgAdmin at http://localhost:18082
2. Register Server → Name: **Primary**
3. Connection:
   - Host name/address: `primary`
   - Port: `5432`
   - Maintenance database: `homelab_db`
   - Username: `replicator`
   - Password: set in `.env` as `REPLICATION_PASSWORD`

Register **Standby** the same way, using host `standby`.

## Troubleshooting

### Standby won't initialize
```bash
# Check primary is healthy first
podman logs homelab-pg-primary | grep "ready to accept connections"

# Check network connectivity
podman exec homelab-pg-standby ping -c 3 primary

# Reinitialize standby (WARNING: deletes standby data)
podman compose down -v
podman compose up -d
```

### Replication lag is high
```bash
# Check on primary
podman exec homelab-pg-primary psql -U replicator -d homelab_db -c \
  "SELECT client_addr, state, sent_lsn, replay_lsn, (extract(epoch from now()) - extract(epoch from replay_lag)) as lag_seconds FROM pg_stat_replication;"
```

### Port conflicts
If ports 15434 or 15435 are in use, change them in `docker-compose.yml`:
```bash
ss -tlnp | grep -E '1543[45]'
```

## Failover (Manual Promotion)

If primary fails, promote standby to primary:

```bash
# 1. Stop old primary (if still running)
podman stop homelab-pg-primary

# 2. Promote standby
podman exec homelab-pg-standby touch /var/lib/postgresql/data/promote

# 3. Restart standby as new primary
podman restart homelab-pg-standby
```

**Note:** After promotion, you'll need to set up a new standby if you want replication again.

## Cleanup

```bash
# Stop containers (preserve data)
podman compose down

# Stop and remove volumes (WARNING: deletes all data!)
podman compose down -v
```

## Resource Usage

- **Primary**: ~30-50MB RAM idle
- **Standby**: ~30-50MB RAM idle
- **pgAdmin**: ~100-150MB RAM
- **Total**: ~200MB RAM
- **Storage**: ~500MB + data growth

## Next Steps

1. Test read load balancing (direct SELECT queries to standby)
2. Monitor replication lag over time
3. Practice failover procedures
4. Consider adding automatic failover (Patroni, etc.)
