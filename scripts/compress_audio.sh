#!/usr/bin/env bash
#
# compress_audio.sh — Compress Bible PAL audio files for app distribution.
#
# Creates 64 kbps mono MP3 copies in assets_audio_compressed/
# while leaving originals in assets/stories/ completely untouched.
#
# Default behavior (Step 5A — mtime-aware):
#   - compress files that don't exist in the mirror
#   - REFRESH existing compressed files when the raw mp3 is newer
#     (avoids shipping stale audio after a story is re-narrated)
#   - skip existing files that are current with the raw
#
# Usage:
#   ./scripts/compress_audio.sh                     # compress missing + refresh stale
#   ./scripts/compress_audio.sh --dry-run           # preview, no encoding
#   ./scripts/compress_audio.sh --verify            # count files + stale check
#   ./scripts/compress_audio.sh --skip-existing     # legacy opt-out: skip ANY existing
#                                                   # compressed file regardless of mtime
#   Flags can combine (e.g. --dry-run --skip-existing).
#

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$PROJECT_ROOT/assets/stories"
DST_DIR="$PROJECT_ROOT/assets_audio_compressed/stories"

# ── Path exclusions (Step 5A bundle-hygiene) ─────────────────────────
# Source-side: skip audio_archive/ (voice-swap snapshots, work-in-progress
# audio that should NOT enter the deployable compressed mirror).
# Destination-side: skip creative/ (retired lane, 2026-05-13 — orphaned
# compressed files that the staging pipeline no longer references).
# Note: this only excludes them from script visibility; the files
# themselves are left on disk unmodified.
src_find_mp3s() {
  find "$SRC_DIR" -name "*.mp3" -type f ! -path "*/audio_archive/*"
}
dst_find_mp3s() {
  find "$DST_DIR" -name "*.mp3" -type f ! -path "*/creative/*"
}

DRY_RUN=false
VERIFY=false
SKIP_EXISTING=false  # legacy opt-out: skip ANY existing compressed file

for arg in "$@"; do
  case "$arg" in
    --dry-run)       DRY_RUN=true ;;
    --verify)        VERIFY=true ;;
    --skip-existing) SKIP_EXISTING=true ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

# ── Verify mode ──────────────────────────────────────────────────────
if $VERIFY; then
  echo "(scope: src excludes audio_archive/; dst excludes creative/)"
  src_count=$(src_find_mp3s | wc -l | tr -d ' ')
  dst_count=0
  if [ -d "$DST_DIR" ]; then
    dst_count=$(dst_find_mp3s | wc -l | tr -d ' ')
  fi
  echo "Originals (deployable):     $src_count files"
  echo "Compressed (traditional):   $dst_count files"

  # Stale check: count compressed files whose raw counterpart is newer.
  # Read-only — no files are modified by --verify.
  stale_count=0
  if [ -d "$DST_DIR" ]; then
    while IFS= read -r dst_file; do
      rel_path="${dst_file#"$DST_DIR/"}"
      src_file="$SRC_DIR/$rel_path"
      if [ -f "$src_file" ] && [ "$src_file" -nt "$dst_file" ]; then
        stale_count=$((stale_count + 1))
      fi
    done < <(dst_find_mp3s)
  fi
  echo "Stale:                      $stale_count file(s) (raw newer than compressed)"

  if [ "$src_count" -eq "$dst_count" ] && [ "$stale_count" -eq 0 ]; then
    echo "✓ Counts match and no stale files."
  elif [ "$src_count" -ne "$dst_count" ]; then
    missing=$((src_count - dst_count))
    echo "✗ $missing file(s) missing from compressed output."
    exit 1
  else
    echo "⚠ $stale_count compressed file(s) are out of date — re-run without --skip-existing to refresh."
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
if $SKIP_EXISTING; then
  echo "=== --skip-existing: legacy mode (any existing compressed file is kept as-is) ==="
  echo ""
fi

total=$(src_find_mp3s | wc -l | tr -d ' ')
count=0
compressed_missing=0
refreshed_stale=0
skipped_current=0
skipped_existing=0   # only incremented when --skip-existing is used
failed=0

while IFS= read -r src_file; do
  # Build mirrored destination path
  rel_path="${src_file#"$SRC_DIR/"}"
  dst_file="$DST_DIR/$rel_path"
  dst_subdir="$(dirname "$dst_file")"

  count=$((count + 1))

  # Decide action for this file
  action=""
  if [ -f "$dst_file" ]; then
    if $SKIP_EXISTING; then
      action="skip_existing"
    elif [ "$src_file" -nt "$dst_file" ]; then
      action="refresh_stale"
    else
      action="skip_current"
    fi
  else
    action="compress_missing"
  fi

  case "$action" in
    skip_existing)
      skipped_existing=$((skipped_existing + 1))
      continue
      ;;
    skip_current)
      skipped_current=$((skipped_current + 1))
      continue
      ;;
    refresh_stale)
      echo "[$count/$total] REFRESH (stale): $rel_path"
      ;;
    compress_missing)
      echo "[$count/$total] NEW: $rel_path"
      ;;
  esac

  if $DRY_RUN; then
    # Increment the counter so dry-run totals match what a real run would do
    if [ "$action" = "refresh_stale" ]; then
      refreshed_stale=$((refreshed_stale + 1))
    else
      compressed_missing=$((compressed_missing + 1))
    fi
    continue
  fi

  # Create output directory
  mkdir -p "$dst_subdir"

  # Re-encode + EBU R128 loudness normalization to -18 LUFS via the shared
  # primitive. See docs/AUDIO_LOUDNESS.md for the calibration story and
  # scripts/loudnorm_audio.sh for the encoder profile (libmp3lame 64k mono
  # 22050 Hz + 300/500 ms pads + 30 ms fades).
  # --force overwrites for refresh_stale; for compress_missing the
  # destination doesn't exist yet so --force is a safe no-op.
  # Destination is always under $DST_DIR — originals at $SRC_DIR are never touched.
  if ! "$PROJECT_ROOT/scripts/loudnorm_audio.sh" \
    "$src_file" "$dst_file" --force >/dev/null; then
    echo "  ERROR: failed to compress+normalize $rel_path" >&2
    failed=$((failed + 1))
    # Remove partial output
    rm -f "$dst_file"
    continue
  fi

  if [ "$action" = "refresh_stale" ]; then
    refreshed_stale=$((refreshed_stale + 1))
  else
    compressed_missing=$((compressed_missing + 1))
  fi

done < <(src_find_mp3s | sort)

echo ""
echo "Done."
echo "  Total raw mp3s:        $total"
echo "  Compressed (new):      $compressed_missing"
echo "  Refreshed (stale):     $refreshed_stale"
echo "  Skipped (current):     $skipped_current"
if $SKIP_EXISTING; then
  echo "  Skipped (--skip-existing): $skipped_existing"
fi
echo "  Failed:                $failed"

if [ "$failed" -gt 0 ]; then
  exit 1
fi
