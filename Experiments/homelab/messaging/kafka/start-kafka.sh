#!/bin/bash
. /etc/kafka/docker/configureDefaults
. /etc/kafka/docker/configure

# Fix log.dirs - the configure script doesn't honor KAFKA_LOG_DIRS
LOG_DIRS="${KAFKA_LOG_DIRS:-/var/lib/kafka/data}"
sed -i "s|^log.dirs=.*|log.dirs=${LOG_DIRS}|" /opt/kafka/config/kraft/server.properties

# Fix advertised.listeners - the configure script doesn't honor KAFKA_ADVERTISED_LISTENERS
if [ -n "$KAFKA_ADVERTISED_LISTENERS" ]; then
    # Extract the PLAINTEXT portion of advertised.listeners
    PLAINTEXT_ADVERTISED=$(echo "$KAFKA_ADVERTISED_LISTENERS" | tr ',' '\n' | grep '^PLAINTEXT://' | head -1)
    if [ -n "$PLAINTEXT_ADVERTISED" ]; then
        sed -i "s|^advertised.listeners=.*|advertised.listeners=${PLAINTEXT_ADVERTISED}|" /opt/kafka/config/kraft/server.properties
    fi
fi

mkdir -p "${LOG_DIRS}"
if [ -z "$(ls -A ${LOG_DIRS} 2>/dev/null)" ]; then
  CLUSTER_ID=$(/opt/kafka/bin/kafka-storage.sh random-uuid)
  echo "Formatting storage at ${LOG_DIRS} with cluster ID: ${CLUSTER_ID}"
  /opt/kafka/bin/kafka-storage.sh format -t "$CLUSTER_ID" -c /opt/kafka/config/kraft/server.properties
fi
echo "===> User"
id
echo "===> Starting Kafka server..."
exec /opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/kraft/server.properties
