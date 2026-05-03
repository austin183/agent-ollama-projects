# MongoDB Replica Set (3-Node)

## Overview

This experiment sets up a MongoDB replica set with 3 data-bearing nodes:
- **Primary**: Read/write node (port 27018)
- **Secondary 1**: Read-only replica (port 27019)
- **Secondary 2**: Read-only replica (port 27020)
- **Test client**: Alpine container for verification
- **Credentials**: Set via `MONGO_ROOT_PASSWORD` in `.env` file

## Services

| Service | Host Port | Purpose |
|---------|-----------|---------|
| mongo1 | 27018 | Primary node (read/write) |
| mongo2 | 27019 | Secondary node (read-only) |
| mongo3 | 27020 | Secondary node (read-only) |
| mongo-init | — | Init container (exits after setup) |
| test-client | — | Verification client |

## How It Works

```
                    ┌─────────────────────────────────┐
                    │        Election Voting           │
                    │   (automatic failover ~12s)      │
                    └──────────┬──────────────────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                │
      ┌───────▼───────┐ ┌─────▼──────┐ ┌──────▼───────┐
      │   mongo1      │ │  mongo2    │ │   mongo3     │
      │  (Primary)    │ │ (Secondary)│ │ (Secondary)  │
      │  Port 27018   │ │ Port 27019 │ │ Port 27020   │
      │  Read/Write   │ │ Read-Only  │ │ Read-Only    │
      └───────────────┘ └────────────┘ └──────────────┘
              │                │                │
              └────────────────┼────────────────┘
                               │
                      Oplog Replication
                   (asynchronous, ~ms lag)
```

1. Primary receives all write operations and records them in the **oplog** (operation log)
2. Secondaries asynchronously replicate the oplog and apply operations
3. All 3 nodes participate in elections for automatic failover
4. If primary fails, secondaries elect a new primary within ~12 seconds
5. KeyFile authentication secures inter-node communication

## Quick Start

```bash
cd ~/homelab/databases/mongodb-replica-set
podman build -t localhost/homelab-mongo-replica:latest .
podman compose up -d
```

**Note**: First startup takes 2-3 minutes. The Dockerfile auto-generates a unique KeyFile for internal authentication, then the `mongo-init` container waits for all 3 nodes to be ready, initializes the replica set, and runs an election. After that it exits automatically. You can check progress with `podman logs homelab-mongo-init`.

**Regenerating the KeyFile**: The KeyFile is auto-generated during image build. To force a new KeyFile, rebuild with `--no-cache`:
```bash
podman build --no-cache -t localhost/homelab-mongo-replica:latest .
podman compose down -v
podman compose up -d
```

## Access

### Direct Database Connections

**Primary (Read/Write):**
- Host: localhost
- Port: 27018
- Username: admin
- Password: (see `.env` → `MONGO_ROOT_PASSWORD`)
- Auth Database: admin

**Secondary 1 (Read-Only):**
- Host: localhost
- Port: 27019
- Username: admin
- Password: (see `.env` → `MONGO_ROOT_PASSWORD`)
- Auth Database: admin

**Secondary 2 (Read-Only):**
- Host: localhost
- Port: 27020
- Username: admin
- Password: (see `.env` → `MONGO_ROOT_PASSWORD`)
- Auth Database: admin

## Verification Commands

> **Note:** Before running verification commands, load your `.env` file:
> ```bash
> export $(grep -v '^#' .env | xargs)
> ```

### Check container status
```bash
podman ps | grep homelab-mongo
```

### Check replica set status
```bash
podman exec homelab-mongo1 mongosh -u admin -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin --quiet --eval 'rs.status().members.forEach(function(m) { print(m.name + ": " + m.stateStr); })'
```

**Expected output:**
```
mongo1:27017: PRIMARY
mongo2:27017: SECONDARY
mongo3:27017: SECONDARY
```

### Check which node is primary
```bash
podman exec homelab-mongo1 mongosh -u admin -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin --quiet --eval 'rs.isMaster().ismaster'
```

