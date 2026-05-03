# TimescaleDB Experiment - Timeline

## Simplification Phase (April 24, 2026)

### Phase 1 - Trivial Cleanup
- **Removed** `version: '3.8'` line from compose file
- **Pinned** TimescaleDB image tag `latest-pg17` → `2.26.3-pg17`
- **Pinned** Alpine test-client tag `latest` → `3.21`

### Phase 2 - Test-Client Standardization
- **Renamed** container_name from `homelab-ts-test-client` → `homelab-timescaledb-test`
- **Standardized** image to `docker.io/alpine:3.21`

### Phase 3 - Secret Hygiene
- **Created** `.env` file with `POSTGRES_PASSWORD=changeme123`
- **Created** `.env.example` with placeholder values and comments
- **Replaced** hardcoded `POSTGRES_PASSWORD=changeme123` with `${POSTGRES_PASSWORD}` in compose file
- **Verified** `.env` is excluded by repo root `.gitignore` (line 37: `.env`)

### Phase 4 - Network Naming
- **Renamed** network key from `timescaledb-network` → `homelab-timescaledb`
- **Removed** redundant `name: homelab-timescaledb-network` field

### Phase 5 - Volume Naming
- **Renamed** volume from `ts_data` → `timescaledb_timescaledb_data`
- **Updated** all service references to use new volume name

