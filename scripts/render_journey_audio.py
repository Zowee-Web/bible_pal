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

# Locked production TTS settings (from scripts/generate_opus_audio.sh,
# unchanged since 2026-06-14). Same shape Slice 2d uses.
ELEVENLABS_DEFAULT_MODEL = "eleven_v3"
# All PAL voice audio uses eleven_v3, not turbo. Locked 2026-06-29 —
# turbo over-clips consonants on short PAL utterances and treats
# punctuation like "!" as performative excitement. v3 has the
# prosodic breath room PAL clips need. Story/reflection audio
# stays on turbo (separate recipe).
# See: feedback_pal_voice_audio_uses_v3 in auto-memory.
ELEVENLABS_VOICE_SETTINGS = {
    "stability": 0.6,
    "similarity_boost": 0.8,
    "style": 0.0,
    "use_speaker_boost": True,
}

# Per the 2026-06-28 audition lock. Texts are FINAL — any change
# requires a new audition pass + re-render. Punctuation matters for
# prosody (commas → mid-sentence pause; "…" → softer trailing).
#
# Authoring source of truth for the wording of these beats:
# docs/JOURNEY_TRANSITION_VOICE.md (relational-center rule, the
# three signature tests, benchmark = coverage map). New/edited clip
# text must pass its Transition Audit before it lands here.
#
# Per-clip `model` override: defaults to ELEVENLABS_DEFAULT_MODEL
# (eleven_turbo_v2_5). Short, expressive utterances render better
# with eleven_v3 — same precedent as the kid lane reflection clips
# per [project_kid_lane_manifest]. Single-name clips (e.g.
# "David.") need v3 to avoid the punched-out quick delivery turbo
# produces on very short input.
CLIPS = [
    # ---- ADULT lane ----
    # DEPRECATED 2026-06-28 by Adam after a doctrine review: the
    # generic "we could spend a little more time together" offer is
    # not memory-grounded. Adult lane pivoted to monolithic
    # per-journey offers (`<journeyId>_offer`) mirroring the kid
    # pivot earlier the same day. Per-journey offers name the
    # remembered story in BOTH the recognition and the offer — the
    # second mention isn't redundant, it's continuity (look-back +
    # look-forward). This clip stays bundled per
    # [feedback_never_delete_audio] but the resolver no longer
    # references it.
    {
        "clip_id": "offer_narrative_adult",
        "text": "We could spend a little more time together… or tell me what's on your heart.",
    },
    {
        "clip_id": "decline_adult",
        # 2026-06-29 voice audit (docs/PAL_VOICE.md): shortened from
        # "Of course. Let's find something for today." — the offer's
        # trailing "or, tell me what's on your heart today" already
        # invites the mood-redirect, so the decline doesn't need to
        # invite again. Brief acknowledgment, then STT opens.
        #
        # Model: eleven_v3 (not turbo). Single short utterances need
        # the prosodic breath room v3 provides; turbo over-clips
        # consonants on 2-word phrases. Matches the offer clips'
        # model choice for tonal consistency across the cascade.
        "text": "Of course.",
        "model": "eleven_v3",
    },
    # ---- Per-adult-journey MONOLITHIC offer (Daniel Arc — first ship) ----
    # Naming convention: `<journeyId>_offer`. Each new adult journey
    # adds one full-line offer clip per voice (~25-40 credits per
    # voice per journey). Memory-grounded design principle: the
    # remembered story is named in both halves of the line.
    {
        "clip_id": "daniel_arc_offer",
        "text": "Would you like to hear what happened next with Daniel… or tell me what's on your heart?",
        "model": "eleven_v3",
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
        # 2026-06-29 voice audit (docs/PAL_VOICE.md): shortened from
        # "Okay! Let's find something else." — same reason as
        # decline_adult. First take used "Okay!" with exclamation;
        # turbo treated the "!" as performative excitement on a
        # 5-char utterance and the result was abrupt + loud. Dropped
        # to "Okay." (period). Second take still abrupt on turbo —
        # switched to eleven_v3 for prosodic breath room.
        "text": "Okay.",
        "model": "eleven_v3",
    },
    # ---- Per-kid-journey character name (Kid David Arc — first ship) ----
    # DEPRECATED 2026-06-28 by Adam after ear-check: stitching a 1-
    # syllable name clip into a kid offer sounds punched-out and
    # unnatural even with v3. The name needs to be embedded in a
    # full conversational phrase (same reason "Hey, Adam!" sounds
    # natural — phrase context, not isolated name). Kid lane pivots
    # to a monolithic per-journey clip below. This clip stays
    # bundled (per [feedback_never_delete_audio]) but the resolver
    # no longer references it.
    {
        "clip_id": "name_david_journey",
        "text": "David.",
        "model": "eleven_v3",
    },
    # ---- Per-kid-journey MONOLITHIC offer (the pivot) ----
    # Naming convention: `kid_<journeyId>_offer`. Each new kid
    # journey adds one full-line offer clip per voice. Cost: ~25-35
    # credits per voice per kid journey. Replaces the 3-clip stitch
    # (carrier_narrative_kid + name_<x>_journey + invitation_narrative_kid)
    # that produced unnatural standalone-name delivery.
    {
        "clip_id": "kid_david_arc_offer",
        "text": "Want to hear another story about David… or, what's on your mind?",
        "model": "eleven_v3",
    },
    # ---- Per-source-story MONOLITHIC offers (Slice 2 Phase 6 FINAL) ----
    # Clip ID convention: `<journeyId>_offer_<sourceStoryIndex>`.
    # Plays AFTER the user heard story at sourceStoryIndex, offering
    # the next-in-journey story. End-of-journey indices get no clip
    # (engine returns null per the Slice 2 strict-newest rule).
    #
    # Register locked at 2026-06-29 voice audit (docs/PAL_VOICE.md):
    # three ellipsis-joined clauses, single continuous spoken thought.
    #
    #   ADULT:
    #     "Last time, we [active-verb] [iconic scene]…
    #      There's more to [character]'s story if you'd like to hear it…
    #      or, tell me what's on your heart today."
    #
    #   KID:
    #     "Last time, we [active-verb] [iconic scene]…
    #      There's more to [character]'s story if you'd like to hear it…
    #      or, what's on your mind?"
    #
    # The trailing "or, …" clause signals the third response path
    # (mood-redirect) to first-time users who would otherwise only
    # see yes/no. Without it, the cascade fails Q7 of the Voice Audit
    # in flow context. Re-render history: V1 lacked the trailing
    # clause and was re-rendered 2026-06-29 after the PAL Voice
    # doctrine landed. V1 audio archived at
    # assets/pal/audio_archive_journey_pre_voice_audit_2026-06-29/.
    #
    # - "Last time" beats "yesterday" — handles the engine's 1-7 day
    #   recency band without per-band re-renders.
    # - "we watched" / "we walked with" / "we stood with" — active
    #   companionship; PAL was there with them.
    # - Storybook scene phrasing ("shepherd boy face a giant" >
    #   "David and Goliath") — captures the moment, not just the label.
    # - "if you'd like to hear it" — gentle invitation, never forced.
    # - "or, tell me…" / "or, what's on your mind?" — explicit
    #   third path. Maps to existing canonical mood prompts.
    #
    # The earlier per-journey monolithic clips (daniel_arc_offer,
    # kid_david_arc_offer) are now orphaned by this pivot; kept
    # bundled per [feedback_never_delete_audio].
    #
    # ADULT — Daniel Arc (sourceStoryIndex 0/1/2; index 3 = end)
    {
        "clip_id": "daniel_arc_offer_0",
        "text": "Last time, we sat with young Daniel as he chose what was true… There's more to his story if you'd like to hear it… or, tell me what's on your heart today.",
        "model": "eleven_v3",
    },
    {
        "clip_id": "daniel_arc_offer_1",
        "text": "Last time, we stood in the fire with Daniel's friends… There's more to his story if you'd like to hear it… or, tell me what's on your heart today.",
        "model": "eleven_v3",
    },
    {
        "clip_id": "daniel_arc_offer_2",
        "text": "Last time, we walked with Daniel into the lions' den… There's more to his story if you'd like to hear it… or, tell me what's on your heart today.",
        "model": "eleven_v3",
    },
    # KID — Kid David Arc (sourceStoryIndex 0/1; index 2 = end)
    {
        "clip_id": "kid_david_arc_offer_0",
        "text": "Last time, we watched a shepherd boy be chosen for something big… There's more to David's story if you'd like to hear it… or, what's on your mind?",
        "model": "eleven_v3",
    },
    {
        "clip_id": "kid_david_arc_offer_1",
        "text": "Last time, we watched a shepherd boy face a giant… There's more to David's story if you'd like to hear it… or, what's on your mind?",
        "model": "eleven_v3",
    },
    # ---- SHORT variants (VESTIGIAL — 2026-06-30) ----
    # Rendered for the mood-button journey recognition path
    # (Slice 2 PR B), then orphaned same day by the Entry-Point
    # Split doctrine (JOURNEY_DOCTRINE.md § Entry-Point Split):
    # the journey cascade fires ONLY from the PAL button; mood
    # buttons are shortcuts with no memory, no beat, no STT.
    #
    # Clips stay bundled per [feedback_never_delete_audio]. The
    # resolver no longer references them; the inventory validator
    # no longer requires them. If a future doctrine reverses the
    # split, these clips are ready to use as-is (no re-render).
    {
        "clip_id": "daniel_arc_offer_0_short",
        "text": "Last time, we sat with young Daniel as he chose what was true… There's more to his story if you'd like to hear it.",
        "model": "eleven_v3",
    },
    {
        "clip_id": "daniel_arc_offer_1_short",
        "text": "Last time, we stood in the fire with Daniel's friends… There's more to his story if you'd like to hear it.",
        "model": "eleven_v3",
    },
    {
        "clip_id": "daniel_arc_offer_2_short",
        "text": "Last time, we walked with Daniel into the lions' den… There's more to his story if you'd like to hear it.",
        "model": "eleven_v3",
    },
    {
        "clip_id": "kid_david_arc_offer_0_short",
        "text": "Last time, we watched a shepherd boy be chosen for something big… There's more to David's story if you'd like to hear it.",
        "model": "eleven_v3",
    },
    {
        "clip_id": "kid_david_arc_offer_1_short",
        "text": "Last time, we watched a shepherd boy face a giant… There's more to David's story if you'd like to hear it.",
        "model": "eleven_v3",
    },
]

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
    *,
    text: str,
    elevenlabs_id: str,
    api_key: str,
    output_path: Path,
    model: str = ELEVENLABS_DEFAULT_MODEL,
) -> None:
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{elevenlabs_id}"
    body = {
        "text": text,
        "model_id": model,
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
            "model": c.get("model", ELEVENLABS_DEFAULT_MODEL),
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
    print(f"TTS model (default):  {ELEVENLABS_DEFAULT_MODEL} (per-clip overrides in table below)")
    print(f"TTS settings:         {ELEVENLABS_VOICE_SETTINGS}")
    print(f"Force overwrite:      {force}")
    print(f"Output root:          {ASSETS_ROOT.relative_to(PROJECT_ROOT)}/{voice_key}/journey/")
    print()
    print(f"{'clip_id':<32} {'chars':>5} {'model':<22} {'exists':>7} {'action':<14} text")
    print("-" * 120)
    for entry in plan:
        if entry["would_skip"]:
            action = "skip (exists)"
        elif entry["exists"] and force:
            action = "OVERWRITE"
        else:
            action = "WOULD render" if not render_mode else "render"
        print(
            f"{entry['clip_id']:<32} {entry['chars']:>5} {entry['model']:<22} "
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
                model=entry["model"],
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
