-- Initialize TimescaleDB extension and create sample hypertable
-- This script runs during the first container start

-- Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Create the sensor_readings table
CREATE TABLE IF NOT EXISTS sensor_readings (
    time        TIMESTAMPTZ NOT NULL,
    device_id   TEXT NOT NULL,
    sensor_type TEXT NOT NULL,
    value       DOUBLE PRECISION NOT NULL,
    unit        TEXT NOT NULL
);

-- Convert the table into a hypertable
SELECT create_hypertable('sensor_readings', 'time', if_not_exists => TRUE);

-- Insert 24 hours of sample sensor data (one reading every 5 minutes)
INSERT INTO sensor_readings (time, device_id, sensor_type, value, unit)
SELECT
    generate_series(
        NOW() - INTERVAL '24 hours',
        NOW(),
        INTERVAL '5 minutes'
    ) AS time,
    'sensor-' || (random() * 9 + 1)::int AS device_id,
    (ARRAY['temperature', 'humidity', 'pressure'])[floor(random() * 3 + 1)::int] AS sensor_type,
    (random() * 50 + 10)::double precision AS value,
    (ARRAY['celsius', '%', 'hPa'])[floor(random() * 3 + 1)::int] AS unit;

-- Set a retention policy to automatically drop data older than 7 days
SELECT add_retention_policy('sensor_readings', INTERVAL '7 days', if_not_exists => TRUE);

-- Create an index on device_id for faster lookups
CREATE INDEX IF NOT EXISTS idx_sensor_readings_device ON sensor_readings (device_id);
