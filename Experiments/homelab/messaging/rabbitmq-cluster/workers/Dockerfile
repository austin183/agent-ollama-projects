FROM docker.io/python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app/workers

RUN pip install --no-cache-dir celery[redis] pika

COPY . .

CMD ["tail", "-f", "/dev/null"]
