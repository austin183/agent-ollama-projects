FROM docker.io/library/python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
    Pillow \
    mutagen \
    psycopg2-binary \
    watchdog

ENV PYTHONUNBUFFERED=1

WORKDIR /app

COPY extractor.py /app/extractor.py
COPY schema.sql /app/schema.sql

CMD ["python", "/app/extractor.py"]
