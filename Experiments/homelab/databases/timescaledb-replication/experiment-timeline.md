# TimescaleDB Replication - Experiment Timeline

**Date:** April 18, 2026  
**Status:** Completed successfully

---

## Setup Phase

### Initial Container Start

All 4 containers started successfully on first attempt:
- `homelab-ts-primary` - started, ran init scripts
- `homelab-ts-standby` - started, entered wait loop
- `homelab-pgadmin-ts` - started
- `homelab-ts-test-client` - started

### Error 1: `$PGDATA` Variable Expansion

**Symptom:** Standby container exited with code 127 immediately after start.

**Logs showed:**
```
rm -rf ""/*;
pg_basebackup -h ts-primary -U replicator -D  -Fp -Xs -P -R -S standby_slot;
echo "standby_mode = on" >> "/postgresql.auto.conf";
```

**Root cause:** Podman-compose was expanding `$PGDATA` (and `$i` in the for loop) to empty strings before passing the command to the container shell. The YAML `>` block scalar preserves `$` literally, but podman-compose's `sh -c` wrapper performed shell expansion.

**Reference:** AGENTS.md notes "Single-quoted heredocs in compose commands don't expand variables; use echo statements instead" - but the actual issue was that podman-compose DOES expand variables in the command block.

**Resolution:** Replaced all `$PGDATA` references with the literal path `/var/lib/postgresql/data`. This avoids variable expansion entirely.

**Files affected:** `docker-compose.yml` standby service `command` block

### Error 2: `standby_mode` Parameter Not Recognized

**Symptom:** After fixing `$PGDATA`, standby started `pg_basebackup` successfully but PostgreSQL failed to start with:
```
unrecognized configuration parameter "standby_mode" in file "/var/lib/postgresql/data/postgresql.auto.conf" line 5
FATAL: configuration file contains errors
```

**Root cause:** PostgreSQL 12+ uses a `standby.signal` file to enter standby mode, not a `standby_mode` config parameter. The plan incorrectly used `echo "standby_mode = on" >> postgresql.auto.conf`.

**Resolution:** Replaced the `echo` line with `touch /var/lib/postgresql/data/standby.signal`.

**Files affected:** `docker-compose.yml` standby service `command` block

### Error 3: pgAdmin Email Validation

**Symptom:** pgAdmin container started but immediately exited with code 1.

**Logs showed:**
```
'admin@homelab.local' does not appear to be a valid email address.
The part after the @-sign is a special-use or reserved name that cannot be used with email.
```

**Root cause:** The `.local` TLD is reserved (RFC 6761) and pgAdmin's email validation rejects it.

**Resolution:** Changed email from `admin@homelab.local` to `admin@homelab.com`.

**Files affected:** `docker-compose.yml` pgadmin-ts service, `README.md`

### Error 4: Test Client DNS Resolution

**Symptom:** Test client could resolve `ts-primary` but not `ts-standby`:
```
server can't find ts-standby: NXDOMAIN
```

**Root cause:** The standby container was recreated manually (outside of `podman compose up`) without the `--network-alias ts-standby` flag. Podman's internal DNS only registers containers with proper aliases.

**Resolution:** Used the container's IP address directly for the test. For production, always start containers through `podman compose up` to ensure proper DNS registration.

---

## Verification Phase

All verification tests passed:

| Test | Command | Result |
|------|---------|--------|
| Primary healthy | `pg_isready -U replicator -d homelab_db` | Accepting connections |
| Standby healthy | `pg_isready -U replicator -d homelab_db` | Accepting connections |
| Replication streaming | `SELECT * FROM pg_stat_replication` | 1 streaming standby at <CONTAINER_IP> |
| Replication slot active | `SELECT * FROM pg_replication_slots` | standby_slot = active |
| Standby in recovery | `SELECT pg_is_in_recovery()` | t (true) |
| Write on primary | `INSERT INTO sensor_readings ...` | INSERT 0 1 |
| Read on standby | `SELECT ... FROM sensor_readings WHERE device_id = 'sensor-999'` | 99.9 celsius (replicated) |
| Standby rejects writes | `INSERT INTO sensor_readings ...` | ERROR: cannot execute INSERT in read-only transaction |
| Replication lag | `SELECT pg_wal_lsn_diff(...) AS lag_bytes` | 0 bytes |
| Test client to primary | `psql -h ts-primary ... SELECT COUNT(*)` | 290 rows |
| Failover promotion | `SELECT pg_promote()` | t (success) |
| Post-promotion check | `SELECT pg_is_in_recovery()` | f (not in recovery) |
| Write to promoted standby | `INSERT INTO sensor_readings ...` | INSERT 0 1 |

---

## Architecture Explanation

