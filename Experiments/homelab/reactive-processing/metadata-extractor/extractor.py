import os
import sys
import time
import hashlib
import json
import subprocess
from datetime import datetime, timezone

from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from PIL import Image
from PIL.ExifTags import TAGS, GPSTAGS
import mutagen
import psycopg2
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT


INPUT_DIR = os.environ.get("INPUT_DIR", "/input")
OUTPUT_DIR = os.environ.get("OUTPUT_DIR", "/output")

DB_CONFIG = {
    "host": os.environ.get("DB_HOST", "postgresql"),
    "port": int(os.environ.get("DB_PORT", 5432)),
    "dbname": os.environ.get("DB_NAME", "metadata"),
    "user": os.environ.get("DB_USER", "metadata_user"),
    "password": os.environ.get("DB_PASSWORD", "metadata_pass_123"),
}

SUPPORTED_IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".tif", ".webp", ".heic", ".heif"}
SUPPORTED_AUDIO_EXTENSIONS = {".mp3", ".wav", ".flac", ".aac", ".ogg", ".m4a", ".wma", ".opus"}
SUPPORTED_VIDEO_EXTENSIONS = {".mp4", ".avi", ".mkv", ".mov", ".wmv", ".flv", ".webm", ".m4v", ".ts"}

PROCESSING_DELAY = 2.0
recently_modified = {}


def get_file_hash(filepath):
    hasher = hashlib.md5()
    try:
        with open(filepath, "rb") as f:
            for chunk in iter(lambda: f.read(8192), b""):
                hasher.update(chunk)
        return hasher.hexdigest()
    except (IOError, OSError) as e:
        print(f"[ERROR] Failed to hash file {filepath}: {e}")
        return None


def connect_db_with_retry(max_retries=30, retry_delay=2):
    for attempt in range(max_retries):
        try:
            conn = psycopg2.connect(**DB_CONFIG)
            conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
            print(f"[INFO] Connected to PostgreSQL on attempt {attempt + 1}")
            return conn
        except psycopg2.OperationalError as e:
            print(f"[WARN] Database not ready (attempt {attempt + 1}/{max_retries}): {e}")
            if attempt < max_retries - 1:
                time.sleep(retry_delay)
    print("[ERROR] Could not connect to PostgreSQL after multiple retries")
    sys.exit(1)


def ensure_table(conn):
    with open("/app/schema.sql", "r") as f:
        schema_sql = f.read()
    with conn.cursor() as cur:
        cur.execute(schema_sql)
    print("[INFO] Database schema verified/created")


def extract_exif_tags(exif):
    result = {}
    try:
        for tag_id, value in exif.get_fields().items():
            tag_name = TAGS.get(tag_id, str(tag_id))
            try:
                if tag_name.upper() in ("GPSINFO", "INTEROPINFO"):
                    continue
                encoded = json.dumps(value, default=str)
                result[tag_name] = json.loads(encoded)
            except (TypeError, ValueError):
                result[tag_name] = str(value)
    except (KeyError, ValueError, TypeError) as e:
        print(f"[WARN] Error reading EXIF tags: {e}")
    return result


def extract_gps(exif):
    try:
        gps_tags = exif.get_ifd(0x8825)
        if not gps_tags:
            return None, None
        lat_ref = gps_tags.get(1)
        lat = gps_tags.get(2)
        lon_ref = gps_tags.get(3)
        lon = gps_tags.get(4)
        if lat and lon:
            def to_degrees(val_list):
                return sum(v / float(d) for v, d in zip(val_list, [60, 3600]))
            lat_deg = to_degrees(lat)
            lon_deg = to_degrees(lon)
            if lat_ref == "S":
                lat_deg = -lat_deg
            if lon_ref == "W":
                lon_deg = -lon_deg
            return lat_deg, lon_deg
    except (KeyError, TypeError, ValueError, IndexError):
        pass
    return None, None


