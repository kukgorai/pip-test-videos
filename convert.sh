#!/bin/bash
set -euo pipefail

# PIP Test Media Converter
# Usage: ./convert.sh <url-or-file> <WIDTHxHEIGHT>
# Examples:
#   ./convert.sh https://example.com/photo.jpg 1080x2400
#   ./convert.sh https://example.com/cat.gif 480x800
#   ./convert.sh /path/to/video.mp4 1080x2400

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
PAGES_BASE="https://kukgorai.github.io/pip-test-videos"
TMP_DIR="/tmp/pip-convert-$$"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

usage() {
  echo "Usage: $0 <url-or-file> <WIDTHxHEIGHT>"
  echo ""
  echo "  url-or-file  URL to fetch or local file path"
  echo "  WIDTHxHEIGHT Target resolution (e.g., 1080x2400)"
  echo ""
  echo "Output: <type>/<WxH>/<file>"
  echo "  video → video/1080x2400/stream.m3u8"
  echo "  image → image/1080x2400/image.jpg"
  echo "  gif   → gif/1080x2400/image.gif"
  exit 1
}

# --- Parse args ---
[[ $# -lt 2 ]] && usage

INPUT="$1"
RESOLUTION="$2"

WIDTH="${RESOLUTION%%x*}"
HEIGHT="${RESOLUTION##*x}"

if [[ -z "$WIDTH" || -z "$HEIGHT" ]]; then
  echo "Error: Invalid resolution format. Use WIDTHxHEIGHT (e.g., 1080x2400)"
  exit 1
fi

mkdir -p "$TMP_DIR"

# --- Fetch if URL ---
if [[ "$INPUT" =~ ^https?:// ]]; then
  # Extract extension from URL (strip query params)
  URL_PATH="${INPUT%%\?*}"
  EXT="${URL_PATH##*.}"
  EXT=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')
  INPUT_FILE="$TMP_DIR/input.$EXT"
  echo "Downloading: $INPUT"
  curl -L -s -o "$INPUT_FILE" "$INPUT"
else
  if [[ ! -f "$INPUT" ]]; then
    echo "Error: File not found: $INPUT"
    exit 1
  fi
  INPUT_FILE="$INPUT"
  EXT="${INPUT##*.}"
  EXT=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')
fi

# --- Detect media type ---
case "$EXT" in
  mp4|mov|webm|mkv|avi)
    MEDIA_TYPE="video"
    ;;
  gif)
    MEDIA_TYPE="gif"
    ;;
  jpg|jpeg|png|webp|bmp|tiff)
    MEDIA_TYPE="image"
    ;;
  *)
    # Fallback: use file command
    MIME=$(file --mime-type -b "$INPUT_FILE")
    case "$MIME" in
      video/*) MEDIA_TYPE="video" ;;
      image/gif) MEDIA_TYPE="gif" ;;
      image/*) MEDIA_TYPE="image" ;;
      *) echo "Error: Cannot detect media type for extension '$EXT' (mime: $MIME)"; exit 1 ;;
    esac
    ;;
esac

echo "Detected: $MEDIA_TYPE (${WIDTH}x${HEIGHT})"

# --- Output directory: <type>/<WxH>/ ---
OUT_DIR="$REPO_DIR/${MEDIA_TYPE}/${RESOLUTION}"
mkdir -p "$OUT_DIR"

# --- Convert ---
case "$MEDIA_TYPE" in
  video)
    echo "Converting video to HLS..."
    ffmpeg -y -i "$INPUT_FILE" \
      -vf "scale=${WIDTH}:${HEIGHT}" \
      -c:v libx264 -c:a aac \
      -f hls -hls_time 4 -hls_playlist_type vod \
      -hls_segment_filename "$OUT_DIR/segment_%03d.ts" \
      "$OUT_DIR/stream.m3u8" 2>&1 | tail -3
    OUT_FILE="stream.m3u8"
    ;;
  image)
    echo "Converting image..."
    OUT_EXT="jpg"
    [[ "$EXT" == "png" ]] && OUT_EXT="png"
    ffmpeg -y -i "$INPUT_FILE" \
      -vf "scale=${WIDTH}:${HEIGHT}" \
      "$OUT_DIR/image.$OUT_EXT" 2>&1 | tail -3
    OUT_FILE="image.$OUT_EXT"
    ;;
  gif)
    echo "Converting GIF..."
    ffmpeg -y -i "$INPUT_FILE" \
      -vf "scale=${WIDTH}:${HEIGHT}" \
      -loop 0 \
      "$OUT_DIR/image.gif" 2>&1 | tail -3
    OUT_FILE="image.gif"
    ;;
esac

echo ""
echo "Output: $OUT_DIR/$OUT_FILE"

# --- Regenerate README.md ---
generate_readme() {
  local readme="$REPO_DIR/README.md"

  echo "# PIP Test Media URLs" > "$readme"
  echo "" >> "$readme"

  # Video section
  local video_files
  video_files=$(find "$REPO_DIR/video" -name "stream.m3u8" 2>/dev/null | sort)
  if [[ -n "$video_files" ]]; then
    echo "## Video (HLS)" >> "$readme"
    echo "" >> "$readme"
    echo "| Resolution | URL |" >> "$readme"
    echo "|------------|-----|" >> "$readme"
    while IFS= read -r f; do
      local res
      res=$(echo "$f" | sed "s|$REPO_DIR/video/||" | sed 's|/stream.m3u8||')
      echo "| ${res} | ${PAGES_BASE}/video/${res}/stream.m3u8 |" >> "$readme"
    done <<< "$video_files"
    echo "" >> "$readme"
  fi

  # MP4 section
  local mp4_files
  mp4_files=$(find "$REPO_DIR/mp4" -name "video.mp4" 2>/dev/null | sort)
  if [[ -n "$mp4_files" ]]; then
    echo "## Video (MP4)" >> "$readme"
    echo "" >> "$readme"
    echo "| Resolution | URL |" >> "$readme"
    echo "|------------|-----|" >> "$readme"
    while IFS= read -r f; do
      local res
      res=$(echo "$f" | sed "s|$REPO_DIR/mp4/||" | sed 's|/video.mp4||')
      echo "| ${res} | ${PAGES_BASE}/mp4/${res}/video.mp4 |" >> "$readme"
    done <<< "$mp4_files"
    echo "" >> "$readme"
  fi

  # Image section
  local image_files
  image_files=$(find "$REPO_DIR/image" -type f \( -name "image.jpg" -o -name "image.png" \) 2>/dev/null | sort)
  if [[ -n "$image_files" ]]; then
    echo "## Image" >> "$readme"
    echo "" >> "$readme"
    echo "| Resolution | URL |" >> "$readme"
    echo "|------------|-----|" >> "$readme"
    while IFS= read -r f; do
      local res filename
      filename=$(basename "$f")
      res=$(echo "$f" | sed "s|$REPO_DIR/image/||" | sed "s|/${filename}||")
      echo "| ${res} | ${PAGES_BASE}/image/${res}/${filename} |" >> "$readme"
    done <<< "$image_files"
    echo "" >> "$readme"
  fi

  # GIF section
  local gif_files
  gif_files=$(find "$REPO_DIR/gif" -name "image.gif" 2>/dev/null | sort)
  if [[ -n "$gif_files" ]]; then
    echo "## GIF" >> "$readme"
    echo "" >> "$readme"
    echo "| Resolution | URL |" >> "$readme"
    echo "|------------|-----|" >> "$readme"
    while IFS= read -r f; do
      local res
      res=$(echo "$f" | sed "s|$REPO_DIR/gif/||" | sed 's|/image.gif||')
      echo "| ${res} | ${PAGES_BASE}/gif/${res}/image.gif |" >> "$readme"
    done <<< "$gif_files"
    echo "" >> "$readme"
  fi
}

echo "Updating README.md..."
generate_readme

# --- Git commit + push ---
cd "$REPO_DIR"
git add "${MEDIA_TYPE}/${RESOLUTION}/" README.md
git commit -m "Add ${MEDIA_TYPE} ${RESOLUTION}" 2>&1 | tail -2
echo "Pushing to GitHub..."
git push 2>&1 | tail -2

# --- Output URL ---
URL="$PAGES_BASE/${MEDIA_TYPE}/${RESOLUTION}/$OUT_FILE"
echo ""
echo "========================================="
echo "GitHub Pages URL (live in ~30s):"
echo "$URL"
echo "========================================="
