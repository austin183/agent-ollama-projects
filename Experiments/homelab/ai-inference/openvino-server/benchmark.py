#!/usr/bin/env python3
"""Benchmark OpenVINO Model Server CPU inference speed."""
import urllib.request
import json
import time
import numpy as np
from PIL import Image

IMG_PATH = "/test-image.jpg"
API_URL = "http://openvino-server:8000/v1/models/resnet:predict"
NUM_REQUESTS = 20

def preprocess_image(img_path):
    img = Image.open(img_path).convert("RGB")
    img = img.resize((224, 224), Image.Resampling.BILINEAR)
    img_array = np.array(img, dtype=np.float32)
    mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
    std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
    img_array = (img_array / 255.0 - mean) / std
    img_array = np.transpose(img_array, (2, 0, 1))
    img_array = np.expand_dims(img_array, axis=0)
    return json.dumps({"instances": img_array.tolist()}).encode("utf-8")

def benchmark():
    payload = preprocess_image(IMG_PATH)
    req = urllib.request.Request(
        API_URL,
        data=payload,
        headers={"Content-Type": "application/json"}
    )

    latencies = []
    print(f"Running {NUM_REQUESTS} inference requests...")
    print()

    for i in range(NUM_REQUESTS):
        start = time.perf_counter()
        with urllib.request.urlopen(req, timeout=30) as resp:
            resp.read()
        elapsed = (time.perf_counter() - start) * 1000
        latencies.append(elapsed)

        if (i + 1) % 5 == 0:
            print(f"  Request {i+1}/{NUM_REQUESTS}: {elapsed:.1f}ms")

    print()
    print(f"{'Metric':<25}{'Value':>12}")
    print("  " + "-" * 38)
    print(f"{'Total requests':<25}{NUM_REQUESTS:>12}")
    print(f"{'Min latency':<25}{min(latencies):>11.1f}ms")
    print(f"{'Max latency':<25}{max(latencies):>11.1f}ms")
    print(f"{'Avg latency':<25}{np.mean(latencies):>11.1f}ms")
    print(f"{'Std deviation':<25}{np.std(latencies):>11.1f}ms")
    print(f"{'Throughput':<25}{1000/np.mean(latencies):>10.2f} req/s")
    print(f"{'P50 latency':<25}{sorted(latencies)[len(latencies)//2]:>11.1f}ms")
    print(f"{'P95 latency':<25}{sorted(latencies)[int(len(latencies)*0.95)]:>11.1f}ms")
    print(f"{'P99 latency':<25}{sorted(latencies)[int(len(latencies)*0.99)]:>11.1f}ms")

if __name__ == "__main__":
    benchmark()