**Expected output:**
```
true
```

### View replication lag on secondaries
```bash
podman exec homelab-mongo1 mongosh -u admin -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin --quiet --eval '
rs.status().members.forEach(function(m) {
  if (m.stateStr === "SECONDARY") {
    print(m.name + ": " + m.optimeDate + " (lag: " + (new Date() - new Date(m.optimeDate)) + "ms)");
  }
})
'
```

### Check replica set configuration
```bash
podman exec homelab-mongo1 mongosh -u admin -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin --quiet --eval 'rs.conf()'
```

### Test primary connectivity
```bash
podman exec homelab-mongo1 mongosh -u admin -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin --quiet --eval '
db.getSiblingDB("homelab").test_collection.insertOne({test: "replica_set", timestamp: new Date()});
db.getSiblingDB("homelab").test_collection.findOne({test: "replica_set"});
'
```

### Test secondary connectivity (read from secondary)
```bash
podman exec homelab-mongo2 mongosh -u admin -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin --quiet --eval '
db.getSiblingDB("homelab").test_collection.findOne({test: "replica_set"});
'
```

**Note**: All commands use `podman exec` because `mongosh` is not installed on the host. If you prefer to use `mongosh` directly, install it first:
```bash
# Debian/Ubuntu
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-keyring.gpg
echo "deb [ signed-by=/usr/share/keyrings/mongodb-keyring.gpg ] http://repo.mongodb.org/apt/debian bookworm/mongodb-org/7.0 main" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
sudo apt update && sudo apt install -y mongodb-mongosh

# Or use the test-client container:
podman exec -it homelab-mongodb-replica-test sh -c "apk add --no-cache mongodb-client && mongosh -u admin -p mongo_root_pass_123 --authenticationDatabase admin"
```

## Testing Replication

### 1. Insert data on primary
```bash
podman exec homelab-mongo1 mongosh -u admin -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin homelab --quiet --eval '
db.replication_test.insertMany([
  { name: "test-1", value: 100, created_at: new Date() },
  { name: "test-2", value: 200, created_at: new Date() },
  { name: "test-3", value: 300, created_at: new Date() }
]);
print("Inserted 3 documents on primary");
'
```

### 2. Query on secondary 1 (data should appear within seconds)
```bash
podman exec homelab-mongo2 mongosh -u admin -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin homelab --quiet --eval '
db.replication_test.find().sort({created_at: 1}).toArray().forEach(function(doc) {
  print(JSON.stringify(doc));
});
'
```

### 3. Query on secondary 2 (data should also be replicated)
```bash
podman exec homelab-mongo3 mongosh -u admin -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin homelab --quiet --eval '
db.replication_test.find().sort({created_at: 1}).toArray().forEach(function(doc) {
  print(JSON.stringify(doc));
});
'
```

### 4. Try to write to secondary (should fail)
```bash
podman exec homelab-mongo2 mongosh -u admin -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin homelab --quiet --eval '
db.replication_test.insertOne({ name: "should-fail", value: 999 });
'
```

**Expected error:**
```
MongoServerError: not primary
```

## Testing Failover

### 1. Record current primary
```bash
CURRENT_PRIMARY=$(podman exec homelab-mongo1 mongosh -u admin -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin --quiet --eval 'rs.status().members.find(m => m.stateStr === "PRIMARY").name')
echo "Current primary: $CURRENT_PRIMARY"
```

### 2. Kill the primary container
```bash
podman stop homelab-mongo1
```

### 3. Wait for election (~12 seconds)
```bash
sleep 15
```

### 4. Check new primary
```bash
podman exec homelab-mongo2 mongosh -u admin -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin --quiet --eval '
rs.status().members.forEach(function(m) {
  print(m.name + ": " + m.stateStr);
});
'
```

**Expected output:** One node should now be PRIMARY (either mongo2 or mongo3).

