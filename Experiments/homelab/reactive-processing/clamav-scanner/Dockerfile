FROM docker.io/debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    clamav-daemon \
    clamav-freshclam \
    clamav-base \
    clamav \
    python3 \
    python3-pip \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 install --no-cache-dir --break-system-packages watchdog

# Create directories
RUN mkdir -p /var/log/clamav /var/lib/clamav /scan /quarantine

# Copy scanner and startup script
COPY scanner.py /app/scanner.py
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

ENV SCAN_DIR=/scan \
    QUARANTINE_DIR=/quarantine \
    PYTHONUNBUFFERED=1

EXPOSE 3310

CMD ["/app/start.sh"]
