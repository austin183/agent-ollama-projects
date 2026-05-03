-- Create a physical replication slot for the standby
-- This prevents WAL segments from being recycled while the standby needs them

SELECT pg_create_physical_replication_slot('standby_slot');
