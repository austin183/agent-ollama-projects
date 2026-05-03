-- Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Create a sample hypertable for sensor data
CREATE TABLE IF NOT EXISTS sensor_readings (
    time        TIMESTAMPTZ       NOT NULL,
    device_id   TEXT              NOT NULL,
    sensor_type TEXT              NOT NULL,
    value       DOUBLE PRECISION  NOT NULL,
    unit        TEXT              NOT NULL
);

-- Convert the table into a hypertable
SELECT create_hypertable('sensor_readings', 'time', if_not_exists => TRUE);

-- Insert sample data
INSERT INTO sensor_readings (time, device_id, sensor_type, value, unit)
VALUES
    (NOW() - INTERVAL '24 hours', 'sensor-001', 'temperature', 22.5, 'celsius'),
    (NOW() - INTERVAL '23 hours', 'sensor-001', 'temperature', 23.1, 'celsius'),
    (NOW() - INTERVAL '22 hours', 'sensor-001', 'temperature', 22.8, 'celsius'),
    (NOW() - INTERVAL '21 hours', 'sensor-002', 'humidity', 45.2, 'percent'),
    (NOW() - INTERVAL '20 hours', 'sensor-002', 'humidity', 46.8, 'percent'),
    (NOW() - INTERVAL '19 hours', 'sensor-002', 'humidity', 44.5, 'percent'),
    (NOW() - INTERVAL '18 hours', 'sensor-003', 'pressure', 1013.25, 'hPa'),
    (NOW() - INTERVAL '17 hours', 'sensor-003', 'pressure', 1012.80, 'hPa'),
    (NOW() - INTERVAL '16 hours', 'sensor-003', 'pressure', 1013.50, 'hPa'),
    (NOW() - INTERVAL '15 hours', 'sensor-001', 'temperature', 24.0, 'celsius'),
    (NOW() - INTERVAL '14 hours', 'sensor-001', 'temperature', 24.5, 'celsius'),
    (NOW() - INTERVAL '13 hours', 'sensor-002', 'humidity', 48.1, 'percent'),
    (NOW() - INTERVAL '12 hours', 'sensor-002', 'humidity', 47.3, 'percent'),
    (NOW() - INTERVAL '11 hours', 'sensor-003', 'pressure', 1014.10, 'hPa'),
    (NOW() - INTERVAL '10 hours', 'sensor-003', 'pressure', 1013.90, 'hPa'),
    (NOW() - INTERVAL '9 hours', 'sensor-001', 'temperature', 25.2, 'celsius'),
    (NOW() - INTERVAL '8 hours', 'sensor-001', 'temperature', 25.8, 'celsius'),
    (NOW() - INTERVAL '7 hours', 'sensor-002', 'humidity', 50.0, 'percent'),
    (NOW() - INTERVAL '6 hours', 'sensor-002', 'humidity', 51.2, 'percent'),
    (NOW() - INTERVAL '5 hours', 'sensor-003', 'pressure', 1012.50, 'hPa'),
    (NOW() - INTERVAL '4 hours', 'sensor-003', 'pressure', 1011.80, 'hPa'),
    (NOW() - INTERVAL '3 hours', 'sensor-001', 'temperature', 23.5, 'celsius'),
    (NOW() - INTERVAL '2 hours', 'sensor-001', 'temperature', 22.9, 'celsius'),
    (NOW() - INTERVAL '1 hour', 'sensor-002', 'humidity', 49.5, 'percent')
ON CONFLICT DO NOTHING;

-- Create a retention policy to auto-drop old data (keep 7 days)
SELECT add_retention_policy('sensor_readings', INTERVAL '7 days', if_not_exists => TRUE);
