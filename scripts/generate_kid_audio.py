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

DEFAULT_MODEL = "eleven_turbo_v2_5"
DEFAULT_SETTINGS = {
    "stability": 0.6, "similarity_boost": 0.8, "style": 0.0, "use_speaker_boost": True,
}


def story_body(path: pathlib.Path) -> str:
    """Prose only — drop the title line + leading blanks (parity with adult txt)."""
    lines = path.read_text(encoding="utf-8").splitlines()
    if lines:
        lines = lines[1:]
    return "\n".join(lines).strip()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--id", required=True, help="kid productionId, e.g. 1801")
    ap.add_argument("--length", required=True, choices=["short", "full", "long"])
    ap.add_argument("--voice", default=None,
                    help="override meta.storyVoiceKey (must be an approved narrator)")
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

    model = meta.get("ttsModel", DEFAULT_MODEL)
    settings = meta.get("ttsVoiceSettings", DEFAULT_SETTINGS)

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
    size = tts(text, out, voice_id, model, settings)
    print(f"OK: wrote {out.relative_to(REPO)} ({size:,} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
