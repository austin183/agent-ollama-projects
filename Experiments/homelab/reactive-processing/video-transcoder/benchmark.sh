#!/bin/bash
# Benchmark: CPU x264 vs CUDA NVENC vs Full CUDA pipeline
set -euo pipefail

INPUT="${1:-/input/test.mp4}"
OUTDIR="${2:-/output/benchmarks}"

if [ ! -f "$INPUT" ]; then
    echo "Usage: $0 <input-video> [output-dir]"
    echo "Error: Input file not found: $INPUT"
    exit 1
fi

mkdir -p "$OUTDIR"
BASENAME=$(basename "$INPUT" | sed 's/\.[^.]*$//')

echo "=============================================="
echo "Video Transcoding Benchmark"
echo "=============================================="
echo "Input: $INPUT"
echo "Output: $OUTDIR"
echo ""

# Get input info
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$INPUT" 2>/dev/null)
SIZE=$(stat -c%s "$INPUT")
echo "Duration: ${DUR}s"
echo "Size: $(( SIZE / 1024 / 1024 )) MB"
echo ""

# --- Test 1: CPU x264 baseline ---
echo "----------------------------------------------"
echo "[1/3] CPU x264 (preset medium, CRF 23)"
echo "----------------------------------------------"
OUT1="$OUTDIR/${BASENAME}_cpu_x264.mkv"
START=$(date +%s%N)
ffmpeg -y -hide_banner -loglevel info \
    -i "$INPUT" \
    -c:v libx264 -preset medium -crf 23 \
    -c:a copy -f matroska \
    "$OUTDIR/${BASENAME}_cpu_x264.mkv" 2>&1 | tee "$OUTDIR/log_cpu.txt"
END=$(date +%s%N)
ELAPSED_CPU=$(( (END - START) / 1000000 ))
OUTSIZE1=$(stat -c%s "$OUTDIR/${BASENAME}_cpu_x264.mkv")
FPS_CPU=$(grep -oP 'fps=\K[0-9.]+' "$OUTDIR/log_cpu.txt" | tail -1 || echo "N/A")
SPEED_CPU=$(grep -oP 'speed=\K[0-9.]+' "$OUTDIR/log_cpu.txt" | tail -1 || echo "N/A")
echo ""
echo "  Time: ${ELAPSED_CPU}ms"
echo "  Output: $(( OUTSIZE1 / 1024 / 1024 )) MB"
echo "  Encode FPS: $FPS_CPU"
echo "  Speed: ${SPEED_CPU}x"
echo ""

# --- Test 2: CUDA NVENC (CPU decode, GPU encode) ---
echo "----------------------------------------------"
echo "[2/3] CUDA NVENC (CPU decode, GPU encode)"
echo "----------------------------------------------"
START=$(date +%s%N)
ffmpeg -y -hide_banner -loglevel info \
    -i "$INPUT" \
    -c:v h264_nvenc -preset p4 -cq 23 \
    -c:a copy -f matroska \
    "$OUTDIR/${BASENAME}_nvenc.mkv" 2>&1 | tee "$OUTDIR/log_nvenc.txt"
END=$(date +%s%N)
ELAPSED_NVENC=$(( (END - START) / 1000000 ))
OUTSIZE2=$(stat -c%s "$OUTDIR/${BASENAME}_nvenc.mkv")
FPS_NVENC=$(grep -oP 'fps=\K[0-9.]+' "$OUTDIR/log_nvenc.txt" | tail -1 || echo "N/A")
SPEED_NVENC=$(grep -oP 'speed=\K[0-9.]+' "$OUTDIR/log_nvenc.txt" | tail -1 || echo "N/A")
GPU_UTIL=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null || echo "N/A")
echo ""
echo "  Time: ${ELAPSED_NVENC}ms"
echo "  Output: $(( OUTSIZE2 / 1024 / 1024 )) MB"
echo "  Encode FPS: $FPS_NVENC"
echo "  Speed: ${SPEED_NVENC}x"
echo "  GPU util (post): ${GPU_UTIL}%"
echo ""

# --- Test 3: Full CUDA (GPU decode + GPU encode) ---
echo "----------------------------------------------"
echo "[3/3] Full CUDA (GPU decode + GPU encode)"
echo "----------------------------------------------"
START=$(date +%s%N)
ffmpeg -y -hide_banner -loglevel info \
    -hwaccel cuda -c:v h264_cuvid \
    -i "$INPUT" \
    -c:v h264_nvenc -preset p4 -cq 23 \
    -c:a copy -f matroska \
    "$OUTDIR/${BASENAME}_fullcuda.mkv" 2>&1 | tee "$OUTDIR/log_fullcuda.txt"
END=$(date +%s%N)
ELAPSED_FULL=$(( (END - START) / 1000000 ))
OUTSIZE3=$(stat -c%s "$OUTDIR/${BASENAME}_fullcuda.mkv")
FPS_FULL=$(grep -oP 'fps=\K[0-9.]+' "$OUTDIR/log_fullcuda.txt" | tail -1 || echo "N/A")
SPEED_FULL=$(grep -oP 'speed=\K[0-9.]+' "$OUTDIR/log_fullcuda.txt" | tail -1 || echo "N/A")
GPU_UTIL2=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null || echo "N/A")
echo ""
echo "  Time: ${ELAPSED_FULL}ms"
echo "  Output: $(( OUTSIZE3 / 1024 / 1024 )) MB"
echo "  Encode FPS: $FPS_FULL"
echo "  Speed: ${SPEED_FULL}x"
echo "  GPU util (post): ${GPU_UTIL2}%"
echo ""

# --- Summary ---
echo "=============================================="
echo "SUMMARY"
echo "=============================================="
printf "%-25s %10s %10s %10s %8s\n" "Method" "Time(ms)" "Size(MB)" "FPS" "Speed"
printf "%-25s %10s %10s %10s %8s\n" "-------------------------" "----------" "----------" "----------" "--------"
printf "%-25s %10d %10d %10s %8s\n" "CPU x264" "$ELAPSED_CPU" "$(( OUTSIZE1 / 1024 / 1024 ))" "$FPS_CPU" "${SPEED_CPU}x"
printf "%-25s %10d %10d %10s %8s\n" "CUDA NVENC" "$ELAPSED_NVENC" "$(( OUTSIZE2 / 1024 / 1024 ))" "$FPS_NVENC" "${SPEED_NVENC}x"
printf "%-25s %10d %10d %10s %8s\n" "Full CUDA" "$ELAPSED_FULL" "$(( OUTSIZE3 / 1024 / 1024 ))" "$FPS_FULL" "${SPEED_FULL}x"
echo ""

# GPU memory
nvidia-smi --query-gpu=name,memory.total,memory.used,utilization.gpu --format=csv 2>/dev/null || true
echo ""
echo "Results saved to: $OUTDIR"
