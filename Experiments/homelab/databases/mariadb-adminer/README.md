# MariaDB + Adminer

## Overview

This experiment sets up MariaDB 11 with Adminer for database management and visualization.

## Quick Start

```bash
# Change to directory
cd ~/homelab/databases/mariadb-adminer
# Create .env file with the passwords
cp .env.example .env
# Start the containers for the experiment
podman compose up -d
```

## Services

| Service | Host Port | Container Port | Purpose |
|---------|-----------|----------------|---------|
| mariadb | 13306 | 3306 | MariaDB database |
| adminer | 18080 | 8080 | Web-based DB admin UI |
| test-client | — | — | Connectivity testing |

## Testing

```bash
# Check all containers are running
podman ps | grep homelab-mariadb

# Test connectivity from test client
podman exec homelab-mariadb-adminer-test ping mariadb
podman exec homelab-mariadb-adminer-test ping adminer

# Test queries (replace -p${MARIADB_PASSWORD} with -pPasswordFromEnv)
podman exec homelab-mariadb-adminer-test mariadb -h mariadb -u homelab -p${MARIADB_PASSWORD} -D homelab_db -e "SELECT * FROM users;"
```

## Expected Output

```
+---------+---------------------+
| username | email               |
+---------+---------------------+
| alice   | alice@homelab.local |
| bob     | bob@homelab.local   |
| charlie | charlie@homelab.local |
+---------+---------------------+
```

## Troubleshooting

### Port 13306 already in use
```bash
# Check what's using port 13306
ss -tlnp | grep 13306
```

### Adminer won't connect to MariaDB
- Ensure you're using service name `mariadb` (not `homelab-mariadb`) from within network
- Check MariaDB is healthy: `podman exec homelab-mariadb mysqladmin -u root -p"${MARIADB_ROOT_PASSWORD}" ping`

### Data persistence
Data is stored in named volumes:
```bash
podman volume ls | grep mariadb-adminer
podman volume inspect mariadb-adminer_mariadb_data
```

### Changing passwords
1. Update `.env` with new values
2. Run `podman compose down -v` (required for MariaDB to pick up new passwords)
3. Run `podman compose up -d`

## Cleanup

```bash
# Stop containers (preserve data)
podman compose down

# Stop and remove volumes (WARNING: deletes all data!)
podman compose down -v
```
