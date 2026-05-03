#!/usr/bin/env python3
"""Watch input directory and convert dropped documents to PDF using LibreOffice."""

import os
import subprocess
import time
import sys
import shutil

INPUT_DIR = "/input"
OUTPUT_DIR = "/output"
PROCESSED_DIR = "/processed"
LOG_FILE = "/logs/converter.log"
STABLE_CHECK_INTERVAL = 0.5
STABLE_CHECKS_NEEDED = 6
STABLE_THRESHOLD = 0.15
PROCESSING_DELAY = 1.0
POLL_INTERVAL = 0.5


def log(message):
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{timestamp}] {message}\n"
    print(line, end="", flush=True)
    try:
        with open(LOG_FILE, "a") as f:
            f.write(line)
    except Exception:
        pass


def is_file_stable(filepath):
    try:
        size1 = os.path.getsize(filepath)
        time.sleep(STABLE_CHECK_INTERVAL)
        size2 = os.path.getsize(filepath)
        if abs(size1 - size2) / max(size1, 1) < STABLE_THRESHOLD:
            return True
    except Exception:
        pass
    return False


def wait_for_file_stable(filepath, timeout=30):
    start = time.time()
    while time.time() - start < timeout:
        try:
            if os.path.exists(filepath) and os.path.isfile(filepath):
                if is_file_stable(filepath):
                    return True
        except Exception:
            pass
        time.sleep(0.3)
    return False


def convert_to_pdf(source_path):
    log(f"Converting: {os.path.basename(source_path)}")

    cmd = [
        "libreoffice",
        "--headless",
        "--convert-to", "pdf",
        source_path,
        "--outdir", OUTPUT_DIR,
    ]

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=120,
        )

        if result.returncode != 0:
            log(f"ERROR: LibreOffice failed for {os.path.basename(source_path)}")
            log(f"  stderr: {result.stderr.strip()}")
            return False

        basename = os.path.splitext(os.path.basename(source_path))[0]
        pdf_path = os.path.join(OUTPUT_DIR, f"{basename}.pdf")

        if os.path.exists(pdf_path):
            size = os.path.getsize(pdf_path)
            log(f"  -> {os.path.basename(pdf_path)} ({size} bytes)")
            try:
                dest = os.path.join(PROCESSED_DIR, os.path.basename(source_path))
                shutil.copy2(source_path, dest)
                os.remove(source_path)
                log(f"  -> Moved source to processed/")
            except Exception as e:
                log(f"  WARNING: Could not move source file: {e}")
            return True
        else:
            log(f"  WARNING: PDF not found at expected path: {pdf_path}")
            available = os.listdir(OUTPUT_DIR) if os.path.exists(OUTPUT_DIR) else []
            if available:
                pdf_path = os.path.join(OUTPUT_DIR, available[-1])
                log(f"  -> Using latest file: {os.path.basename(pdf_path)}")
                return True
            log(f"  ERROR: No output files found in {OUTPUT_DIR}")
            return False

    except subprocess.TimeoutExpired:
        log(f"  ERROR: Conversion timed out for {os.path.basename(source_path)}")
        return False
    except Exception as e:
        log(f"  ERROR: {e}")
        return False


def process_new_files():
    try:
        if not os.path.exists(INPUT_DIR):
            log(f"ERROR: Input directory does not exist: {INPUT_DIR}")
            return

        files = sorted(os.listdir(INPUT_DIR))
        for filename in files:
            filepath = os.path.join(INPUT_DIR, filename)

            if not os.path.isfile(filepath):
                continue

            if filename.lower().endswith(".pdf"):
                continue

            if not wait_for_file_stable(filepath):
                log(f"Skipping unstable file: {filename}")
                continue

            convert_to_pdf(filepath)
            time.sleep(PROCESSING_DELAY)

    except Exception as e:
        log(f"ERROR in process_new_files: {e}")


def main():
    os.makedirs(INPUT_DIR, exist_ok=True)
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    os.makedirs(PROCESSED_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)

    log("=" * 60)
    log("Document Converter started")
    log(f"Input:  {INPUT_DIR}")
    log(f"Output: {OUTPUT_DIR}")
    log("=" * 60)

    while True:
        try:
            process_new_files()
        except Exception as e:
            log(f"ERROR: {e}")
        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()
