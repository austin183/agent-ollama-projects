CREATE TABLE IF NOT EXISTS transcode_jobs (
    id SERIAL PRIMARY KEY,
    filename TEXT NOT NULL,
    file_size_bytes BIGINT,
    input_codec TEXT,
    input_width INT,
    input_height INT,
    input_duration_secs FLOAT,
    output_codec TEXT,
    preset TEXT,
    crf INT,
    command TEXT,
    output_file TEXT,
    output_size_bytes BIGINT,
    encode_fps FLOAT,
    speed_x FLOAT,
    gpu_util_pct FLOAT,
    gpu_mem_used_mb FLOAT,
    cpu_usage_pct FLOAT,
    status TEXT NOT NULL DEFAULT 'pending',
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_transcode_jobs_status ON transcode_jobs(status);
CREATE INDEX IF NOT EXISTS idx_transcode_jobs_created ON transcode_jobs(created_at);
