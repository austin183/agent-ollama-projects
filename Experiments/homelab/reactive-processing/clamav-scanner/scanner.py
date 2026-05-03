#!/usr/bin/env python3
"""
ClamAV virus scanner: watches a directory for new files,
scans them with ClamAV daemon via Unix socket, and moves
clean files to output or infected files to quarantine.
"""

import os
import sys
import time
import shutil
import socket
import tempfile
from pathlib import Path
from datetime import datetime, timezone

from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

SCAN_DIR = os.getenv("SCAN_DIR", "/scan")
QUARANTINE_DIR = os.getenv("QUARANTINE_DIR", "/quarantine")
OUTPUT_DIR = os.getenv("OUTPUT_DIR", "/output")

# File size limit for scanning (100MB)
MAX_SCAN_SIZE = 100 * 1024 * 1024

# ClamAV daemon socket
CLAMD_SOCKET = "/var/run/clamav/clamd.ctl"


def clamd_command(command, timeout=30):
    """Send a command to clamd via Unix socket and return the response."""
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        sock.connect(CLAMD_SOCKET)
        sock.sendall((command + "\n").encode())

        response = b""
        while True:
            data = sock.recv(4096)
            if not data:
                break
            response += data
            if b"OK" in response or b"FOUND" in response or b"ERROR" in response:
                if b"\n" in response:
                    break

        sock.close()
        return response.decode().strip()
    except FileNotFoundError:
        return None
    except (socket.error, socket.timeout, ConnectionRefusedError) as e:
        print(f"  [DEBUG] Socket error: {e}")
        return None


def is_clamav_ready():
    """Check if ClamAV daemon is ready by sending a PING command."""
    try:
        result = clamd_command("PING")
        return result is not None and "PONG" in result
    except Exception:
        return False


def scan_file(filepath):
    """Scan a single file using clamd via Unix socket.

    Returns:
        tuple: (is_infected: bool, virus_name: str | None, error: str | None)
    """
    filepath = str(filepath)

    try:
        file_size = os.path.getsize(filepath)
    except OSError as e:
        return False, None, f"Cannot stat file: {e}"

    if file_size > MAX_SCAN_SIZE:
        return False, None, f"File too large ({file_size} bytes), skipping"

    try:
        output = clamd_command(f"SCAN {filepath}")
    except Exception as e:
        return False, None, f"Scan error: {e}"

    if output is None:
        return False, None, "Cannot connect to ClamAV daemon"

    if "FOUND" in output:
        virus_name = extract_virus_name(output, filepath)
        return True, virus_name, None
    elif "OK" in output:
        return False, None, None
    else:
        return False, None, f"Unexpected response: {output}"


def extract_virus_name(output, filepath):
    """Extract virus name from clamd scan response."""
    filepath_str = str(filepath)
    for line in output.split("\n"):
        if filepath_str in line and "FOUND" in line:
            # Format: "/path/to/file: VirusName FOUND"
            parts = line.split(":")
            if len(parts) >= 2:
                virus_part = parts[-1].replace("FOUND", "").strip()
                if virus_part:
                    return virus_part
    return "Unknown"


def quarantine_file(filepath):
    """Move an infected file to the quarantine directory."""
    filepath = Path(filepath)
    quarantine_path = Path(QUARANTINE_DIR) / f"{filepath.name}.{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}.infected"

    try:
        shutil.move(str(filepath), str(quarantine_path))
        return str(quarantine_path)
    except Exception as e:
        print(f"  [ERROR] Failed to quarantine {filepath.name}: {e}")
        return None


def copy_to_output(filepath):
    """Copy a clean file to the output directory."""
    filepath = Path(filepath)
    timestamp = datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')
    output_path = Path(OUTPUT_DIR) / f"{timestamp}_{filepath.name}"

    try:
        shutil.copy2(str(filepath), str(output_path))
        return str(output_path)
    except Exception as e:
        print(f"  [ERROR] Failed to copy to output: {e}")
        return None


