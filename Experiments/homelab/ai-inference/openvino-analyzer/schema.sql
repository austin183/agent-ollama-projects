-- Schema for OpenVINO image detection results

CREATE TABLE IF NOT EXISTS detections (
    id SERIAL PRIMARY KEY,
    filename VARCHAR(500) NOT NULL,
    file_path TEXT NOT NULL,
    file_size_bytes BIGINT,
    image_width INTEGER,
    image_height INTEGER,
    image_format VARCHAR(20),
    model_name VARCHAR(100) DEFAULT 'yolov8n',
    model_input_size VARCHAR(20) DEFAULT '640x640',
    inference_device VARCHAR(20) DEFAULT 'GPU',
    inference_latency_ms DOUBLE PRECISION,
    detections JSONB NOT NULL,
    detection_count INTEGER GENERATED ALWAYS AS (json_array_length(detections::json)) STORED,
    processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_detections_filename ON detections(filename);
CREATE INDEX IF NOT EXISTS idx_detections_processed_at ON detections(processed_at DESC);
CREATE INDEX IF NOT EXISTS idx_detections_detection_count ON detections(detection_count);
CREATE INDEX IF NOT EXISTS idx_detections_detections_gin ON detections USING GIN (detections);
