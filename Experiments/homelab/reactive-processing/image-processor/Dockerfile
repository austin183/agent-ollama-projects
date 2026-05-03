FROM docker.io/library/python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir watchdog Pillow pymongo

COPY watcher.py /app/watcher.py

ENV PYTHONUNBUFFERED=1
CMD ["python", "/app/watcher.py"]
