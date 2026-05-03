# TimescaleDB Time-Series Database Experiment

## Overview

Demonstrates TimescaleDB, a PostgreSQL extension that provides automatic partitioning, compression, and retention policies for time-series data while maintaining full SQL compatibility.

## Quick Start

```bash
cd databases/timescaledb
cp .env.example .env
podman compose up -d
```

## Services

| Service | Port | Purpose |
|---------|------|---------|
| timescaledb | 15433 (host) → 5432 (container) | TimescaleDB time-series database |
| test-client | N/A | Alpine container for connectivity verification |

## Testing

```bash
# Check container status
podman ps | grep timescaledb

# Verify TimescaleDB extension
podman exec homelab-timescaledb psql -U homelab -d homelab_db -c "SELECT extversion FROM pg_extension WHERE extname = 'timescaledb';"

# Query sample data
podman exec homelab-timescaledb psql -U homelab -d homelab_db -c "SELECT device_id, sensor_type, value, time FROM sensor_readings ORDER BY time DESC LIMIT 5;"

# Test connectivity from test client
podman exec homelab-timescaledb-test ping -c 3 homelab-timescaledb

# Hypertable properties
podman exec homelab-timescaledb psql -U homelab -d homelab_db -c "SELECT hypertable_name, num_chunks FROM timescaledb_information.hypertables;"
```

## Troubleshooting

- **Init scripts not running**: Init scripts in `/docker-entrypoint-initdb.d/` only run on first start with empty data volume. Run `podman compose down -v` then `podman compose up -d` to re-run them.
- **Port conflicts**: Port 15433 should be free. Check with `ss -tlnp | grep 15433`.
- **Connection refused**: Wait for healthcheck to pass (`podman ps | grep timescaledb` should show `healthy`).
- **Wrong password**: Ensure `.env` file exists with `POSTGRES_PASSWORD` set. The `.env` file is gitignored.
- **Shebang errors**: PostgreSQL init scripts are raw SQL — do not include `#!/usr/bin/env psql` or similar shebang lines.

## Cleanup

```bash
# Stop and keep data
podman compose down

# Stop and remove data (careful!)
podman compose down -v
```

---

## How It Works

TimescaleDB is a PostgreSQL extension that transforms regular PostgreSQL tables into efficient time-series hypertables. It provides automatic partitioning, compression, and retention policies while maintaining full SQL compatibility.

**Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│                    homelab-timescaledb-network                │
│                                                               │
│  ┌─────────────────────┐         ┌──────────────────┐       │
│  │   homelab-          │         │  homelab-        │       │
│  │   timescaledb       │◄────────│  timescaledb-test│       │
│  │                     │  psql   │  (Alpine)        │       │
│  │  Port 15433:5432    │         │                  │       │
│  │                     │         │  Connectivity    │       │
│  │  Hypertable:        │         │  verification    │       │
│  │  sensor_readings    │         │                  │       │
│  └─────────────────────┘         └──────────────────┘       │
│                                                               │
│  Volume: timescaledb_timescaledb_data (/var/lib/postgresql/   │
│          data)                                                │
└─────────────────────────────────────────────────────────────┘
```

**Data Flow:**
1. Container starts with init script that creates TimescaleDB extension and sample hypertable
2. Sample sensor data inserted (temperature, humidity, pressure over 24 hours)
3. Retention policy auto-drops data older than 7 days
4. Test client verifies connectivity and runs queries

## Verification Commands

### 1. Check container status
```bash
podman ps | grep timescaledb
```

**Expected output:**
```
homelab-timescaledb   Up ... (healthy)
```

### 2. Verify TimescaleDB extension is loaded
```bash
podman exec homelab-timescaledb psql -U homelab -d homelab_db -c "SELECT * FROM pg_extension WHERE extname = 'timescaledb';"
```

**Expected output:**
```
 oid  |   extname    | extowner | extnamespace | extrelocatable | extversion | extconfig | extcondition
------+--------------+----------+--------------+----------------+------------+-----------+--------------
 34626| timescaledb  |       10 |        2200 | f              | 2.26.3     |           |
(1 row)
```

### 3. Verify hypertable was created
```bash
podman exec homelab-timescaledb psql -U homelab -d homelab_db -c "\dt+"
```

**Expected output:**
```
 Schema |        Name        | Type  |  Owner   | Persistence | Access method |  Size   | Description
--------+--------------------+-------+----------+-------------+---------------+---------+-------------
 public | _timescaledb_...   | table | postgres | permanent   | heap          | 10 MB   |
 public | sensor_readings    | table | homelab  | permanent   | heap          | 8192 bytes|
