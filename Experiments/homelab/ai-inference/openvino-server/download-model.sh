#!/bin/bash
# download-model.sh - Downloads OpenVINO model files to the models directory
# Usage: ./download-model.sh [model_name]
#
# Available models:
#   resnet50         - Image classification (224x224 input, 1000 classes)
#   mobilenet-ssd    - Object detection (300x300 input)
#   efficientnet-b0  - Image classification (224x224 input)

set -e

MODEL_NAME="${1:-resnet50}"
MODEL_DIR="models/${MODEL_NAME}"
VERSION_DIR="${MODEL_DIR}/1"

mkdir -p "$VERSION_DIR"

echo "Downloading ${MODEL_NAME} model to ${VERSION_DIR}..."

case "$MODEL_NAME" in
    resnet50)
        # ResNet-50 Image Classification model (OpenVINO IR format)
        echo "Downloading model weights..."
        wget -N -P "$VERSION_DIR" \
            "https://storage.openvinotoolkit.org/repositories/open_model_zoo/2022.1/models_bin/2/resnet50-binary-0001/FP32-INT1/resnet50-binary-0001.xml"
        wget -N -P "$VERSION_DIR" \
            "https://storage.openvinotoolkit.org/repositories/open_model_zoo/2022.1/models_bin/2/resnet50-binary-0001/FP32-INT1/resnet50-binary-0001.bin"
        # Rename to model.xml/model.bin for OVMS compatibility
        mv "${VERSION_DIR}/resnet50-binary-0001.xml" "${VERSION_DIR}/model.xml"
        mv "${VERSION_DIR}/resnet50-binary-0001.bin" "${VERSION_DIR}/model.bin"
        ;;
    mobilenet-ssd)
        # MobileNet SSD Object Detection model
        echo "Downloading model weights..."
        wget -N -P "$VERSION_DIR" \
            "https://storage.openvinotoolkit.org/repositories/open_model_zoo/2022.1/models_bin/2/mobilenet-ssd/mobilenet-ssd.xml"
        wget -N -P "$VERSION_DIR" \
            "https://storage.openvinotoolkit.org/repositories/open_model_zoo/2022.1/models_bin/2/mobilenet-ssd/mobilenet-ssd.bin"
        mv "${VERSION_DIR}/mobilenet-ssd.xml" "${VERSION_DIR}/model.xml"
        mv "${VERSION_DIR}/mobilenet-ssd.bin" "${VERSION_DIR}/model.bin"
        ;;
    efficientnet-b0)
        echo "Downloading EfficientNet-B0 model..."
        wget -N -P "$VERSION_DIR" \
            "https://storage.openvinotoolkit.org/repositories/open_model_zoo/2022.1/models_bin/2/efficientnet-b0/pytorch/openvino/2022.1/int8/efficientnet-b0.xml"
        wget -N -P "$VERSION_DIR" \
            "https://storage.openvinotoolkit.org/repositories/open_model_zoo/2022.1/models_bin/2/efficientnet-b0/pytorch/openvino/2022.1/int8/efficientnet-b0.bin"
        mv "${VERSION_DIR}/efficientnet-b0.xml" "${VERSION_DIR}/model.xml"
        mv "${VERSION_DIR}/efficientnet-b0.bin" "${VERSION_DIR}/model.bin"
        ;;
    *)
        echo "Unknown model: ${MODEL_NAME}"
        echo "Available models: resnet50, mobilenet-ssd, efficientnet-b0"
        exit 1
        ;;
esac

echo ""
echo "Model files:"
ls -lh "${VERSION_DIR}/"
echo ""
echo "Model ready at: ${VERSION_DIR}/"
