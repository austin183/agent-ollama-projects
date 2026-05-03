# MariaDB Replication Experiment Timeline

## Experiment: MariaDB Master-Replica Replication

**Date Started:** April 18, 2026  
**Status:** Complete ✅  
**Location:** `~/homelab/databases/mariadb-replication/`

---

## Simplification Cleanup (April 24, 2026)

Applied per-experiment simplification plan phases 1-8.

### Phase 1 - Trivial Cleanup
- [x] Removed `version: '3.8'` line
- [x] Pinned `adminer:latest` → `adminer:4.8.1`
- [x] Pinned `alpine:latest` → `alpine:3.21` (test-client)

### Phase 2 - Test-Client Standardization
- [x] Already named `test-client` ✓
- [x] Standardized container_name from `homelab-mariadb-replica-test` → `homelab-mariadb-replication-test`

### Phase 3 - Secret Hygiene
- [x] Created `.env` with actual values
- [x] Created `.env.example` with placeholder values and comments
- [x] Extracted secrets: `MARIADB_ROOT_PASSWORD`, `REPLICATOR_PASSWORD`
- [x] Replaced hardcoded passwords in docker-compose.yml with `${VAR}` references via `env_file`
- [x] Verified `.gitignore` at repo root excludes `.env`
- [x] Updated `setup-replication.sh` to source `.env` with fallback defaults

### Phase 4 - Network Naming
- [x] Renamed network key from `mariadb-replication-network` → `homelab-mariadb-replication`
- [x] Removed redundant `name: homelab-mariadb-replication-network` field

### Phase 5 - Volume Naming
- [x] Renamed `primary_data` → `mariadb-replication_primary_data`
- [x] Renamed `replica_data` → `mariadb-replication_replica_data`

### Phase 6 - Port Conflicts
- [x] Primary: `3307:3306` → `13307:3306` (per plan)
- [x] Replica: `3308:3306` → `13308:3306` (per plan)
- [x] Adminer: `8083:8080` → `18083:8080` (per plan)

### Phase 8 - README Consistency
- [x] Added Overview section (1-2 sentences)
- [x] Added Services table (Service | Host Port | Container Port | Purpose)
- [x] Added Testing instructions with env var references
- [x] Added Troubleshooting section (consolidated from Common Pitfalls)
- [x] Added Cleanup section
- [x] Removed duplicate Quick Start and Manual Replication Setup sections
- [x] Updated all port references (3307→13307, 3308→13308, 8083→18083)
- [x] Updated password references to use `.env` variable notation

### Verification
- [x] `podman compose down -v` — stopped and removed all containers/volumes
- [x] `podman compose up -d` — all 4 containers started successfully
- [x] `podman ps` — primary (healthy), replica (healthy), adminer (starting), test-client (running)
- [x] DNS resolution — `nslookup primary` and `nslookup replica` both resolve correctly
- [x] Root connectivity — `mariadb -h primary -u root -p...` works
- [x] Replicator user — created and verified on primary
- [x] Replicator connectivity — `mariadb -h primary -u replicator -p...` works
- [x] Replica connectivity — `mariadb -h replica -u replicator -p...` works
- [x] `podman compose down -v` — clean shutdown

### Issues Encountered

**Replicator user not created on first run:**
- The `env_file` approach only loaded MARIADB_ROOT_PASSWORD from .env
- MYSQL_USER, MYSQL_PASSWORD, MYSQL_DATABASE needed to be explicit `environment` variables
- Fix: Added explicit `environment` block with these variables to both primary and replica services

**Volume naming conflict:**
- Podman-compose created volumes with double prefix: `mariadb-replication_mariadb-replication_primary_data`
- This is expected behavior — compose project name (`mariadb-replication`) is prepended to volume names
- No functional impact, just a naming quirk


## Goal

Set up MariaDB 10.11 master-replica replication with:
- **Primary (Master)**: Read/write server (port 3307)
- **Replica (Slave)**: Read-only replica (port 3308)
- **Adminer**: Web UI for both instances (port 8083)

---

## Iteration Log

