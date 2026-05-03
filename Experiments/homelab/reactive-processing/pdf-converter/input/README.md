# Input Directory

Drop images here to be processed. The watcher monitors this directory for new files.

Supported formats: JPEG, PNG, AVIF, WebP, GIF, BMP, TIFF, ICO.

Each image will be resized to three scales (half, quarter, eighth) and written to the `output/` directory. Metadata is extracted and stored in MongoDB.
