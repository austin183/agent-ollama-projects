#!/usr/bin/env python3
"""
OpenVINO Image Analyzer: watches a directory for new images,
runs YOLOv8n object detection via OpenVINO Model Server,
and stores results in PostgreSQL.
"""

import os
import sys
import time
import json
import base64
import hashlib
import urllib.request
import urllib.error
from datetime import datetime, timezone
from pathlib import Path
from io import BytesIO

import psycopg2
import psycopg2.extras
from PIL import Image
import numpy as np
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# Configuration
DB_HOST = os.getenv("DB_HOST", "postgresql")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "detections")
DB_USER = os.getenv("DB_USER", "detect_user")
DB_PASSWORD = os.getenv("DB_PASSWORD", "detect_pass_123")
OVMS_HOST = os.getenv("OVMS_HOST", "openvino-server")
OVMS_PORT = int(os.getenv("OVMS_PORT", "8000"))
INPUT_DIR = os.getenv("INPUT_DIR", "/input")
OUTPUT_DIR = os.getenv("OUTPUT_DIR", "/output")
CONFIDENCE_THRESHOLD = float(os.getenv("CONFIDENCE_THRESHOLD", "0.4"))

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tiff", ".tif"}
PROCESSED_HASHES = set()


def get_file_hash(filepath):
    """Get MD5 hash for deduplication."""
    h = hashlib.md5()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def preprocess_image(image_path, target_size=(640, 640)):
    """
    Preprocess image for YOLOv8n (640x640 input).
    Returns numpy array in NCHW format with values [0, 1].
    """
    with Image.open(image_path) as img:
        orig_width, orig_height = img.size
        img_array = np.array(img)

        if len(img_array.shape) == 2:
            img_array = np.stack([img_array] * 3, axis=-1)

        if img_array.shape[2] == 4:
            img_array = img_array[:, :, :3]

        resized = np.array(img.resize(target_size, Image.LANCZOS))

        if len(resized.shape) == 2:
            resized = np.stack([resized] * 3, axis=-1)

        img_normalized = resized.astype(np.float32) / 255.0
        img_transposed = np.transpose(img_normalized, (2, 0, 1))
        img_batch = np.expand_dims(img_transposed, axis=0)

    return img_batch, orig_width, orig_height


def send_inference(image_batch):
    """
    Send preprocessed image to OpenVINO Model Server for inference.
    Returns raw model output array.
    """
    url = f"http://{OVMS_HOST}:{OVMS_PORT}/v1/models/yolov8n:predict"

    payload = {
        "instances": [
            {
                "image": base64.b64encode(image_batch.tobytes()).decode("utf-8"),
                "shape": image_batch.shape,
                "dtype": "FP32",
            }
        ]
    }

    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    start_time = time.time()
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            result = json.loads(resp.read().decode("utf-8"))
            latency = (time.time() - start_time) * 1000
            return result, latency
    except urllib.error.URLError as e:
        print(f"[ERROR] Inference failed: {e}")
        raise


def parse_yolov8_output(raw_output, orig_width, orig_height, threshold=0.4):
    """
    Parse YOLOv8n model output into detection results.

    YOLOv8 output format: [batch, num_anchors_or_boxes, xywh + confidence + classes]
    For YOLOv8n ONNX: output shape is typically [1, 84, 8400] or [1, 84, num_boxes]
    - First 4 values: x, y, width, height (center-relative, 0-1)
    - 5th value: objectness confidence
    - Remaining 80 values: class probabilities (COCO dataset)

    Returns list of detection dicts with bounding boxes in original image coordinates.
    """
    detections = []

    if isinstance(raw_output, dict):
        if "predictions" in raw_output:
            predictions = raw_output["predictions"]
        elif "outputs" in raw_output:
            predictions = raw_output["outputs"]
        else:
            predictions = [raw_output]
    elif isinstance(raw_output, list):
        predictions = raw_output
    else:
        predictions = [raw_output]

    for prediction in predictions:
        if isinstance(prediction, dict):
            if "outputs" in prediction:
                output = prediction["outputs"]
            elif "output0" in prediction:
                output = prediction["output0"]
            elif "predictions" in prediction:
                output = prediction["predictions"]
            else:
                continue

            if not isinstance(output, list):
                continue

            try:
                if len(output) >= 2 and isinstance(output[0], list) and isinstance(output[1], list):
                    # TensorFlow Serving format: [output_name, values]
                    values = output[1] if isinstance(output[1], list) else [output[1]]
                elif isinstance(output, list) and len(output) > 0:
                    values = output
                else:
                    continue

                values = np.array(values, dtype=np.float32)

                if values.ndim == 1:
                    values = values.reshape(1, -1)

                if values.ndim != 2:
                    continue

                if values.shape[0] == 1:
                    values = values.T

                if values.shape[1] < 7:
                    continue

                boxes = values[:, :4]
                confidences = values[:, 4]
                classes = values[:, 5].astype(int)

                if values.shape[1] > 6:
                    class_probs = values[:, 6]
                else:
                    class_probs = confidences

                for i in range(len(boxes)):
                    cx, cy, bw, bh = boxes[i]

                    if cx > 1.0 or cy > 1.0 or bw > 1.0 or bh > 1.0:
                        cx, cy, bw, bh = cx / 640.0, cy / 640.0, bw / 640.0, bh / 640.0

                    x1 = max(0, int((cx - bw / 2) * orig_width))
                    y1 = max(0, int((cy - bh / 2) * orig_height))
                    x2 = min(orig_width, int((cx + bw / 2) * orig_width))
                    y2 = min(orig_height, int((cy + bh / 2) * orig_height))

                    confidence = float(max(confidences[i], class_probs[i]))

                    if confidence >= threshold:
                        detections.append({
                            "class_id": int(classes[i]),
                            "class_name": f"class_{classes[i]}",
                            "confidence": round(confidence, 4),
                            "bbox": {
                                "x1": x1,
                                "y1": y1,
                                "x2": x2,
                                "y2": y2,
                            },
                        })

            except (ValueError, IndexError, TypeError) as e:
                print(f"  [WARN] Could not parse output: {e}")
                continue

    detections.sort(key=lambda d: d["confidence"], reverse=True)
    return detections


