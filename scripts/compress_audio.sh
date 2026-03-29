#!/usr/bin/env bash
#
# compress_audio.sh — Compress Bible PAL audio files for app distribution.
#
# Creates 64 kbps mono MP3 copies in assets_audio_compressed/
# while leaving originals in assets/stories/ completely untouched.
#
# Usage:
#   ./scripts/compress_audio.sh              # compress all files
#   ./scripts/compress_audio.sh --dry-run    # preview only, no encoding
#   ./scripts/compress_audio.sh --verify     # compare file counts
#

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$PROJECT_ROOT/assets/stories"
DST_DIR="$PROJECT_ROOT/assets_audio_compressed/stories"

DRY_RUN=false
VERIFY=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --verify)  VERIFY=true ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

# ── Verify mode ──────────────────────────────────────────────────────
if $VERIFY; then
  src_count=$(find "$SRC_DIR" -name "*.mp3" -type f | wc -l | tr -d ' ')
  dst_count=0
  if [ -d "$DST_DIR" ]; then
    dst_count=$(find "$DST_DIR" -name "*.mp3" -type f | wc -l | tr -d ' ')
  fi
  echo "Originals:  $src_count files"
  echo "Compressed: $dst_count files"
  if [ "$src_count" -eq "$dst_count" ]; then
    echo "✓ Counts match."
  else
    missing=$((src_count - dst_count))
    echo "✗ $missing file(s) missing from compressed output."
    exit 1
  fi

  # Compare total sizes
  src_size=$(du -sh "$SRC_DIR" | cut -f1)
  dst_size=$(du -sh "$DST_DIR" | cut -f1)
  echo ""
  echo "Original size:   $src_size"
  echo "Compressed size: $dst_size"
  exit 0
fi

# ── Compression ──────────────────────────────────────────────────────
if ! command -v ffmpeg &>/dev/null; then
  echo "ERROR: ffmpeg not found. Install it first." >&2
  exit 1
fi

if $DRY_RUN; then
  echo "=== DRY RUN — no files will be written ==="
  echo ""
fi

total=$(find "$SRC_DIR" -name "*.mp3" -type f | wc -l | tr -d ' ')
count=0
skipped=0
errors=0

while IFS= read -r src_file; do
  # Build mirrored destination path
  rel_path="${src_file#"$SRC_DIR/"}"
  dst_file="$DST_DIR/$rel_path"
  dst_subdir="$(dirname "$dst_file")"

  count=$((count + 1))

  # Skip if compressed version already exists
  if [ -f "$dst_file" ]; then
    skipped=$((skipped + 1))
    continue
  fi

  echo "[$count/$total] $rel_path"

  if $DRY_RUN; then
    continue
  fi

  # Create output directory
  mkdir -p "$dst_subdir"

  # Re-encode: 64 kbps, mono, optimized for voice
  if ! ffmpeg -nostdin -loglevel error -y -i "$src_file" \
    -codec:a libmp3lame \
    -b:a 64k \
    -ac 1 \
    -ar 22050 \
    -compression_level 2 \
    "$dst_file" 2>&1; then
    echo "  ERROR: failed to compress $rel_path" >&2
    errors=$((errors + 1))
    # Remove partial output
    rm -f "$dst_file"
  fi

done < <(find "$SRC_DIR" -name "*.mp3" -type f | sort)

echo ""
echo "Done."
echo "  Total:    $total"
echo "  Encoded:  $((count - skipped - errors))"
echo "  Skipped:  $skipped (already existed)"
echo "  Errors:   $errors"

if [ "$errors" -gt 0 ]; then
  exit 1
fi