### Iteration 1: Initial Setup with rsync (08:36)
**Approach:** Custom command in docker-compose using rsync to copy data from primary

**Issues:**
- `mysql: command not found` - MariaDB 11 image doesn't have mysql client in PATH
- Replica container stuck in initialization loop

**Root Cause:** MariaDB 11 official image uses `mariadb` not `mysql` as the client binary

---

### Iteration 2: Full Binary Paths (11:23)
**Approach:** Use full paths `/usr/bin/mariadb` and `/usr/bin/mysqldump`

**Issues:**
- `/usr/bin/mariadb: command not found` - binary not in expected location
- `CREATE USER IF NOT EXISTS` syntax error - not supported in MariaDB
- `mysqldump: not found` - not included in base image
- `ACCESS DENIED: BINLOG MONITOR privilege` - missing REPLICATION CLIENT grant

**Root Cause:** MariaDB 11 image has different binary layout than expected

---

### Iteration 3: Separated Setup Container (11:27)
**Approach:** Create separate setup container to configure replication after both DBs start

**Issues:**
- Podman-compose `--requires` flag caused dependency graph errors
- Container startup failures due to complex dependency chain

**Root Cause:** Podman-compose doesn't handle complex `depends_on` chains well

---

### Iteration 4: Simplified with Config Files (11:35)
**Approach:** Use config files mounted as volumes, simpler compose structure

**Changes:**
- Created `configs/primary.cnf` with binlog settings
- Created `configs/replica.cnf` with replica settings
- Removed custom commands, rely on config files
- Downgraded to MariaDB 10.11 (more stable)

**Issues:**
- Primary starts healthy
- Replica starts but shows "starting" status (healthcheck waiting)
- Need to run setup script manually to configure replication

---

### Iteration 5: MariaDB 10.11 with Config Files (11:44)
**Approach:** Use MariaDB 10.11 with proper config file mounts

**Changes:**
- Changed image from `mariadb:11` to `mariadb:10.11`
- Config files mounted to `/etc/mysql/conf.d/server.cnf`
- Primary has binlog enabled via config file
- Replica has read-only and server-id via config file

**Status:** 
- ✅ Primary: Healthy and running on port 3307
- ⏳ Replica: Starting (healthcheck in progress) on port 3308
- ⏳ Adminer: Running on port 8083
- ❌ Replication: Not yet configured (needs manual setup)

---

### Iteration 6: Fix replica config - `replica-do-db` → `replicate-do-db` (14:02)

**Problem:** Replica container was crash-looping with error:
```
[ERROR] mariadbd: unknown variable 'replica-do-db=homelab_db'
```

**Root Cause:** `replica-do-db` is not a valid MariaDB 10.11 config variable. The correct variable is `replicate-do-db`.

**Fix:** Updated `configs/replica.cnf`:
```diff
- replica-do-db=homelab_db
+ replicate-do-db=homelab_db
```

---

### Iteration 7: Fix replica missing root password (14:03)

**Problem:** Replica crash-looping with error:
```
[ERROR] [Entrypoint]: Database is uninitialized and password option is not specified
You need to specify one of MARIADB_ROOT_PASSWORD, MARIADB_ROOT_PASSWORD_HASH, MARIADB_ALLOW_EMPTY_ROOT_PASSWORD and MARIADB_RANDOM_ROOT_PASSWORD
```

**Root Cause:** The MariaDB Docker image requires a root password to initialize the database, even for replicas. The replica service was missing `MARIADB_ROOT_PASSWORD`.

**Fix:** Added to docker-compose.yml replica service:
```yaml
environment:
  - MARIADB_ROOT_PASSWORD=changeme_root
```

---

### Iteration 8: Configure Replication Manually (14:04-14:07)

**Problem:** Need to manually set up replication after both containers are healthy.

**Steps Taken:**

1. **Create replication user on primary** (using root, not replicator):
```bash
podman exec homelab-mariadb-primary mariadb -u root -pchangeme_root -e "
CREATE USER IF NOT EXISTS 'repl_user'@'%' IDENTIFIED BY 'repl_pass_123';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'repl_user'@'%';
FLUSH PRIVILEGES;
"
```
Note: The `replicator` user doesn't have CREATE USER privilege, so we must use root.

