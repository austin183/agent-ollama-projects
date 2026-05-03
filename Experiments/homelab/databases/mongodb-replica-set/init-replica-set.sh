#!/bin/bash
set -e

# === Configuration (overridable via environment variables) ===
MONGO_HOST="${MONGO_HOST:-mongo1}"
MONGO_PORT="${MONGO_PORT:-27017}"
MONGO_USER="${MONGO_USER:-admin}"
MONGO_PASS="${MONGO_PASS:-${MONGO_ROOT_PASSWORD}}"
MONGO_AUTH_DB="${MONGO_AUTH_DB:-admin}"
REPLICA_SET_NAME="${REPLICA_SET_NAME:-homelab-rs}"
MONGO_MEMBERS="${MONGO_MEMBERS:-mongo1:27017,mongo2:27017,mongo3:27017}"

echo "=== MongoDB Replica Set Init ==="
echo "Replica set: $REPLICA_SET_NAME"
echo "Members: $MONGO_MEMBERS"
echo "Init host: $MONGO_HOST:$MONGO_PORT"
echo ""

# === Step 1: Check if replica set is already initialized ===
echo "Checking if replica set is already initialized..."
rs_status_output=$(mongosh --host "$MONGO_HOST" --port "$MONGO_PORT" \
    -u "$MONGO_USER" -p "$MONGO_PASS" \
    --authenticationDatabase "$MONGO_AUTH_DB" \
    --quiet --eval 'try { JSON.stringify(rs.status()); } catch(e) { "NOT_INITIALIZED"; }' 2>&1)

if echo "$rs_status_output" | grep -q '"members"'; then
  echo "Replica set already initialized."
  echo ""
  echo "Current status:"
  mongosh --host "$MONGO_HOST" --port "$MONGO_PORT" \
    -u "$MONGO_USER" -p "$MONGO_PASS" \
    --authenticationDatabase "$MONGO_AUTH_DB" \
    --quiet --eval 'rs.status().members.forEach(function(m) { print(m.name + ": " + m.stateStr); })'
  echo ""
  echo "Replica set is already running. No action needed."
  exit 0
fi
echo "Replica set not initialized. Proceeding..."
echo ""

# === Step 2: Wait for all nodes to be ready ===
echo "Waiting for all MongoDB nodes to be ready..."
for node in $(echo "$MONGO_MEMBERS" | tr ',' ' '); do
  node_host=$(echo "$node" | cut -d: -f1)
  node_port=$(echo "$node" | cut -d: -f2)
  ready=false
  for i in $(seq 1 30); do
    if mongosh --host "$node_host" --port "$node_port" \
        -u "$MONGO_USER" -p "$MONGO_PASS" \
        --authenticationDatabase "$MONGO_AUTH_DB" \
        --quiet --eval "db.adminCommand('ping')" > /dev/null 2>&1; then
      # Second verification ping to avoid false positives during early startup
      if mongosh --host "$node_host" --port "$node_port" \
          -u "$MONGO_USER" -p "$MONGO_PASS" \
          --authenticationDatabase "$MONGO_AUTH_DB" \
          --quiet --eval "db.adminCommand('ping')" > /dev/null 2>&1; then
        echo "$node is ready (verified)!"
        ready=true
        break
      fi
    fi
    echo "Waiting for $node... (attempt $i/30)"
    sleep 5
  done
  if [ "$ready" = false ]; then
    echo "ERROR: $node did not become ready in time"
    exit 1
  fi
done
echo ""

# === Step 3: Build replica set configuration ===
echo "Initializing replica set..."
MEMBERS_JSON=""
idx=0
for node in $(echo "$MONGO_MEMBERS" | tr ',' ' '); do
  if [ $idx -gt 0 ]; then
    MEMBERS_JSON="${MEMBERS_JSON},"
  fi
  MEMBERS_JSON="${MEMBERS_JSON}
    { _id: ${idx}, host: \"${node}\" }"
  idx=$((idx + 1))
done

# === Step 4: Initialize with retry ===
init_retry=0
max_retries=3
init_success=false

while [ $init_retry -lt $max_retries ] && [ "$init_success" = false ]; do
  init_retry=$((init_retry + 1))
  echo "Init attempt $init_retry/$max_retries..."

  init_output=$(mongosh --host "$MONGO_HOST" --port "$MONGO_PORT" \
    -u "$MONGO_USER" -p "$MONGO_PASS" \
    --authenticationDatabase "$MONGO_AUTH_DB" \
    --quiet <<JSEOF 2>&1
rs.initiate({
  _id: "${REPLICA_SET_NAME}",
  members: [${MEMBERS_JSON}
  ]
})
JSEOF
)

  if echo "$init_output" | grep -qE '(ok: 1|\"ok\" : 1)'; then
    echo "Replica set initialized successfully!"
    init_success=true
  else
    echo "Init attempt $init_retry failed:"
    echo "$init_output"
    if [ $init_retry -lt $max_retries ]; then
      echo "Retrying in 5 seconds..."
      sleep 5
    fi
  fi
done

if [ "$init_success" = false ]; then
  echo "ERROR: Failed to initialize replica set after $max_retries attempts"
  exit 1
fi

# === Step 5: Wait for election to complete (dynamic, not fixed sleep) ===
echo ""
echo "Waiting for election to complete..."
election_wait=0
max_election_wait=30
primary_found=false

while [ $election_wait -lt $max_election_wait ] && [ "$primary_found" = false ]; do
  election_wait=$((election_wait + 1))
  is_primary=$(mongosh --host "$MONGO_HOST" --port "$MONGO_PORT" \
    -u "$MONGO_USER" -p "$MONGO_PASS" \
    --authenticationDatabase "$MONGO_AUTH_DB" \
    --quiet --eval 'rs.isMaster().ismaster' 2>/dev/null)

  if [ "$is_primary" = "true" ]; then
    echo "Election complete! $MONGO_HOST is now PRIMARY."
    primary_found=true
  else
    echo "Waiting for election... ($election_wait/$max_election_wait)"
    sleep 3
  fi
done

if [ "$primary_found" = false ]; then
  echo "WARNING: Could not confirm primary election after $max_election_wait attempts"
  echo "Checking current status:"
fi

# === Step 6: Print final status ===
echo ""
echo "Replica set status:"
mongosh --host "$MONGO_HOST" --port "$MONGO_PORT" \
  -u "$MONGO_USER" -p "$MONGO_PASS" \
  --authenticationDatabase "$MONGO_AUTH_DB" \
  --quiet --eval 'rs.status().members.forEach(function(m) { print(m.name + ": " + m.stateStr); })'

echo ""
echo "Replica set initialization complete!"
