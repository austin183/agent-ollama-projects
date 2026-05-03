# PostgreSQL Replication Experiment Timeline

## Experiment: PostgreSQL Streaming Replication (Primary + Standby)

**Date Started:** April 17, 2026  
**Status:** Complete  
**Location:** `~/homelab/databases/postgresql-replication/`

---

## Simplification Cleanup (April 24, 2026)

Applied per-experiment simplification plan phases 1-8.

### Phase 1 - Trivial Cleanup
- [x] Removed `version: '3.8'` line
- [x] Pinned pgAdmin image from `:latest` to `9.9.0`
- [x] Pinned Alpine test-client from `:latest` to `3.21`

### Phase 2 - Test-Client Standardization
- [x] Renamed test-client container_name from `homelab-pg-replica-test` to `homelab-postgresql-replication-test`

### Phase 3 - Secret Hygiene
- [x] Created `.env` with actual secret values
- [x] Created `.env.example` with placeholder values and comments
- [x] Replaced `replica_pass_123` with `${REPLICATION_PASSWORD}` (used in POSTGRES_PASSWORD and PGPASSWORD)
- [x] Replaced `changeme456` with `${PGADMIN_PASSWORD}` (used in PGADMIN_DEFAULT_PASSWORD)
- [x] Verified `.env` is excluded by `.gitignore` at repo root

### Phase 4 - Network Naming
- [x] Renamed network key from `replication-network` to `homelab-postgresql-replication`
- [x] Removed redundant `name: homelab-replication-network` field

### Phase 5 - Volume Naming
- [x] Renamed volumes to `postgresql-replication_<service>_<purpose>` convention:
  - `primary_data` → `postgresql-replication_primary_data`
  - `standby_data` → `postgresql-replication_standby_data`
  - `pgadmin_data` → `postgresql-replication_pgadmin_data`

### Phase 6 - Port Conflicts
- [x] Ports already matched target allocation:
  - Primary: 15434:5432 (no change needed)
  - Standby: 15435:5432 (no change needed)
  - pgAdmin: 18082:80 (no change needed)

### Phase 8 - README Consistency
- [x] Updated Overview section
- [x] Added Services table
- [x] Updated all port references (5434→15434, 5435→15435, 8082→18082)
- [x] Updated container name references
- [x] Updated verification commands to use .env variable extraction
- [x] Added .env setup instructions to Quick Start
- [x] Updated Troubleshooting section
- [x] Added Cleanup section
- [x] Removed unused `configs/` directory

### Verification Results
```
✅ podman compose up -d - All 4 containers started successfully
✅ homelab-pg-primary - healthy, accepting connections
✅ homelab-pg-standby - healthy, streaming WAL from primary
✅ homelab-pgadmin-replica - healthy, serving on port 18082
✅ Test client connectivity to primary - SELECT count(*) FROM users → 3 rows
✅ Test client connectivity to standby - SELECT count(*) FROM users → 3 rows (replicated)
✅ Replication status - state=streaming, lag < 1ms
✅ Data replication - INSERT on primary, visible on standby within seconds
✅ Standby read-only - INSERT on standby correctly rejected with "read-only transaction" error
✅ podman compose down -v - Clean shutdown and volume removal
```

### Design Decisions
- Used `PGPASSWORD` env var (in addition to `POSTGRES_PASSWORD`) for standby's `pg_isready`/`pg_basebackup` commands, since pg tools look for `PGPASSWORD` specifically
- Standby command uses `$PGDATA` (compose expands `$$` to `$`), which the shell then resolves at runtime
- Removed `configs/` directory as it was unused (init scripts handle all configuration)
- Volume names use `postgresql-replication_` prefix (project name from directory) as prefix added by podman-compose
- Created `Dockerfile.test-client` to bake postgresql-client, curl, wget, iputils, bind-tools into the test image
- Updated compose to `build:` test-client instead of `image: alpine:3.21` so psql/nslookup are pre-installed
- This follows the pattern from `databases/postgresql-pgadmin/Dockerfile.test-client`

## Goal

Set up PostgreSQL 16 streaming replication with:
- **Primary**: Read/write server (port 5434)
- **Standby**: Read-only replica (port 5435)
- **pgAdmin**: Web UI for both instances (port 8082)

---

## Iteration Log

### Iteration 1: Initial Setup (20:39)
**Approach:** Custom command in docker-compose to modify postgresql.conf on startup

**Changes:**
- Created docker-compose.yml with custom `command` for primary
- Used `echo` to append replication settings
- Standby uses `pg_basebackup` with `-R -C` flags

**Issues:**
- PostgreSQL 16 Alpine doesn't allow root execution
- Error: `"root" execution of the PostgreSQL server is not permitted`

**Root Cause:** The custom shell command was running as root before dropping to postgres user

---

### Iteration 2: Environment Variables (20:41)
**Approach:** Pass replication settings via environment variables

**Changes:**
```yaml
environment:
  - wal_level=replica
  - max_wal_senders=3
  - wal_keep_size=64MB
```

**Issues:**
- Environment variables don't modify postgresql.conf
- Settings were ignored by PostgreSQL

**Learning:** PostgreSQL doesn't read arbitrary environment variables as config parameters

---

### Iteration 3: Init Script Approach (21:03)
**Approach:** Use init script in `/docker-entrypoint-initdb.d/`

