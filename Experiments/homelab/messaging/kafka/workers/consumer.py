import json
import os
import time
from confluent_kafka import Consumer, KafkaError
from datetime import datetime, timezone

BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092")
TOPIC = os.getenv("KAFKA_TOPIC", "app.logs")
GROUP_ID = os.getenv("KAFKA_CONSUMER_GROUP", "app")

conf = {
    'bootstrap.servers': BOOTSTRAP,
    'group.id': GROUP_ID,
    'auto.offset.reset': 'earliest',
    'enable.auto.commit': True,
    'auto.commit.interval.ms': 5000,
}

consumer = Consumer(conf)
consumer.subscribe([TOPIC])

print(f"Kafka Consumer started")
print(f"  Bootstrap: {BOOTSTRAP}")
print(f"  Topic: {TOPIC}")
print(f"  Consumer group: {GROUP_ID}")
print(f"  Auto-offset-reset: earliest")
print()

level_counts = {}
total = 0
no_message_count = 0
MAX_IDLE = 120  # seconds without messages before exiting

last_message_time = time.time()

try:
    while no_message_count < MAX_IDLE:
        msg = consumer.poll(timeout=1.0)

        if msg is None:
            no_message_count += 1
            continue

        if msg.error():
            if msg.error().code() == KafkaError._PARTITION_EOF:
                print(f"End of partition reached {msg.topic()} [{msg.partition()}] offset {msg.offset()}")
                no_message_count += 1
                continue
            else:
                raise KafkaError(msg.error())

        no_message_count = 0
        total += 1
        value = msg.value()
        if isinstance(value, bytes):
            value = json.loads(value)

        level = value.get("level", "UNKNOWN")
        level_counts[level] = level_counts.get(level, 0) + 1

        ts = value.get("timestamp", "unknown")
        service = value.get("service", "unknown")
        m = value.get("message", "")

        print(f"[{ts}] [{level:5s}] {service}: {m}")

        if total <= 3:
            print(f"  -> partition={msg.partition()}, offset={msg.offset()}")

except KeyboardInterrupt:
    print("\nShutting down consumer...")
finally:
    print(f"\n--- Summary ---")
    print(f"Total messages consumed: {total}")
    for level, count in sorted(level_counts.items()):
        print(f"  {level}: {count}")
    consumer.close()
