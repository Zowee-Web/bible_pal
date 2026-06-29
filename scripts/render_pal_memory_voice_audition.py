#!/usr/bin/env python3
"""
render_pal_memory_voice_audition.py — One-shot audition tool

Renders ONE stitched audition pair per PAL voice ("Yesterday you sat with"
+ "Daniel") so Adam can pick the memory-line voice editorially before
the full 14-clip render in Slice 2d.

Per the PAL Memory Doctrine (docs/PAL_MEMORY_DOCTRINE.md, Slice 2b Audio
Architecture section) the carrier and the display-name ship as separate
clips and stitch at delivery time. This script renders them separately
on purpose: a solo render of "Yesterday you sat with Daniel." would NOT
expose the real prosody question — whether the carrier's continuing
inflection meets the name's terminal inflection naturally.

Output (per voice in the registry):
  docs/reports/pal_memory_voice_audition_assets/<VOICE_KEY>/
    carrier_yesterday_sat_with.mp3    — carrier solo
    name_daniel.mp3                    — name solo
    audition_stitched.mp3              — stitched: carrier + 250ms + name

Total ElevenLabs cost: 2 short clips × 3 voices = ~180 credits.

USAGE
-----
  ./scripts/render_pal_memory_voice_audition.py                # dry-run (default)
  ./scripts/render_pal_memory_voice_audition.py --render       # actually call API
  ./scripts/render_pal_memory_voice_audition.py --voice HOPE   # one voice only

REQUIRES
--------
  - .env with ELEVENLABS_API_KEY
  - ffmpeg on PATH (for stitching)
  - Python 3.8+ stdlib only (no external packages)

GUARDRAILS
----------
  - Dry-run by default. Explicit --render required to spend credits.
  - Idempotent: skips clips that already exist on disk.
  - TTS settings match the locked production config from
    generate_opus_audio.sh (turbo_v2_5 / 0.6 / 0.8 / 0.0).
  - Carrier text ends WITHOUT punctuation so the model produces a
    continuing inflection (leads into a name).
  - Name text ends WITH a period so the model produces a terminal
    inflection (sentence-completing).
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

# ----------------------------------------------------------------------------
# Configuration — matches lib/core/pal_voice_registry.dart + the locked
# TTS settings from scripts/generate_opus_audio.sh (eleven_turbo_v2_5).
# ----------------------------------------------------------------------------

PROJECT_ROOT = Path(__file__).resolve().parent.parent
ENV_FILE = PROJECT_ROOT / ".env"
OUTPUT_ROOT = PROJECT_ROOT / "docs" / "reports" / "pal_memory_voice_audition_assets"

VOICES = [
    {
        "voice_key": "VOICE_HOPE",
        "display_name": "Hope",
        "gender": "female",
        "description": "Bright encouragement",
        "elevenlabs_id": "qBDvhofpxp92JgXJxDjB",
    },
    {
        "voice_key": "VOICE_SHEPHERD",
        "display_name": "Shepherd",
        "gender": "male",
        "description": "Wise storyteller",
        "elevenlabs_id": "EkK5I93UQWFDigLMpZcX",
    },
    {
        "voice_key": "VOICE_STILLWATER",
        "display_name": "Stillwater",
        "gender": "male",
        "description": "Calm companion",
        "elevenlabs_id": "uju3wxzG5OhpWcoi3SMy",
    },
]

# The two clips that make up the audition pair. Texts chosen for prosody:
#   - carrier ends WITHOUT punctuation → continuing inflection (leads in)
#   - name ends WITH a period → terminal inflection (sentence completes)
CLIPS = [
    {
        "clip_id": "carrier_yesterday_sat_with",
        "text": "Yesterday you sat with",
        "kind": "carrier",
    },
    {
        "clip_id": "name_daniel",
        "text": "Daniel.",
        "kind": "name",
    },
]

# Stitch gap — matches PalMemoryAudioPolicy.carrierToNameGap (250ms).
STITCH_GAP_MS = 250

# Locked production TTS settings (from generate_opus_audio.sh).
# All PAL voice audio uses eleven_v3 (NOT turbo). Locked 2026-06-29.
# See: feedback_pal_voice_audio_uses_v3 in auto-memory.
ELEVENLABS_MODEL = "eleven_v3"
ELEVENLABS_VOICE_SETTINGS = {
    "stability": 0.6,
    "similarity_boost": 0.8,
    "style": 0.0,
    "use_speaker_boost": True,
}

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------


def load_env_var(name: str) -> str | None:
    """Read a single variable from .env (no python-dotenv dependency)."""
    if not ENV_FILE.exists():
        return None
    for line in ENV_FILE.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        if key.strip() == name:
            return value.strip().strip("\"'")
    return None


def render_elevenlabs(
    *, text: str, elevenlabs_id: str, api_key: str, output_path: Path
) -> None:
    """Call ElevenLabs TTS and write the MP3 to output_path. Raises on error."""
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{elevenlabs_id}"
    body = {
        "text": text,
        "model_id": ELEVENLABS_MODEL,
        "voice_settings": ELEVENLABS_VOICE_SETTINGS,
    }
    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        headers={
            "xi-api-key": api_key,
            "Content-Type": "application/json",
            "Accept": "audio/mpeg",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            mp3_bytes = resp.read()
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")
        raise SystemExit(
            f"ElevenLabs returned HTTP {e.code} for {elevenlabs_id}: {detail}"
        )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(mp3_bytes)


def stitch_pair(*, carrier: Path, name: Path, output: Path, gap_ms: int) -> None:
    """Concat carrier + silence + name into output using ffmpeg."""
    if not shutil.which("ffmpeg"):
        raise SystemExit(
            "ffmpeg not on PATH — install ffmpeg to produce the stitched audition file. "
            "Individual clips are still available; stitch them manually if needed."
        )
    # Use anullsrc for the silence, then concat the three streams.
    gap_s = gap_ms / 1000.0
    cmd = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "warning",
        "-y",
        "-i",
        str(carrier),
        "-f",
        "lavfi",
        "-t",
        f"{gap_s}",
        "-i",
        "anullsrc=r=44100:cl=mono",
        "-i",
        str(name),
        "-filter_complex",
        "[0:a][1:a][2:a]concat=n=3:v=0:a=1[out]",
        "-map",
        "[out]",
        "-codec:a",
        "libmp3lame",
        "-q:a",
        "4",
        str(output),
    ]
    subprocess.run(cmd, check=True)


# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--render",
        action="store_true",
        help="Actually call ElevenLabs and write audio files. Default is dry-run.",
    )
    parser.add_argument(
        "--voice",
        type=str,
        default=None,
        help="Limit to one voice by short name (HOPE / SHEPHERD / STILLWATER).",
    )
    parser.add_argument(
        "--skip-stitch",
        action="store_true",
        help="Render solo clips only; do not produce the stitched audition file.",
    )
    args = parser.parse_args()

    voices = VOICES
    if args.voice is not None:
        short = args.voice.upper().replace("VOICE_", "")
        voices = [v for v in VOICES if v["voice_key"] == f"VOICE_{short}"]
        if not voices:
            print(f"Unknown voice: {args.voice}. Pick from HOPE / SHEPHERD / STILLWATER.")
            return 2

    print("=" * 72)
    print("PAL Memory Voice Audition — render plan")
    print("=" * 72)
    print(f"Mode:          {'RENDER' if args.render else 'DRY-RUN (no API calls)'}")
    print(f"Output root:   {OUTPUT_ROOT.relative_to(PROJECT_ROOT)}")
    print(f"TTS model:     {ELEVENLABS_MODEL}")
    print(f"Voice settings: {ELEVENLABS_VOICE_SETTINGS}")
    print(f"Stitch gap:    {STITCH_GAP_MS}ms (matches PalMemoryAudioPolicy.carrierToNameGap)")
    print()

    api_key: str | None = None
    if args.render:
        api_key = load_env_var("ELEVENLABS_API_KEY")
        if not api_key:
            print("ELEVENLABS_API_KEY not found in .env. Aborting.")
            return 2

    total_renders = 0
    total_stitches = 0
    total_skipped = 0

    for v in voices:
        voice_dir = OUTPUT_ROOT / v["voice_key"]
        print(f"--- {v['voice_key']} ({v['display_name']}, {v['gender']}, {v['description']}) ---")
        clip_paths: dict[str, Path] = {}
        for c in CLIPS:
            out_path = voice_dir / f"{c['clip_id']}.mp3"
            clip_paths[c["kind"]] = out_path
            if out_path.exists():
                print(f"  skip (exists): {out_path.relative_to(PROJECT_ROOT)}")
                total_skipped += 1
                continue
            print(f"  {'WOULD render' if not args.render else 'render'}: "
                  f"{c['clip_id']} = {c['text']!r}")
            if args.render:
                render_elevenlabs(
                    text=c["text"],
                    elevenlabs_id=v["elevenlabs_id"],
                    api_key=api_key,  # type: ignore[arg-type]
                    output_path=out_path,
                )
                total_renders += 1

        if args.skip_stitch:
            continue

        stitched = voice_dir / "audition_stitched.mp3"
        if stitched.exists():
            print(f"  skip (exists): {stitched.relative_to(PROJECT_ROOT)}")
            total_skipped += 1
        elif args.render:
            # Only stitch if both clips exist on disk after this pass.
            if all(clip_paths[k].exists() for k in ("carrier", "name")):
                print(f"  stitch:        {stitched.relative_to(PROJECT_ROOT)}")
                stitch_pair(
                    carrier=clip_paths["carrier"],
                    name=clip_paths["name"],
                    output=stitched,
                    gap_ms=STITCH_GAP_MS,
                )
                total_stitches += 1
            else:
                print(f"  skip stitch:   clips missing (re-run --render)")
        else:
            print(f"  WOULD stitch:  {stitched.relative_to(PROJECT_ROOT)}")

    print()
    print("=" * 72)
    print("Summary")
    print("=" * 72)
    print(f"Voices considered: {len(voices)}")
    print(f"Renders performed: {total_renders}")
    print(f"Stitches performed: {total_stitches}")
    print(f"Skipped (already on disk): {total_skipped}")
    if not args.render:
        print()
        print("This was a dry-run. To actually render:")
        print("  ./scripts/render_pal_memory_voice_audition.py --render")
    else:
        print()
        print(f"Listen to each stitched audition under:")
        print(f"  {OUTPUT_ROOT.relative_to(PROJECT_ROOT)}/<VOICE_KEY>/audition_stitched.mp3")
        print(f"Compare the solo carrier/name files to assess prosody fit.")
        print(f"Record the decision in:")
        print(f"  docs/reports/pal_memory_voice_choice_2026-06-19.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
