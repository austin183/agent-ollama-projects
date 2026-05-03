#!/usr/bin/env python3
"""
Reactive video transcoder: watches input/ for new video files,
transcodes them with FFmpeg (NVENC), and logs job metadata to PostgreSQL.
"""

import os
import sys
import time
import json
import subprocess
import hashlib
from datetime import datetime, timezone
from pathlib import Path

import psycopg2
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# Configuration
PG_HOST = os.getenv("PG_HOST", "postgresql")
PG_PORT = os.getenv("PG_PORT", "5432")
PG_USER = os.getenv("PG_USER", "transcoder")
PG_PASSWORD = os.getenv("PG_PASSWORD", "transcoderlab123")
PG_DB = os.getenv("PG_DB", "transcoder")
INPUT_DIR = os.getenv("INPUT_DIR", "/input")
OUTPUT_DIR = os.getenv("OUTPUT_DIR", "/output")
ENCODER = os.getenv("ENCODER", "nvenc")
CRF = os.getenv("CRF", "23")
PRESET = os.getenv("PRESET", "p4")

VIDEO_EXTENSIONS = {
    ".mkv", ".mp4", ".avi", ".mov", ".wmv", ".flv",
    ".webm", ".m4v", ".mts", ".m2ts", ".ts",
}

processed_hashes = set()


def get_db_conn():
    return psycopg2.connect(
        host=PG_HOST, port=PG_PORT,
        user=PG_USER, password=PG_PASSWORD, dbname=PG_DB
    )


def init_db():
    schema_path = Path("/app/schema.sql")
    if not schema_path.exists():
        print("[WARN] schema.sql not found, skipping DB init")
        return
    with open(schema_path) as f:
        sql = f.read()
    conn = get_db_conn()
    try:
        cur = conn.cursor()
        cur.execute(sql)
        conn.commit()
        print("Database schema initialized")
    finally:
        conn.close()


