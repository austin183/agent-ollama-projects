FROM docker.io/library/alpine:3.21

RUN apk add --no-cache \
    postgresql-client \
    curl \
    bash \
    jq \
    file \
    util-linux-misc \
    tar \
    unzip

COPY --chmod=755 query.sh /query.sh
