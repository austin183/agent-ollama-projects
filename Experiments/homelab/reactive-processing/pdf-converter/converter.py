#!/usr/bin/env python3
"""Watch input directory for PDF files and convert them to markdown and plain text."""

import os
import subprocess
import time
import sys
import shutil
import glob

INPUT_DIR = "/input"
OUTPUT_DIR = "/output"
PROCESSED_DIR = "/processed"
LOG_FILE = "/logs/converter.log"
STABLE_CHECK_INTERVAL = 0.5
STABLE_CHECKS_NEEDED = 6
STABLE_THRESHOLD = 0.15
PROCESSING_DELAY = 1.0
POLL_INTERVAL = 0.5
CONVERSION_TIMEOUT = 120
OCR_LANG = "eng"


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


def detect_pdf_type(filepath):
    try:
        result = subprocess.run(
            ["pdftotext", "-list", filepath],
            capture_output=True,
            text=True,
            timeout=10,
        )
        text_info = result.stdout.strip()
        if "extractable text" in text_info.lower() or "text" in text_info.lower():
            return "text"
        return "scanned"
    except Exception:
        log(f"  WARNING: Could not detect PDF type, defaulting to scanned")
        return "scanned"


def convert_text_pdf(source_path):
    basename = os.path.splitext(os.path.basename(source_path))[0]
    log(f"  Text-based PDF detected, converting with pandoc + pdftotext")

    md_success = False
    txt_success = False

    md_path = os.path.join(OUTPUT_DIR, f"{basename}.md")
    txt_path = os.path.join(OUTPUT_DIR, f"{basename}.txt")

    try:
        result = subprocess.run(
            ["pandoc", source_path, "-f", "pdf", "-t", "markdown", "-o", md_path],
            capture_output=True,
            text=True,
            timeout=CONVERSION_TIMEOUT,
        )
        if result.returncode == 0 and os.path.exists(md_path):
            size = os.path.getsize(md_path)
            log(f"  -> {os.path.basename(md_path)} ({size} bytes)")
            md_success = True
        else:
            log(f"  WARNING: pandoc failed for {basename}: {result.stderr.strip()[:200]}")
    except subprocess.TimeoutExpired:
        log(f"  ERROR: pandoc timed out for {basename}")
    except Exception as e:
        log(f"  ERROR: pandoc failed for {basename}: {e}")

    try:
        result = subprocess.run(
            ["pdftotext", source_path, txt_path],
            capture_output=True,
            text=True,
            timeout=CONVERSION_TIMEOUT,
        )
        if result.returncode == 0 and os.path.exists(txt_path):
            size = os.path.getsize(txt_path)
            log(f"  -> {os.path.basename(txt_path)} ({size} bytes)")
            txt_success = True
        else:
            log(f"  WARNING: pdftotext failed for {basename}: {result.stderr.strip()[:200]}")
    except subprocess.TimeoutExpired:
        log(f"  ERROR: pdftotext timed out for {basename}")
    except Exception as e:
        log(f"  ERROR: pdftotext failed for {basename}: {e}")

    return md_success or txt_success


def convert_scanned_pdf(source_path):
    basename = os.path.splitext(os.path.basename(source_path))[0]
    log(f"  Scanned PDF detected, converting with pdftoppm + tesseract OCR")

    temp_dir = f"/tmp/ocr_{basename}_{int(time.time())}"
    os.makedirs(temp_dir, exist_ok=True)

    try:
        result = subprocess.run(
            ["pdftoppm", "-png", source_path, os.path.join(temp_dir, "page")],
            capture_output=True,
            text=True,
            timeout=CONVERSION_TIMEOUT,
        )
        if result.returncode != 0:
            log(f"  ERROR: pdftoppm failed: {result.stderr.strip()}")
            return False

        images = sorted(glob.glob(os.path.join(temp_dir, "page-*.png")))
        if not images:
            log(f"  ERROR: No page images generated")
            return False

        log(f"  -> {len(images)} page(s) converted to images")

        all_texts = []
        for i, img in enumerate(images):
            page_num = i + 1
            log(f"  OCR processing page {page_num}/{len(images)}")
            result = subprocess.run(
                ["tesseract", img, os.path.join(temp_dir, f"page{page_num}"), "-l", OCR_LANG],
                capture_output=True,
                text=True,
                timeout=120,
            )
            txt_file = os.path.join(temp_dir, f"page{page_num}.txt")
            if os.path.exists(txt_file):
                with open(txt_file, "r") as f:
                    text = f.read().strip()
                if text:
                    all_texts.append(f"--- PAGE {page_num} ---\n{text}")

        if all_texts:
            md_path = os.path.join(OUTPUT_DIR, f"{basename}.md")
            with open(md_path, "w") as f:
                f.write("\n\n".join(all_texts))
            size = os.path.getsize(md_path)
            log(f"  -> {os.path.basename(md_path)} ({size} bytes)")
            return True
        else:
            log(f"  ERROR: OCR produced no text output")
            return False

    except subprocess.TimeoutExpired:
        log(f"  ERROR: OCR pipeline timed out for {basename}")
        return False
    except Exception as e:
        log(f"  ERROR: OCR pipeline failed: {e}")
        return False
    finally:
        try:
            shutil.rmtree(temp_dir, ignore_errors=True)
        except Exception:
            pass


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

            if not filename.lower().endswith(".pdf"):
                continue

            if not wait_for_file_stable(filepath):
                log(f"Skipping unstable file: {filename}")
                continue

            log(f"Processing: {filename}")
            basename = os.path.splitext(filename)[0]
            output_md = os.path.join(OUTPUT_DIR, f"{basename}.md")
            output_txt = os.path.join(OUTPUT_DIR, f"{basename}.txt")

            if os.path.exists(output_md) and os.path.exists(output_txt):
                log(f"  -> Skipping, output files already exist")
                try:
                    dest = os.path.join(PROCESSED_DIR, filename)
                    shutil.copy2(filepath, dest)
                    os.remove(filepath)
                except Exception as e:
                    log(f"  WARNING: Could not move source file: {e}")
                continue

            pdf_type = detect_pdf_type(filepath)
            if pdf_type == "text":
                success = convert_text_pdf(filepath)
            else:
                success = convert_scanned_pdf(filepath)

            if success:
                try:
                    dest = os.path.join(PROCESSED_DIR, filename)
                    shutil.copy2(filepath, dest)
                    os.remove(filepath)
                    log(f"  -> Moved source to processed/")
                except Exception as e:
                    log(f"  WARNING: Could not move source file: {e}")
            else:
                log(f"  ERROR: Conversion failed for {filename}")

            time.sleep(PROCESSING_DELAY)

    except Exception as e:
        log(f"ERROR in process_new_files: {e}")


def main():
    os.makedirs(INPUT_DIR, exist_ok=True)
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    os.makedirs(PROCESSED_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)

    log("=" * 60)
    log("PDF Converter started")
    log(f"Input:  {INPUT_DIR}")
    log(f"Output: {OUTPUT_DIR}")
    log(f"OCR Language: {OCR_LANG}")
    log("=" * 60)

    while True:
        try:
            process_new_files()
        except Exception as e:
            log(f"ERROR: {e}")
        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()
