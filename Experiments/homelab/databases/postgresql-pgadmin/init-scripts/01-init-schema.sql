-- Sample schema for testing PostgreSQL
-- This will be auto-executed on first container start

CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS experiments (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    status VARCHAR(20) DEFAULT 'planned',
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample data
INSERT INTO users (username, email) VALUES
    ('alice', 'alice@homelab.local'),
    ('bob', 'bob@homelab.local'),
    ('charlie', 'charlie@homelab.local')
ON CONFLICT (username) DO NOTHING;

INSERT INTO experiments (name, status) VALUES
    ('PostgreSQL + pgAdmin', 'active'),
    ('MariaDB + Adminer', 'planned'),
    ('MongoDB', 'planned'),
    ('Redis', 'planned')
ON CONFLICT DO NOTHING;
