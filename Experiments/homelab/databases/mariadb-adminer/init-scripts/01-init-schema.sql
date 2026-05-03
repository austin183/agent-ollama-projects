CREATE DATABASE IF NOT EXISTS homelab_db;
USE homelab_db;

CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS experiments (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    domain VARCHAR(50) NOT NULL,
    status ENUM('planned', 'running', 'stopped', 'completed') DEFAULT 'planned',
    ram_budget_mb INT,
    storage_estimate_gb DECIMAL(5,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP NULL,
    completed_at TIMESTAMP NULL
);

INSERT INTO users (username, email) VALUES
    ('alice', 'alice@homelab.local'),
    ('bob', 'bob@homelab.local'),
    ('charlie', 'charlie@homelab.local');

INSERT INTO experiments (name, domain, status, ram_budget_mb, storage_estimate_gb) VALUES
    ('MariaDB + Adminer', 'Databases', 'running', 300, 1.0),
    ('PostgreSQL + pgAdmin', 'Databases', 'running', 350, 1.5),
    ('MongoDB', 'Databases', 'planned', 400, 1.0),
    ('Redis', 'Databases', 'planned', 150, 0.5);
