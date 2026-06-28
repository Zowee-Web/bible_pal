#!/usr/bin/env python3
"""
render_journey_audio.py — Slice 2 Phase 6 production renderer

Renders the journey-continuation offer + decline clips per voice
into the canonical asset path the inventory validator and runtime
resolver both look for:

  assets/pal/audio/<VOICE>/journey/<clipId>.mp3

This is Slice 2 Phase 6 of the Journey Doctrine
(docs/JOURNEY_DOCTRINE.md). The 2026-06-28 audition
(docs/reports/journey_offer_line_audition_2026-06-28.md) locked the
offer-line copy and the `<function>_<style>_<lane>` clip-id
convention. First ship: VOICE_STILLWATER only.

SIX CLIPS (Slice 2 first ship, VOICE_STILLWATER):
  - offer_narrative_adult         — adult Narrative offer (full line)
  - decline_adult                 — adult decline (style-agnostic)
  - carrier_narrative_kid         — kid Narrative offer carrier
                                    (precedes the character name clip)
  - invitation_narrative_kid      — kid Narrative offer invitation
                                    (follows the character name clip)
  - decline_kid                   — kid decline (style-agnostic)
  - name_david_journey            — per-journey character clip; one
                                    per kid journey with a characterName

Total billed characters: ~250. ~$1 in ElevenLabs credits.

USAGE
-----
  ./scripts/render_journey_audio.py                     # dry-run (default)
  ./scripts/render_journey_audio.py --render            # actually call API
  ./scripts/render_journey_audio.py --voice STILLWATER  # explicit (default)
  ./scripts/render_journey_audio.py --render --force    # overwrite existing

REQUIRES
--------
  - .env with ELEVENLABS_API_KEY (only when --render)
  - Python 3.8+ stdlib only (no external packages)

GUARDRAILS
----------
  - Dry-run by default. Explicit --render required to spend credits.
  - Idempotent: skips clips that already exist on disk. Partial-render
    recovery is free — re-run --render fills only the missing clips.
  - Atomic writes: API output goes to a sibling .partial path then
    atomic-renames to the final path; an interrupted render never
    leaves a half-written MP3 that idempotency would mistake for
    complete.
  - Per-clip failures don't abort the batch; failed clipIds are listed
    at the end and the script exits non-zero so the next idempotent
    re-run finishes the job.
  - No tail-trim by default. If post-render listening exposes a
    trailing-breath artifact on `carrier_narrative_kid` (ends in
    "about" — similar shape to the Slice 2d "with" issue), a separate
    follow-up slice handles the trim (mirror the Slice 2d audition
    pattern).

NEXT STEP AFTER --render
------------------------
  flutter test test/features/journey/journey_audio_inventory_validator_test.dart
"""

from __future__ import annotations

import argparse
import json
import shutil
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

# Voice IDs mirrored from lib/core/pal_voice_registry.dart. Slice 2
# first ship: STILLWATER only (kept locked as the memory voice via
# the 2026-06-19 audition + as the default voice via PR #41).
VOICES = {
    "VOICE_HOPE": {
        "display_name": "Hope",
        "elevenlabs_id": "qBDvhofpxp92JgXJxDjB",
    },
    "VOICE_SHEPHERD": {
        "display_name": "Shepherd",
        "elevenlabs_id": "EkK5I93UQWFDigLMpZcX",
    },
    "VOICE_STILLWATER": {
        "display_name": "Stillwater",
        "elevenlabs_id": "uju3wxzG5OhpWcoi3SMy",
    },
}

# Per the 2026-06-28 audition lock. Texts are FINAL — any change
# requires a new audition pass + re-render. Punctuation matters for
# prosody (commas → mid-sentence pause; "…" → softer trailing).
CLIPS = [
    # ---- ADULT lane ----
    {
        "clip_id": "offer_narrative_adult",
        "text": "We could spend a little more time together… or tell me what's on your heart.",
    },
    {
        "clip_id": "decline_adult",
        "text": "Of course. Let's find something for today.",
    },
    # ---- KID lane ----
    {
        "clip_id": "carrier_narrative_kid",
        "text": "Want to hear another story about",
    },
    {
        "clip_id": "invitation_narrative_kid",
        "text": "or pick something else?",
    },
    {
        "clip_id": "decline_kid",
        "text": "Okay! Let's find something else.",
    },
    # ---- Per-kid-journey character name (Kid David Arc — first ship) ----
    {
        "clip_id": "name_david_journey",
        "text": "David.",
    },
]

# Locked production TTS settings (from scripts/generate_opus_audio.sh,
# unchanged since 2026-06-14). Same shape Slice 2d uses.
ELEVENLABS_MODEL = "eleven_turbo_v2_5"
ELEVENLABS_VOICE_SETTINGS = {
    "stability": 0.6,
    "similarity_boost": 0.8,
    "style": 0.0,
    "use_speaker_boost": True,
}