### 5. Write to new primary
```bash
podman exec homelab-mongo2 mongosh -u admin -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin homelab --quiet --eval '
db.replication_test.insertOne({ name: "after-failover", value: 400, created_at: new Date() });
print("Write succeeded on new primary!");
'
```

### 6. Restore old primary (optional)
```bash
podman start homelab-mongo1
```

The old primary will rejoin as a secondary after catching up via oplog.

## Using the Test Client Container

The `homelab-mongodb-replica-test` container has Alpine installed but not `mongosh`. Use it to install and run MongoDB shell commands:

```bash
# Install mongosh in the test container
podman exec homelab-mongodb-replica-test sh -c "apk add --no-cache mongodb-client"

# Connect to the replica set (auto-discovers all members)
podman exec homelab-mongodb-replica-test mongosh "mongodb://admin:${MONGO_ROOT_PASSWORD}@mongo1:27017,mongo2:27017,mongo3:27017/?replicaSet=homelab-rs&authSource=admin"

# Switch to read from secondary
db.getMongo().setReadPref("secondary")
db.replication_test.find().toArray()

# Manually trigger re-election
rs.stepDown(60)
```

### Connect to a specific node
```bash
podman exec homelab-mongodb-replica-test mongosh -u admin -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin --host mongo1:27017
```

## Common Pitfalls

### Containers fail to start — forgot to build the image

The compose file references a locally built image (`localhost/homelab-mongo-replica:latest`). If you haven't built it yet, containers will fail with a "pull" error. Always build first:

```bash
podman build -t localhost/homelab-mongo-replica:latest .
podman compose up -d
```

### Replica set won't initialize
```bash
# Check all containers are running
podman ps | grep homelab-mongo

# Check mongo-init container logs
podman logs homelab-mongo-init

# Check individual node logs
podman logs homelab-mongo1 | tail -20
podman logs homelab-mongo2 | tail -20
podman logs homelab-mongo3 | tail -20

# If init failed, clean up and restart
podman compose down -v
podman compose up -d
```

### KeyFile errors on rebuild

If you see `bad file` errors after rebuilding, the KeyFile may have changed between nodes. Rebuild all nodes cleanly:
```bash
podman build --no-cache -t localhost/homelab-mongo-replica:latest .
podman compose down -v
podman compose up -d
```

### Election not completing
```bash
# Check if all nodes can reach each other
podman exec homelab-mongo1 mongosh --host mongo2:27017 -u admin -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin --eval "db.adminCommand('ping')"
podman exec homelab-mongo1 mongosh --host mongo3:27017 -u admin -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin --eval "db.adminCommand('ping')"

# Check network connectivity
podman exec homelab-mongo1 ping -c 3 mongo2
podman exec homelab-mongo1 ping -c 3 mongo3
```

### Port conflicts
If ports 27018, 27019, or 27020 are in use, change them in `docker-compose.yml`:
```yaml
ports:
  - "27021:27017/tcp"  # mongo1 on 27021
  - "27022:27017/tcp"  # mongo2 on 27022
  - "27023:27017/tcp"  # mongo3 on 27023
```

## Stop and Clean Up

```bash
# Stop containers (preserve data)
podman compose down

# Stop and remove volumes (WARNING: deletes all data!)
podman compose down -v
```

## Resource Usage

- **mongo1 (Primary)**: ~800MB - 1GB RAM idle
- **mongo2 (Secondary)**: ~800MB - 1GB RAM idle
- **mongo3 (Secondary)**: ~800MB - 1GB RAM idle
- **mongo-init**: ~50MB RAM (exits after initialization)
- **test-client**: ~5MB RAM
- **Total**: ~2.5 - 3.5GB RAM
- **Storage**: ~300MB per data volume + data growth
- **Image size**: ~1.4GB (shared across all mongo containers)

## Next Steps

1. Test read load balancing (direct SELECT queries to secondaries)
2. Monitor replication lag over time
3. Practice failover procedures
4. Test write concern levels (`w: "majority"`)
5. Consider adding automatic read preference routing
