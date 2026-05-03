FROM docker.io/python:3.11-slim

RUN pip install --no-cache-dir redis

WORKDIR /app

COPY worker.py /app/worker.py
COPY producer.py /app/producer.py

CMD ["python", "worker.py"]
