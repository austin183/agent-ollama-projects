#!/bin/sh
set -e

echo "Configuring PostgreSQL for replication..."

# PGDATA is set by the postgres image
echo "PGDATA is: $PGDATA"

# Append replication settings to postgresql.conf
echo "" >> "$PGDATA/postgresql.conf"
echo "# Replication settings" >> "$PGDATA/postgresql.conf"
echo "wal_level = replica" >> "$PGDATA/postgresql.conf"
echo "max_wal_senders = 3" >> "$PGDATA/postgresql.conf"
echo "wal_keep_size = 64MB" >> "$PGDATA/postgresql.conf"
echo "listen_addresses = '*'" >> "$PGDATA/postgresql.conf"

# Append replication access to pg_hba.conf
echo "" >> "$PGDATA/pg_hba.conf"
echo "# Replication connections" >> "$PGDATA/pg_hba.conf"
echo "host replication replicator 0.0.0.0/0 scram-sha-256" >> "$PGDATA/pg_hba.conf"

echo "PostgreSQL configured for replication"
