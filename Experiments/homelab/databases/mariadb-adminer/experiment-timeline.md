# MariaDB + Adminer - Experiment Timeline

## Setup Phase

### Errors Encountered

1. **Volume naming issue**: Initial volume name `mariadb-adminer_mariadb_data` was doubled by podman-compose to `mariadb-adminer_mariadb-adminer_mariadb_data`. 
   - **Root cause**: podman-compose prefixes the project name (derived from directory name) to all named volumes.
   - **Resolution**: Changed volume name to `mariadb_data` so podman-compose creates `mariadb-adminer_mariadb_data` (correct).

### Files Created
- `.env` - Actual secret values (MARIADB_ROOT_PASSWORD, MARIADB_PASSWORD)
- `.env.example` - Template with placeholder values and comments

## Verification Phase

### Commands Run and Results

```bash
# Container status check
podman ps --filter label=io.podman.compose.project=mariadb-adminer
# Output:
# homelab-mariadb - Up 20 seconds (starting)
# homelab-mariadb-adminer - Up 19 seconds (healthy)
# homelab-mariadb-adminer-test - Up 18 seconds
```

```bash
# DNS resolution test
podman exec homelab-mariadb-adminer-test ping -c 2 mariadb
# Output: 2 packets transmitted, 2 packets received, 0% packet loss

podman exec homelab-mariadb-adminer-test ping -c 2 adminer
# Output: 2 packets transmitted, 2 packets received, 0% packet loss
```

```bash
# MariaDB root connectivity
podman exec homelab-mariadb-adminer-test sh -c 'mysql -h mariadb -u root -pchangeme_root -e "SELECT 1 AS test;"'
# Output: test | 1
```

```bash
# Application user and init data verification
podman exec homelab-mariadb-adminer-test sh -c 'mysql -h mariadb -u homelab -pchangeme123 -D homelab_db -e "SELECT * FROM users;"'
# Output:
# id | username | email                | created_at
# 1  | alice    | alice@homelab.local  | 2026-04-24 19:29:31
# 2  | bob      | bob@homelab.local    | 2026-04-24 19:29:31
# 3  | charlie  | charlie@homelab.local| 2026-04-24 19:29:31
```

### Interpretation
All containers started successfully. DNS resolution between services works. MariaDB init scripts executed correctly (users table populated). Application user can connect and query data.

## Architecture

### Services
- **mariadb**: MariaDB 11 database with init schema from `./init-scripts/01-init-schema.sql`
- **adminer**: Adminer 4 web-based database administration interface
- **test-client**: Alpine 3.21 container for connectivity testing

### Data Flow
1. MariaDB initializes with `MYSQL_ROOT_PASSWORD`, creates `homelab` user and `homelab_db` database
2. Init scripts in `/docker-entrypoint-initdb.d/` run once on first start (create tables + seed data)
3. Adminer connects to MariaDB using service name `mariadb` on the bridge network
4. Test client can reach both services by name for verification

### Design Decisions
- **Port 13306**: Moved from 3306 to avoid conflicts with host MySQL/MariaDB instances
- **Port 18080**: Moved from 8080 to avoid conflicts with adguard-home and openvino-server
- **Network `homelab-mariadb-adminer`**: Named consistently, redundant `name:` field dropped
- **Volume `mariadb_data`**: Simple name; podman-compose prefixes project name automatically
- **Adminer image pinned to `:4`**: Latest stable major version, avoids `:latest` tag
- **`.env` for secrets**: Root password and app password extracted from compose file

## Testing Checklist

```
Experiment Setup Progress:
- [x] Compose file uses full image references
- [x] Ports are > 1024 (13306, 18080)
- [x] Test client container included
- [x] Healthcheck port matches service config
- [x] Volumes use named volume strategy
- [x] Network name follows homelab-* pattern
- [x] README includes wizard steps (not applicable - no wizard)
- [x] Verification commands documented
- [x] Expected output samples provided
- [x] .env file created with actual secrets
- [x] .env.example created with placeholders
- [x] version: '3.8' removed
- [x] Alpine test-client pinned to 3.21
```

## Common Questions

**Q: Why is MariaDB taking longer to become healthy than Adminer?**
A: MariaDB's healthcheck runs `healthcheck.sh --connect --innodb_initialized` which waits for InnoDB to fully initialize. This can take 10-30s on first run. Adminer starts immediately since it's just a PHP web app.

**Q: What happens if I change passwords in .env?**
A: You must run `podman compose down -v` to wipe the database volume, then `podman compose up -d`. MariaDB only reads initial passwords on first start (when data directory is empty).

**Q: Can I access MariaDB from the host?**
A: Yes, on port 13306. Use `mysql -h localhost -P 13306 -u homelab -p` (note: MariaDB client uses `-P` for port, not `-p`).

## Resource Usage

- **MariaDB**: ~150-200MB RAM (typical for fresh MariaDB 11)
- **Adminer**: ~20-30MB RAM (PHP-FPM + web server)
- **Test client**: ~5MB RAM (alpine sleep process)
- **Total**: ~200-250MB RAM, minimal CPU
- **Storage**: ~50MB image sizes + volume for DB data (initially ~10MB with seed data)

## Lessons Learned

1. **Volume naming with podman-compose**: The project name prefix behavior means volume names should be simple (e.g., `mariadb_data`) rather than pre-prefixed. The resulting podman volume name will be `<project>_<volume>` = `mariadb-adminer_mariadb_data`.

2. **Port 13306 is safe**: No conflicts found. The host port allocation table was accurate.

3. **Adminer `:4` tag**: Pinned to major version 4 (current stable). This is more stable than `:latest` while still getting minor updates.

4. **README was already good**: The existing README had comprehensive documentation. Only needed port updates and container name changes.

## What Didn't Work

- Initial volume naming attempt (`mariadb-adminer_mariadb_data`) resulted in doubled project name. Had to restart with `podman compose down -v` and use simpler `mariadb_data` name.
