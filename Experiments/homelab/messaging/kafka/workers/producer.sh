#!/bin/bash
# Kafka Log Producer - uses kafka-console-producer.sh
BOOTSTRAP="kafka:9092"
LOG_TOPIC="${KAFKA_TOPIC:-app.logs}"
ERROR_TOPIC="${KAFKA_ERROR_TOPIC:-app.errors}"
INTERVAL="${LOG_INTERVAL:-5}"

LOG_LEVELS=("DEBUG" "INFO" "WARN" "ERROR" "FATAL")
SERVICES=("api-gateway" "auth-service" "user-service" "payment-service" "notification-service")

echo "Kafka Log Producer started"
echo "  Bootstrap: $BOOTSTRAP"
echo "  Log topic: $LOG_TOPIC"
echo "  Error topic: $ERROR_TOPIC"
echo "  Interval: ${INTERVAL}s"
echo ""

seq=0
while true; do
    seq=$((seq + 1))
    
    # Pick a random log level weighted
    rand=$((RANDOM % 100))
    if [ $rand -lt 30 ]; then
        level="DEBUG"
    elif [ $rand -lt 70 ]; then
        level="INFO"
    elif [ $rand -lt 85 ]; then
        level="WARN"
    elif [ $rand -lt 95 ]; then
        level="ERROR"
    else
        level="FATAL"
    fi
    
    service_idx=$((RANDOM % 5))
    case $service_idx in
        0) service="api-gateway" ;;
        1) service="auth-service" ;;
        2) service="user-service" ;;
        3) service="payment-service" ;;
        4) service="notification-service" ;;
    esac
    
    id=$((RANDOM % 9000 + 1000))
    ms=$((RANDOM % 4996 + 5))
    pct=$((RANDOM % 36 + 60))
    
    case "$level" in
        DEBUG) message="Cache hit for key user:${id}" ;;
        INFO) message="Request processed in ${ms}ms" ;;
        WARN) message="High memory usage: ${pct}%" ;;
        ERROR) message="Database connection failed: timeout after 30s" ;;
        FATAL) message="Out of memory: heap space exhausted" ;;
    esac
    
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
    
    # Build JSON message
    json_msg="{\"seq\":${seq},\"timestamp\":\"${timestamp}\",\"level\":\"${level}\",\"service\":\"${service}\",\"message\":\"${message}\"}"
    
    # Send to appropriate topic
    if [ "$level" = "ERROR" ] || [ "$level" = "FATAL" ]; then
        echo "$json_msg" | /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server "$BOOTSTRAP" --topic "$ERROR_TOPIC" 2>/dev/null
    else
        echo "$json_msg" | /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server "$BOOTSTRAP" --topic "$LOG_TOPIC" 2>/dev/null
    fi
    
    echo "[${level}] ${service} ${message}"
    
    sleep "$INTERVAL"
done