def store_detection(filename, image_path, detections, latency_ms, orig_width, orig_height, img_format):
    """Store detection results in PostgreSQL."""
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
                image_format, detections, inference_latency_ms)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s)""",
            (
                filename,
                str(image_path),
                file_size,
                orig_width,
                orig_height,
                img_format,
                json.dumps(detections),
                round(latency_ms, 2),
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
    """Process a single image: preprocess, infer, parse, store."""
    filepath = Path(filepath)

    if filepath.suffix.lower() not in IMAGE_EXTENSIONS:
        return

    try:
        file_size = filepath.stat().st_size
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

    output_dir = Path(OUTPUT_DIR)
    output_dir.mkdir(parents=True, exist_ok=True)

    try:
        with Image.open(str(filepath)) as img:
            img_format = img.format or filepath.suffix.lstrip(".")
            image_batch, orig_w, orig_h = preprocess_image(str(filepath))
    except Exception as e:
        print(f"  [ERROR] Preprocessing failed: {e}")
        return

    print(f"  Preprocessed: {orig_w}x{orig_h} -> 640x640 (NCHW FP32)")

    try:
        raw_output, latency = send_inference(image_batch)
        print(f"  Inference latency: {latency:.1f}ms")
    except Exception as e:
        print(f"  [ERROR] Inference failed: {e}")
        return

    detections = parse_yolov8_output(raw_output, orig_w, orig_h, CONFIDENCE_THRESHOLD)
    print(f"  Detections: {len(detections)} objects found")

    for d in detections[:5]:
        bbox = d["bbox"]
        print(
            f"    - {d['class_name']} ({d['confidence']:.2%}): "
            f"[{bbox['x1']},{bbox['y1']},{bbox['x2']},{bbox['y2']}]"
        )

    if detections:
        success = store_detection(
            filepath.name, filepath, detections, latency, orig_w, orig_h, img_format
        )
        if success:
            print(f"  Results stored in PostgreSQL")
        else:
            print(f"  [WARN] Results NOT stored")
    else:
        print("  No objects detected above threshold")


class WatcherHandler(FileSystemEventHandler):
    """Handle filesystem events in the input directory."""

    def on_created(self, event):
        if not event.is_directory:
            process_image(event.src_path)

    def on_modified(self, event):
        if not event.is_directory:
            process_image(event.src_path)


def main():
    print("=" * 60)
    print("OpenVINO Image Analyzer")
    print("=" * 60)
    print(f"  Input directory:   {INPUT_DIR}")
    print(f"  Output directory:  {OUTPUT_DIR}")
    print(f"  OpenVINO Model:    yolov8n (YOLOv8n)")
    print(f"  Model Server:      {OVMS_HOST}:{OVMS_PORT}")
    print(f"  PostgreSQL:        {DB_HOST}:{DB_PORT}/{DB_NAME}")
    print(f"  Confidence thresh: {CONFIDENCE_THRESHOLD}")
    print("=" * 60)

    input_path = Path(INPUT_DIR)
    if not input_path.exists():
        print(f"Creating input directory: {INPUT_DIR}")
        input_path.mkdir(parents=True, exist_ok=True)

    output_path = Path(OUTPUT_DIR)
    output_path.mkdir(parents=True, exist_ok=True)

    try:
        conn = psycopg2.connect(
            host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
            user=DB_USER, password=DB_PASSWORD, connect_timeout=10,
        )
        conn.close()
        print("PostgreSQL connection: OK")
    except Exception as e:
        print(f"PostgreSQL connection: FAILED ({e})")

    try:
        url = f"http://{OVMS_HOST}:{OVMS_PORT}/v1/models/yolov8n"
        with urllib.request.urlopen(url, timeout=5) as resp:
            print(f"OpenVINO Model Server: OK ({resp.status})")
    except Exception as e:
        print(f"OpenVINO Model Server: FAILED ({e})")
        print("Watcher will retry on each file event.")

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
    print("Analyzer stopped.")


if __name__ == "__main__":
    main()
