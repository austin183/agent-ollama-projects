# PostgreSQL + pgAdmin

## Overview

This experiment sets up PostgreSQL 16 with pgAdmin 4 for database management and visualization on the homelab.

## Quick Start

```bash
cd ~/homelab/databases/postgresql-pgadmin
podman compose up -d
```

## Services

| Service | Port | Purpose |
|---------|------|---------|
| PostgreSQL | 15432 | Relational database (container: 5432) |
| pgAdmin | 18081 | Web-based database administration (container: 80) |

## Testing

```bash
# Check container status
podman ps | grep homelab-pg

# Test connectivity from test client
podman exec homelab-postgresql-pgadmin-test ping postgresql
podman exec homelab-postgresql-pgadmin-test nslookup postgresql

# Test database query
POSTGRES_PASS=$(grep POSTGRES_PASSWORD .env | cut -d= -f2)
podman exec homelab-postgresql-pgadmin-test sh -c "PGPASSWORD=$POSTGRES_PASS psql -h postgresql -U homelab -d homelab_db -c 'SELECT * FROM users;'"
```

### Expected Output

```
 username |        email
----------+----------------------
 alice    | alice@homelab.local
 bob      | bob@homelab.local
 charlie  | charlie@homelab.local
(3 rows)
```

## Access

### pgAdmin Web UI
- URL: http://localhost:18081
- Email: admin@homelab.localdomain
- Password: configured in `.env` as `PGADMIN_DEFAULT_PASSWORD`

### Direct PostgreSQL Connection
- Host: localhost
- Port: 15432
- Database: homelab_db
- User: homelab
- Password: configured in `.env` as `POSTGRES_PASSWORD`

## Adding pgAdmin Server

1. Open pgAdmin at http://localhost:18081
2. Click **Register Server** (or **+** icon under Servers)
3. Configuration:
    - **Name**: PostgreSQL
    - **Host name/address**: postgresql
    - **Port**: 5432
    - **Database**: postgres
    - **Username**: homelab
    - **Password**: value of `POSTGRES_PASSWORD` from `.env`
4. Click **Save**

## Troubleshooting

### Port 15432 already in use
```bash
# Check what's using port 15432
ss -tlnp | grep 15432

# Stop conflicting service or change host port in docker-compose.yml
```

### pgAdmin won't connect to PostgreSQL
- Ensure you're using service name `postgresql` (not `homelab-postgresql`)
- Check PostgreSQL is healthy: `podman exec homelab-postgresql pg_isready -U homelab`

### Data persistence
Data is stored in named volumes:
```bash
podman volume ls | grep postgresql-pgadmin
podman volume inspect homelab-postgresql-pgadmin_postgresql_data
```

### Changing secrets
After modifying `.env`, always clean and restart:
```bash
podman compose down -v
podman compose up -d
```

## Cleanup

```bash
# Stop containers (preserve data)
podman compose down

# Stop and remove volumes (WARNING: deletes all data!)
podman compose down -v
```
