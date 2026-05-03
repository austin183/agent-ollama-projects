#!/bin/bash
set -e

DB_HOST="${PG_HOST:-postgresql}"
DB_PORT="${PG_PORT:-5432}"
DB_NAME="${PG_DB:-transcoder}"
DB_USER="${PG_USER:-transcoder}"

export PGPASSWORD="${PG_PASSWORD}"

if [ -z "$PGPASSWORD" ]; then
  echo "ERROR: PG_PASSWORD environment variable is not set"
  exit 1
fi

case "${1:-help}" in
  connectivity)
    echo "Testing PostgreSQL connectivity..."
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c 'SELECT 1 as connected'
    ;;
  jobs)
    echo "All transcode jobs:"
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
      -c 'SELECT id, filename, status, input_width, input_height, output_codec, encode_fps, speed_x, created_at FROM transcode_jobs ORDER BY created_at DESC'
    ;;
  recent)
    echo "Recent transcode jobs:"
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
      -c 'SELECT id, filename, status, input_width, input_height, input_duration_secs, output_codec, encode_fps, speed_x, gpu_util_pct FROM transcode_jobs ORDER BY created_at DESC LIMIT 5'
    ;;
  summary)
    echo "Transcode summary:"
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
      -c 'SELECT status, COUNT(*) as count FROM transcode_jobs GROUP BY status'
    ;;
  cleanup)
    echo "Clearing all job records..."
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c 'TRUNCATE transcode_jobs RESTART IDENTITY'
    ;;
  *)
    echo "Usage: $0 {connectivity|jobs|recent|summary|cleanup}"
    echo ""
    echo "  connectivity  - Test PostgreSQL connection"
    echo "  jobs          - All transcode jobs"
    echo "  recent        - Recent transcode jobs"
    echo "  summary       - Job status summary"
    echo "  cleanup       - Clear all records"
    ;;
esac
