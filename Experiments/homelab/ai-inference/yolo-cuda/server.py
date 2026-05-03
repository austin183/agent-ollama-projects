#!/usr/bin/env python3
"""
YOLO CUDA Server: FastAPI server that runs YOLOv8n object detection
on NVIDIA GPU using ultralytics with CUDA backend.
"""

import os
import base64
import time
import io
from contextlib import asynccontextmanager

import numpy as np
from PIL import Image
from fastapi import FastAPI, UploadFile, File, HTTPException
from pydantic import BaseModel


MODEL_SIZE = os.getenv("MODEL_SIZE", "nano")
MODEL_MAP = {
    "nano": "yolov8n.pt",
    "small": "yolov8s.pt",
    "medium": "yolov8m.pt",
}
MODEL_NAME = MODEL_MAP.get(MODEL_SIZE, "yolov8n.pt")


@asynccontextmanager
async def lifespan(app: FastAPI):
    global model
    print(f"Loading {MODEL_NAME} on CUDA...")
    from ultralytics import YOLO
    model = YOLO(MODEL_NAME)
    model.to("cuda")
    print(f"Model loaded on CUDA: {MODEL_NAME}")
    yield
    del model


app = FastAPI(title="YOLO CUDA Detection", lifespan=lifespan)


class DetectionResult(BaseModel):
    class_id: int
    class_name: str
    confidence: float
    bbox: list  # [x1, y1, x2, y2]


class InferenceResponse(BaseModel):
    image_width: int
    image_height: int
    inference_latency_ms: float
    detections: list[DetectionResult]


@app.get("/health")
async def health():
    import torch
    return {
        "status": "ok",
        "model": MODEL_NAME,
        "cuda_available": torch.cuda.is_available(),
        "cuda_device": torch.cuda.get_device_name(0) if torch.cuda.is_available() else "N/A",
    }


@app.post("/detect", response_model=InferenceResponse)
async def detect(file: UploadFile = File(...)):
    contents = await file.read()
    img = Image.open(io.BytesIO(contents)).convert("RGB")
    orig_width, orig_height = img.size

    start = time.time()
    results = model(img, verbose=False)
    latency_ms = (time.time() - start) * 1000

    result = results[0]
    detections = []

    for box in result.boxes:
        cls_id = int(box.cls[0])
        cls_name = result.names[cls_id]
        conf = float(box.conf[0])
        xyxy = box.xyxy[0].cpu().numpy().astype(int).tolist()

        detections.append(DetectionResult(
            class_id=cls_id,
            class_name=cls_name,
            confidence=round(conf, 4),
            bbox=xyxy,
        ))

    detections.sort(key=lambda d: d.confidence, reverse=True)

    return InferenceResponse(
        image_width=orig_width,
        image_height=orig_height,
        inference_latency_ms=round(latency_ms, 2),
        detections=detections,
    )


@app.post("/detect-base64", response_model=InferenceResponse)
async def detect_base64(data: dict):
    import base64 as b64
    img_data = b64.b64decode(data["image"])
    img = Image.open(io.BytesIO(img_data)).convert("RGB")
    orig_width, orig_height = img.size

    start = time.time()
    results = model(img, verbose=False)
    latency_ms = (time.time() - start) * 1000

    result = results[0]
    detections = []

    for box in result.boxes:
        cls_id = int(box.cls[0])
        cls_name = result.names[cls_id]
        conf = float(box.conf[0])
        xyxy = box.xyxy[0].cpu().numpy().astype(int).tolist()

        detections.append(DetectionResult(
            class_id=cls_id,
            class_name=cls_name,
            confidence=round(conf, 4),
            bbox=xyxy,
        ))

    detections.sort(key=lambda d: d.confidence, reverse=True)

    return InferenceResponse(
        image_width=orig_width,
        image_height=orig_height,
        inference_latency_ms=round(latency_ms, 2),
        detections=detections,
    )