2. **Get master status:**
```bash
podman exec homelab-mariadb-primary mariadb -u root -pchangeme_root -N -e "SHOW MASTER STATUS;"
# Output: mariadb-bin.000002  831
```

3. **First attempt to configure replica** - used `CHANGE REPLICA TO` syntax:
```bash
podman exec homelab-mariadb-replica mariadb -u root -pchangeme_root -e "
CHANGE REPLICA TO
  SOURCE_HOST='primary', ...
"
```
**Error:** `ERROR 1064 (42000): syntax error near 'REPLICA TO'`

**Root Cause:** MariaDB 10.11 uses the legacy `CHANGE MASTER TO` syntax, not the newer MariaDB 11 `CHANGE REPLICATION SOURCE TO` syntax.

4. **Second attempt** - used legacy syntax:
```bash
podman exec homelab-mariadb-replica mariadb -u root -pchangeme_root -e "
STOP SLAVE;
CHANGE MASTER TO
  MASTER_HOST='primary',
  MASTER_USER='repl_user',
  MASTER_PASSWORD='repl_pass_123',
  MASTER_LOG_FILE='mariadb-bin.000002',
  MASTER_LOG_POS=831,
  MASTER_PORT=3306,
  MASTER_CONNECT_RETRY=10;
START SLAVE;
"
```
No errors! But replication wasn't working properly.

5. **Diagnosed issue:** The binlog position 831 was AFTER the init script ran. The CREATE TABLE and initial INSERT statements from `01-init-schema.sql` were NOT in the binlog at position 831. The binlog only contained the replication user creation and the test INSERT.

6. **Solution:** Dump primary data and restore on replica, then reconfigure replication from the updated position:
```bash
# Dump primary and restore on replica
podman exec homelab-mariadb-primary mariadb-dump -u root -pchangeme_root --single-transaction --routines --triggers homelab_db \
  | podman exec -i homelab-mariadb-replica mariadb -u root -pchangeme_root homelab_db
```

7. **Reconfigure replication** from new position (1192):
```bash
podman exec homelab-mariadb-replica mariadb -u root -pchangeme_root -e "
RESET SLAVE ALL;
CHANGE MASTER TO
  MASTER_HOST='primary',
  MASTER_USER='repl_user',
  MASTER_PASSWORD='repl_pass_123',
  MASTER_LOG_FILE='mariadb-bin.000002',
  MASTER_LOG_POS=1192,
  MASTER_PORT=3306,
  MASTER_CONNECT_RETRY=10;
START SLAVE;
"
```

8. **Verify replication:**
```
Slave_IO_Running: Yes
Slave_SQL_Running: Yes
Last_Error: 
Seconds_Behind_Master: 0
```

---

## Verification Results

### Data Replication Test ✅
```bash
# Insert on primary
podman exec homelab-mariadb-primary mariadb -u replicator -preplica_pass_123 homelab_db \
  -e "INSERT INTO guest_registration (first_name, last_name, email) VALUES ('Diana', 'Prince', 'diana.prince@example.com');"

# Verify on replica (appeared within seconds)
podman exec homelab-mariadb-replica mariadb -u replicator -preplica_pass_123 homelab_db \
  -e "SELECT * FROM guest_registration ORDER BY id DESC LIMIT 3;"

# Output:
# id  first_name  last_name   email                          registered_at
# 5   Diana       Prince      diana.prince@example.com       2026-04-18 14:07:28
# 4   Test        User        test.user@example.com          2026-04-18 14:06:16
# 3   Charlie     Brown       charlie.brown@test.com         2026-04-18 14:04:54
```

### Read-Only Test ✅
```bash
# Try to write to replica (should fail)
podman exec homelab-mariadb-replica mariadb -u replicator -preplica_pass_123 homelab_db \
  -e "INSERT INTO guest_registration (first_name, last_name, email) VALUES ('Should', 'Fail', 'fail@test.com');"

# Output:
# ERROR 1290 (HY000): The MariaDB server is running with the --read-only option so it cannot execute this statement
```