### Phase 6 - Port Conflicts
- **Fixed** host port from `5433` → `15433` per plan (conflict with metadata-extractor's port 25433)
- **Verified** port 15433 was free before starting

### Phase 8 - README Updates
- **Added** Overview section (1-2 sentences)
- **Added** Quick Start section
- **Added** Services table
- **Added** Testing section with key commands
- **Updated** Troubleshooting section with new port reference
- **Added** Secret management note
- **Updated** architecture diagram with new names/ports
- **Updated** all verification command references (container names, ports)

### Verification Results
- **Container status:** Both containers running and healthy ✅
- **TimescaleDB extension:** Version 2.26.3 loaded ✅
- **Hypertable:** `sensor_readings` with 1 chunk ✅
- **Sample data:** 24 records accessible ✅
- **Network connectivity:** 0% packet loss from test-client ✅
- **Port mapping:** 15433:5432 working correctly ✅

## Setup Phase

### Initial Setup
- **Date:** April 18, 2026
- **Action:** Created directory structure at `~/homelab/databases/timescaledb/`
- **Action:** Created `docker-compose.yml` with TimescaleDB + test client
- **Action:** Created init script at `init-scripts/01-init.sql`

### Error 1: Init Script Shebang Line
- **Error:** `syntax error at or near "#!/" at character 1`
- **Root Cause:** PostgreSQL init scripts don't support shebang lines (`#!/usr/bin/env psql`)
- **Resolution:** Removed the shebang line from `01-init.sql`
- **Lesson:** PostgreSQL init scripts are executed as raw SQL, not shell scripts

### Error 2: Volume Recreation Required
- **Issue:** After fixing the init script, the hypertable and sample data were not created
- **Root Cause:** Init scripts only run on first start with empty data volume
- **Resolution:** Ran `podman compose down -v` to remove the volume, then `podman compose up -d` to recreate
- **Lesson:** Always use `-v` flag when changing init scripts for time-series DB experiments

## Verification Phase

### Test 1: TimescaleDB Extension
- **Command:** `podman exec homelab-timescaledb psql -U homelab -d homelab_db -c "SELECT * FROM pg_extension WHERE extname = 'timescaledb';"`
- **Result:** ✅ Extension loaded (version 2.26.3)
- **Output:**
```
oid  |   extname   | extowner | extnamespace | extrelocatable | extversion | extconfig | extcondition
-----+-------------+----------+--------------+----------------+------------+-----------+--------------
16385| timescaledb |       10 |         2200 | f              | 2.26.3     | {...}     | {"","WHERE id >= 1",...}
```

### Test 2: Hypertable Creation
- **Command:** `podman exec homelab-timescaledb psql -U homelab -d homelab_db -c "\dt+"`
- **Result:** ✅ Hypertable `sensor_readings` created
- **Output:**
```
Schema |      Name       | Type  |  Owner  | Persistence | Access method |    Size    | Description
--------+-----------------+-------+---------+-------------+---------------+------------+-------------
public | sensor_readings | table | homelab | permanent   | heap          | 8192 bytes |
```

### Test 3: Sample Data Query
- **Command:** `podman exec homelab-timescaledb psql -U homelab -d homelab_db -c "SELECT device_id, sensor_type, value, unit, time FROM sensor_readings ORDER BY time DESC LIMIT 10;"`
- **Result:** ✅ 24 sample records inserted (temperature, humidity, pressure)
- **Output:** 10 most recent records retrieved successfully

### Test 4: Hypertable Properties
- **Command:** `podman exec homelab-timescaledb psql -U homelab -d homelab_db -c "SELECT hypertable_name, num_chunks FROM timescaledb_information.hypertables;"`
- **Result:** ✅ Hypertable with 1 chunk
- **Output:**
```
hypertable_name | num_chunks
-----------------+------------
sensor_readings |          1
```

### Test 5: Retention Policy
- **Command:** `podman exec homelab-timescaledb psql -U homelab -d homelab_db -c "SELECT job_id, hypertable_name FROM timescaledb_information.job_stats WHERE hypertable_name = 'sensor_readings';"`
- **Result:** ✅ Retention policy job active (job_id 1000)
- **Output:**
```
job_id | hypertable_name
--------+-----------------
   1000 | sensor_readings
```

### Test 6: Network Connectivity
- **Command:** `podman exec homelab-ts-test-client ping -c 3 homelab-timescaledb`
- **Result:** ✅ 0% packet loss
- **Output:**
```
PING homelab-timescaledb (<CONTAINER_IP>): 56 data bytes
64 bytes from <CONTAINER_IP>: seq=0 ttl=42 time=0.081 ms
64 bytes from <CONTAINER_IP>: seq=1 ttl=42 time=0.068 ms
64 bytes from <CONTAINER_IP>: seq=2 ttl=42 time=0.076 ms
--- homelab-timescaledb ping statistics ---
3 packets transmitted, 3 packets received, 0% packet loss
```

## Configuration Phase

### Manual Steps Taken
1. Created `docker-compose.yml` with TimescaleDB + test client
2. Created init script with sample sensor data (24 records over 24 hours)
3. Fixed init script by removing shebang line
4. Recreated volume to re-run init script
5. Verified all components are working

### Architecture Explanation

```
┌─────────────────────────────────────────────────────────────┐
│                     homelab-timescaledb-network              │
│                                                             │
│  ┌─────────────────────┐         ┌──────────────────┐      │
│  │   homelab-          │         │  homelab-ts-     │      │
│  │   timescaledb       │◄────────│  test-client     │      │
│  │                     │  psql   │  (Alpine)        │      │
│  │  Port 5433:5432     │         │                  │      │
│  │                     │         │  Connectivity    │      │
│  │  Hypertable:        │         │  verification    │      │
│  │  sensor_readings    │         │                  │      │
│  └─────────────────────┘         └──────────────────┘      │
│                                                             │
│  Volume: ts_data (/var/lib/postgresql/data)                 │
└─────────────────────────────────────────────────────────────┘
```

**Key Concepts:**
- **Hypertable:** TimescaleDB's core abstraction - automatically partitions data by time
- **Chunk:** A single partition of the hypertable (currently 1 chunk for 24 hours of data)
- **Retention Policy:** Background job (job_id 1000) that auto-drops data older than 7 days
- **Extension:** TimescaleDB loads as a PostgreSQL extension (version 2.26.3)

## Design Decisions

### Why TimescaleDB over InfluxDB?
- **SQL compatibility:** Uses familiar PostgreSQL syntax, easier migration for existing PostgreSQL users
- **Single database:** No need to manage separate TSDB + PostgreSQL
- **Rich ecosystem:** Full PostgreSQL tooling (pgAdmin, DBeaver, etc.) works
- **Extensions:** Can leverage other PostgreSQL extensions (PostGIS, etc.)

### Why port 5433 instead of 5432?
- Existing PostgreSQL experiment uses port 5432
- Avoids conflicts when running multiple database experiments

### Volume strategy
- **Named volume** for data directory (managed by Podman, easier backup/restore)
- **Bind mount** for init scripts (editable on host, version controlled)

## Testing Checklist

### Original Setup (April 18)
```
Experiment Setup Progress:
- [x] Compose file uses full image references (docker.io/timescale/timescaledb:latest-pg17)
- [x] Ports are > 1024 (5433:5432)
- [x] Test client container included (homelab-ts-test-client)
- [x] Healthcheck port matches service config (pg_isready)
- [x] Volumes use hybrid strategy (named + bind)
- [x] Network name follows homelab-* pattern (homelab-timescaledb-network)
- [x] README includes wizard steps (if applicable)
- [x] Verification commands documented
- [x] Expected output samples provided
```

### Post-Simplification (April 24)
```
Simplification Checklist:
- [x] Phase 1: Removed version line, pinned image tags (2.26.3-pg17, alpine:3.21)
- [x] Phase 2: Test-client container renamed to homelab-timescaledb-test
- [x] Phase 3: POSTGRES_PASSWORD extracted to .env file
- [x] Phase 4: Network key renamed to homelab-timescaledb, redundant name: removed
- [x] Phase 5: Volume renamed to timescaledb_timescaledb_data
- [x] Phase 6: Host port changed from 5433 to 15433
- [x] Phase 8: README updated with template sections
- [x] Verification: All tests pass with new configuration
```

## Common Questions Answered

### Q: Why is the init script not running?
**A:** Init scripts in `/docker-entrypoint-initdb.d/` only run on first start with empty data volume. If you need to re-run them, delete the volume with `podman compose down -v`.

### Q: Can I connect with pgAdmin or DBeaver?
**A:** Yes! Connect to `localhost:15433` with user `homelab`, password from `.env`, database `homelab_db`.

### Q: How much RAM does this use?
**A:** ~200-300MB for this lightweight setup with sample data.

### Q: What happens to the sample data after 7 days?
**A:** The retention policy automatically drops data older than 7 days. The background job runs daily to clean up old chunks.

### Q: Can I add more sensor types?
**A:** Yes! Just create additional tables and convert them to hypertables:
```sql
CREATE TABLE cpu_readings (...);
SELECT create_hypertable('cpu_readings', 'time');
```

## Resource Usage

| Resource | Budget | Actual | Notes |
|----------|--------|--------|-------|
| RAM | 500MB | ~7MB | Extremely lightweight with sample data |
| Storage | 1GB + growth | ~48MB | Initial download ~300MB, data dir 47.7MB |
| CPU | Background | 1.14% | No background tasks running |
| PIDs | - | 8 | 8 processes for PostgreSQL + TimescaleDB |

## Lessons Learned

### What Worked
- TimescaleDB extension loads cleanly in the container
- Init scripts work well for setting up sample data
- Network connectivity between containers is reliable
- Port mapping (15433:5432) avoids conflicts with existing PostgreSQL and metadata-extractor
- Secret extraction to .env file works correctly with podman-compose
- Image pinning to specific versions (2.26.3-pg17) improves reproducibility

### What Didn't Work
- Shebang lines in SQL init scripts cause syntax errors
- Retention policy view names differ between TimescaleDB versions
- Volume recreation is required when changing init scripts

### What to Do Differently Next Time
- Test init scripts locally before running in containers
- Check TimescaleDB version-specific documentation for view names
- Consider using a Dockerfile to bake in init scripts for reproducibility
- Apply simplification phases during initial setup rather than retroactively
