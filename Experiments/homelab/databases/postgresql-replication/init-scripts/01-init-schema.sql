-- 01-init-schema.sql
-- Sample schema for testing PostgreSQL replication
-- This will be auto-executed on first container start

CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS replication_test (
    id SERIAL PRIMARY KEY,
    data TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS guest_registration (
    id SERIAL PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL,
    registered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample data
INSERT INTO users (username, email) VALUES
    ('alice', 'alice@homelab.local'),
    ('bob', 'bob@homelab.local'),
    ('charlie', 'charlie@homelab.local')
ON CONFLICT (username) DO NOTHING;

INSERT INTO replication_test (data) VALUES
    ('Initial test data 1'),
    ('Initial test data 2'),
    ('Initial test data 3')
ON CONFLICT DO NOTHING;

INSERT INTO guest_registration (first_name, last_name, email) VALUES
    ('John', 'Doe', 'john.doe@example.com'),
    ('Jane', 'Smith', 'jane.smith@example.com')
ON CONFLICT DO NOTHING;