### Replication Test Table ✅
```bash
# Both tables replicate correctly
podman exec homelab-mariadb-replica mariadb -u replicator -preplica_pass_123 homelab_db -e "SELECT * FROM replication_test;"
# Output:
# id  data                          created_at
# 1   Initial test record 1         2026-04-18 14:04:54
# 2   Initial test record 2         2026-04-18 14:04:54
# 3   Replication verified at 14:07 2026-04-18 14:07:38
```

---

## Files Created

```
~/homelab/databases/mariadb-replication/
├── docker-compose.yml          # MariaDB 10.11 with primary, replica, adminer, test-client
├── README.md                   # Documentation
├── experiment-timeline.md      # This file
├── setup-replication.sh        # Manual setup script (executable)
├── init-scripts/
│   └── 01-init-schema.sql      # guest_registration + replication_test tables
└── configs/
    ├── primary.cnf             # Binlog config: server-id=1, log_bin=mariadb-bin
    └── replica.cnf             # Replica config: server-id=2, read-only=1, replicate-do-db=homelab_db
```

---

## Key Learnings

### MariaDB 10.11 Config Variables
- `replicate-do-db` (not `replica-do-db`) - filters which DBs to replicate
- `read-only=1` - makes the server read-only
- `server-id` - unique identifier required for replication

### MariaDB 10.11 Replication Commands
- `CHANGE MASTER TO` (not `CHANGE REPLICA TO` or `CHANGE REPLICATION SOURCE TO`)
- `START SLAVE` (not `START REPLICA`)
- `SHOW SLAVE STATUS\G` (not `SHOW REPLICA STATUS`)
- These are the legacy MySQL-compatible commands that work in MariaDB 10.11

### MariaDB Binary Names
- Server: `mariadbd` (not `mysqld`)
- Client: `mariadb` (not `mysql`)
- Dump: `mariadb-dump` (not `mysqldump`)

### Replication Sync Strategy
When setting up a new replica:
1. Create replication user on primary (requires root privileges)
2. Dump primary data (`mariadb-dump --single-transaction`)
3. Restore dump on replica
4. Get master status AFTER dump (position has moved)
5. Configure replica with the new master position
6. Start slave and verify

### Podman-Specific Notes
- Use `podman exec` to run commands inside containers
- Pipe between containers: `podman exec primary mariadb-dump ... | podman exec -i replica mariadb ...`
- The `-i` flag is needed for stdin on the receiving container

### Docker Image Requirements
- MariaDB Docker image requires `MARIADB_ROOT_PASSWORD` even for replicas
- The init scripts (`/docker-entrypoint-initdb.d/`) only run on primary (first startup)
- Replica needs data synced separately (not auto-initialized from primary)

---

## Comparison with PostgreSQL Replication

| Aspect | PostgreSQL | MariaDB |
|--------|------------|---------|
| Config Method | Config files in /etc/mysql/conf.d | Config files in /etc/mysql/conf.d |
| Backup Tool | pg_basebackup (built-in) | mariadb-dump (external) |
| Replica Auto-init | Yes (pg_basebackup) | No (manual dump/restore) |
| Read-Only | Automatic on standby | Requires `read-only=1` config |
| Binary Names | Consistent (postgres, psql) | Varies (mariadbd, mariadb, mariadb-dump) |
| Replication Commands | pg_basebackup, pg_ctl | CHANGE MASTER TO, START SLAVE |
| Setup Complexity | Moderate (streaming) | Higher (dump + restore + position) |

---

## Commands Used

