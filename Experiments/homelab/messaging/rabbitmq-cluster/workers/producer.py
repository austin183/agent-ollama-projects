import os
import time
import datetime

from celery import Celery

broker_url = os.environ.get(
    "CELERY_BROKER_URL",
    "amqp://homelab:homelab123@rabbitmq1:5672//",
)
app = Celery("tasks", broker=broker_url)


if __name__ == "__main__":
    print("Celery Producer - sending tasks via Celery...")
    print(f"Broker: {broker_url}")
    print()

    tasks = [
        ("tasks.resize_image", {"width": 800, "height": 600, "format": "webp"}),
        ("tasks.send_email", {"to": "user@example.com", "subject": "Hello from Celery"}),
        ("tasks.generate_report", {"report_type": "monthly", "year": 2026}),
        ("tasks.process_video", {"duration": 120, "codec": "h264"}),
        ("tasks.resize_image", {"width": 200, "height": 200, "format": "jpg"}),
    ]

    for i, (task_name, kwargs) in enumerate(tasks, 1):
        print(f"[{i}/{len(tasks)}] Sending {task_name}...")
        result = app.send_task(task_name, kwargs=kwargs)
        print(f"      Task ID: {result.id}")
        time.sleep(1)

    print()
    print(f"Done! {len(tasks)} tasks sent to Celery.")
    print("Check the celery-worker logs to see tasks being processed.")
    print("Check Flower at http://localhost:5555 to monitor task status.")