def extract_image_metadata(filepath):
    meta = {}
    try:
        with Image.open(filepath) as img:
            meta["width"] = img.size[0]
            meta["height"] = img.size[1]
            meta["format"] = img.format or "UNKNOWN"
            meta["mode"] = img.mode
            meta["color_space"] = img.mode

            exif_data = img.getexif()
            if exif_data:
                raw_exif = extract_exif_tags(exif_data)
                meta["exif"] = raw_exif

                lat, lon = extract_gps(exif_data)
                meta["gps_latitude"] = lat
                meta["gps_longitude"] = lon

                make = raw_exif.get("Make")
                if make:
                    meta["camera_make"] = make.strip()
                model = raw_exif.get("ExifImageTag", raw_exif.get("Model"))
                if model:
                    meta["camera_model"] = str(model).strip()
                exposure = raw_exif.get("ExposureTime")
                if exposure:
                    meta["exposure_time"] = str(exposure)
                aperture = raw_exif.get("FNumber")
                if aperture:
                    meta["aperture"] = str(aperture)
                focal = raw_exif.get("FocalLength")
                if focal:
                    meta["focal_length"] = str(focal)
                iso = raw_exif.get("ISOSpeedRatings")
                if iso:
                    meta["iso"] = int(iso) if isinstance(iso, (int, float)) else None
                wb = raw_exif.get("WhiteBalance")
                if wb:
                    meta["white_balance"] = str(wb)
                software = raw_exif.get("Software")
                if software:
                    meta["software"] = str(software).strip()

                date_taken = raw_exif.get("DateTimeOriginal", raw_exif.get("DateTime"))
                if date_taken:
                    try:
                        meta["date_created"] = datetime.strptime(date_taken, "%Y:%m:%d %H:%M:%S").replace(tzinfo=timezone.utc)
                    except ValueError:
                        pass
    except Exception as e:
        print(f"[ERROR] Failed to extract image metadata from {filepath}: {e}")
    return meta


def extract_audio_metadata(filepath):
    meta = {}
    try:
        audio = mutagen.File(filepath)
        if not audio:
            return meta

        meta["duration_seconds"] = audio.info.length if audio.info else None
        meta["bitrate"] = audio.info.bitrate / 1000 if audio.info and audio.info.bitrate else None

        if audio.tags:
            for key, value in audio.tags.items():
                lower_key = key.lower()
                if "title" in lower_key:
                    meta["title"] = str(value)
                elif "artist" in lower_key:
                    meta["artist"] = str(value)
                elif "album" in lower_key:
                    meta["album"] = str(value)
                elif "genre" in lower_key:
                    meta["genre"] = str(value)
                elif "track" in lower_key:
                    try:
                        track_str = str(value).split("/")[0].strip()
                        meta["track_number"] = int(track_str)
                    except (ValueError, IndexError):
                        pass

        if hasattr(audio.info, "sample_rate"):
            meta["sample_rate"] = audio.info.sample_rate
        if hasattr(audio.info, "channels"):
            meta["channel_layout"] = "stereo" if audio.info.channels == 2 else "mono" if audio.info.channels == 1 else f"{audio.info.channels}ch"
        if hasattr(audio.info, "bitrate"):
            meta["bitrate"] = audio.info.bitrate / 1000

        meta["format"] = audio.info.asf.profile if hasattr(audio.info, "asf") else (audio.info.codec_full_name if hasattr(audio.info, "codec_full_name") else (audio.info.codec if hasattr(audio.info, "codec") else "UNKNOWN"))
    except Exception as e:
        print(f"[ERROR] Failed to extract audio metadata from {filepath}: {e}")
    return meta


