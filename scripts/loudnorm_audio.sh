#!/usr/bin/env bash
#
# loudnorm_audio.sh — Bible PAL audio loudness normalization primitive.
#
# Two-pass EBU R128 loudness normalization with the locked Bible PAL
# encoder profile. Encoder + pad + fade values are intentionally hard-
# coded — they reflect calibration owned by docs/AUDIO_LOUDNESS.md.
#
# Target:  -18 LUFS integrated, TP -1.5 dBTP, LRA 11.
# Padding: 300 ms head + 500 ms tail (silence inserted by the filter).
# Fades:   30 ms in/out, applied after pads.
# Encoder: libmp3lame, 64 kbps CBR, mono, 22050 Hz.
#
# Usage:
#   ./scripts/loudnorm_audio.sh <input.mp3> <output.mp3> [--force] [--highpass]
#
# --highpass: 80 Hz high-pass before normalization to strip plosive "thump".
#             Off by default (adult audio unchanged); the kid lane uses it.
#
# Default behavior is idempotent: if <output.mp3> already exists, the
# script prints "SKIP (exists)" and exits 0 without touching anything.
# Use --force to overwrite an existing output (e.g. when re-running
# against a source that has been re-rendered).
#
# Exit codes:
#   0   success or idempotent skip
#   1   ffmpeg / ffprobe failure or input missing
#   2   bad CLI arguments
#

set -euo pipefail

# ── Locked Bible PAL audio pipeline values ──────────────────────────
# See docs/AUDIO_LOUDNESS.md for the calibration story behind -18 LUFS.
TARGET_I=-18
TARGET_TP=-1.5
TARGET_LRA=11
HEAD_PAD_MS=300
TAIL_PAD_S=0.5
FADE_S=0.03
OUT_BITRATE="64k"
OUT_SAMPLERATE=22050
OUT_CHANNELS=1

if [ $# -lt 2 ]; then
  cat >&2 <<EOF
Usage: $0 <input.mp3> <output.mp3> [--force]

Two-pass EBU R128 loudnorm to ${TARGET_I} LUFS / TP ${TARGET_TP} dBTP / LRA ${TARGET_LRA}.
Pads ${HEAD_PAD_MS} ms head + ${TAIL_PAD_S} s tail, ${FADE_S} s fade in/out.
Output: mono ${OUT_SAMPLERATE} Hz / ${OUT_BITRATE} mp3.

Default: idempotent — skip if <output.mp3> already exists.
--force: overwrite an existing output.
EOF
  exit 2
fi

IN="$1"
OUT="$2"
shift 2
FORCE=false
HIGHPASS=false
for arg in "$@"; do
  case "$arg" in
    --force)    FORCE=true ;;
    --highpass) HIGHPASS=true ;;
    *) echo "ERROR: unknown flag: $arg" >&2; exit 2 ;;
  esac
done

# Optional high-pass to strip sub-bass plosive "thump" (used by the KID lane;
# ElevenLabs renders push plosives hot near 0 dBFS). 80 Hz is inaudible-safe for
# narration and removes the pop at the source. OFF by default — adults unchanged.
HP_PREFIX=""
if [ "$HIGHPASS" = "true" ]; then
  HP_PREFIX="highpass=f=80,"
fi

if [ ! -f "$IN" ]; then
  echo "ERROR: input not found: $IN" >&2
  exit 1
fi

if [ -f "$OUT" ] && [ "$FORCE" != "true" ]; then
  echo "SKIP (exists): $OUT"
  exit 0
fi

if ! command -v ffmpeg >/dev/null || ! command -v ffprobe >/dev/null; then
  echo "ERROR: ffmpeg/ffprobe not on PATH" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"

# ── Pass 1: measure integrated loudness on the raw input ────────────
JSON=$(ffmpeg -hide_banner -nostdin -i "$IN" \
  -af "${HP_PREFIX}loudnorm=I=${TARGET_I}:TP=${TARGET_TP}:LRA=${TARGET_LRA}:print_format=json" \
  -f null - 2>&1 | sed -n '/^{/,/^}/p')

extract() {
  echo "$1" | sed -nE "s/.*\"$2\" *: *\"(-?[0-9.]+)\".*/\1/p" | head -1
}

MI=$(extract "$JSON"  input_i)
MTP=$(extract "$JSON" input_tp)
MLRA=$(extract "$JSON" input_lra)
MTH=$(extract "$JSON" input_thresh)
OFF=$(extract "$JSON" target_offset)

if [ -z "$MI" ] || [ -z "$MTP" ] || [ -z "$MLRA" ] || [ -z "$MTH" ] || [ -z "$OFF" ]; then
  echo "ERROR: pass-1 loudnorm measurement failed for $IN" >&2
  exit 1
fi

# Fade-out starts FADE_S seconds before the padded output ends.
DUR=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$IN")
if [ -z "$DUR" ]; then
  echo "ERROR: could not read duration for $IN" >&2
  exit 1
fi
TOTAL_DUR=$(echo "$DUR + 0.3 + ${TAIL_PAD_S}" | bc -l)
FADE_OUT_ST=$(echo "$TOTAL_DUR - ${FADE_S}" | bc -l)

# ── Pass 2: apply with measured values + pad + fades + re-encode ────
FILTERS="${HP_PREFIX}adelay=${HEAD_PAD_MS},apad=pad_dur=${TAIL_PAD_S},loudnorm=I=${TARGET_I}:TP=${TARGET_TP}:LRA=${TARGET_LRA}:measured_I=${MI}:measured_TP=${MTP}:measured_LRA=${MLRA}:measured_thresh=${MTH}:offset=${OFF}:linear=true,afade=t=in:d=${FADE_S},afade=t=out:st=${FADE_OUT_ST}:d=${FADE_S}"

if ! ffmpeg -hide_banner -nostdin -loglevel error -y -i "$IN" \
  -af "$FILTERS" \
  -c:a libmp3lame -b:a "$OUT_BITRATE" -ar "$OUT_SAMPLERATE" -ac "$OUT_CHANNELS" \
  "$OUT"; then
  echo "ERROR: pass-2 encode failed for $IN -> $OUT" >&2
  rm -f "$OUT"
  exit 1
fi

echo "OK: $OUT"