(2 rows)
```

### 4. Query sample data
```bash
podman exec homelab-timescaledb psql -U homelab -d homelab_db -c "SELECT device_id, sensor_type, value, unit, time FROM sensor_readings ORDER BY time DESC LIMIT 10;"
```

**Expected output:**
```
 device_id | sensor_type | value  |  unit   |         time
-----------+-------------+--------+---------+------------------------
 sensor-002| humidity    |   49.5 | percent | 2026-04-18 15:31:00+00
 sensor-001| temperature |  22.9  | celsius | 2026-04-18 14:31:00+00
 sensor-001| temperature |  23.5  | celsius | 2026-04-18 13:31:00+00
 sensor-003| pressure    | 1011.8 | hPa     | 2026-04-18 12:31:00+00
 sensor-003| pressure    | 1012.5 | hPa     | 2026-04-18 11:31:00+00
(5 rows)
```

### 5. Verify hypertable properties
```bash
podman exec homelab-timescaledb psql -U homelab -d homelab_db -c "SELECT hypertable_name, num_chunks FROM timescaledb_information.hypertables;"
```

**Expected output:**
```
 hypertable_name | num_chunks
-----------------+------------
 sensor_readings |          1
(1 row)
```

### 6. Verify retention policy
```bash
podman exec homelab-timescaledb psql -U homelab -d homelab_db -c "SELECT job_id, hypertable_name FROM timescaledb_information.job_stats WHERE hypertable_name = 'sensor_readings';"
```

**Expected output:**
```
 job_id | hypertable_name
--------+-----------------
   1000 | sensor_readings
(1 row)
```

### 7. Test connectivity from test client
```bash
podman exec homelab-timescaledb-test ping -c 3 homelab-timescaledb
```

**Expected output:**
```
PING homelab-timescaledb (172.x.x.x): 56 data bytes
64 bytes from 172.x.x.x: seq=0 ttl=64 time=0.123 ms
64 bytes from 172.x.x.x: seq=1 ttl=64 time=0.089 ms
64 bytes from 172.x.x.x: seq=2 ttl=64 time=0.095 ms

--- homelab-timescaledb ping statistics ---
3 packets transmitted, 3 received, 0% packet loss
```

### 8. Query from test client using psql
```bash
podman exec homelab-timescaledb-test sh -c "apk add --no-cache postgresql-client 2>/dev/null && psql -h homelab-timescaledb -U homelab -d homelab_db -c 'SELECT COUNT(*) FROM sensor_readings;'"
```

**Expected output:**
```
 count
-------
    24
(1 row)
```

## Common Pitfalls

### Port conflicts
- Port 5432 is commonly used by PostgreSQL. This experiment uses **15433** on the host to avoid conflicts with the existing PostgreSQL instance (port 5432) and metadata-extractor (port 25433).

### Init scripts timing
- Init scripts in `/docker-entrypoint-initdb.d/` only run on **first start** with empty data volume
- If you need to re-run init scripts, delete the volume: `podman compose down -v`
- After recreating, the init script will run again

### TimescaleDB version compatibility
- The `2.26.3-pg17` tag uses PostgreSQL 17 with TimescaleDB 2.26.3
- If you need a specific PostgreSQL version, use tags like `latest-pg16` or `latest-pg15`

### Resource usage
- TimescaleDB inherits PostgreSQL's resource profile
- With default settings, expect ~200-300MB RAM for this lightweight setup
- The hypertable chunks add minimal overhead

## Design Decisions

### Why TimescaleDB over InfluxDB?
- **SQL compatibility:** Uses familiar PostgreSQL syntax, easier migration for existing PostgreSQL users
- **Single database:** No need to manage separate TSDB + PostgreSQL
- **Rich ecosystem:** Full PostgreSQL tooling (pgAdmin, DBeaver, etc.) works
- **Extensions:** Can leverage other PostgreSQL extensions (PostGIS, etc.)

### Why port 15433 instead of 5432?
- Existing PostgreSQL experiment uses port 5432
- metadata-extractor experiment uses port 25433
- Avoids conflicts when running multiple database experiments

### Volume strategy
- **Named volume** `timescaledb_timescaledb_data` for data directory (managed by Podman, easier backup/restore)
- **Bind mount** for init scripts (editable on host, version controlled)

### Secret management
- `POSTGRES_PASSWORD` extracted to `.env` file (gitignored)
- `.env.example` provided with placeholder values for reference

## Next Steps

- Connect with pgAdmin or DBeaver for GUI access (host: `localhost:15433`, user: `homelab`, password: from `.env`)
- Create additional hypertables for different sensor types
- Experiment with continuous aggregates for pre-computed summaries
- Test data compression on older chunks
- Set up remote access from other homelab services
