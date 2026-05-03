import os
import time
import json
import redis
import hashlib
from datetime import datetime, timezone

REDIS_URL = os.environ.get("REDIS_URL", "redis://localhost:6379/0")
QUEUE_NAME = os.environ.get("QUEUE_NAME", "task_queue")


def process_task(task_data):
    """Process a single task from the queue."""
    task_id = task_data.get("id", "unknown")
    task_type = task_data.get("type", "unknown")
    payload = task_data.get("payload", {})

    print(f"[{datetime.now(timezone.utc).isoformat()}] Processing task {task_id} (type: {task_type})")

    # Simulate different types of work
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
    print(f"  Connecting to: {REDIS_URL}")
    print(f"  Listening on queue: {QUEUE_NAME}")

    while True:
        try:
            r = redis.from_url(REDIS_URL, decode_responses=True)
            r.ping()
            print(f"  Connected to Redis successfully")
            break
        except redis.ConnectionError as e:
            print(f"  Waiting for Redis... ({e})")
            time.sleep(3)

    print(f"  Ready to process tasks!")

    while True:
        try:
            r = redis.from_url(REDIS_URL, decode_responses=True)

            # Blocking pop with 5 second timeout
            item = r.blpop(QUEUE_NAME, timeout=5)

            if item:
                queue_key, task_json = item
                task_data = json.loads(task_json)
                result = process_task(task_data)

                # Store result
                result_key = f"result:{task_data.get('id', 'unknown')}"
                r.setex(result_key, 3600, json.dumps(result))
                print(f"  -> Result stored at {result_key}")
            else:
                # No tasks, keep waiting
                pass

        except redis.ConnectionError:
            print("  Redis connection lost, reconnecting...")
            time.sleep(3)
        except Exception as e:
            print(f"  Error: {e}")
            time.sleep(1)


if __name__ == "__main__":
    main()
