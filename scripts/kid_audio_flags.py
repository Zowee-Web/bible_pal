#!/usr/bin/env python3
"""
kid_audio_flags.py — emit the loudnorm_audio.sh flags for one kid-lane audio file.

scripts/compress_audio.sh calls this for every kids/<id>/audio_*.mp3 so the
published mirror is reproduced exactly from the raw renders — high-pass on all
kid audio, a 250 Hz de-bloom on warm-voiced narrators, and per-reflection
loudness targets. Calibration lives in scripts/kid_audio_overrides.json.

Usage:
  kid_audio_flags.py kids/1820/audio_1820_reflection.mp3
  -> --highpass --debloom --target=-23

Bright "good" voice story (no de-bloom, default loudness):
  kid_audio_flags.py kids/1801/audio_1801_short.mp3
  -> --highpass
"""
from __future__ import annotations
import json
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
CONF = json.loads((REPO / "scripts" / "kid_audio_overrides.json").read_text())


def voice_for(story_id: str) -> str | None:
    meta = REPO / "assets" / "stories" / "kids" / story_id / f"meta_{story_id}.json"
    if not meta.exists():
        return None
    try:
        return json.loads(meta.read_text()).get("storyVoiceKey")
    except Exception:
        return None


def flags_for(rel_path: str) -> str:
    m = re.search(r"kids/(\d+)/audio_\d+_(short|full|long|reflection)\.mp3$", rel_path)
    if not m:
        # Not a recognized kid story clip — high-pass only (safe kid default).
        return "--highpass"
    story_id, kind = m.group(1), m.group(2)
    voice = voice_for(story_id)
    warm = voice not in set(CONF["goodVoices"])  # unknown/legacy voice -> treat as warm

    flags = ["--highpass"]
    if warm:
        flags.append("--debloom")
    if kind == "reflection":
        target = CONF.get("reflectionOverrides", {}).get(story_id)
        if target is None:
            target = CONF["reflectionTargetWarm"] if warm else CONF["reflectionTargetGood"]
        flags.append(f"--target={target}")
    # stories use loudnorm's default (-18); no --target needed
    return " ".join(flags)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: kid_audio_flags.py <kids/<id>/audio_<id>_<kind>.mp3>", file=sys.stderr)
        sys.exit(2)
    print(flags_for(sys.argv[1]))