### Streaming Replication Flow

1. **Initialization:** `pg_basebackup` creates a physical copy of the primary's data directory on the standby
2. **WAL streaming:** The standby connects to the primary and receives WAL (Write-Ahead Log) records in real-time
3. **WAL replay:** The standby replays WAL records to stay in sync with the primary
4. **Replication slot:** `standby_slot` prevents the primary from recycling WAL segments that the standby hasn't received yet
5. **Read-only enforcement:** The standby runs PostgreSQL in recovery mode, which rejects all write transactions

### Why Hypertables Replicate Transparently

TimescaleDB hypertables are just PostgreSQL partitioned tables with some metadata. Since streaming replication operates at the PostgreSQL storage layer (WAL), all table types replicate the same way - no TimescaleDB-specific replication config is needed.

### Architecture Decision: Manual Container Start for Standby

The standby was started manually (`podman run`) rather than through `podman compose up` because:
- The compose `depends_on` for the standby didn't work reliably (known podman-compose issue)
- The standby needs to wait for the primary to be fully ready before `pg_basebackup`
- The wait loop in the command block handles this, but compose's healthcheck-based depends_on can be flaky

### Architecture Decision: Literal Paths vs `$PGDATA`

Using `/var/lib/postgresql/data` instead of `$PGDATA` avoids the variable expansion issue. The trade-off is slightly less portable (hard-coded path), but it works reliably with podman-compose.

---

## Testing Checklist

```
Experiment Setup Progress:
- [x] Compose file uses full image references
- [x] Ports are > 1024 (5436, 5437, 8085)
- [x] Test client container included
- [x] Healthcheck port matches service config
- [x] Volumes use hybrid strategy (named volumes for data)
- [x] Network name follows homelab-* pattern
- [x] README includes verification commands
- [x] Expected output samples provided
- [x] experiment-timeline.md documents errors and resolutions
```

---

## Resource Usage

| Container | RAM | CPU | Notes |
|-----------|-----|-----|-------|
| homelab-ts-primary | 6.8 MB | 0.31% | Very light with ~290 rows |
| homelab-ts-standby | 6.8 MB | 0.43% | Similar to primary |
| homelab-pgadmin-ts | varies | 0% | Flask web app |
| homelab-ts-test-client | 49 KB | 1.28% | Alpine sleep process |

**Total:** ~14 MB RAM for both PostgreSQL instances. Well under the ~500MB budget. The plan's 150MB estimate per instance was conservative.

---

## Lessons Learned

1. **Always use literal paths in compose command blocks** - shell variable expansion by podman-compose is unpredictable
2. **PostgreSQL 12+ uses `standby.signal` file** - not `standby_mode` config parameter
3. **pgAdmin rejects `.local` TLD** - use `.com` or another valid domain
4. **Manually started containers need explicit `--network-alias`** - otherwise DNS resolution fails
5. **`podman compose depends_on` is unreliable** - use command-level wait loops instead
6. **RAM usage is much lower than expected** - PostgreSQL instances used ~7MB each with minimal data

---

## Simplification Cleanup (April 25, 2026)

Applied per-experiment simplification plan (Phases 1-6, 8):

| Phase | Changes |
|-------|---------|
| 1 - Trivial | Removed `version: '3.8'`; pinned `timescaledb:2.26.3-pg17`, `pgadmin4:9.9.0` |
| 2 - Test-Client | `alpine:latest` → `Dockerfile.test-client` (alpine:3.21 + tools); container → `homelab-timescaledb-replication-test` |
| 3 - Secrets | Extracted `POSTGRES_PASSWORD`, `PGADMIN_PASSWORD` to `.env`/`.env.example` |
| 4 - Network | `ts-replication-network` + `name:` → `homelab-timescaledb-replication` |
| 5 - Volumes | `primary_data` → `timescaledb-replication_primary_data` (etc.) |
| 6 - Ports | 5436→15436, 5437→15437, 8085→18086 |
| 8 - README | Updated ports, added Services table, Testing section with test-client commands |

### Issues Encountered
- **`$i` variable expansion in standby command**: podman-compose expands `$i` to empty in `sh -c` blocks. Fixed with `$$i` escape (cosmetic only — loop logic still works).
- **Old network/volumes**: Had to manually remove `homelab-ts-replication-network` and leftover volumes before clean start.

### Verification Results
All tests passed:
- Primary: accepting connections ✓
- Standby: accepting connections, `pg_is_in_recovery() = t` ✓
- Replication: 1 streaming standby, sent_lsn = replay_lsn ✓
- Write on primary → read on standby: replicated successfully ✓
- Standby rejects writes: `ERROR: cannot execute INSERT in a read-only transaction` ✓