**Changes:**
- Created `00-config-replication.sh` that appends to postgresql.conf
- Script runs after database initialization
- Used `$$PGDATA` to reference data directory

**Issues:**
- `$$PGDATA` expanded to literal string instead of variable
- Error: `/docker-entrypoint-initdb.d/00-config-replication.sh: line 7: can't create 49PGDATA/postgresql.conf: nonexistent directory`

**Root Cause:** In heredoc with single quotes, variables aren't expanded. Need to use `$PGDATA` not `$$PGDATA`

---

### Iteration 4: Variable Fix (21:12)
**Approach:** Fix variable expansion in init script

**Changes:**
- Changed `$$PGDATA` to `$PGDATA` in shell script
- Added debug output to verify PGDATA is set

**Issues:**
- Init scripts ran after database was already initialized (from previous run)
- Standby initialized its own database before pg_basebackup could connect
- Stale `99-config-replication.sh` file causing errors

**Root Cause:** Volumes persisted between runs with partially configured data

---

### Iteration 5: Proper Standby Initialization (April 18, 2026 - SUCCESS)

**Approach:** Add wait mechanism for primary readiness in standby startup

**Changes:**
1. Removed stale `99-config-replication.sh` file
2. Fixed `00-config-replication.sh` to use `echo` instead of heredoc (avoids variable expansion issues)
3. Added retry loop in standby command to wait for primary using `pg_isready`
4. Added `PGPASSWORD` environment variable for `pg_isready` and `pg_basebackup`
5. Added `guest_registration` table with first_name, last_name, email columns

**Status:** ✅ SUCCESSFUL

**Verification:**
```bash
# Replication is active
SELECT * FROM pg_stat_replication;
# Shows: state=streaming, sent_lsn=write_lsn=flush_lsn=replay_lsn

# Insert on primary
INSERT INTO guest_registration (first_name, last_name, email) 
VALUES ('Alice', 'Johnson', 'alice.johnson@test.com');

# Query on standby - data replicated!
SELECT * FROM guest_registration;
# Shows all 3 records including the new one
```

**Key Learnings:**
- Standby must wait for primary to be fully ready before running pg_basebackup
- Use `PGPASSWORD` env var with `pg_isready` to avoid password prompts
- Always clean volumes (`podman compose down -v`) when fixing init scripts
- Heredocs with single quotes don't expand variables; use multiple echo statements instead

---

## Current Files

```
~/homelab/databases/postgresql-replication/
├── docker-compose.yml
├── README.md
├── init-scripts/
│   ├── 00-config-replication.sh
│   ├── 01-init-schema.sql
│   └── 02-setup-replication.sql
└── configs/ (unused - removed)
    ├── primary.conf
    ├── standby.conf
    └── pg_hba.conf
```

---

## Key Learnings

### PostgreSQL Init Scripts
- Scripts in `/docker-entrypoint-initdb.d/` run **before** PostgreSQL starts
- They execute as the `postgres` user (not root)
- `$PGDATA` is set by the entrypoint script
- `.sh` and `.sql` files are executed in alphabetical order

### Replication Configuration
Must set in `postgresql.conf`:
```
wal_level = replica
max_wal_senders = 3
wal_keep_size = 64MB
listen_addresses = '*'
```

Must add to `pg_hba.conf`:
```
host replication replicator 0.0.0.0/0 scram-sha-256
```

### pg_basebackup Requirements
- Primary must have replication configured **before** first connection
- Need to create replication slot: `pg_create_physical_replication_slot('standby_slot')`
- Use `-R` flag to create `standby.signal` file
- Use `-S` flag to associate with replication slot

---

## Next Steps (After Break)

1. Verify replication is active:
   ```bash
   podman exec homelab-pg-primary psql -U replicator -c "SELECT * FROM pg_stat_replication;"
   ```

2. Test data replication:
   ```bash
   # Insert on primary
   psql -h localhost -p 5434 -U replicator -d homelab_db -c "INSERT INTO replication_test (data) VALUES ('test');"
   
   # Query on standby
   psql -h localhost -p 5435 -U replicator -d homelab_db -c "SELECT * FROM replication_test;"
   ```

3. If still failing, consider:
   - Using a custom Dockerfile to bake in config
   - Using `postgreSql.conf` override via volume mount
   - Checking if POSTGRES_HOST_AUTH_METHOD is interfering

---

## Commands Used

```bash
# Start experiment
cd ~/homelab/databases/postgresql-replication
podman compose up -d

# Check status
podman ps --filter "name=homelab-pg"

# View logs
podman logs --tail 50 homelab-pg-primary
podman logs --tail 50 homelab-pg-standby

# Check replication status
PGPASSWORD=replica_pass_123 podman exec -e PGPASSWORD=replica_pass_123 \
  homelab-pg-primary psql -U replicator -d homelab_db \
  -c "SELECT * FROM pg_stat_replication;"

# Clean restart
podman compose down -v
podman compose up -d
```

---

## Resources

- [PostgreSQL Streaming Replication](https://www.postgresql.org/docs/16/warm-standby.html)
- [pg_basebackup Documentation](https://www.postgresql.org/docs/16/app-pgbasebackup.html)
- [Official PostgreSQL Docker Image](https://hub.docker.com/_/postgres)

---

*Last Updated: April 18, 2026, 08:01*
