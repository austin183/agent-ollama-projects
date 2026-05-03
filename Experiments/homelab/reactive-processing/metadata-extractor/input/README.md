# Input Directory

Drop media files here (images, audio, video) to trigger automatic metadata extraction.

## Supported Formats

**Images:** JPG, JPEG, PNG, GIF, BMP, TIFF, WEBP, HEIC, HEIF
**Audio:** MP3, WAV, FLAC, AAC, OGG, M4A, WMA, OPUS
**Video:** MP4, AVI, MKV, MOV, WMV, FLV, WEBM, M4V, TS

## What Happens

1. Watcher detects new file via inotify
2. Metadata is extracted (EXIF for images, tags for audio, stream info for video)
3. Data is stored in PostgreSQL
4. Original file is removed after processing

## Tips

- Files are processed in order of arrival
- Duplicate files (same MD5 hash) are skipped
- Files still being written are skipped (2-second debounce)
