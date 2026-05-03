import os
import sys
import json
import time
import uuid
import random
import redis
from datetime import datetime, timezone

REDIS_URL = os.environ.get("REDIS_URL", "redis://localhost:6379/0")
QUEUE_NAME = os.environ.get("QUEUE_NAME", "task_queue")


def create_task(task_type="echo", **kwargs):
    """Create a task dictionary."""
    task = {
        "id": str(uuid.uuid4())[:8],
        "type": task_type,
        "payload": kwargs,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    return task


def main():
    print(f"[{datetime.now(timezone.utc).isoformat()}] Redis Producer starting...")
    print(f"  Connecting to: {REDIS_URL}")
    print(f"  Publishing to queue: {QUEUE_NAME}")
    print(f"  Press Ctrl+C to stop\n")

    while True:
        try:
            r = redis.from_url(REDIS_URL, decode_responses=True)
            r.ping()
            print(f"  Connected to Redis\n")
            break
        except redis.ConnectionError as e:
            print(f"  Waiting for Redis... ({e})")
            time.sleep(3)

    task_types = ["echo", "hash", "transform"]

    try:
        while True:
            task_type = random.choice(task_types)

            if task_type == "echo":
                task = create_task(
                    task_type="echo",
                    message=f"Hello from producer at {datetime.now(timezone.utc).strftime('%H:%M:%S')}",
                )
            elif task_type == "hash":
                input_str = f"sample data {random.randint(1, 10000)}"
                task = create_task(task_type="hash", input=input_str)
            else:
                task = create_task(
                    task_type="transform",
                    items=[f"item_{i}" for i in range(random.randint(3, 8))],
                )

            # Publish to queue
            r = redis.from_url(REDIS_URL, decode_responses=True)
            r.rpush(QUEUE_NAME, json.dumps(task))

            print(f"  Queued task: id={task['id']}, type={task['type']}")

            # Fetch result if available (within TTL)
            result_key = f"result:{task['id']}"
            time.sleep(1)  # Give worker time to process
            result = r.get(result_key)
            if result:
                result_data = json.loads(result)
                print(f"  Result: {json.dumps(result_data, indent=2)}")
            else:
                print(f"  Result not yet available")

            print()
            time.sleep(random.uniform(2, 5))

    except KeyboardInterrupt:
        print(f"\n[{datetime.now(timezone.utc).isoformat()}] Producer stopped by user")
        sys.exit(0)


if __name__ == "__main__":
    main()