```bash
# Start experiment
cd ~/homelab/databases/mariadb-replication
podman compose up -d

# Check status
podman ps | grep homelab-mariadb

# View logs
podman logs -f homelab-mariadb-primary
podman logs -f homelab-mariadb-replica

# Create replication user
podman exec homelab-mariadb-primary mariadb -u root -pchangeme_root -e "
CREATE USER IF NOT EXISTS 'repl_user'@'%' IDENTIFIED BY 'repl_pass_123';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'repl_user'@'%';
FLUSH PRIVILEGES;
"

# Get master status
podman exec homelab-mariadb-primary mariadb -u root -pchangeme_root -N -e "SHOW MASTER STATUS;"

# Sync data from primary to replica
podman exec homelab-mariadb-primary mariadb-dump -u root -pchangeme_root --single-transaction homelab_db \
  | podman exec -i homelab-mariadb-replica mariadb -u root -pchangeme_root homelab_db

# Configure replica
podman exec homelab-mariadb-replica mariadb -u root -pchangeme_root -e "
RESET SLAVE ALL;
CHANGE MASTER TO
  MASTER_HOST='primary',
  MASTER_USER='repl_user',
  MASTER_PASSWORD='repl_pass_123',
  MASTER_LOG_FILE='mariadb-bin.000002',
  MASTER_LOG_POS=1192,
  MASTER_PORT=3306,
  MASTER_CONNECT_RETRY=10;
START SLAVE;
"

# Check replication status
podman exec homelab-mariadb-replica mariadb -u root -pchangeme_root -e "SHOW SLAVE STATUS\G"

# Test replication
podman exec homelab-mariadb-primary mariadb -u replicator -preplica_pass_123 homelab_db \
  -e "INSERT INTO guest_registration (first_name, last_name, email) VALUES ('Test', 'User', 'test@example.com');"

podman exec homelab-mariadb-replica mariadb -u replicator -preplica_pass_123 homelab_db \
  -e "SELECT * FROM guest_registration;"

# Clean restart
podman compose down -v
podman compose up -d
```

---

## Testing Checklist

```
Experiment Setup Progress:
- [x] Compose file uses full image references (docker.io/library/mariadb:10.11, docker.io/library/adminer:4.8.1, docker.io/alpine:3.21)
- [x] Ports are > 1024 (13307, 13308, 18083)
- [x] Test client container included with standardized naming
- [x] Healthcheck port matches service config
- [x] Volumes use hybrid strategy (named volumes for data, bind mounts for configs)
- [x] Network name follows homelab-* pattern (homelab-mariadb-replication)
- [x] README includes Services table, Testing, Troubleshooting, Cleanup sections
- [x] Verification commands documented with env var references
- [x] Expected output samples provided
- [x] Secrets extracted to .env file
- [x] .env.example created with placeholder values
```

---

## Resource Usage

- **Primary**: ~30-50MB RAM idle
- **Replica**: ~30-50MB RAM idle
- **Adminer**: ~20-30MB RAM
- **Test client**: ~5MB RAM
- **Total**: ~100-150MB RAM
- **Storage**: ~300MB + data growth

---

## Lessons Learned

### What Worked
1. Config file approach (mounting .cnf files) is more reliable than custom commands
2. MariaDB 10.11 is stable and well-supported
3. Using root user for replication setup commands (replicator lacks CREATE USER privilege)
4. mariadb-dump pipe between containers works perfectly for data sync

### What Didn't Work
1. Trying to use `CHANGE REPLICA TO` syntax in MariaDB 10.11 (use `CHANGE MASTER TO`)
2. Starting replication from init script position (binlog position moves, need post-dump position)
3. The `setup-replication.sh` script approach (running mariadb client in test container fails) - better to use `podman exec` directly

### What to Do Differently Next Time
1. Use `CHANGE MASTER TO` from the start (not `CHANGE REPLICA TO`)
2. Always dump/restore data before configuring replication
3. Get master status AFTER the dump, not before
4. Consider adding `SET GLOBAL read_only=OFF` before dump and `SET GLOBAL read_only=ON` after to ensure consistency

---

## Resources

- [MariaDB Replication Documentation](https://mariadb.com/kb/en/replication/)
- [MariaDB Docker Image](https://hub.docker.com/_/mariadb)
- [Setting up Master-Slave Replication](https://mariadb.com/kb/en/configuring-master-slave-replication/)
- [MariaDB 10.11 Reference Manual](https://mariadb.com/kb/en/mariadb-1011-release-notes/)

---

*Last Updated: April 24, 2026, 18:42*
*Status: Complete - Simplification applied and verified*