def process_file(filepath):
    """Process a single file: wait for write to complete, scan, then route."""
    filepath = Path(filepath)

    # Skip temporary files (watchdog may fire before write completes)
    if filepath.name.startswith(".") or filepath.name.endswith(".tmp") or filepath.name.endswith(".part"):
        return

    # Wait for file write to complete (debounce)
    time.sleep(2)

    # Verify file still exists and get stable size
    try:
        if not filepath.exists():
            return
        size_before = filepath.stat().st_size
        time.sleep(1)
        if not filepath.exists():
            return
        size_after = filepath.stat().st_size
        if size_before != size_after:
            print(f"  [INFO] File still changing, skipping: {filepath.name}")
            return
    except OSError:
        return

    # Copy to temp location for scanning (input dir may be read-only)
    try:
        with tempfile.NamedTemporaryFile(dir="/tmp", prefix=f"scan_{filepath.name}_", delete=False) as tmp:
            tmp.write(filepath.read_bytes())
            tmp_path = tmp.name
    except Exception as e:
        print(f"  [ERROR] Failed to copy file for scanning: {e}")
        return

    print(f"\n[SCANNING] {filepath.name} ({filepath.stat().st_size} bytes)")

    is_infected, virus_name, error = scan_file(tmp_path)

    # Clean up temp file
    try:
        os.unlink(tmp_path)
    except OSError:
        pass

    if error:
        print(f"  [ERROR] Scan error: {error}")
        return

    if is_infected:
        print(f"  [ALERT] VIRUS DETECTED: {virus_name}")
        # Write infected content to quarantine
        try:
            quarantine_path = Path(QUARANTINE_DIR) / f"{filepath.name}.{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}.infected"
            quarantine_path.write_bytes(filepath.read_bytes())
            print(f"  [QUARANTINE] Saved to: {quarantine_path}")
        except Exception as e:
            print(f"  [ERROR] Failed to quarantine: {e}")
    else:
        print(f"  [CLEAN] No threats detected")
        output_path = copy_to_output(tmp_path if os.path.exists(tmp_path) else filepath)
        if output_path:
            print(f"  [OUTPUT] Saved to: {output_path}")


class ScanHandler(FileSystemEventHandler):
    """Handle filesystem events in the scan directory."""

    def on_created(self, event):
        if not event.is_directory:
            process_file(event.src_path)

    def on_modified(self, event):
        if not event.is_directory:
            process_file(event.src_path)


def main():
    print("=" * 60)
    print("ClamAV Virus Scanner")
    print("=" * 60)
    print(f"  Scan directory:    {SCAN_DIR}")
    print(f"  Output dir:        {OUTPUT_DIR}")
    print(f"  Quarantine dir:    {QUARANTINE_DIR}")
    print(f"  Max scan size:     {MAX_SCAN_SIZE / (1024*1024):.0f}MB")
    print("=" * 60)

    # Verify directories exist
    scan_path = Path(SCAN_DIR)
    scan_path.mkdir(parents=True, exist_ok=True)

    output_path = Path(OUTPUT_DIR)
    output_path.mkdir(parents=True, exist_ok=True)

    quarantine_path = Path(QUARANTINE_DIR)
    quarantine_path.mkdir(parents=True, exist_ok=True)

    # Wait for ClamAV daemon to be ready
    print("\n[STARTUP] Waiting for ClamAV daemon...")
    retries = 30
    while not is_clamav_ready() and retries > 0:
        print(f"  Waiting... ({retries} retries left)")
        time.sleep(2)
        retries -= 1

    if not is_clamav_ready():
        print("[ERROR] ClamAV daemon did not become ready. Check logs.")
        print("  podman logs homelab-clamav-scanner")
        sys.exit(1)

    print("[STARTUP] ClamAV daemon is ready.\n")
    print(f"Watching for new files in {SCAN_DIR}...\n")
    print("Drop files into the scan directory to scan them.\n")

    # Start watching
    handler = ScanHandler()
    observer = Observer()
    observer.schedule(handler, SCAN_DIR, recursive=False)
    observer.start()

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nShutting down scanner...")
        observer.stop()

    observer.join()
    print("Scanner stopped.")


if __name__ == "__main__":
    main()
