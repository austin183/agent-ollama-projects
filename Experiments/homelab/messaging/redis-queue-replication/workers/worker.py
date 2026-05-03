import os
import time
import json
import redis
import hashlib
from datetime import datetime, timezone

REDIS_PRIMARY_URL = os.environ.get("REDIS_PRIMARY_URL", "redis://localhost:6379/0")
REDIS_REPLICA_URL = os.environ.get("REDIS_REPLICA_URL", "redis://localhost:6379/0")
QUEUE_NAME = os.environ.get("QUEUE_NAME", "task_queue")


def process_task(task_data):
    """Process a single task from the queue."""
    task_id = task_data.get("id", "unknown")
    task_type = task_data.get("type", "unknown")
    payload = task_data.get("payload", {})

    print(f"[{datetime.now(timezone.utc).isoformat()}] Processing task {task_id} (type: {task_type})")

    if task_type == "hash":
        input_str = payload.get("input", "")
        result = hashlib.sha256(input_str.encode()).hexdigest()
        print(f"  -> SHA256({input_str[:20]}...) = {result[:32]}...")
        return {"task_id": task_id, "result": result}

    elif task_type == "transform":
        items = payload.get("items", [])
        result = [item.upper() if isinstance(item, str) else item * 2 for item in items]
        print(f"  -> Transformed {len(items)} items")
        return {"task_id": task_id, "result": result}

    elif task_type == "echo":
        print(f"  -> Echoing back: {payload}")
        return {"task_id": task_id, "result": payload}

    else:
        print(f"  -> Unknown task type: {task_type}")
        return {"task_id": task_id, "result": None, "error": f"Unknown type: {task_type}"}


def main():
    print(f"[{datetime.now(timezone.utc).isoformat()}] Redis Worker starting...")
    print(f"  Primary: {REDIS_PRIMARY_URL}")
    print(f"  Replica: {REDIS_REPLICA_URL}")
    print(f"  Listening on queue: {QUEUE_NAME}")
    print(f"  Note: BLPOP is a write operation, must read from primary")

    primary = None
    replica = None

    while True:
        try:
            primary = redis.from_url(REDIS_PRIMARY_URL, decode_responses=True)
            primary.ping()
            replica = redis.from_url(REDIS_REPLICA_URL, decode_responses=True)
            replica.ping()
            print(f"  Connected to primary and replica successfully")
            break
        except redis.ConnectionError as e:
            print(f"  Waiting for Redis... ({e})")
            time.sleep(3)

    print(f"  Ready to process tasks from primary...")

    while True:
        try:
            # BLPOP is a write operation (removes item from list), must use primary
            item = primary.blpop(QUEUE_NAME, timeout=5)

            if item:
                queue_key, task_json = item
                task_data = json.loads(task_json)
                result = process_task(task_data)

                # Store result on primary (replicates to replica automatically)
                result_key = f"result:{task_data.get('id', 'unknown')}"
                primary.setex(result_key, 3600, json.dumps(result))
                print(f"  -> Result stored at {result_key} on primary")
            else:
                pass

        except redis.ConnectionError:
            print("  Redis connection lost, reconnecting...")
            time.sleep(3)
            primary = None
            replica = None
            while True:
                try:
                    primary = redis.from_url(REDIS_PRIMARY_URL, decode_responses=True)
                    primary.ping()
                    replica = redis.from_url(REDIS_REPLICA_URL, decode_responses=True)
                    replica.ping()
                    print("  Reconnected to Redis")
                    break
                except redis.ConnectionError:
                    time.sleep(3)
        except Exception as e:
            print(f"  Error: {e}")
            time.sleep(1)


if __name__ == "__main__":
    main()
