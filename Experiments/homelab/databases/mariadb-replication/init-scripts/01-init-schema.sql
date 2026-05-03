CREATE DATABASE IF NOT EXISTS homelab_db;
USE homelab_db;

CREATE TABLE IF NOT EXISTS guest_registration (
    id INT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    registered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS replication_test (
    id INT AUTO_INCREMENT PRIMARY KEY,
    data VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO guest_registration (first_name, last_name, email) VALUES
    ('Alice', 'Johnson', 'alice.johnson@test.com'),
    ('Bob', 'Smith', 'bob.smith@test.com'),
    ('Charlie', 'Brown', 'charlie.brown@test.com');

INSERT INTO replication_test (data) VALUES
    ('Initial test record 1'),
    ('Initial test record 2');
