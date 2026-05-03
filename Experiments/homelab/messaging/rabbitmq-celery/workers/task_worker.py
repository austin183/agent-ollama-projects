import os
import time
import json
import logging
from datetime import datetime

from celery import Celery

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

broker_url = os.environ.get(
    "CELERY_BROKER_URL",
    "amqp://homelab:changeme@rabbitmq:5672//",
)
app = Celery("tasks", broker=broker_url)


@app.task(bind=True, name="tasks.resize_image")
def resize_image(self, width, height, format="webp"):
    logger.info(
        "[resize_image] Processing: %dx%d -> %s", width, height, format
    )
    time.sleep(2)
    result = {
        "original": f"{width}x{height}",
        "output_format": format,
        "processed_at": datetime.utcnow().isoformat(),
    }
    logger.info("[resize_image] Done: %s", result)
    return result


@app.task(bind=True, name="tasks.send_email")
def send_email(self, to, subject, body="Hello from Celery"):
    logger.info("[send_email] Sending to %s: %s", to, subject)
    time.sleep(1)
    result = {
        "to": to,
        "subject": subject,
        "status": "sent",
        "sent_at": datetime.utcnow().isoformat(),
    }
    logger.info("[send_email] Done: %s", result)
    return result


@app.task(bind=True, name="tasks.generate_report")
def generate_report(self, report_type, year):
    logger.info(
        "[generate_report] Generating %s report for %s", report_type, year
    )
    time.sleep(3)
    result = {
        "report_type": report_type,
        "year": year,
        "pages": 12,
        "generated_at": datetime.utcnow().isoformat(),
    }
    logger.info("[generate_report] Done: %s", result)
    return result


@app.task(bind=True, name="tasks.process_video")
def process_video(self, duration, codec="h264"):
    logger.info(
        "[process_video] Processing %ds video with %s codec", duration, codec
    )
    time.sleep(4)
    result = {
        "duration": duration,
        "codec": codec,
        "output_file": f"output_{duration}s_{codec}.mp4",
        "processed_at": datetime.utcnow().isoformat(),
    }
    logger.info("[process_video] Done: %s", result)
    return result


@app.task(bind=True, name="tasks.echo")
def echo(self, message):
    logger.info("[echo] Received: %s", message)
    return {"echo": message, "received_at": datetime.utcnow().isoformat()}


if __name__ == "__main__":
    logger.info("Starting Celery worker...")
    logger.info("Broker: %s", broker_url)
    logger.info("Connected queues: resize_image, send_email, generate_report, process_video, echo")
    app.start()
