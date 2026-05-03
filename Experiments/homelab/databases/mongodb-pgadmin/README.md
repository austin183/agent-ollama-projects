# MongoDB + pgAdmin

Playground for comparing MongoDB (NoSQL) with PostgreSQL admin tools in a single isolated network.

## Quick Start

```bash
cd ~/homelab/databases/mongodb-pgadmin

# Ensure .env exists with MONGO_INITDB_ROOT_PASSWORD
cp .env.example .env  # if starting fresh

# Start the experiment
podman compose up -d

# Watch logs
podman compose logs -f

# Stop the experiment
podman compose down

# Stop and remove all data
podman compose down -v
```

## Services

| Service | Image | Host Port | Container Port | Purpose |
|---------|-------|-----------|----------------|---------|
| mongodb | mongo:7.0 | 27017 | 27017 | NoSQL document database |
| pgadmin | dpage/pgadmin4:9.9.0 | 18085 | 80 | PostgreSQL admin web UI |
| test-client | alpine:3.21 | - | - | Connectivity testing |

## Testing

```bash
# Check containers are running
podman ps --filter network=homelab-mongodb-pgadmin

# Test MongoDB connectivity
podman exec homelab-mongodb mongosh --eval "db.adminCommand('ping')"

# Test from test-client
podman exec homelab-mongodb-pgadmin-test sh -c "ping -c 2 mongodb"
podman exec homelab-mongodb-pgadmin-test sh -c "ping -c 2 pgadmin"

# Query MongoDB with auth
MONGO_PASS=$(grep MONGO_INITDB_ROOT_PASSWORD .env | cut -d= -f2)
podman exec homelab-mongodb mongosh -u admin -p "$MONGO_PASS" --authenticationDatabase admin --eval "show dbs"
```

## Troubleshooting

- **MongoDB healthcheck fails initially**: MongoDB takes ~15-30 seconds to fully start. The healthcheck has a 30s start_period.
- **Can't connect with mongosh**: The `mongosh` client is inside the container. Use `podman exec homelab-mongodb mongosh`.
- **pgAdmin not accessible on port 18085**: pgAdmin may take 30-60 seconds to initialize on first run. Check logs: `podman logs homelab-pgadmin | grep -i "ready"`
- **Stale data on restart**: If MongoDB data seems corrupted, remove the volume: `podman compose down -v && podman compose up -d`
- **Password authentication errors**: Ensure `.env` file exists with the correct `MONGO_INITDB_ROOT_PASSWORD` value.

## Cleanup

```bash
podman compose down -v
```

## Architecture

```
┌─────────────────────────────────────────────────┐
│            homelab-mongodb-pgadmin               │
│                                                  │
│  ┌──────────────┐    ┌──────────────────┐       │
│  │   mongodb    │    │     pgadmin      │       │
│  │  MongoDB 7.0 │    │   pgAdmin 9.9.0  │       │
│  │  :27017      │    │    :80           │       │
│  └──────────────┘    └──────────────────┘       │
│        │                    │                    │
│        └──── test-client ───┘                    │
│              (Alpine 3.21)                       │
└─────────────────────────────────────────────────┘
```

## MongoDB Shell Commands Reference

```bash
# Connect to MongoDB shell
podman exec -it homelab-mongodb mongosh

# Connect with credentials
MONGO_PASS=$(grep MONGO_INITDB_ROOT_PASSWORD .env | cut -d= -f2)
podman exec homelab-mongodb mongosh -u admin -p "$MONGO_PASS"

# Switch to admin database
use admin

# List databases
show dbs

# Switch to homelab database
use homelab

# List collections
show collections

# Find all documents in a collection
db.users.find().pretty()

# Count documents
db.products.countDocuments()

# Aggregation example
db.metrics.aggregate([
  { $group: { _id: null, avgValue: { $avg: "$value" } } }
])

# Create a new collection and insert
db.orders.insertOne({
  item: "Mouse",
  price: 29.99,
  quantity: 5,
  orderDate: new Date()
})

# Create an index
db.users.createIndex({ email: 1 }, { unique: true })

# Update a document
db.users.updateOne(
  { name: "Alice" },
  { $set: { role: "superadmin" } }
)

# Delete a document
db.users.deleteOne({ name: "Charlie" })
```

## Sample Data

On first startup, the following sample data is created in the `homelab` database:

- **users** (3 docs): Alice, Bob, Charlie with roles and emails
- **products** (4 docs): Electronics and office supplies with prices
- **metrics** (3 docs): CPU, memory, and disk I/O metrics
- **sessions** (1 doc): Demo session with TTL index for auto-expiry

## Credentials

### MongoDB
- Root username: `admin`
- Root password: set in `.env` as `MONGO_INITDB_ROOT_PASSWORD`

### pgAdmin
- Email: `admin@homelab.com`
- Password: `pgadmin_pass_123`

Access pgAdmin at http://127.0.0.1:18085

To add a PostgreSQL server in pgAdmin:
1. Right-click "Servers" → "Register" → "Server"
2. Name: any name (e.g., "Local PostgreSQL")
3. Host: `homelab-postgresql` (service name on network) or connect via host IP
4. Port: `5432`
5. Maintenance DB: `postgres`
6. Username: `postgres`

## Resource Usage

After startup, check resource usage:

```bash
# Live stats for all containers
podman stats --format "table {{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}\t{{.NetIO}}"

# Storage used by volume
podman volume inspect mongodb-pgadmin_mongodb_data --format '{{.Mountpoint}}'
du -sh ~/.local/share/containers/storage/volumes/*
```

Typical idle usage:
- MongoDB: ~200-400 MB RAM
- pgAdmin: ~100-200 MB RAM
- Total: ~300-600 MB RAM

## Volume Strategy

- **Named volume** (`mongodb-pgadmin_mongodb_data`): MongoDB data directory at `/data/db`
  - Managed by Podman, persists across container rebuilds
  - Data survives `podman compose down` (without `-v`)
- **Bind mount** for init scripts (`./init-scripts`): Version-controlled, editable on host

## Design Decisions

### Why MongoDB 7.0?
- Current LTS version with stable feature set
- Good documentation and community support
- Supports multi-document ACID transactions

### Why port 27017?
- MongoDB's default port, no conflict with existing services
- Port 27017 was confirmed free before deployment

### Why include pgAdmin?
- Allows comparing MongoDB queries against PostgreSQL queries
- pgAdmin provides a familiar SQL interface for contrast
- Can connect to other PostgreSQL containers on the same network

### Why hybrid volume strategy?
- Named volume for MongoDB data (Podman-managed, cleaner lifecycle)
- Bind mount for init scripts (editable on host, version-controlled)

## Next Steps

- Try MongoDB vs PostgreSQL query patterns side by side
- Import real data into MongoDB collections
- Set up pgAdmin to connect to the PostgreSQL containers in `databases/postgresql-pgadmin/`
- Experiment with MongoDB aggregation pipelines
- Test replica set setup (future experiment)