def extract_video_metadata(filepath):
    meta = {}
    try:
        cmd = [
            "ffprobe",
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            filepath
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode != 0:
            print(f"[WARN] ffprobe failed for {filepath}: {result.stderr.strip()}")
            return meta

        info = json.loads(result.stdout)

        video_stream = None
        audio_stream = None
        for stream in info.get("streams", []):
            if stream.get("codec_type") == "video" and not video_stream:
                video_stream = stream
            elif stream.get("codec_type") == "audio" and not audio_stream:
                audio_stream = stream

        fmt = info.get("format", {})
        meta["duration_seconds"] = float(fmt.get("duration", 0))
        meta["bitrate"] = int(fmt.get("bit_rate", 0)) // 1000
        meta["format"] = fmt.get("format_name", fmt.get("format_long_name", "UNKNOWN"))

        if video_stream:
            meta["width"] = int(video_stream.get("width", 0))
            meta["height"] = int(video_stream.get("height", 0))
            meta["codec"] = video_stream.get("codec_name", "UNKNOWN")
            display_size = video_stream.get("display_aspect_ratio")
            if display_size:
                meta["display_aspect_ratio"] = display_size
            framerate = video_stream.get("r_frame_rate")
            if framerate and "/" in framerate:
                num, den = framerate.split("/")
                if int(den) > 0:
                    meta["frame_rate"] = float(num) / float(den)

        if audio_stream:
            if "sample_rate" in audio_stream:
                meta["sample_rate"] = int(audio_stream["sample_rate"])
            if "channels" in audio_stream:
                channels = int(audio_stream["channels"])
                meta["channel_layout"] = "stereo" if channels == 2 else "mono" if channels == 1 else f"{channels}ch"
            if "codec_name" in audio_stream:
                meta["audio_codec"] = audio_stream["codec_name"]

    except subprocess.TimeoutExpired:
        print(f"[ERROR] ffprobe timed out for {filepath}")
    except Exception as e:
        print(f"[ERROR] Failed to extract video metadata from {filepath}: {e}")
    return meta


def store_metadata(conn, metadata):
    sql = """
        INSERT INTO media_metadata
            (filename, file_path, file_type, file_size_bytes, duration_seconds,
             width, height, format, codec, bitrate, sample_rate, channel_layout,
             artist, album, title, track_number, genre, date_created,
             gps_latitude, gps_longitude, camera_make, camera_model,
             exposure_time, aperture, focal_length, iso, white_balance, software,
             all_metadata, file_hash)
        VALUES
            (%(filename)s, %(file_path)s, %(file_type)s, %(file_size_bytes)s, %(duration_seconds)s,
             %(width)s, %(height)s, %(format)s, %(codec)s, %(bitrate)s, %(sample_rate)s, %(channel_layout)s,
             %(artist)s, %(album)s, %(title)s, %(track_number)s, %(genre)s, %(date_created)s,
             %(gps_latitude)s, %(gps_longitude)s, %(camera_make)s, %(camera_model)s,
             %(exposure_time)s, %(aperture)s, %(focal_length)s, %(iso)s, %(white_balance)s, %(software)s,
             %(all_metadata)s, %(file_hash)s)
    """
    with conn.cursor() as cur:
        cur.execute(sql, metadata)
    print(f"[INFO] Stored metadata for: {metadata['filename']}")


def generate_thumbnail(image_path, output_dir):
    try:
        with Image.open(image_path) as img:
            img_copy = img.copy()
            img_copy.thumbnail((400, 400))
            base, ext = os.path.splitext(image_path)
            thumb_path = f"{base}_thumb{ext}"
            save_kwargs = {}
            if img.format == "JPEG":
                save_kwargs["quality"] = 85
            elif img.format == "PNG":
                save_kwargs["optimize"] = True
            elif img.format == "WEBP":
                save_kwargs["quality"] = 85
            img_copy.save(thumb_path, **save_kwargs)
            print(f"[INFO] Generated thumbnail: {thumb_path}")
            return thumb_path
    except Exception as e:
        print(f"[WARN] Failed to generate thumbnail for {image_path}: {e}")
        return None


def cleanup_file(filepath):
    try:
        os.remove(filepath)
        print(f"[INFO] Cleaned up: {filepath}")
    except Exception as e:
        print(f"[WARN] Failed to cleanup {filepath}: {e}")


def process_file(filepath):
    filename = os.path.basename(filepath)
    ext = os.path.splitext(filename)[1].lower()
    file_hash = get_file_hash(filepath)

    if file_hash:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM media_metadata WHERE file_hash = %s", (file_hash,))
            row = cur.fetchone()
            if row:
                print(f"[INFO] Duplicate file (hash {file_hash}), skipping: {filename}")
                return

    file_size = os.path.getsize(filepath)
    file_type = None
    if ext in SUPPORTED_IMAGE_EXTENSIONS:
        file_type = "image"
    elif ext in SUPPORTED_AUDIO_EXTENSIONS:
        file_type = "audio"
    elif ext in SUPPORTED_VIDEO_EXTENSIONS:
        file_type = "video"

    if not file_type:
        print(f"[INFO] Unsupported file type: {filename} (ext={ext})")
        return

    print(f"[INFO] Processing {file_type}: {filename}")
    metadata = {
        "filename": filename,
        "file_path": os.path.abspath(filepath),
        "file_type": file_type,
        "file_size_bytes": file_size,
        "duration_seconds": None,
        "width": None,
        "height": None,
        "format": None,
        "codec": None,
        "bitrate": None,
        "sample_rate": None,
        "channel_layout": None,
        "artist": None,
        "album": None,
        "title": None,
        "track_number": None,
        "genre": None,
        "date_created": None,
        "gps_latitude": None,
        "gps_longitude": None,
        "camera_make": None,
        "camera_model": None,
        "exposure_time": None,
        "aperture": None,
        "focal_length": None,
        "iso": None,
        "white_balance": None,
        "software": None,
        "file_hash": file_hash,
    }

    if file_type == "image":
        img_meta = extract_image_metadata(filepath)
        metadata.update(img_meta)
        thumb = generate_thumbnail(filepath, OUTPUT_DIR)
        if thumb:
            cleanup_file(thumb)
    elif file_type == "audio":
        audio_meta = extract_audio_metadata(filepath)
        metadata.update(audio_meta)
    elif file_type == "video":
        video_meta = extract_video_metadata(filepath)
        metadata.update(video_meta)

    metadata["all_metadata"] = json.dumps({
        "file_type": file_type,
        "file_size_bytes": file_size,
        "format": metadata.get("format"),
        "width": metadata.get("width"),
        "height": metadata.get("height"),
        "duration_seconds": metadata.get("duration_seconds"),
        "codec": metadata.get("codec"),
        "bitrate": metadata.get("bitrate"),
        "artist": metadata.get("artist"),
        "album": metadata.get("album"),
        "title": metadata.get("title"),
        "camera_make": metadata.get("camera_make"),
        "camera_model": metadata.get("camera_model"),
    }, default=str)

    store_metadata(conn, metadata)
    cleanup_file(filepath)


class MediaHandler(FileSystemEventHandler):
    def on_created(self, event):
        self._handle_event(event)

    def on_modified(self, event):
        self._handle_event(event)

    def _handle_event(self, event):
        if event.is_directory:
            return

        filepath = event.src_path
        if not os.path.isfile(filepath):
            return

        ext = os.path.splitext(filepath)[1].lower()
        all_extensions = SUPPORTED_IMAGE_EXTENSIONS | SUPPORTED_AUDIO_EXTENSIONS | SUPPORTED_VIDEO_EXTENSIONS
        if ext not in all_extensions:
            return

        now = time.time()
        last_modified = recently_modified.get(filepath, 0)
        if now - last_modified < PROCESSING_DELAY:
            return
        recently_modified[filepath] = now

        time.sleep(1)
        print(f"[INFO] Detected new file: {filepath}")
        try:
            process_file(filepath)
        except Exception as e:
            print(f"[ERROR] Failed to process {filepath}: {e}")


if __name__ == "__main__":
    os.makedirs(INPUT_DIR, exist_ok=True)
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print("[INFO] Media Metadata Extractor starting...")
    print(f"[INFO] Input directory: {INPUT_DIR}")
    print(f"[INFO] Output directory: {OUTPUT_DIR}")

    conn = connect_db_with_retry()
    ensure_table(conn)

    event_handler = MediaHandler()
    observer = Observer()
    observer.schedule(event_handler, INPUT_DIR, recursive=False)
    observer.start()
    print(f"[INFO] Watching {INPUT_DIR} for new media files...")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("[INFO] Shutting down...")
        observer.stop()
    observer.join()