def get_file_hash(filepath):
    h = hashlib.md5()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def probe_video(filepath):
    """Extract video metadata with ffprobe."""
    cmd = [
        "ffprobe", "-v", "error",
        "-select_streams", "v:0",
        "-show_entries", "stream=codec_name,width,height,r_frame_rate,duration",
        "-show_entries", "format=duration,size",
        "-of", "json",
        filepath,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        print(f"  [ERROR] ffprobe failed: {result.stderr}")
        return None
    data = json.loads(result.stdout)
    stream = data.get("streams", [{}])[0]
    fmt = data.get("format", {})
    # Parse frame rate
    fps_str = stream.get("r_frame_rate", "0/1")
    num, den = fps_str.split("/") if "/" in fps_str else (fps_str, "1")
    fps = int(num) / max(int(den), 1)
    return {
        "codec": stream.get("codec_name"),
        "width": int(stream.get("width", 0)),
        "height": int(stream.get("height", 0)),
        "duration": float(fmt.get("duration", stream.get("duration", 0))),
        "file_size": int(fmt.get("size", 0)),
        "fps": fps,
    }


def build_ffmpeg_cmd(input_path, output_path):
    """Build FFmpeg command with NVENC encoding."""
    codec = "h264_nvenc" if ENCODER == "nvenc" else "hevc_nvenc"
    cmd = [
        "ffmpeg", "-y",
        "-hwaccel", "cuda",
        "-i", str(input_path),
        "-c:v", codec,
        "-preset", PRESET,
        "-cq", CRF,
        "-c:a", "copy",
        str(output_path),
    ]
    return cmd


def parse_ffmpeg_output(stderr):
    """Parse FFmpeg output for encode FPS and speed."""
    encode_fps = 0.0
    speed_x = 0.0
    for line in stderr.split("\n"):
        # Look for "time=... fps=... speed=..."
        if "fps=" in line and "speed=" in line:
            try:
                parts = line.split()
                for i, part in enumerate(parts):
                    if part == "fps=" and i + 1 < len(parts):
                        fps_str = parts[i + 1].replace(",", ".")
                        encode_fps = float(fps_str)
                    if part == "speed=" and i + 1 < len(parts):
                        speed_str = parts[i + 1].replace(",", ".").replace("x", "")
                        speed_x = float(speed_str)
            except (ValueError, IndexError):
                pass
    return encode_fps, speed_x


def get_gpu_stats():
    """Query NVIDIA GPU stats via nvidia-smi."""
    try:
        result = subprocess.run(
            [
                "nvidia-smi", "--query-gpu",
                "utilization.gpu,memory.used",
                "--format=csv,noheader,nounits"
            ],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            parts = result.stdout.strip().split(",")
            return float(parts[0]), float(parts[1])
    except Exception:
        pass
    return None, None


def process_video(filepath):
    """Process a single video file: transcode + log metadata."""
    filepath = Path(filepath)

    if filepath.suffix.lower() not in VIDEO_EXTENSIONS:
        return

    # Debounce for partial writes
    time.sleep(2)

    try:
        file_hash = get_file_hash(str(filepath))
    except (OSError, IOError):
        return

    if file_hash in processed_hashes:
        return
    processed_hashes.add(file_hash)

    print(f"\n{'=' * 60}")
    print(f"[PROCESSING] {filepath.name}")

    # Probe input
    info = probe_video(str(filepath))
    if not info:
        print("  [ERROR] Failed to probe video")
        return

    print(f"  Input: {info['width']}x{info['height']} {info['codec']} "
          f"{info['duration']:.1f}s {info['file_size'] / 1024 / 1024:.1f}MB")

    # Record pending job
    try:
        conn = get_db_conn()
        cur = conn.cursor()
        cur.execute(
            """INSERT INTO transcode_jobs
               (filename, file_size_bytes, input_codec, input_width,
                input_height, input_duration_secs, status, created_at)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s) RETURNING id""",
            (
                filepath.name, info["file_size"], info["codec"],
                info["width"], info["height"], info["duration"],
                "running", datetime.now(timezone.utc),
            )
        )
        job_id = cur.fetchone()[0]
        cur.execute("UPDATE transcode_jobs SET started_at = %s WHERE id = %s",
                    (datetime.now(timezone.utc), job_id))
        conn.commit()
    except Exception as e:
        print(f"  [ERROR] DB error: {e}")
        return

    # Build output path
    stem = filepath.stem
    output_dir = Path(OUTPUT_DIR)
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / f"{stem}_transcoded.mkv"

    # Run FFmpeg
    cmd = build_ffmpeg_cmd(filepath, output_path)
    cmd_str = " ".join(cmd)
    print(f"  Command: {cmd_str}")

    start_time = time.monotonic()
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
        elapsed = time.monotonic() - start_time

        if result.returncode != 0:
            print(f"  [ERROR] FFmpeg failed (exit {result.returncode})")
            print(f"  stderr: {result.stderr[-500:]}")
            conn = get_db_conn()
            cur = conn.cursor()
            cur.execute(
                "UPDATE transcode_jobs SET status = %s, error_message = %s, "
                "completed_at = %s WHERE id = %s",
                ("failed", result.stderr[-1000:], datetime.now(timezone.utc), job_id)
            )
            conn.commit()
            conn.close()
            return

        encode_fps, speed_x = parse_ffmpeg_output(result.stderr)
        gpu_util, gpu_mem = get_gpu_stats()
        out_size = output_path.stat().st_size if output_path.exists() else 0

        print(f"  Output: {out_size / 1024 / 1024:.1f}MB "
              f"({encode_fps:.0f} fps, {speed_x:.1f}x realtime)")
        if gpu_util is not None:
            print(f"  GPU: {gpu_util:.0f}% util, {gpu_mem:.0f}MB used")

        # Update job record
        conn = get_db_conn()
        cur = conn.cursor()
        cur.execute(
            """UPDATE transcode_jobs SET
               output_codec = %s, preset = %s, crf = %s, command = %s,
               output_file = %s, output_size_bytes = %s,
               encode_fps = %s, speed_x = %s,
               gpu_util_pct = %s, gpu_mem_used_mb = %s,
               status = %s, completed_at = %s
               WHERE id = %s""",
            (
                ENCODER, PRESET, int(CRF), cmd_str,
                str(output_path.name), out_size,
                encode_fps, speed_x,
                gpu_util, gpu_mem,
                "completed", datetime.now(timezone.utc),
                job_id,
            )
        )
        conn.commit()
        conn.close()
        print(f"  Job {job_id}: completed in {elapsed:.1f}s")

    except subprocess.TimeoutExpired:
        print("  [ERROR] FFmpeg timed out")
        conn = get_db_conn()
        cur = conn.cursor()
        cur.execute(
            "UPDATE transcode_jobs SET status = %s, error_message = %s, "
            "completed_at = %s WHERE id = %s",
            ("failed", "timeout", datetime.now(timezone.utc), job_id)
        )
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"  [ERROR] {e}")
        try:
            conn = get_db_conn()
            cur = conn.cursor()
            cur.execute(
                "UPDATE transcode_jobs SET status = %s, error_message = %s, "
                "completed_at = %s WHERE id = %s",
                ("failed", str(e), datetime.now(timezone.utc), job_id)
            )
            conn.commit()
            conn.close()
        except Exception:
            pass


class VideoWatcherHandler(FileSystemEventHandler):
    def on_created(self, event):
        if not event.is_directory:
            process_video(event.src_path)

    def on_modified(self, event):
        if not event.is_directory:
            process_video(event.src_path)


def wait_for_db(max_retries=30):
    """Wait for PostgreSQL to be ready."""
    for i in range(max_retries):
        try:
            conn = get_db_conn()
            conn.close()
            return True
        except Exception:
            if i < max_retries - 1:
                time.sleep(2)
    return False


def main():
    print("=" * 60)
    print("Video Transcoder Watcher (NVENC)")
    print("=" * 60)
    print(f"  Input:    {INPUT_DIR}")
    print(f"  Output:   {OUTPUT_DIR}")
    print(f"  Encoder:  {ENCODER} (preset={PRESET}, cq={CRF})")
    print(f"  Database: {PG_HOST}:{PG_PORT}/{PG_DB}")
    print(f"  Formats:  {', '.join(sorted(VIDEO_EXTENSIONS))}")
    print("=" * 60)

    # Check FFmpeg NVENC support
    try:
        result = subprocess.run(
            ["ffmpeg", "-encoders"], capture_output=True, text=True, timeout=10
        )
        has_nvenc = "h264_nvenc" in (result.stdout + result.stderr)
        has_hevc = "hevc_nvenc" in (result.stdout + result.stderr)
        print(f"  NVENC H.264:  {'YES' if has_nvenc else 'NO'}")
        print(f"  NVENC HEVC:   {'YES' if has_hevc else 'NO'}")
    except Exception as e:
        print(f"  [WARN] Could not check NVENC: {e}")

    # Check GPU
    try:
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu", "name",
             "--format=csv,noheader"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            print(f"  GPU: {result.stdout.strip()}")
    except Exception:
        print("  GPU: nvidia-smi not available")

    # Wait for database
    print("Waiting for PostgreSQL...")
    if not wait_for_db():
        print("[ERROR] PostgreSQL not available, exiting")
        sys.exit(1)
    print("PostgreSQL: connected")

    # Initialize schema
    init_db()

    # Ensure directories
    Path(INPUT_DIR).mkdir(parents=True, exist_ok=True)
    Path(OUTPUT_DIR).mkdir(parents=True, exist_ok=True)

    # Start watcher
    handler = VideoWatcherHandler()
    observer = Observer()
    observer.schedule(handler, INPUT_DIR, recursive=False)
    observer.start()

    print(f"\nWatching for new videos in {INPUT_DIR}...")
    print("Drop video files into the input directory to transcode them.\n")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nShutting down...")
        observer.stop()
    observer.join()


if __name__ == "__main__":
    main()
