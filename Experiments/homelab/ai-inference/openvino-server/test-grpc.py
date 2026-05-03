#!/usr/bin/env python3
"""Test OpenVINO Model Server gRPC API."""
import sys
import os
import numpy as np
from PIL import Image

try:
    import grpc
except ImportError:
    print("grpcio required. Install: pip install grpcio")
    sys.exit(1)

# Try to import generated protobuf files
try:
    from google.protobuf import empty_pb2
    from model_service import services_pb2
    from model_service import model_service_pb2
    from model_service import model_service_pb2_grpc
except ImportError:
    print("gRPC protobuf stubs not found.")
    print("Generate with: python -m grpc_tools.protoc -I. --python_out=. --grpc_python_out=. model_config.proto")
    print("Or test with REST API instead.")
    sys.exit(1)

def preprocess_image(img_path):
    """Load and resize image to 224x224, convert to NCHW FP32 format."""
    img = Image.open(img_path).convert("RGB")
    img = img.resize((224, 224), Image.Resampling.BILINEAR)
    img_array = np.array(img, dtype=np.float32)
    mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
    std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
    img_array = (img_array / 255.0 - mean) / std
    img_array = np.transpose(img_array, (2, 0, 1))
    img_array = np.expand_dims(img_array, axis=0)
    return img_array

def test_grpc():
    """Test gRPC connection and inference."""
    target = "openvino-server:9000"
    print(f"Connecting to gRPC endpoint: {target}")

    channel = grpc.insecure_channel(target)
    stub = model_service_pb2_grpc.ModelServiceStub(channel)

    # Check model status
    print("\n--- Model Status ---")
    request = services_pb2.ModelSpec(name="resnet")
    try:
        response = stub.GetModelStatus(request)
        print(f"Model state: {response.version_status[0].state}")
        print(f"State name: {services_pb2.ModelStatusProto.State.Name(response.version_status[0].state)}")
    except grpc.RpcError as e:
        print(f"GetModelStatus error: {e.code()}: {e.details()}")
        return

    # Get model metadata
    print("\n--- Model Metadata ---")
    try:
        response = stub.GetModelConfig(request)
        print(f"Config received: {response is not None}")
    except grpc.RpcError as e:
        print(f"GetModelConfig error: {e.code()}: {e.details()}")

    # Infer request
    img_path = "/test-image.jpg"
    if not os.path.exists(img_path):
        print(f"Image not found at {img_path}")
        return

    print("\n--- gRPC Inference ---")
    img_array = preprocess_image(img_path)
    tensor = services_pb2.TensorProto(
        dtype="DT_FLOAT",
        float_val=img_array.flatten().tolist(),
        shape=[1, 3, 224, 224],
    )

    infer_request = services_pb2.ModelInferRequest(
        model_spec=services_pb2.ModelSpec(name="resnet"),
        inputs_tensor_contents=[tensor],
    )

    try:
        response = stub.ModelInfer(infer_request)
        print(f"Inference successful!")
        print(f"Output tensors: {len(response.outputs)}")
        if response.outputs:
            output_data = response.outputs[0].float_val
            top_indices = np.argsort(output_data)[::-1][:10]
            print(f"\nTop 10 predictions:")
            for i, idx in enumerate(top_indices, 1):
                print(f"  {i:2d}. Class {idx}: {output_data[idx]:.4f}")
    except grpc.RpcError as e:
        print(f"ModelInfer error: {e.code()}: {e.details()}")

    channel.close()

if __name__ == "__main__":
    test_grpc()
