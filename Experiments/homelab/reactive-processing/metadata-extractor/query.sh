#!/bin/bash
set -e

DB_HOST="${DB_HOST:-postgresql}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-metadata}"
DB_USER="${DB_USER:-metadata_user}"

export PGPASSWORD="${DB_PASSWORD}"

if [ -z "$PGPASSWORD" ]; then
  echo "ERROR: DB_PASSWORD environment variable is not set"
  echo "Set it in your .env file or pass it to the container"
  exit 1
fi

PSQL="psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -t -A"

case "${1:-help}" in
  connectivity)
    echo "Testing PostgreSQL connectivity..."
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c 'SELECT 1 as connected'
    ;;
  count)
    echo "Total files processed:"
    $PSQL -c 'SELECT COUNT(*) FROM media_metadata'
    ;;
  list)
    echo "Recently processed files:"
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
      -c 'SELECT filename, file_type, width, height, format, processed_at FROM media_metadata ORDER BY processed_at DESC LIMIT 10'
    ;;
  images)
    echo "Image metadata:"
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
      -c 'SELECT filename, width, height, format, camera_make, camera_model, processed_at FROM media_metadata WHERE file_type='"'"'image'"'"' ORDER BY processed_at DESC LIMIT 10'
    ;;
  audio)
    echo "Audio metadata:"
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
      -c 'SELECT filename, artist, album, title, duration_seconds, bitrate, processed_at FROM media_metadata WHERE file_type='"'"'audio'"'"' ORDER BY processed_at DESC LIMIT 10'
    ;;
  video)
    echo "Video metadata:"
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
      -c 'SELECT filename, width, height, codec, duration_seconds, frame_rate, processed_at FROM media_metadata WHERE file_type='"'"'video'"'"' ORDER BY processed_at DESC LIMIT 10'
    ;;
  gps)
    echo "GPS coordinates:"
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
      -c 'SELECT filename, camera_make, camera_model, gps_latitude, gps_longitude FROM media_metadata WHERE gps_latitude IS NOT NULL'
    ;;
  duplicates)
    echo "Checking for duplicate hashes (should be empty):"
    $PSQL -c "SELECT file_hash, COUNT(*) FROM media_metadata GROUP BY file_hash HAVING COUNT(*) > 1"
    ;;
  cleanup)
    echo "Clearing all metadata records..."
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c 'TRUNCATE media_metadata'
    ;;
  *)
    echo "Usage: $0 {connectivity|count|list|images|audio|video|gps|duplicates|cleanup}"
    echo ""
    echo "  connectivity  - Test PostgreSQL connection"
    echo "  count         - Total files processed"
    echo "  list          - Recently processed files"
    echo "  images        - Image metadata"
    echo "  audio         - Audio metadata"
    echo "  video         - Video metadata"
    echo "  gps           - GPS coordinates from images"
    echo "  duplicates    - Check for duplicate hashes"
    echo "  cleanup       - Clear all records"
    ;;
esac
