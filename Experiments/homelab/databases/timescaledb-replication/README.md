# TimescaleDB Replication Experiment

Primary-standby streaming replication with TimescaleDB hypertables. Demonstrates how time-series data replicates transparently over PostgreSQL WAL streaming.

## Quick Start

```bash
cd ~/homelab/databases/timescaledb-replication
cp .env.example .env    # Edit passwords if desired
podman compose up -d
```

## Services

| Service | Host Port | Container Port | Purpose |
|---------|-----------|----------------|---------|
| ts-primary | 15436 | 5432 | Read-write TimescaleDB primary |
| ts-standby | 15437 | 5432 | Read-only standby (streaming replication) |
| pgadmin | 18086 | 80 | pgAdmin web UI for monitoring |
| test-client | — | — | Alpine container with DB client tools |

## Architecture

```
Host (localhost:15436) --> homelab-ts-primary (MASTER, RW)
                                     |
                                     | streaming replication (WAL)
                                     v
Host (localhost:15437) --> homelab-ts-standby (STANDBY, RO)

Host (localhost:18086) --> homelab-pgadmin-ts (monitoring UI)
```

1. **Primary** accepts reads and writes, ships WAL records to the standby
2. **Standby** runs `pg_basebackup` on first start, then continuously replays WAL
3. **Hypertables** replicate transparently — they're just partitioned tables at the PostgreSQL layer
4. **Replication slot** (`standby_slot`) prevents WAL recycling before the standby receives it

## Testing

```bash
# Check both containers are healthy
podman exec homelab-timescaledb-replication-test pg_isready -h ts-primary -U replicator -d homelab_db
podman exec homelab-timescaledb-replication-test pg_isready -h ts-standby -U replicator -d homelab_db

# Check replication status (should show 1 streaming standby)
podman exec homelab-timescaledb-replication-test psql -h ts-primary -U replicator -d homelab_db -c \
  "SELECT client_addr, state, sent_lsn, replay_lsn FROM pg_stat_replication;"

# Check standby is in recovery mode
podman exec homelab-timescaledb-replication-test psql -h ts-standby -U replicator -d homelab_db -c \
  "SELECT pg_is_in_recovery();"

# Write on primary, read on standby
podman exec homelab-timescaledb-replication-test psql -h ts-primary -U replicator -d homelab_db -c \
  "INSERT INTO sensor_readings (time, device_id, sensor_type, value, unit) VALUES (NOW(), 'sensor-test', 'temperature', 25.5, 'celsius');"

sleep 2
podman exec homelab-timescaledb-replication-test psql -h ts-standby -U replicator -d homelab_db -c \
  "SELECT device_id, value FROM sensor_readings WHERE device_id = 'sensor-test';"

# Standby rejects writes
podman exec homelab-timescaledb-replication-test psql -h ts-standby -U replicator -d homelab_db -c \
  "INSERT INTO sensor_readings (time, device_id, sensor_type, value, unit) VALUES (NOW(), 'x', 'x', 0, 'x');"
  
# Expected: ERROR: cannot execute INSERT in a read-only transaction
```

## Accessing the Database

Connect via pgAdmin
- Browser -> http://localhost:18086
- Email: admin@homelab.com
- Password: changeme456

## Troubleshooting

- **`$PGDATA` variable expansion**: Podman-compose expands shell variables in command blocks. The compose file uses literal paths (`/var/lib/postgresql/data`) to avoid this.
- **`standby.signal` vs `standby_mode`**: PostgreSQL 12+ uses a `standby.signal` file, not a `standby_mode` config parameter.
- **pgAdmin email validation**: The `.local` TLD is reserved and rejected by pgAdmin. This experiment uses `.com`.
- **Volume resets**: Always run `podman compose down -v` when changing init scripts or volume names. Stale data causes silent failures.
- **Standby startup timing**: The standby waits up to 120 seconds for the primary. Check logs with `podman logs homelab-ts-standby` if it fails.

## Cleanup

```bash
podman compose down          # Stop containers, keep data
podman compose down -v       # Stop containers and remove volumes (data loss)
```
