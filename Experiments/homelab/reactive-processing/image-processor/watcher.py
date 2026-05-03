#!/usr/bin/env python3
"""
Reactive image processor: watches a directory for new images,
resizes them to scaled variants, and extracts metadata to MongoDB.
"""

import os
import sys
import time
import hashlib
from datetime import datetime, timezone
from pathlib import Path

from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from PIL import Image
from pymongo import MongoClient

# Configuration
MONGO_URI = os.getenv("MONGO_URI", "mongodb://mongodb:27017")
MONGO_DB = os.getenv("MONGO_DB", "image_metadata")
MONGO_COLLECTION = os.getenv("MONGO_COLLECTION", "images")
INPUT_DIR = os.getenv("INPUT_DIR", "/input")
OUTPUT_DIR = os.getenv("OUTPUT_DIR", "/output")
RESIZE_SCALES = [float(s) for s in os.getenv("RESIZE_SCALES", "0.5,0.25,0.125").split(",")]

SUFFIX_MAP = {0.5: "_half", 0.25: "_quarter", 0.125: "_eighth"}

# Supported image extensions
IMAGE_EXTENSIONS = {
    ".jpg", ".jpeg", ".png", ".webp", ".gif",
    ".bmp", ".tiff", ".tif", ".ico", ".avif",
}

# Track processed files by hash to avoid reprocessing
processed_hashes = set()


def get_file_hash(filepath):
    """Get MD5 hash of file for deduplication."""
    h = hashlib.md5()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def extract_metadata(image_path, pil_image):
    """Extract all metadata from an image file. Returns a dict with dynamic keys."""
    meta = {
        "filename": os.path.basename(image_path),
        "file_size_bytes": os.path.getsize(image_path),
        "dimensions": pil_image.size,  # (width, height)
        "mode": pil_image.mode,  # RGB, RGBA, L, etc.
        "format": pil_image.format,
        "processed_at": datetime.now(timezone.utc).isoformat(),
    }

    # EXIF data
    exif = pil_image.getexif()
    if exif:
        exif_dict = {}
        for tag_id, value in exif.items():
            tag_name = exif.get_description(tag_id) if hasattr(exif, 'get_description') else str(tag_id)
            try:
                # Convert complex types to strings for MongoDB storage
                exif_dict[tag_name] = str(value)
            except Exception:
                exif_dict[tag_name] = repr(value)
        if exif_dict:
            meta["exif"] = exif_dict

    return meta


def resize_image(input_path, output_path, scale):
    """Resize image to scale factor (e.g., 0.5 = half size)."""
    with Image.open(input_path) as img:
        new_size = (int(img.width * scale), int(img.height * scale))
        resized = img.resize(new_size, Image.LANCZOS)

        # Handle format-specific save options
        suffix = SUFFIX_MAP.get(scale, f"_x{scale}")
        save_kwargs = {}

        if img.format in ("JPEG", "JPG"):
            save_kwargs["quality"] = 85
        elif img.format == "PNG":
            save_kwargs["optimize"] = True

        resized.save(output_path, **save_kwargs)
        return output_path


def store_metadata(metadata):
    """Store metadata in MongoDB."""
    try:
        client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=5000)
        client.admin.command("ping")
        db = client[MONGO_DB]
        collection = db[MONGO_COLLECTION]
        result = collection.insert_one(metadata)
        return str(result.inserted_id)
    except Exception as e:
        print(f"[ERROR] MongoDB error: {e}")
        return None


def process_image(filepath):
    """Process a single image: resize + extract metadata."""
    filepath = Path(filepath)

    # Skip non-image files
    if filepath.suffix.lower() not in IMAGE_EXTENSIONS:
        return

    # Skip temporary/partial writes (watchdog fires on file creation before write completes)
    try:
        file_size = filepath.stat().st_size
    except OSError:
        return

    # Debounce: wait a moment to ensure file write is complete
    time.sleep(1)

    # Check for duplicate processing
    try:
        file_hash = get_file_hash(str(filepath))
    except (OSError, IOError):
        return

    if file_hash in processed_hashes:
        return
    processed_hashes.add(file_hash)

    print(f"\n[PROCESSING] {filepath.name}")

    # Resize
    stem = filepath.stem
    output_dir = Path(OUTPUT_DIR)
    output_dir.mkdir(parents=True, exist_ok=True)

    try:
        with Image.open(str(filepath)) as img:
            for scale in RESIZE_SCALES:
                suffix = SUFFIX_MAP.get(scale, f"_x{scale}")
                out_path = output_dir / f"{stem}{suffix}{filepath.suffix}"
                resize_image(str(filepath), str(out_path), scale)
                print(f"  Resized: {out_path.name} ({img.width}x{img.height} -> {int(img.width*scale)}x{int(img.height*scale)})")
    except Exception as e:
        print(f"  [ERROR] Resize failed: {e}")
        return

    # Extract metadata
    try:
        with Image.open(str(filepath)) as img:
            meta = extract_metadata(str(filepath), img)
            inserted_id = store_metadata(meta)
            if inserted_id:
                print(f"  Metadata stored in MongoDB (doc id: {inserted_id})")
                # Print a sample of extracted fields
                for key in ("dimensions", "format", "mode", "file_size_bytes"):
                    if key in meta:
                        print(f"    {key}: {meta[key]}")
                if "exif" in meta:
                    print(f"    exif tags: {len(meta['exif'])} fields extracted")
            else:
                print("  [WARN] Metadata not stored (MongoDB connection issue)")
    except Exception as e:
        print(f"  [ERROR] Metadata extraction failed: {e}")


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
    print("Image Processor Watcher")
    print("=" * 60)
    print(f"  Input directory:  {INPUT_DIR}")
    print(f"  Output directory: {OUTPUT_DIR}")
    print(f"  Resize scales:    {RESIZE_SCALES}")
    print(f"  MongoDB:          {MONGO_URI}")
    print(f"  DB/Collection:    {MONGO_DB}/{MONGO_COLLECTION}")
    print(f"  Supported formats: {', '.join(sorted(IMAGE_EXTENSIONS))}")
    print("=" * 60)

    # Verify input directory exists
    input_path = Path(INPUT_DIR)
    if not input_path.exists():
        print(f"[ERROR] Input directory does not exist: {INPUT_DIR}")
        print("Creating it...")
        input_path.mkdir(parents=True, exist_ok=True)

    # Verify output directory exists
    output_path = Path(OUTPUT_DIR)
    output_path.mkdir(parents=True, exist_ok=True)

    # Connect to MongoDB on startup
    try:
        client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=5000)
        client.admin.command("ping")
        print("MongoDB connection: OK")
    except Exception as e:
        print(f"MongoDB connection: FAILED ({e})")
        print("Watcher will retry on each file event.")

    # Start watching
    handler = WatcherHandler()
    observer = Observer()
    observer.schedule(handler, INPUT_DIR, recursive=False)
    observer.start()

    print(f"\nWatching for new images in {INPUT_DIR}...")
    print("Drop images into the input directory to process them.\n")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nShutting down watcher...")
        observer.stop()

    observer.join()
    print("Watcher stopped.")


if __name__ == "__main__":
    main()
