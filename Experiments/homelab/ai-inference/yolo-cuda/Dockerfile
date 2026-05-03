FROM docker.io/nvidia/cuda:12.4.1-runtime-ubuntu22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 \
    python3-pip \
    libgl1 \
    libglib2.0-0 \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN python3.11 -m pip install --no-cache-dir \
    ultralytics \
    fastapi \
    uvicorn \
    python-multipart \
    Pillow

ENV PYTHONUNBUFFERED=1

WORKDIR /app

COPY server.py /app/server.py

EXPOSE 8000

CMD ["python3.11", "-m", "uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000"]
