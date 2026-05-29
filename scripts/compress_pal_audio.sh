#!/usr/bin/env bash
#
# compress_pal_audio.sh — Compress Bible PAL voice audio for app distribution.
#
# Mirrors scripts/compress_audio.sh but for PAL voice clips
# (assets/pal/audio/VOICE_*). Creates 64 kbps mono MP3 copies in
# assets_pal_compressed/ while leaving originals untouched.
#
# Usage:
#   ./scripts/compress_pal_audio.sh              # compress all
#   ./scripts/compress_pal_audio.sh --dry-run    # preview only
#   ./scripts/compress_pal_audio.sh --verify     # compare counts/sizes
#

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$PROJECT_ROOT/assets/pal/audio"
DST_DIR="$PROJECT_ROOT/assets_pal_compressed/audio"

DRY_RUN=false
VERIFY=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --verify)  VERIFY=true ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

if $VERIFY; then
  src_count=$(find "$SRC_DIR" -name "*.mp3" -type f | wc -l | tr -d ' ')
  dst_count=0
  if [ -d "$DST_DIR" ]; then
    dst_count=$(find "$DST_DIR" -name "*.mp3" -type f | wc -l | tr -d ' ')
  fi
  echo "Originals:  $src_count files"
  echo "Compressed: $dst_count files"
  if [ "$src_count" -eq "$dst_count" ]; then
    echo "Counts match."
  else
    echo "$((src_count - dst_count)) file(s) missing from compressed output."
    exit 1
  fi
  src_size=$(du -sh "$SRC_DIR" | cut -f1)
  dst_size=$(du -sh "$DST_DIR" | cut -f1)
  echo ""
  echo "Original size:   $src_size"
  echo "Compressed size: $dst_size"
  exit 0
fi

if ! command -v ffmpeg &>/dev/null; then
  echo "ERROR: ffmpeg not found." >&2
  exit 1
fi

if $DRY_RUN; then
  echo "=== DRY RUN ==="
fi

total=$(find "$SRC_DIR" -name "*.mp3" -type f | wc -l | tr -d ' ')
count=0
skipped=0
errors=0

while IFS= read -r src_file; do
  rel_path="${src_file#"$SRC_DIR/"}"
  dst_file="$DST_DIR/$rel_path"
  dst_subdir="$(dirname "$dst_file")"

  count=$((count + 1))

  if [ -f "$dst_file" ]; then
    skipped=$((skipped + 1))
    continue
  fi

  if [ $((count % 50)) -eq 0 ] || [ "$count" -le 5 ]; then
    echo "[$count/$total] $rel_path"
  fi

  if $DRY_RUN; then
    continue
  fi

  mkdir -p "$dst_subdir"

  if ! ffmpeg -nostdin -loglevel error -y -i "$src_file" \
    -codec:a libmp3lame \
    -b:a 64k \
    -ac 1 \
    -ar 22050 \
    -compression_level 2 \
    "$dst_file" 2>&1; then
    echo "  ERROR: failed to compress $rel_path" >&2
    errors=$((errors + 1))
    rm -f "$dst_file"
  fi

done < <(find "$SRC_DIR" -name "*.mp3" -type f | sort)

echo ""
echo "Done."
echo "  Total:   $total"
echo "  Encoded: $((count - skipped - errors))"
echo "  Skipped: $skipped"
echo "  Errors:  $errors"

if [ "$errors" -gt 0 ]; then
  exit 1
fi
