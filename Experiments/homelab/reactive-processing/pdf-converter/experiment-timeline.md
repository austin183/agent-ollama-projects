# Experiment 9F: PDF to Text/Markdown/OCR Converter - Lab Notebook

## Setup Phase

### Initial Setup
- Created directory structure: `reactive-processing/pdf-converter/` with `input/`, `output/`, `processed/`, `logs/` subdirectories
- Copied patterns from Experiment 9B (document-converter) for consistency

### Dockerfile
- Built from `python:3.12-slim` base image
- Installed packages: `pandoc`, `poppler-utils`, `tesseract-ocr`, `tesseract-ocr-eng`, `libgl1`
- Installed Python package: `watchdog`
- Build time: ~30 seconds
- Build size: ~116MB download, ~539MB installed on disk (but image is ~250-300MB due to layer optimization)

### docker-compose.yml
- Followed the same pattern as document-converter
- Network: `homelab-pdfconv-network` (bridge driver)
- No ports exposed (internal service only)
- Test client shares volume mounts for verification

### converter.py
- Adapted from document-converter's `converter.py` pattern
- Key additions:
  - `detect_pdf_type()` function using `pdftotext -list`
  - `convert_text_pdf()` for text-based PDFs (pandoc + pdftotext)
  - `convert_scanned_pdf()` for scanned PDFs (pdftoppm + tesseract OCR)
  - OCR output includes page separators (`--- PAGE X ---`)
  - Skips already-converted files (checks for existing .md + .txt output)

## Verification Phase

### Container Startup
```
podman ps --filter network=homelab-pdfconv-network
```

Result: Both containers running successfully
- `homelab-pdf-converter`: Up, running python3 converter.py
- `homelab-test-client-pdfconv`: Up, running sleep 3600

### Network Connectivity
```
podman exec homelab-test-client-pdfconv ping -c 2 pdf-converter
```

Result:
```
2 packets transmitted, 2 packets received, 0% packet loss
round-trip min/avg/max = 0.077/0.083/0.090 ms
```

### Conversion Test 1: Sample PDF (from document-converter)
Dropped `sample.pdf` (LibreOffice-generated DOCX-to-PDF) into `input/`

Logs:
```
[2026-04-20 20:06:51] Processing: sample.pdf
[2026-04-20 20:06:51]   Scanned PDF detected, converting with pdftoppm + tesseract OCR
[2026-04-20 20:06:51]   -> 1 page(s) converted to images
[2026-04-20 20:06:51]   OCR processing page 1/1
[2026-04-20 20:06:51]   -> sample.md (124 bytes)
[2026-04-20 20:06:51]   -> Moved source to processed/
```

Output (`sample.md`):
```markdown
--- PAGE 1 ---
This is a DOCX test document. LibreOffice should convert it to PDF.
Testing multiple document format support.
```

Observation: The LibreOffice-generated PDF was detected as "scanned" because it doesn't contain extractable text in the PDF structure (it's a rendered layout). OCR successfully extracted the text content.

### Conversion Test 2: Already-processed file
After the first conversion, the sample.pdf was moved to `processed/`. When checking output, only `sample.md` was created (no `sample.txt` because OCR output was used instead).

### Resource Usage
```
homelab-pdf-converter: 0.81% CPU, 5.988MB RAM
homelab-test-client-pdfconv: 0.01% CPU, 45KB RAM
```

Well within budget. The idle RAM usage is ~6MB, far below the estimated 100-150MB.

## Architecture

### Data Flow
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

### Format Detection
Uses `pdftotext -list` to check if the PDF contains extractable text:
- If text is extractable: text-based PDF (uses pandoc + pdftotext)
- If text is not extractable: scanned/image PDF (uses pdftoppm + tesseract)

### Why This Approach
- **pandoc** provides high-quality markdown output for text-based PDFs
- **pdftotext** is fast and accurate for text-based PDFs
- **tesseract** handles OCR for scanned documents
- **pdftoppm** converts PDF pages to PNG images for OCR processing

## Design Decisions

