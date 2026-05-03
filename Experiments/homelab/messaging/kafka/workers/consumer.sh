#!/bin/bash
# Kafka Log Consumer - uses kafka-console-consumer.sh
BOOTSTRAP="kafka:9092"
TOPIC="${KAFKA_TOPIC:-app.logs}"
GROUP_ID="${KAFKA_CONSUMER_GROUP:-app}"

echo "Kafka Log Consumer started"
echo "  Bootstrap: $BOOTSTRAP"
echo "  Topic: $TOPIC"
echo "  Consumer group: $GROUP_ID"
echo "  Auto-offset-reset: earliest"
echo ""

# Consume messages and parse them
/opt/kafka/bin/kafka-console-consumer.sh \
    --bootstrap-server "$BOOTSTRAP" \
    --topic "$TOPIC" \
    --group "$GROUP_ID" \
    --from-beginning \
    --timeout-ms 30000 \
    --property print.value=true 2>/dev/null | while IFS= read -r line; do
    # Parse JSON fields
    level=$(echo "$line" | grep -oP '"level":"\K[^"]+' || echo "UNKNOWN")
    service=$(echo "$line" | grep -oP '"service":"\K[^"]+' || echo "unknown")
    message=$(echo "$line" | grep -oP '"message":"\K[^"]+' || echo "")
    ts=$(echo "$line" | grep -oP '"timestamp":"\K[^"]+' || echo "unknown")
    
    echo "[${ts}] [${level}] ${service}: ${message}"
done

echo ""
echo "--- Consumer finished (timeout) ---"