CREDITS_PER_CHAR_LOW = 0.5
CREDITS_PER_CHAR_HIGH = 0.7

# ----------------------------------------------------------------------------
# Helpers (load_env_var + render_elevenlabs mirror render_pal_memory_audio.py)
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


def journey_clip_path(voice_key: str, clip_id: str) -> Path:
    return ASSETS_ROOT / voice_key / "journey" / f"{clip_id}.mp3"


# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------


def build_plan(voice_key: str, force: bool) -> list[dict]:
    plan: list[dict] = []
    for c in CLIPS:
        out = journey_clip_path(voice_key, c["clip_id"])
        plan.append({
            "clip_id": c["clip_id"],
            "text": c["text"],
            "out_path": out,
            "exists": out.exists(),
            "would_skip": out.exists() and not force,
            "chars": len(c["text"]),
        })
    return plan


def print_plan(voice_key: str, voice_meta: dict, plan: list[dict], *,
               render_mode: bool, force: bool) -> None:
    print("=" * 72)
    print("Journey Audio — Slice 2 Phase 6 render plan")
    print("=" * 72)
    print(f"Mode:                 {'RENDER (will spend credits)' if render_mode else 'DRY-RUN (no API calls)'}")
    print(f"Voice:                {voice_key} — {voice_meta['display_name']}")
    print(f"Voice ID:             {voice_meta['elevenlabs_id'][:8]}… (from pal_voice_registry.dart)")
    print(f"TTS model:            {ELEVENLABS_MODEL}")
    print(f"TTS settings:         {ELEVENLABS_VOICE_SETTINGS}")
    print(f"Force overwrite:      {force}")
    print(f"Output root:          {ASSETS_ROOT.relative_to(PROJECT_ROOT)}/{voice_key}/journey/")
    print()
    print(f"{'clip_id':<32} {'chars':>5} {'exists':>7} {'action':<14} text")
    print("-" * 100)
    for entry in plan:
        if entry["would_skip"]:
            action = "skip (exists)"
        elif entry["exists"] and force:
            action = "OVERWRITE"
        else:
            action = "WOULD render" if not render_mode else "render"
        print(
            f"{entry['clip_id']:<32} {entry['chars']:>5} "
            f"{'yes' if entry['exists'] else 'no':>7} {action:<14} {entry['text']!r}"
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
    print(f"Clips total:                  {len(plan)} (Slice 2 first-ship set)")
    print(f"Clips to render this run:     {len(to_render)}  (skipping {len(plan) - len(to_render)} already on disk)")
    if overwrite:
        print(f"OVERWRITING existing clips:   {len(overwrite)}  ← --force is on")
    print(f"Total billed characters:      {chars}")
    print(f"Estimated credits:            {low}–{high}  (turbo_v2_5 ≈ {CREDITS_PER_CHAR_LOW}–{CREDITS_PER_CHAR_HIGH} credits/char)")
    print(f"API calls:                    {len(to_render)}")


def run(plan: list[dict], voice_meta: dict, *, api_key: str) -> tuple[list[str], list[str]]:
    """Execute the render plan. Returns (rendered_clip_ids, failed_clip_ids).

    Atomic write per clip: API output → sibling .partial path →
    atomic-rename to final. An interrupted run never leaves a half-
    written MP3 that idempotency would mistake for complete on the
    next run.
    """
    rendered: list[str] = []
    failed: list[str] = []
    for entry in plan:
        if entry["would_skip"]:
            continue
        clip_id = entry["clip_id"]
        final = entry["out_path"]
        try:
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
            print(f"  ok      {clip_id}")
            rendered.append(clip_id)
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", errors="replace")[:200]
            print(f"  FAIL    {clip_id}  HTTP {e.code}: {detail}")
            failed.append(clip_id)
        except Exception as e:  # noqa: BLE001 — keep batch going
            print(f"  FAIL    {clip_id}  {type(e).__name__}: {e}")
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
        help="Voice short name (HOPE / SHEPHERD / STILLWATER). Defaults to "
             "STILLWATER per Slice 2 first-ship plan.",
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

    plan = build_plan(voice_key=voice_key, force=args.force)
    print_plan(
        voice_key, voice_meta, plan,
        render_mode=args.render, force=args.force,
    )

    if not args.render:
        print()
        print("This was a dry-run. To actually render:")
        print(f"  ./scripts/render_journey_audio.py --render --voice {short}")
        return 0

    # --render path: validate environment, then execute the plan.
    api_key = load_env_var("ELEVENLABS_API_KEY")
    if not api_key:
        print()
        print("ELEVENLABS_API_KEY not found in .env. Aborting before any API call.")
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
    print("Next step — confirm clips landed at the expected layout:")
    print(f"  flutter test test/features/journey/journey_audio_inventory_validator_test.dart")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
