#!/usr/bin/env python3
"""Test OpenVINO Model Server REST API with a sample image."""
import urllib.request
import urllib.error
import json
import base64
import os
import sys
import time

IMG_PATH = "/test-image.jpg"
API_URL = "http://openvino-server:8000/v1/models/resnet:predict"

# ImageNet class labels (top 10)
IMAGENET_CLASSES = {
    111: "tabby cat", 112: "tiger cat", 281: "Egyptian cat",
    282: "Persian cat", 283: "Siamese cat", 284: "Domestic cat",
    155: "lynx", 285: "kitten", 567: "hamster", 773: "dog",
}

def preprocess_image(img_path):
    """Load and resize image to 224x224, convert to NCHW FP32 format."""
    try:
        from PIL import Image
        import numpy as np
    except ImportError:
        print("PIL and numpy required. Install: pip install Pillow numpy")
        sys.exit(1)

    img = Image.open(img_path).convert("RGB")
    img = img.resize((224, 224), Image.Resampling.BILINEAR)

    img_array = np.array(img, dtype=np.float32)
    mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
    std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
    img_array = (img_array / 255.0 - mean) / std
    img_array = np.transpose(img_array, (2, 0, 1))
    img_array = np.expand_dims(img_array, axis=0)

    return img_array.tolist()

def predict(image_path):
    """Send image to OVMS and get predictions."""
    data = preprocess_image(image_path)

    # TensorFlow Serving API format: use "instances" key, not "inputs"
    payload = {
        "instances": data
    }

    req = urllib.request.Request(
        API_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )

    with urllib.request.urlopen(req, timeout=30) as response:
        result = json.loads(response.read().decode("utf-8"))

    return result

def top_k_predictions(result, k=10):
    """Extract top-k predictions from OVMS response."""
    # OVMS uses "predictions" key (TensorFlow Serving API), not "outputs"
    predictions = result.get("predictions", [])
    if not predictions:
        print("No predictions in response")
        return []

    # Each prediction is a list of 1000 logit scores
    pred_data = predictions[0]
    predictions_list = [(i, score) for i, score in enumerate(pred_data)]
    predictions_list.sort(key=lambda x: x[1], reverse=True)

    return predictions_list[:k]

if __name__ == "__main__":
    if not os.path.exists(IMG_PATH):
        print(f"ERROR: Image not found at {IMG_PATH}")
        sys.exit(1)

    print("=== OpenVINO Model Server - ResNet-50 Inference ===")
    print(f"Image: {IMG_PATH}")

    print("\nSending inference request...")
    start = time.time()
    result = predict(IMG_PATH)
    elapsed = time.time() - start

    print(f"\nInference time: {elapsed*1000:.1f}ms\n")

    preds = top_k_predictions(result, k=10)

    print(f"  {'Rank':<6}{'Class ID':<12}{'Score':>10}")
    print("  " + "-" * 30)
    for rank, (class_id, score) in enumerate(preds, 1):
        label = IMAGENET_CLASSES.get(class_id, f"class {class_id}")
        print(f"  {rank:<6}{class_id:<12}{score:>10.4f}")

    print(f"\nTop prediction: Class {preds[0][0]} (logit={preds[0][1]:.4f})")
    print("\nTEST PASSED - OpenVINO Model Server running on CPU!")
