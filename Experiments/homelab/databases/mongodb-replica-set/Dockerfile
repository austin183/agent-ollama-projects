FROM docker.io/library/mongo:7.0

RUN mkdir -p /data/config && \
    openssl rand -base64 756 > /data/config/keyfile && \
    chown mongodb:mongodb /data/config/keyfile && \
    chmod 400 /data/config/keyfile
