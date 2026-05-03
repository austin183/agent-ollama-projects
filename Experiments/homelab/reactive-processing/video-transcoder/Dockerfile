FROM docker.io/nvidia/cuda:12.6.0-base-ubuntu22.04

# Build dependencies for FFmpeg
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential nasm yasm git pkg-config \
    libx264-dev libx265-dev libnuma-dev libvpx-dev libopus-dev \
    python3 && \
    # Install NVIDIA Video Codec SDK headers (required for CUVID)
    git clone --depth 1 https://github.com/FFmpeg/nv-codec-headers.git /nv-codec-headers && \
    cd /nv-codec-headers && make install && cd / && rm -rf /nv-codec-headers && \
    # Download and build FFmpeg with NVENC/CUVID
    git clone --depth 1 https://git.ffmpeg.org/ffmpeg.git /ffmpeg-src && \
    cd /ffmpeg-src && \
    ./configure --enable-gpl --enable-version3 --enable-nonfree \
        --enable-nvenc --enable-cuvid --enable-libx264 --enable-libx265 \
        --enable-libvpx --enable-libopus \
        --disable-debug --disable-doc && \
    make -j$(nproc) && \
    make install && \
    cd / && rm -rf /ffmpeg-src && \
    apt-get remove -y build-essential git && \
    apt-get autoremove -y && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Runtime deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip curl && \
    rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir psycopg2-binary watchdog

WORKDIR /app
COPY watcher.py /app/watcher.py
COPY benchmark.sh /app/benchmark.sh
COPY schema.sql /app/schema.sql
RUN chmod +x /app/benchmark.sh

ENV PYTHONUNBUFFERED=1
ENV LD_LIBRARY_PATH=/usr/local/lib

HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
    CMD python3 -c "import subprocess; subprocess.run(['ffmpeg', '-encoders'], capture_output=True, check=True)" || exit 1

CMD ["python3", "/app/watcher.py"]
