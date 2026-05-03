# Document to PDF Converter

## Overview

A reactive file processing service that monitors an input directory and automatically converts dropped documents (DOCX, ODT, XLSX, PPTX, etc.) to PDF using LibreOffice headless.

## Quick Start

```bash
cd reactive-processing/document-converter
podman compose build
podman compose up -d
```

## Services

| Service | Port | Purpose |
|---------|------|---------|
| doc-converter | None (internal) | Watches input/ directory, converts documents to PDF |
| test-client | None | Alpine container with volume mounts for testing |

## How It Works

### Architecture

```
User drops file  -->  /input  -->  Watcher (Python)  -->  LibreOffice  -->  /output (.pdf)
                                                                                |
                                                                       Source moved to  -->  /processed
```

**Data Flow:**
1. User drops a document (ODT, DOCX, XLSX, PPTX, etc.) into the `input/` directory
2. The Python watcher detects the new file and waits for it to stabilize (file write complete)
3. LibreOffice headless converts the file to PDF, outputting to `output/`
4. The source file is moved to `processed/` (copy + delete for cross-filesystem compatibility)
5. PDFs remain in `output/` for the user to retrieve

### Supported Formats

LibreOffice headless supports a wide range of input formats:
- **Documents:** DOCX, ODT, RTF, TXT, HTML, DOC
- **Spreadsheets:** XLSX, ODS, CSV, XLS
- **Presentations:** PPTX, ODP, PPT
- **Images:** PNG, JPG, TIFF (converted to single-page PDF)

## Verification

### Check containers are running

```bash
podman ps --filter name=homelab-doc-converter
```

Expected output:
```
CONTAINER ID  IMAGE                             COMMAND         STATUS
<id>          localhost/homelab/doc-converter   python3 ...     Up ...
<id>          docker.io/alpine:3.21             sleep 3600      Up ...
```

### Test conversion

```bash
# Drop a document into the input directory
cp /path/to/your-document.docx reactive-processing/document-converter/input/

# Wait ~5 seconds, then check output
sleep 5
ls -la reactive-processing/document-converter/output/
```

Expected output:
```
report.pdf  (PDF version of the document)
```

### Check logs

```bash
podman logs homelab-doc-converter | grep -E 'Converting|ERROR|Moved'
```

Expected output:
```
[2026-04-20 23:40:42] Converting: sample.docx
[2026-04-20 23:40:43]   -> sample.pdf (15183 bytes)
[2026-04-20 23:40:43]   -> Moved source to processed/
```

### Verify network connectivity

```bash
podman exec homelab-doc-converter-test ping -c 2 doc-converter
```

Expected output:
```
64 bytes from 10.x.x.x: seq=0 ttl=42 time=0.0xx ms
64 bytes from 10.x.x.x: seq=1 ttl=42 time=0.0xx ms
2 packets transmitted, 2 received, 0% packet loss
```

### Validate PDF output

```bash
file reactive-processing/document-converter/output/*.pdf
```

Expected output:
```
output/report.pdf: PDF document, version 1.7, N page(s)
```

## Directory Structure

```
document-converter/
├── docker-compose.yml    # Service definitions
├── Dockerfile            # Custom image build
├── converter.py          # Watcher + converter script
├── samples/              # Sample files for testing
├── input/                # Drop documents here
├── output/               # Converted PDFs appear here
├── processed/            # Original source files after conversion
└── logs/                 # Converter logs
```

## Common Pitfalls

### Cross-device link errors
`os.rename()` fails when source and destination are on different filesystems (separate bind mounts). The fix uses `shutil.copy2()` + `os.remove()` instead.

### LibreOffice desktop environment overhead
The `linuxserver/libreoffice` image includes a Wayland desktop (Selkies) for GUI access. This is unnecessary for headless conversion but adds ~80MB RAM overhead. A lighter custom image could be built but would require more setup.

### File stability detection
LibreOffice may fail if it reads a file while it's still being written. The watcher checks file size stability before converting (6 checks at 0.5s intervals, allowing 15% variance).

### Large files
Complex documents (heavy images, many pages) may take 10-30 seconds to convert. The conversion timeout is set to 120 seconds.

## Resource Usage

| Metric | Value | Budget |
|--------|-------|--------|
| RAM | ~81MB | ~400MB |
| Storage | ~400MB image | ~200MB + output |
| CPU | <1% idle, spikes during conversion | ~400MB RAM budget |

## Testing

```bash
# Drop a document into the input directory
cp /path/to/your-document.docx reactive-processing/document-converter/input/

# Wait ~5 seconds, then check output
sleep 5
ls -la reactive-processing/document-converter/output/

# Verify network connectivity
podman exec homelab-doc-converter-test ping -c 2 doc-converter

# Check logs
podman logs homelab-doc-converter | grep -E 'Converting|ERROR|Moved'

# Validate PDF output
file reactive-processing/document-converter/output/*.pdf
```

## Troubleshooting

- **Cross-device link errors**: `os.rename()` fails on separate bind mounts. The converter uses `shutil.copy2()` + `os.remove()` instead.
- **File re-processed continuously**: Source files are moved to `processed/` after conversion to prevent re-processing.
- **LibreOffice desktop overhead**: The `linuxserver/libreoffice` image includes a Wayland desktop (~80MB RAM). A custom image from `python:slim` + `libreoffice-core` would be lighter.
- **Large files**: Complex documents may take 10-30s. Conversion timeout is 120s.
- **File still being written**: The watcher checks file size stability (6 checks at 0.5s, 15% variance threshold) before converting.

## Cleanup

```bash
podman compose down -v
```
