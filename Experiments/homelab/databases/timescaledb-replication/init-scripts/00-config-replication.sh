#!/bin/bash
set -e

# Configure PostgreSQL for streaming replication
# This script runs during the first container start when PGDATA is empty

echo "Configuring PostgreSQL for streaming replication..."

# Append replication settings to postgresql.conf
cat >> /var/lib/postgresql/data/postgresql.conf <<EOF

# Replication settings
wal_level = replica
max_wal_senders = 3
wal_keep_size = 64MB
listen_addresses = '*'
EOF

# Add replication entry to pg_hba.conf
# Allow the replicator user to connect for streaming replication
cat >> /var/lib/postgresql/data/pg_hba.conf <<EOF

# Replication connections
local   replication     replicator                        scram-sha-256
host    replication     replicator        127.0.0.1/32    scram-sha-256
host    replication     replicator        0.0.0.0/0       scram-sha-256
host    replication     replicator        ::1/128         scram-sha-256
host    replication     replicator        ::/0            scram-sha-256
EOF

echo "Replication configuration complete."
echo "wal_level = replica"
echo "max_wal_senders = 3"
echo "wal_keep_size = 64MB"
