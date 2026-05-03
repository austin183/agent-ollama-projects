import os
import sys
import json
import time
import uuid
import random
import redis
from datetime import datetime, timezone

REDIS_PRIMARY_URL = os.environ.get("REDIS_PRIMARY_URL", "redis://localhost:6379/0")
REDIS_REPLICA_URL = os.environ.get("REDIS_REPLICA_URL", "redis://localhost:6379/0")
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
    print(f"  Primary: {REDIS_PRIMARY_URL}")
    print(f"  Replica: {REDIS_REPLICA_URL}")
    print(f"  Publishing to queue on primary: {QUEUE_NAME}")
    print(f"  Reading results from replica: {QUEUE_NAME}")
    print(f"  Press Ctrl+C to stop\n")

    primary = None

    while True:
        try:
            primary = redis.from_url(REDIS_PRIMARY_URL, decode_responses=True)
            primary.ping()
            print(f"  Connected to primary\n")
            break
        except redis.ConnectionError as e:
            print(f"  Waiting for primary... ({e})")
            time.sleep(3)

    replica = None
    while True:
        try:
            replica = redis.from_url(REDIS_REPLICA_URL, decode_responses=True)
            replica.ping()
            print(f"  Connected to replica\n")
            break
        except redis.ConnectionError as e:
            print(f"  Waiting for replica... ({e})")
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

            # Publish to queue on primary
            primary.rpush(QUEUE_NAME, json.dumps(task))

            print(f"  Queued task on primary: id={task['id']}, type={task['type']}")

            # Read result from replica (demonstrates read-through-replication)
            result_key = f"result:{task['id']}"
            time.sleep(2)  # Give worker time to process
            result = replica.get(result_key)
            if result:
                result_data = json.loads(result)
                print(f"  Result from replica: {json.dumps(result_data, indent=2)}")
            else:
                print(f"  Result not yet available on replica")

            print()
            time.sleep(random.uniform(3, 6))

    except KeyboardInterrupt:
        print(f"\n[{datetime.now(timezone.utc).isoformat()}] Producer stopped by user")
        sys.exit(0)


if __name__ == "__main__":
    main()
