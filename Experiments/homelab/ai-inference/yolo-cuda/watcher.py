#!/usr/bin/env python3
"""
YOLO CUDA Watcher: watches input directory for new images,
runs detection via YOLO CUDA server API,
and stores results in PostgreSQL.
"""

import os
import sys
import time
import json
import hashlib
import urllib.request
import urllib.error
import urllib.parse
from datetime import datetime, timezone
from pathlib import Path
from io import BytesIO

import psycopg2
from PIL import Image
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler


DB_HOST = os.getenv("DB_HOST", "postgresql")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "detections")
DB_USER = os.getenv("DB_USER", "detect_user")
DB_PASSWORD = os.getenv("DB_PASSWORD", "detect_pass_123")
YOLO_HOST = os.getenv("YOLO_HOST", "yolo-server")
YOLO_PORT = int(os.getenv("YOLO_PORT", "8000"))
INPUT_DIR = os.getenv("INPUT_DIR", "/input")
OUTPUT_DIR = os.getenv("OUTPUT_DIR", "/output")
CONFIDENCE_THRESHOLD = float(os.getenv("CONFIDENCE_THRESHOLD", "0.4"))

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tiff", ".tif"}
PROCESSED_HASHES = set()


def get_file_hash(filepath):
    h = hashlib.md5()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def send_inference(image_path):
    url = f"http://{YOLO_HOST}:{YOLO_PORT}/detect"
    with open(image_path, "rb") as f:
        img_data = f.read()

    boundary = "boundary_yolo_cuda"
    filename = os.path.basename(image_path)

    body = b""
    body += f"--{boundary}\r\n".encode()
    body += f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'.encode()
    body += "Content-Type: application/octet-stream\r\n\r\n".encode()
    body += img_data
    body += b"\r\n--" + boundary.encode() + b"--\r\n"

    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        method="POST",
    )

    start_time = time.time()
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            result = json.loads(resp.read().decode("utf-8"))
            latency = (time.time() - start_time) * 1000
            return result, latency
    except urllib.error.URLError as e:
        print(f"[ERROR] Inference failed: {e}")
        raise


def store_detection(filename, image_path, result, orig_width, orig_height, img_format):
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            dbname=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            connect_timeout=10,
        )
        cur = conn.cursor()

        file_size = os.path.getsize(image_path)

        cur.execute(
            """INSERT INTO detections
               (filename, file_path, file_size_bytes, image_width, image_height,
                image_format, model_name, inference_device, inference_latency_ms, detections)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
            (
                filename,
                str(image_path),
                file_size,
                orig_width,
                orig_height,
                img_format,
                result.get("model", "yolov8n"),
                "CUDA",
                result.get("inference_latency_ms", 0),
                json.dumps(result.get("detections", [])),
            ),
        )

        conn.commit()
        cur.close()
        conn.close()
        return True
    except Exception as e:
        print(f"  [ERROR] PostgreSQL error: {e}")
        return False


def process_image(filepath):
    filepath = Path(filepath)

    if filepath.suffix.lower() not in IMAGE_EXTENSIONS:
        return

    try:
        filepath.stat()
    except OSError:
        return

    time.sleep(1)

    try:
        file_hash = get_file_hash(str(filepath))
    except (OSError, IOError):
        return

    if file_hash in PROCESSED_HASHES:
        return
    PROCESSED_HASHES.add(file_hash)

    print(f"\n[PROCESSING] {filepath.name}")

    try:
        with Image.open(str(filepath)) as img:
            img_format = img.format or filepath.suffix.lstrip(".")
            orig_w, orig_h = img.size
    except Exception as e:
        print(f"  [ERROR] Failed to open image: {e}")
        return

    print(f"  Image: {orig_w}x{orig_h} ({img_format})")

    try:
        result, latency = send_inference(str(filepath))
        print(f"  Inference latency: {latency:.1f}ms")
    except Exception as e:
        print(f"  [ERROR] Inference failed: {e}")
        return

    detections = result.get("detections", [])
    print(f"  Detections: {len(detections)} objects found")

    for d in detections[:5]:
        bbox = d["bbox"]
        print(
            f"    - {d['class_name']} ({d['confidence']:.2%}): "
            f"[{bbox[0]},{bbox[1]},{bbox[2]},{bbox[3]}]"
        )

    if detections:
        success = store_detection(
            filepath.name, filepath, result, orig_w, orig_h, img_format
        )
        if success:
            print(f"  Results stored in PostgreSQL")
        else:
            print(f"  [WARN] Results NOT stored")
    else:
        print("  No objects detected above threshold")


class WatcherHandler(FileSystemEventHandler):
    def on_created(self, event):
        if not event.is_directory:
            process_image(event.src_path)

    def on_modified(self, event):
        if not event.is_directory:
            process_image(event.src_path)


def main():
    print("=" * 60)
    print("YOLO CUDA Image Analyzer")
    print("=" * 60)
    print(f"  Input directory:   {INPUT_DIR}")
    print(f"  Output directory:  {OUTPUT_DIR}")
    print(f"  YOLO Server:       {YOLO_HOST}:{YOLO_PORT}")
    print(f"  PostgreSQL:        {DB_HOST}:{DB_PORT}/{DB_NAME}")
    print(f"  Confidence thresh: {CONFIDENCE_THRESHOLD}")
    print("=" * 60)

    input_path = Path(INPUT_DIR)
    if not input_path.exists():
        print(f"Creating input directory: {INPUT_DIR}")
        input_path.mkdir(parents=True, exist_ok=True)

    output_path = Path(OUTPUT_DIR)
    output_path.mkdir(parents=True, exist_ok=True)

    # Wait for PostgreSQL
    pg_ready = False
    for attempt in range(30):
        try:
            conn = psycopg2.connect(
                host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
                user=DB_USER, password=DB_PASSWORD, connect_timeout=5,
            )
            conn.close()
            print("PostgreSQL connection: OK")
            pg_ready = True
            break
        except Exception as e:
            if attempt < 29:
                print(f"PostgreSQL not ready (attempt {attempt+1}/30), retrying...")
                time.sleep(2)

    if not pg_ready:
        print("PostgreSQL connection: FAILED after 30 attempts")
        sys.exit(1)

    # Wait for YOLO server
    yolo_ready = False
    for attempt in range(30):
        try:
            url = f"http://{YOLO_HOST}:{YOLO_PORT}/health"
            with urllib.request.urlopen(url, timeout=10) as resp:
                health = json.loads(resp.read().decode("utf-8"))
                print(f"YOLO Server: OK (CUDA: {health.get('cuda_available', 'N/A')})")
                yolo_ready = True
                break
        except Exception as e:
            if attempt < 29:
                print(f"YOLO server not ready (attempt {attempt+1}/30), retrying...")
                time.sleep(2)

    if not yolo_ready:
        print("YOLO Server: FAILED after 30 attempts")
        sys.exit(1)

    handler = WatcherHandler()
    observer = Observer()
    observer.schedule(handler, INPUT_DIR, recursive=False)
    observer.start()

    print(f"\nWatching for new images in {INPUT_DIR}...")
    print("Drop images into the input directory to analyze them.\n")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nShutting down...")
        observer.stop()

    observer.join()
    print("Watcher stopped.")


if __name__ == "__main__":
    main()
