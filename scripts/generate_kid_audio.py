#!/usr/bin/env python3
"""
generate_kid_audio.py — render narration for ONE kid-lane story.

The main story-factory audio script (scripts/story_factory/generate_audio.py)
is hard-wired to assets/stories/{traditional,creative}/{id}/ and its --mode
choices, so it cannot drive the kids/ lane. This thin wrapper REUSES that
script's own tts() / validate_story_voice() (same engine, retries, and 400ms
tail-pad) but points at kids/<productionId>/, reading the per-story
meta_<id>.json exactly like the real pipeline (voice, model, settings).

Kid stories live at assets/stories/kids/<productionId>/:
  meta_<id>.json, story_<id>_<length>.txt, audio_<id>_<length>.mp3
anchorId stays canonical in kid_anchor_registry.json; <productionId> (1801+)
is the production handle. Narrates prose only (title line stripped). Single
take. Does NOT touch the manifest.

USAGE
  python3 scripts/generate_kid_audio.py --id 1801 --length short
  python3 scripts/generate_kid_audio.py --id 1801 --length full --voice VOICE_ARABELLA
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
SF = REPO / "scripts" / "story_factory"
sys.path.insert(0, str(SF))

from generate_audio import tts, load_env  # noqa: E402
from story_voice_registry import validate_story_voice, VoiceValidationError  # noqa: E402

sys.path.insert(0, str(REPO / "scripts"))
from audio_endclip import clip_score, DEFAULT_THRESHOLD  # noqa: E402

DEFAULT_MODEL = "eleven_turbo_v2_5"        # story narration (long; cost matters)
# Reflections are ~10 words, so the priciest/most-expressive model is essentially
# free there and reads more naturally on a question's intonation (Adam 2026-06-15).
# v3 is also the one model that still exhibits the synthesis-drop end-clip
# (everything else moved to turbo), and a reflection's final word IS the
# meaning-bearing word of its question — so it can't use the story-style
# trailing-safety-phrase. We keep v3 for its question intonation and instead
# GUARD it: measure the rendered tail and re-roll a clip-flagged take (the drop
# is non-deterministic, so a fresh take is almost always clean). See
# audio_endclip.py + feedback_audio_end_clip.
REFLECTION_MODEL = "eleven_v3"
DEFAULT_SETTINGS = {
    "stability": 0.6, "similarity_boost": 0.8, "style": 0.0, "use_speaker_boost": True,
}
DEFAULT_MAX_RETRIES = 3   # extra re-rolls when a reflection take is clip-flagged


def render_with_clip_guard(text, out, voice_id, model, settings,
                           max_retries, threshold):
    """Render, then auto-regenerate while the take is clip-flagged.

    Returns the byte size written. Keeps the BEST (lowest-score) take if every
    attempt is flagged, and warns loudly so a human ear-checks — never loops
    forever, never silently ships a clip."""
    import shutil
    attempts = max_retries + 1
    best_score = None
    best_snapshot = out.with_suffix(".best.mp3")
    try:
        for i in range(1, attempts + 1):
            size = tts(text, out, voice_id, model, settings)
            score = clip_score(str(out))
            ok = score <= threshold
            print(f"  clip-guard {i}/{attempts}: score={score:.2f} "
                  f"(thr {threshold}) -> {'clean' if ok else 'CLIPPED, re-rolling'}")
            if ok:
                return size
            if best_score is None or score < best_score:
                best_score = score
                shutil.copyfile(out, best_snapshot)
        shutil.copyfile(best_snapshot, out)   # restore least-bad take
        print(f"  WARNING: clip-guard exhausted {attempts} takes; kept best "
              f"(score={best_score:.2f}). EAR-CHECK {out.name} before shipping.")
        return out.stat().st_size
    finally:
        if best_snapshot.exists():
            best_snapshot.unlink()


def story_body(path: pathlib.Path) -> str:
    """Prose only — drop the title line + leading blanks (parity with adult txt)."""
    lines = path.read_text(encoding="utf-8").splitlines()
    if lines:
        lines = lines[1:]
    return "\n".join(lines).strip()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--id", required=True, help="kid productionId, e.g. 1801")
    ap.add_argument("--length", required=True,
                    choices=["short", "full", "long", "reflection"])
    ap.add_argument("--voice", default=None,
                    help="override meta.storyVoiceKey (must be an approved narrator)")
    ap.add_argument("--max-retries", type=int, default=DEFAULT_MAX_RETRIES,
                    help="reflection clip-guard re-rolls when a take is flagged "
                         f"(default {DEFAULT_MAX_RETRIES})")
    ap.add_argument("--clip-threshold", type=float, default=DEFAULT_THRESHOLD,
                    help=f"end-clip score threshold (default {DEFAULT_THRESHOLD})")
    ap.add_argument("--no-clip-guard", action="store_true",
                    help="disable the reflection clip-guard (single take)")
    args = ap.parse_args()

    base = REPO / "assets" / "stories" / "kids" / str(args.id)
    meta_path = base / f"meta_{args.id}.json"
    if not meta_path.exists():
        print(f"ABORT: meta not found: {meta_path.relative_to(REPO)}")
        return 1
    meta = json.loads(meta_path.read_text(encoding="utf-8"))

    load_env(REPO)

    voice_key = args.voice or meta.get("storyVoiceKey")
    try:
        validate_story_voice(voice_key or "")
    except VoiceValidationError as exc:
        print(f"ABORT: {exc}")
        return 1
    voice_id = os.environ.get(voice_key, "").strip()
    if not voice_id:
        print(f"ABORT: {voice_key} not set in .env")
        return 1

    if args.length == "reflection":
        model = meta.get("reflectionTtsModel", REFLECTION_MODEL)
    else:
        model = meta.get("ttsModel", DEFAULT_MODEL)
    settings = meta.get("ttsVoiceSettings", DEFAULT_SETTINGS)

    if args.length == "reflection":
        txt = base / f"reflection_{args.id}.txt"
        if not txt.exists():
            print(f"ABORT: reflection file not found: {txt.relative_to(REPO)}")
            return 1
        text = txt.read_text(encoding="utf-8").strip()  # single question, no title
        out = base / f"audio_{args.id}_reflection.mp3"
    else:
        txt = base / f"story_{args.id}_{args.length}.txt"
        if not txt.exists():
            print(f"ABORT: story file not found: {txt.relative_to(REPO)}")
            return 1
        text = story_body(txt)
        out = base / f"audio_{args.id}_{args.length}.mp3"

    print(f"Story : {args.id} '{meta.get('title')}' [{meta.get('anchorId')}] / {args.length}")
    print(f"Voice : {voice_key} ({voice_id})")
    print(f"Model : {model}  settings {settings}")
    print(f"Text  : {txt.relative_to(REPO)} ({len(text.split())} words, {len(text)} chars)")
    print(f"Out   : {out.relative_to(REPO)}")
    # Clip-guard applies to reflections (the v3 lane prone to synthesis-drop and
    # unable to use the trailing-safety-phrase). Stories render in turbo and use
    # the prose rule, so they take a single deterministic pass.
    if args.length == "reflection" and not args.no_clip_guard:
        size = render_with_clip_guard(text, out, voice_id, model, settings,
                                      args.max_retries, args.clip_threshold)
    else:
        size = tts(text, out, voice_id, model, settings)
    print(f"OK: wrote {out.relative_to(REPO)} ({size:,} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
