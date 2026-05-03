#!/bin/sh
set -e

# Generate SECRET_KEY if not already set
if [ -z "$SECRET_KEY" ]; then
  export SECRET_KEY=$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')
fi

# Run the original docker-entrypoint.sh in the background
# Note: dumb-init is already our parent (set in Dockerfile ENTRYPOINT)
/usr/local/bin/docker-entrypoint.sh &
ENTRYPOINT_PID=$!

# Poll /api/healthz until Gitea is ready (use HTTP_PORT, not ROOT_URL)
HTTP_PORT="${GITEA__SERVER__HTTP_PORT:-3000}"
echo "Waiting for Gitea to start on port ${HTTP_PORT}..."
for i in $(seq 1 60); do
  if wget --spider -q "http://localhost:${HTTP_PORT}/api/healthz" 2>/dev/null; then
    echo "Gitea is ready!"
    break
  fi
  sleep 2
done

# Create admin user
if [ -n "$GITEA_ADMIN_USER" ] && [ -n "$GITEA_ADMIN_PASSWORD" ] && [ -n "$GITEA_ADMIN_EMAIL" ]; then
  echo "Creating admin user: ${GITEA_ADMIN_USER}"
  /usr/local/bin/gitea admin user create \
    --username "$GITEA_ADMIN_USER" \
    --password "$GITEA_ADMIN_PASSWORD" \
    --email "$GITEA_ADMIN_EMAIL" \
    --admin \
    --must-change-password=false || echo "Admin user may already exist"
fi

# Wait for the entrypoint process to keep the container alive
wait $ENTRYPOINT_PID
