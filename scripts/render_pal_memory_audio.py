#!/usr/bin/env python3
"""
render_pal_memory_audio.py — Slice 2d production renderer

Renders the 14 PAL Memory seed clips per voice (9 carriers + 5 names)
into the canonical asset path the inventory validator and runtime
resolver both look for:

  assets/pal/audio/<VOICE>/memory/<clipId>.mp3

This is Slice 2d of the PAL Memory Doctrine (docs/PAL_MEMORY_DOCTRINE.md).
The 2026-06-19 audition (docs/reports/pal_memory_voice_choice_2026-06-19.md)
locked VOICE_STILLWATER as the first-ship memory voice and set two
prosody constants in lib/features/pal_memory/memory_audio_policy.dart:

  - carrierToNameGap         =  50ms  (applied at runtime by the stitcher)
  - carrierTailTrimDuration  = 300ms  (applied HERE, at render time)

The tail trim removes a trailing breath/exhale artifact ElevenLabs
turbo_v2_5 leaves on Stillwater carriers — clips on disk are the final
form, no runtime trim. Name clips are NEVER trimmed (their terminal
inflection is the prosody we want).

CARRIER vs NAME prosody (matters for ElevenLabs):
  - Carrier text ends WITHOUT punctuation → continuing inflection
  - Name    text ends WITH    a period   → terminal inflection

USAGE
-----
  ./scripts/render_pal_memory_audio.py                          # dry-run (default)
  ./scripts/render_pal_memory_audio.py --render                 # actually call API
  ./scripts/render_pal_memory_audio.py --voice STILLWATER       # explicit voice (default)
  ./scripts/render_pal_memory_audio.py --render --force         # overwrite existing
  ./scripts/render_pal_memory_audio.py --render --skip-trim     # raw carriers (debugging only)

REQUIRES
--------
  - .env with ELEVENLABS_API_KEY (only when --render)
  - ffmpeg + ffprobe on PATH (for carrier tail trim; only when --render)
  - Python 3.8+ stdlib only (no external packages)

GUARDRAILS
----------
  - Dry-run by default. Explicit --render required to spend credits.
  - Idempotent: skips clips that already exist on disk. Partial-render
    recovery is free — re-run --render fills only the missing clips.
  - Atomic carrier writes: API output goes to a tempfile, ffmpeg trims
    INTO the final path; an interrupted carrier render never leaves a
    half-trimmed MP3 on disk.
  - Per-clip failures don't abort the batch; failed clipIds are listed
    at the end and the script exits non-zero so the next idempotent
    re-run finishes the job.

NEXT STEP AFTER --render
------------------------
  flutter test test/features/pal_memory/memory_audio_inventory_validator_test.dart
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------

PROJECT_ROOT = Path(__file__).resolve().parent.parent
ENV_FILE = PROJECT_ROOT / ".env"
ASSETS_ROOT = PROJECT_ROOT / "assets" / "pal" / "audio"

# Voice ids mirrored from lib/core/pal_voice_registry.dart. STILLWATER's id
# is also captured in PalMemoryAudioPolicy as the locked memory voice
# (2026-06-19 audition, commit ae92c718).
VOICES = {
    "VOICE_HOPE": {
        "display_name": "Hope",
        "description": "Bright encouragement",
        "elevenlabs_id": "qBDvhofpxp92JgXJxDjB",
    },
    "VOICE_SHEPHERD": {
        "display_name": "Shepherd",
        "description": "Wise storyteller",
        "elevenlabs_id": "EkK5I93UQWFDigLMpZcX",
    },
    "VOICE_STILLWATER": {
        "display_name": "Stillwater",
        "description": "Calm companion",
        "elevenlabs_id": "uju3wxzG5OhpWcoi3SMy",
    },
}

# 9 carriers — exact mirror of PalMemoryTemplates in
# lib/features/pal_memory/pal_memory_templates.dart. Texts end without
# punctuation by design (continuing inflection that leads into a name).
CARRIERS = [
    ("carrier_yesterday_sat_with",              "Yesterday you sat with"),
    ("carrier_yesterday_spent_time_with",       "Yesterday you spent time with"),
    ("carrier_yesterday_listened_to",           "Yesterday you listened to"),
    ("carrier_few_days_ago_sat_with",           "A few days ago you sat with"),
    ("carrier_few_days_ago_spent_time_with",    "A few days ago you spent time with"),
    ("carrier_few_days_ago_listened_to",        "A few days ago you listened to"),
    ("carrier_earlier_this_week_sat_with",      "Earlier this week you sat with"),
    ("carrier_earlier_this_week_spent_time_with", "Earlier this week you spent time with"),
    ("carrier_earlier_this_week_listened_to",   "Earlier this week you listened to"),
]

# 5 names — exact mirror of assets/pal/memory/display_name_registry.json.
# Texts end WITH a period (terminal inflection).
NAMES = [
    ("name_daniel",                "Daniel."),
    ("name_the_good_samaritan",    "the Good Samaritan."),
    ("name_the_lost_son",          "the lost son."),
    ("name_jonah",                 "Jonah."),
    ("name_david_and_goliath",     "David and Goliath."),
]

# Locked from PalMemoryAudioPolicy.carrierTailTrimDuration. Applied at
# render time to every CARRIER. Names are NEVER trimmed.
CARRIER_TAIL_TRIM_MS = 300

# Locked production TTS settings (from scripts/generate_opus_audio.sh).
ELEVENLABS_MODEL = "eleven_turbo_v2_5"
ELEVENLABS_VOICE_SETTINGS = {
    "stability": 0.6,
    "similarity_boost": 0.8,
    "style": 0.0,
    "use_speaker_boost": True,
}

# Rough ElevenLabs billing rule — turbo_v2_5 is ~0.5 credits per
# character. Used for dry-run estimate only; the dashboard is truth.
CREDITS_PER_CHAR_LOW = 0.5
CREDITS_PER_CHAR_HIGH = 0.7

# ----------------------------------------------------------------------------
# Helpers (load_env_var + render_elevenlabs mirror the audition script)
# ----------------------------------------------------------------------------


def load_env_var(name: str) -> str | None:
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
    with urllib.request.urlopen(req, timeout=60) as resp:
        mp3_bytes = resp.read()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(mp3_bytes)


def probe_duration_seconds(path: Path) -> float:
    out = subprocess.check_output([
        "ffprobe", "-v", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        str(path),
    ])
    return float(out.strip())


def trim_tail(*, source: Path, output: Path, trim_ms: int, kind: str) -> None:
    """Trim trim_ms off the tail of `source`, writing the result to `output`."""
    assert kind == "carrier", (
        f"trim_tail is for carriers only — refusing to trim a {kind} clip "
        "(names need their terminal inflection intact)."
    )
    duration_s = probe_duration_seconds(source)
    trim_s = trim_ms / 1000.0
    kept_s = duration_s - trim_s
    if kept_s <= 0:
        raise RuntimeError(
            f"Refusing to trim: {source.name} duration {duration_s:.3f}s "
            f"is shorter than tail trim {trim_s}s. Re-render or shorten trim."
        )
    output.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "ffmpeg", "-hide_banner", "-loglevel", "warning", "-y",
        "-i", str(source),
        "-t", f"{kept_s:.6f}",
        "-codec:a", "libmp3lame", "-q:a", "4",
        str(output),
    ]
    subprocess.run(cmd, check=True)


def memory_clip_path(voice_key: str, clip_id: str) -> Path:
    return ASSETS_ROOT / voice_key / "memory" / f"{clip_id}.mp3"


# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------


def build_plan(voice_key: str, skip_trim: bool, force: bool) -> list[dict]:
    plan: list[dict] = []
    for clip_id, text in CARRIERS:
        out = memory_clip_path(voice_key, clip_id)
        plan.append({
            "clip_id": clip_id,
            "text": text,
            "kind": "carrier",
            "out_path": out,
            "exists": out.exists(),
            "would_skip": out.exists() and not force,
            "tail_trim_ms": 0 if skip_trim else CARRIER_TAIL_TRIM_MS,
            "chars": len(text),
        })
    for clip_id, text in NAMES:
        out = memory_clip_path(voice_key, clip_id)
        plan.append({
            "clip_id": clip_id,
            "text": text,
            "kind": "name",
            "out_path": out,
            "exists": out.exists(),
            "would_skip": out.exists() and not force,
            "tail_trim_ms": 0,
            "chars": len(text),
        })
    return plan


def print_plan(voice_key: str, voice_meta: dict, plan: list[dict], *, render_mode: bool, skip_trim: bool, force: bool) -> None:
    print("=" * 72)
    print("PAL Memory Audio — Slice 2d render plan")
    print("=" * 72)
    print(f"Mode:                 {'RENDER (will spend credits)' if render_mode else 'DRY-RUN (no API calls)'}")
    print(f"Voice:                {voice_key} — {voice_meta['display_name']} ({voice_meta['description']})")
    print(f"Voice ID:             {voice_meta['elevenlabs_id'][:8]}… (sourced from PalMemoryAudioPolicy)")
    print(f"TTS model:            {ELEVENLABS_MODEL}")
    print(f"TTS settings:         {ELEVENLABS_VOICE_SETTINGS}")
    print(f"Carrier tail trim:    {0 if skip_trim else CARRIER_TAIL_TRIM_MS}ms"
          + (" (--skip-trim: PRODUCTION RENDERS MUST APPLY THE TRIM)" if skip_trim else ""))
    print(f"Force overwrite:      {force}")
    print(f"Output root:          {ASSETS_ROOT.relative_to(PROJECT_ROOT)}/{voice_key}/memory/")
    print()
    print(f"{'kind':<8} {'clip_id':<46} {'chars':>5} {'exists':>7} {'action':<14} {'trim':<7}")
    print("-" * 100)
    for entry in plan:
        if entry["would_skip"]:
            action = "skip (exists)"
        elif entry["exists"] and force:
            action = "OVERWRITE"
        else:
            action = "WOULD render" if not render_mode else "render"
        trim_label = f"{entry['tail_trim_ms']}ms" if entry["kind"] == "carrier" else "—"
        print(
            f"{entry['kind']:<8} {entry['clip_id']:<46} {entry['chars']:>5} "
            f"{'yes' if entry['exists'] else 'no':>7} {action:<14} {trim_label:<7}"
        )

    to_render = [e for e in plan if not e["would_skip"]]
    overwrite = [e for e in to_render if e["exists"]]
    chars = sum(e["chars"] for e in to_render)
    low = int(chars * CREDITS_PER_CHAR_LOW)
    high = int(chars * CREDITS_PER_CHAR_HIGH)
    print()
    print("=" * 72)
    print("Summary")
    print("=" * 72)
    print(f"Clips total:                  {len(plan)} (expected by inventory validator)")
    print(f"Clips to render this run:     {len(to_render)}  (skipping {len(plan) - len(to_render)} already on disk)")
    if overwrite:
        print(f"OVERWRITING existing clips:   {len(overwrite)}  ← --force is on")
    print(f"Total billed characters:      {chars}")
    print(f"Estimated credits:            {low}–{high}  (turbo_v2_5 ≈ {CREDITS_PER_CHAR_LOW}–{CREDITS_PER_CHAR_HIGH} credits/char)")
    print(f"API calls:                    {len(to_render)}")
    print(f"ffmpeg invocations:           {len([e for e in to_render if e['kind'] == 'carrier' and e['tail_trim_ms'] > 0])}  (carrier tail trims)")


def run(plan: list[dict], voice_meta: dict, *, api_key: str) -> tuple[list[str], list[str]]:
    """Execute the render plan. Returns (rendered_clip_ids, failed_clip_ids)."""
    rendered: list[str] = []
    failed: list[str] = []
    for entry in plan:
        if entry["would_skip"]:
            continue
        clip_id = entry["clip_id"]
        try:
            if entry["kind"] == "name":
                # Names: API output written directly to a sibling .partial,
                # then atomically renamed to final.
                final = entry["out_path"]
                final.parent.mkdir(parents=True, exist_ok=True)
                with tempfile.NamedTemporaryFile(
                    dir=final.parent, prefix=f".{clip_id}.", suffix=".partial.mp3", delete=False
                ) as tmp:
                    partial = Path(tmp.name)
                render_elevenlabs(
                    text=entry["text"],
                    elevenlabs_id=voice_meta["elevenlabs_id"],
                    api_key=api_key,
                    output_path=partial,
                )
                partial.replace(final)
                print(f"  ok      name     {clip_id}")
            else:
                # Carriers: API output to a tempfile (not in assets/),
                # then ffmpeg trims INTO the final path. Tempfile is
                # auto-cleaned. An interrupted run never half-writes
                # the final path.
                final = entry["out_path"]
                final.parent.mkdir(parents=True, exist_ok=True)
                with tempfile.TemporaryDirectory(prefix="pal_memory_render_") as tmpdir:
                    raw = Path(tmpdir) / f"{clip_id}.raw.mp3"
                    render_elevenlabs(
                        text=entry["text"],
                        elevenlabs_id=voice_meta["elevenlabs_id"],
                        api_key=api_key,
                        output_path=raw,
                    )
                    # Trim/copy into a sibling .partial in the final dir,
                    # then atomic rename. If ffmpeg or copy crashes mid-write
                    # the final path never appears — next run re-renders
                    # cleanly instead of skip-ing a corrupt MP3.
                    partial = final.with_name(f".{clip_id}.partial.mp3")
                    if entry["tail_trim_ms"] > 0:
                        trim_tail(
                            source=raw,
                            output=partial,
                            trim_ms=entry["tail_trim_ms"],
                            kind="carrier",
                        )
                        partial.replace(final)
                        print(f"  ok      carrier  {clip_id}  (trimmed {entry['tail_trim_ms']}ms)")
                    else:
                        shutil.copyfile(raw, partial)
                        partial.replace(final)
                        print(f"  ok      carrier  {clip_id}  (NOT TRIMMED — --skip-trim)")
            rendered.append(clip_id)
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", errors="replace")[:200]
            print(f"  FAIL    {entry['kind']:<8} {clip_id}  HTTP {e.code}: {detail}")
            failed.append(clip_id)
        except Exception as e:  # noqa: BLE001 — keep batch going
            print(f"  FAIL    {entry['kind']:<8} {clip_id}  {type(e).__name__}: {e}")
            failed.append(clip_id)
    return rendered, failed


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--render",
        action="store_true",
        help="Actually call ElevenLabs and write audio. Default is dry-run.",
    )
    parser.add_argument(
        "--voice",
        type=str,
        default="STILLWATER",
        help="Voice short name (HOPE / SHEPHERD / STILLWATER). Defaults to STILLWATER "
             "per the 2026-06-19 audition decision.",
    )
    parser.add_argument(
        "--skip-trim",
        action="store_true",
        help="Skip the 300ms carrier tail trim (debugging only — production "
             "renders MUST apply it).",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Overwrite existing clips. Default skips clips already on disk "
             "(idempotent partial-render recovery).",
    )
    args = parser.parse_args()

    short = args.voice.upper().replace("VOICE_", "")
    voice_key = f"VOICE_{short}"
    voice_meta = VOICES.get(voice_key)
    if voice_meta is None:
        print(f"Unknown voice: {args.voice}. Pick from HOPE / SHEPHERD / STILLWATER.")
        return 2

    plan = build_plan(voice_key=voice_key, skip_trim=args.skip_trim, force=args.force)
    print_plan(
        voice_key, voice_meta, plan,
        render_mode=args.render, skip_trim=args.skip_trim, force=args.force,
    )

    if not args.render:
        print()
        print("This was a dry-run. To actually render:")
        print(f"  ./scripts/render_pal_memory_audio.py --render --voice {short}")
        return 0

    # --render path: validate environment, then execute the plan.
    api_key = load_env_var("ELEVENLABS_API_KEY")
    if not api_key:
        print()
        print("ELEVENLABS_API_KEY not found in .env. Aborting before any API call.")
        return 2
    needs_ffmpeg = any(
        e["kind"] == "carrier" and e["tail_trim_ms"] > 0 and not e["would_skip"]
        for e in plan
    )
    if needs_ffmpeg and not (shutil.which("ffmpeg") and shutil.which("ffprobe")):
        print()
        print("ffmpeg and ffprobe must both be on PATH for carrier tail trimming.")
        print("Install them or re-run with --skip-trim (debugging only).")
        return 2

    print()
    print("=" * 72)
    print("Executing render")
    print("=" * 72)
    rendered, failed = run(plan, voice_meta, api_key=api_key)

    print()
    print("=" * 72)
    print("Render complete")
    print("=" * 72)
    print(f"Rendered: {len(rendered)}")
    print(f"Failed:   {len(failed)}")
    if failed:
        print(f"  failed clipIds: {failed}")
    skipped = [e["clip_id"] for e in plan if e["would_skip"]]
    print(f"Skipped (already on disk): {len(skipped)}")
    print()
    print("Next step — confirm all 14 clips landed in the expected layout:")
    print(f"  flutter test test/features/pal_memory/memory_audio_inventory_validator_test.dart")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
