#!/usr/bin/env bash
# Query helper for YOLO CUDA experiment
# Usage: podman exec homelab-yolo-cuda-test /query.sh <command>

set -e

DB_HOST="${DB_HOST:-postgresql}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-detections}"
DB_USER="${DB_USER:-detect_user}"
DB_PASS="${DB_PASSWORD:-detect_pass_123}"

psql_opts="-h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME"

case "${1:-help}" in
    connectivity)
        echo "Testing PostgreSQL connectivity..."
        PGPASSWORD=$DB_PASS psql $psql_opts -c "SELECT 1 AS connected;"
        ;;
    count)
        echo "Total detections:"
        PGPASSWORD=$DB_PASS psql $psql_opts -c "SELECT COUNT(*) AS total FROM detections;"
        ;;
    list)
        echo "Recent detections:"
        PGPASSWORD=$DB_PASS psql $psql_opts -c \
            "SELECT id, filename, image_width, image_height, detection_count,
                    inference_latency_ms, processed_at
             FROM detections ORDER BY processed_at DESC LIMIT 10;"
        ;;
    details)
        echo "Detailed detection results:"
        PGPASSWORD=$DB_PASS psql $psql_opts -c \
            "SELECT id, filename, detection_count, inference_latency_ms,
                    json_agg(
                        json_build_object(
                            'class', d->>'class_name',
                            'confidence', d->>'confidence',
                            'bbox', d->'bbox'
                        )
                    ) AS objects
             FROM detections, json_array_elements(detections) AS d
             WHERE id = COALESCE(NULLIF('$2', ''), (SELECT MAX(id) FROM detections))::INTEGER
             GROUP BY id, filename, detection_count, inference_latency_ms;"
        ;;
    objects)
        echo "Most detected object types:"
        PGPASSWORD=$DB_PASS psql $psql_opts -c \
            "SELECT d->>'class_name' AS object,
                    COUNT(*) AS times_detected,
                    ROUND(AVG(d->>'confidence')::numeric, 2) AS avg_confidence
             FROM detections, json_array_elements(detections) AS d
             GROUP BY d->>'class_name'
             ORDER BY times_detected DESC
             LIMIT 10;"
        ;;
    high_conf)
        echo "High confidence detections (>80%):"
        PGPASSWORD=$DB_PASS psql $psql_opts -c \
            "SELECT id, filename, processed_at,
                    json_agg(
                        json_build_object(
                            'class', d->>'class_name',
                            'confidence', d->>'confidence',
                            'bbox', d->'bbox'
                        )
                    ) AS objects
             FROM detections, json_array_elements(detections) AS d
             WHERE (d->>'confidence')::float >= 0.8
             GROUP BY id, filename, processed_at
             ORDER BY processed_at DESC LIMIT 10;"
        ;;
    recent)
        echo "Last 5 processed images:"
        PGPASSWORD=$DB_PASS psql $psql_opts -c \
            "SELECT filename, image_width, image_height, detection_count,
                    ROUND(inference_latency_ms, 1) AS latency_ms, processed_at
             FROM detections ORDER BY processed_at DESC LIMIT 5;"
        ;;
    clear)
        echo "Clearing all detection records..."
        PGPASSWORD=$DB_PASS psql $psql_opts -c "TRUNCATE detections;"
        echo "Done."
        ;;
    schema)
        echo "Table schema:"
        PGPASSWORD=$DB_PASS psql $psql_opts -c "\d detections"
        ;;
    help|*)
        echo "YOLO CUDA Image Analyzer - Query Helper"
        echo ""
        echo "Usage: /query.sh <command> [args]"
        echo ""
        echo "Commands:"
        echo "  connectivity   Test PostgreSQL connection"
        echo "  count          Total detection records"
        echo "  list           Recent detections (summary)"
        echo "  details <id>   Detailed results for specific detection"
        echo "  objects        Most detected object types"
        echo "  high_conf      High confidence detections (>80%)"
        echo "  recent         Last 5 processed images"
        echo "  clear          Clear all records"
        echo "  schema         Show table schema"
        echo "  help           Show this help"
        ;;
esac
