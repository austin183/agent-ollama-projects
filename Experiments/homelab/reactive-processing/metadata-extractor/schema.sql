CREATE TABLE IF NOT EXISTS media_metadata (
    id SERIAL PRIMARY KEY,
    filename VARCHAR(500) NOT NULL,
    file_path TEXT NOT NULL,
    file_type VARCHAR(20) NOT NULL CHECK (file_type IN ('image', 'audio', 'video')),
    file_size_bytes BIGINT,
    duration_seconds DOUBLE PRECISION,
    width INTEGER,
    height INTEGER,
    format VARCHAR(50),
    codec VARCHAR(100),
    bitrate INTEGER,
    sample_rate INTEGER,
    channel_layout VARCHAR(50),
    artist VARCHAR(200),
    album VARCHAR(200),
    title VARCHAR(500),
    track_number INTEGER,
    genre VARCHAR(100),
    date_created TIMESTAMP,
    gps_latitude DOUBLE PRECISION,
    gps_longitude DOUBLE PRECISION,
    camera_make VARCHAR(200),
    camera_model VARCHAR(200),
    exposure_time VARCHAR(50),
    aperture VARCHAR(50),
    focal_length VARCHAR(50),
    iso INTEGER,
    white_balance VARCHAR(50),
    software VARCHAR(200),
    all_metadata JSONB,
    file_hash VARCHAR(32),
    processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_media_metadata_filename ON media_metadata(filename);
CREATE INDEX IF NOT EXISTS idx_media_metadata_file_type ON media_metadata(file_type);
CREATE INDEX IF NOT EXISTS idx_media_metadata_processed_at ON media_metadata(processed_at);
CREATE INDEX IF NOT EXISTS idx_media_metadata_file_hash ON media_metadata(file_hash);
