#!/usr/bin/env python3
"""
Download YOLOv8n ONNX model and convert to OpenVINO IR format.
Run: python3 download-and-convert.py
"""

import openvino as ov
import urllib.request
import os
import sys

MODEL_DIR = "models/yolov8n"
ONNX_URL = "https://github.com/ultralytics/assets/releases/download/v8.3.0/yolov8n.onnx"
ONNX_PATH = os.path.join(MODEL_DIR, "yolov8n.onnx")
IR_PATH = os.path.join(MODEL_DIR, "model")

os.makedirs(MODEL_DIR, exist_ok=True)

# Check if already converted
if os.path.exists(f"{IR_PATH}.xml") and os.path.exists(f"{IR_PATH}.bin"):
    print("OpenVINO IR model already exists, skipping download and conversion.")
    sys.exit(0)

# Download ONNX model
if not os.path.exists(ONNX_PATH):
    print(f"Downloading YOLOv8n ONNX model from {ONNX_URL}...")
    urllib.request.urlretrieve(ONNX_URL, ONNX_PATH)
    print(f"Downloaded: {ONNX_PATH}")
else:
    print(f"ONNX model already exists: {ONNX_PATH}")

# Check if downloaded file is valid (not HTML)
with open(ONNX_PATH, "rb") as f:
    header = f.read(8)
    if header.startswith(b"<!DOCTYPE") or header.startswith(b"<html"):
        print("[ERROR] Downloaded file is HTML, not ONNX. The URL may have changed.")
        os.remove(ONNX_PATH)
        sys.exit(1)

# Convert to OpenVINO IR format
print("Converting ONNX to OpenVINO IR format...")
model = ov.convert_model(ONNX_PATH, model_name="yolov8n", output_dir=MODEL_DIR)
print(f"Conversion complete: {IR_PATH}.xml and {IR_PATH}.bin")

# Verify files
for f in [f"{IR_PATH}.xml", f"{IR_PATH}.bin"]:
    if os.path.exists(f):
        size = os.path.getsize(f)
        print(f"  {os.path.basename(f)}: {size:,} bytes")
    else:
        print(f"  [ERROR] {f} not found!")
        sys.exit(1)

print("\nModel is ready. Start the server with:")
print("  podman compose up -d")
