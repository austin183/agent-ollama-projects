FROM docker.io/linuxserver/libreoffice:latest

WORKDIR /app

RUN pip install --no-cache-dir watchdog

COPY converter.py /app/converter.py

CMD ["python3", "/app/converter.py"]
