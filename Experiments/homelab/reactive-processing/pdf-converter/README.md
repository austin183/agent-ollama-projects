# PDF Converter

## Overview

Reactive file processing service that monitors an input directory for PDF files and automatically converts them to markdown and plain text. Scanned/image PDFs receive OCR processing via Tesseract.

## Quick Start

```bash
cd reactive-processing/pdf-converter
podman compose up -d
```

## Services

| Service | Port | Purpose |
|---------|------|---------|
| pdf-converter | None (file-based) | Watches `input/` for PDFs, converts to `.md` + `.txt` in `output/` |
| test-client | None | Alpine container with shared volumes for testing |

## How It Works

This experiment implements a reactive file processing service that monitors an input directory for PDF files and automatically converts them to markdown and plain text formats. Scanned/image PDFs receive OCR processing via Tesseract.

### Architecture

```
User drops PDF  -->  /input  -->  Watcher (Python)  -->  Format Detection
                                                                     |
                                                      +--------------+--------------+
                                                      |                             |
                                                      ▼                             ▼
                                                Text-based PDF            Scanned/Image PDF
                                                      |                             |
                                                      ▼                             ▼
                                               pandoc -> .md              pdftoppm -> images
                                               pdftotext -> .txt                    |
                                                                                  tesseract -> text
                                                      +------------------------+
                                                      |
                                                      ▼
                                               /output (markdown + text)
                                               /processed (original PDF)
```

**Data Flow:**
1. User drops a PDF into the `input/` directory
2. The Python watcher detects the new file and waits for it to stabilize (file write complete)
3. The watcher detects if the PDF is text-based or scanned using `pdftotext -list`
4. Text-based PDFs are converted using `pandoc` (markdown) and `pdftotext` (plain text)
5. Scanned PDFs are converted using `pdftoppm` (pages to images) then `tesseract` (OCR)
6. The source PDF is moved to `processed/` (copy + delete for cross-filesystem compatibility)
7. Converted files remain in `output/` for the user to retrieve

### Format Detection

The converter uses `pdftotext -list` to check if a PDF contains extractable text:
- **Text-based PDFs** (most documents): Fast conversion with pandoc + pdftotext
- **Scanned/Image PDFs** (photos of documents): OCR pipeline with pdftoppm + tesseract

### Supported Output

| PDF Type | Markdown (.md) | Plain Text (.txt) |
|----------|---------------|-------------------|
| Text-based | Yes (via pandoc) | Yes (via pdftotext) |
| Scanned | Yes (via OCR) | No (OCR quality too low) |

## Verification

### Check containers are running

```bash
podman ps --filter name=homelab-pdf-converter
```

Expected output:
```
CONTAINER ID  IMAGE                                      COMMAND         STATUS
<id>          localhost/homelab/pdf-converter:latest     python3 ...     Up ...
<id>          docker.io/library/alpine:3.21             sleep 3600      Up ...
```

### Test conversion with a PDF file

```bash
# Drop any PDF into the input directory
cp /path/to/your-document.pdf input/

# Wait ~5 seconds, then check output
sleep 5
ls -la output/
```

Expected output:
```
<your-document>.md  (markdown version of the document)
<your-document>.txt (plain text version of the document)
```

### Check logs

### Check logs

```bash
podman logs homelab-pdf-converter | grep -E 'Processing|Converting|ERROR|Moved|page'
```

Expected output:
```
[2026-04-20 10:00:00] Processing: your-document.pdf
[2026-04-20 10:00:01] Text-based PDF detected, converting with pandoc + pdftotext
[2026-04-20 10:00:02]   -> your-document.md (15234 bytes)
[2026-04-20 10:00:02]   -> your-document.txt (12456 bytes)
[2026-04-20 10:00:02]   -> Moved source to processed/
```

### Verify network connectivity

```bash
podman exec homelab-pdf-converter-test ping -c 2 pdf-converter
```

Expected output:
```
64 bytes from 10.x.x.x: seq=0 ttl=42 time=0.0xx ms
64 bytes from 10.x.x.x: seq=1 ttl=42 time=0.0xx ms
2 packets transmitted, 2 received, 0% packet loss
```

### Validate output format

```bash
# Check markdown output
head -20 reactive-processing/pdf-converter/output/*.md

# Check text output
head -20 reactive-processing/pdf-converter/output/*.txt

# Verify processed originals
ls -la reactive-processing/pdf-converter/processed/
```

## Directory Structure

```
pdf-converter/
├── docker-compose.yml    # Service definitions
├── Dockerfile            # Custom image build
├── converter.py          # Watcher + converter script
├── input/                # Drop PDFs here
├── output/               # Converted .md + .txt files appear here
├── processed/            # Original PDFs after conversion
└── logs/                 # Converter logs
```

## Common Pitfalls

### OCR is slow for multi-page documents
Tesseract OCR processes each page sequentially. A 20-page scanned document may take 2-5 minutes. The conversion timeout is set to 120 seconds per step.

### pandoc PDF support requires poppler
The `pandoc -f pdf` filter depends on poppler utilities (pdftocairo). Ensure `poppler-utils` is installed in the Docker image.

### Cross-device link errors
`os.rename()` fails when source and destination are on different filesystems (separate bind mounts). The fix uses `shutil.copy2()` + `os.remove()` instead, matching the pattern from experiment 9B.

### File stability detection
The watcher checks file size stability before converting (6 checks at 0.5s intervals, allowing 15% variance) to prevent reading incomplete file downloads.

### Skips already-converted files
If both `.md` and `.txt` output files already exist in the output directory, the converter skips the input PDF to avoid duplicate processing.

## Resource Usage

| Metric | Estimate | Notes |
|--------|----------|-------|
| RAM | ~100-150MB | python:3.12-slim + tools |
| Storage | ~250MB image | Base + pandoc + poppler + tesseract |
| CPU | <1% idle, spikes during conversion | OCR is CPU-intensive |
| Network | Internal only | No external connections |

## Cleanup

```bash
podman compose down -v
```
