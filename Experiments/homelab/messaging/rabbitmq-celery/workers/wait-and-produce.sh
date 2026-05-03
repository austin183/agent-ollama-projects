#!/bin/sh
echo "Waiting for RabbitMQ..."
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
  if python -c "import socket; s=socket.socket(); s.settimeout(2); s.connect(('rabbitmq', 5672)); s.close()" 2>/dev/null; then
    echo "RabbitMQ is ready!"
    exec python /app/workers/producer.py
  fi
  echo "  attempt $i/30 - waiting 2s"
  sleep 2
done
echo "ERROR: RabbitMQ did not become ready in time"
exit 1
