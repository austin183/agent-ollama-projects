import json
import time
import random
import os
import sys
from confluent_kafka import Producer, KafkaError
from datetime import datetime, timezone

BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092")
LOG_TOPIC = os.getenv("KAFKA_TOPIC", "app.logs")
ERROR_TOPIC = os.getenv("KAFKA_ERROR_TOPIC", "app.errors")
INTERVAL = int(os.getenv("LOG_INTERVAL", "5"))

LOG_LEVELS = ["DEBUG", "INFO", "WARN", "ERROR", "FATAL"]
LOG_LEVEL_WEIGHTS = [30, 40, 15, 10, 5]
SERVICES = ["api-gateway", "auth-service", "user-service", "payment-service", "notification-service"]
MESSAGES = {
    "DEBUG": ["Cache hit for key user:{id}", "Query execution time: {ms}ms", "Connection pool: {n}/10 active"],
    "INFO": ["Request processed in {ms}ms", "User {id} logged in", "Payment of ${amount} completed", "Email sent to user {id}"],
    "WARN": ["High memory usage: {pct}%", "Slow query detected: {ms}ms", "Rate limit approaching for client {id}", "Disk usage at {pct}%"],
    "ERROR": ["Database connection failed: timeout after 30s", "Payment processing error: invalid card", "Authentication failed for user {id}", "Service unavailable: user-service"],
    "FATAL": ["Out of memory: heap space exhausted", "Database cluster unreachable", "SSL certificate expired", "Unrecoverable state transition"],
}


def delivery_report(err, msg):
    if err is not None:
        print(f"Delivery failed: {err}")
    else:
        topic = msg.topic()
        partition = msg.partition()
        offset = msg.offset()
        print(f"  -> delivered to {topic} partition={partition} offset={offset}")


conf = {
    'bootstrap.servers': BOOTSTRAP,
    'acks': 1,
    'retries': 3,
    'delivery.report.only.error': False,
}

producer = Producer(conf)

print(f"Kafka Producer started")
print(f"  Bootstrap: {BOOTSTRAP}")
print(f"  Log topic: {LOG_TOPIC}")
print(f"  Error topic: {ERROR_TOPIC}")
print(f"  Interval: {INTERVAL}s")
print()

seq = 0
try:
    while True:
        seq += 1
        level = random.choices(LOG_LEVELS, weights=LOG_LEVEL_WEIGHTS, k=1)[0]
        service = random.choice(SERVICES)
        msg_template = random.choice(MESSAGES[level])
        message = msg_template.format(
            id=random.randint(1000, 9999),
            ms=random.randint(5, 5000),
            n=random.randint(1, 10),
            amount=random.uniform(10, 500),
            pct=random.randint(60, 95),
        )

        event = {
            "seq": seq,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": level,
            "service": service,
            "message": message,
        }

        topic = ERROR_TOPIC if level in ("ERROR", "FATAL") else LOG_TOPIC
        value = json.dumps(event).encode('utf-8')

        producer.poll(0)
        producer.produce(topic, value=value, on_delivery=delivery_report)
        producer.flush(10)

        print(f"[{level:5s}] {service:20s} {message[:50]}")

        time.sleep(INTERVAL)
except KeyboardInterrupt:
    print("\nShutting down producer...")
finally:
    producer.flush(10)
    producer.close()
