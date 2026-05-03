#!/usr/bin/env bash
# Download YOLOv8n ONNX model and convert to OpenVINO IR format.
# Run this script before starting the containers:
#   bash download-model.sh
# Then start with: podman compose up -d

set -e

MODEL_DIR="models/yolov8n"
ONNX_URL="https://github.com/ultralytics/assets/releases/download/v8.3.0/yolov8n.onnx"
MODEL_XML="${MODEL_DIR}/model.xml"
MODEL_BIN="${MODEL_DIR}/model.bin"

mkdir -p "${MODEL_DIR}"

if [ -f "${MODEL_XML}" ] && [ -f "${MODEL_BIN}" ]; then
    echo "Model already exists, skipping download."
    exit 0
fi

echo "Downloading YOLOv8n ONNX model..."
wget -q --show-progress -O "${MODEL_DIR}/yolov8n.onnx" "${ONNX_URL}"

echo "Checking downloaded model..."
file "${MODEL_DIR}/yolov8n.onnx"

if file "${MODEL_DIR}/yolov8n.onnx" | grep -q "HTML"; then
    echo "[ERROR] Downloaded file is HTML, not ONNX. The URL may have changed."
    echo "Try downloading manually from: https://github.com/ultralytics/assets/releases/tag/v8.3.0"
    exit 1
fi

echo ""
echo "Model downloaded. Convert to OpenVINO IR format by running inside the server container:"
echo ""
echo "  podman exec homelab-openvino-analyzer-server mo \\"
echo "    --input_model /models/yolov8n/yolov8n.onnx \\"
echo "    --output_dir /models/yolov8n \\"
echo "    --model_name yolov8n"
echo ""
echo "Then update docker-compose.yml to point to the IR model files."
echo "Or use the Dockerfile build which does this automatically."