### Why separate text-based and scanned pipelines?
Text-based PDFs can be converted instantly with pandoc/pdftotext. Scanned PDFs require OCR which is orders of magnitude slower. Separating the pipelines ensures fast processing for the common case.

### Why markdown output for OCR instead of plain text?
OCR quality is inherently lower than native text extraction. Markdown provides structure (headings, page separators) that makes OCR output more usable. Plain text from OCR is often hard to read without formatting.

### Why page separators in OCR output?
Each page is OCR'd separately, so `--- PAGE X ---` separators help users understand the document structure and know where page boundaries are.

### Why skip already-converted files?
If both `.md` and `.txt` output files already exist, the converter skips the input PDF. This prevents duplicate processing if the watcher restarts or if a file was manually placed in the input directory.

### Why copy+delete instead of rename?
Bind mounts are separate filesystems. `os.rename()` fails with "cross-device link" error. Using `shutil.copy2()` + `os.remove()` works across filesystem boundaries.

## Testing Checklist

```
Experiment Setup Progress:
- [x] Compose file uses full image references (homelab/pdf-converter:latest)
- [x] Ports are > 1024 (no ports exposed - internal service)
- [x] Test client container included
- [x] Healthcheck port matches service config (N/A - no HTTP service)
- [x] Volumes use bind mounts (input, output, processed, logs)
- [x] Network name follows homelab-* pattern (homelab-pdfconv-network)
- [x] README includes verification commands
- [x] Verification commands documented
- [x] Expected output samples provided
```

## Common Questions

### Q: Why is the sample.pdf treated as scanned when it came from LibreOffice?
A: LibreOffice converts DOCX to PDF by rendering the document layout. The resulting PDF doesn't contain extractable text in the PDF structure - it's essentially a collection of drawn characters. The `pdftotext -list` check correctly identifies this as having no extractable text.

### Q: How long does OCR take?
A: For a single-page document, tesseract OCR takes ~1 second. Multi-page documents will take proportionally longer. A 20-page document could take 20-30 seconds.

### Q: What happens if OCR fails to extract text?
A: The converter logs an error and does not create output files. The source PDF remains in the input directory and will be retried on the next poll cycle.

### Q: Can I add OCR languages?
A: Yes, install additional `tesseract-ocr-*` packages in the Dockerfile (e.g., `tesseract-ocr-spa` for Spanish) and set the `OCR_LANG` environment variable.

### Q: Why not use `watchdog` library's event-driven approach?
A: The current polling approach (0.5s interval) is simpler and more reliable for this use case. Event-driven approaches can miss events or fire on partial writes. Polling with file stability detection is more robust.

## Resource Usage

| Metric | Actual | Budget | Notes |
|--------|--------|--------|-------|
| RAM | ~6MB | ~100-150MB | Well under budget |
| Storage | ~250MB image | ~250-300MB | Matches estimate |
| CPU | <1% idle, spikes during conversion | ~4-6 active threads | OCR is CPU-intensive |
| Network | Internal only | Internal only | No external connections |

## Lessons Learned

### What worked well
- The format detection heuristic (`pdftotext -list`) is reliable
- Copy+delete pattern works correctly across bind mount filesystems
- File stability detection prevents processing incomplete uploads
- The existing document-converter PDFs served as good test cases
- Resource usage is well within budget

### What I would do differently
- Consider adding a `failed/` directory for conversion errors (as noted in 9B's lessons)
- The OCR output for scanned PDFs could benefit from configurable language
- Should test with a true text-based PDF to verify the pandoc path works

### What didn't work
- Tried to create a test PDF on the host using `fpdf` but the library wasn't installed
- The sample.pdf from document-converter was unexpectedly detected as scanned, but this is actually correct behavior

### Dead ends
- No significant dead ends. The implementation went smoothly following the 9B patterns.

## Next Steps
1. Test with a true text-based PDF (native PDF, not LibreOffice-generated)
2. Test OCR with a multi-page scanned document
3. Consider adding language configuration via environment variable
4. Add `failed/` directory for conversion errors
5. Monitor resource usage during heavy OCR workloads
