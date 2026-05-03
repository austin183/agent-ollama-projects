-- Configure replication settings
-- This runs after database initialization

-- Create replication slot
SELECT pg_create_physical_replication_slot('standby_slot');
