FROM docker.io/python:3.11-slim

WORKDIR /app/workers

# Install Java for Kafka CLI tools
RUN apt-get update && apt-get install -y --no-install-recommends openjdk-21-jre-headless wget tar && \
    wget -q https://archive.apache.org/dist/kafka/3.9.0/kafka_2.13-3.9.0.tgz && \
    tar -xzf kafka_2.13-3.9.0.tgz && \
    mv kafka_2.13-3.9.0 /opt/kafka && \
    rm kafka_2.13-3.9.0.tgz && \
    pip install --no-cache-dir confluent-kafka && \
    apt-get remove -y wget && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

# Copy worker Python scripts
COPY producer.py consumer.py /app/workers/

CMD ["python", "producer.py"]
