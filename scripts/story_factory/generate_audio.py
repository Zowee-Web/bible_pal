#!/usr/bin/env python3
"""
generate_audio.py — Generate ElevenLabs TTS audio for existing Bible PAL stories.

Uses mood-based voice selection from the approved narrator pool.
PAL voices and banned voices are enforced at validation level.

Usage:
    python3 generate_audio.py --story_id 1001 --mode traditional
    python3 generate_audio.py --story_id 2001 --mode creative
    python3 generate_audio.py --story_id 1001 --mode traditional --voice_key VOICE_ARABELLA
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import sys
import time
import urllib.error
import urllib.request

from story_voice_registry import (
    validate_story_voice,
    validate_reflection_voice,
    VoiceValidationError,
)


def load_env(root: pathlib.Path) -> None:
    """Load .env from repo root safely."""
    env_file = root / ".env"
    if not env_file.exists():
        return
    for line in env_file.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = re.sub(r"\s+#.*$", "", value)
        os.environ[key.strip()] = value.strip()


TRANSIENT_CODES = {429, 502, 503}
MAX_RETRIES = 3


def tts(text: str, outfile: pathlib.Path, voice_id: str) -> int:
    """Generate TTS audio via ElevenLabs. Returns file size in bytes."""
    api_key = os.environ["ELEVENLABS_API_KEY"]
    payload = json.dumps({
        "text": text,
        "model_id": "eleven_multilingual_v2",
        "voice_settings": {"stability": 0.5, "similarity_boost": 0.75},
    }).encode()
    req = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}",
        data=payload,
        headers={
            "xi-api-key": api_key,
            "Content-Type": "application/json",
            "Accept": "audio/mpeg",
        },
    )
    for attempt in range(MAX_RETRIES + 1):
        try:
            with urllib.request.urlopen(req, timeout=300) as resp:
                audio = resp.read()
            break
        except urllib.error.HTTPError as exc:
            if exc.code in TRANSIENT_CODES and attempt < MAX_RETRIES:
                wait = 2 ** attempt
                print(f"    TTS transient HTTP {exc.code}, retry in {wait}s...")
                time.sleep(wait)
                continue
            raise

    if len(audio) < 1000:
        raise RuntimeError(
            f"Audio too small ({len(audio)} bytes) for {outfile.name}"
        )
    outfile.write_bytes(audio)
    return len(audio)


def main() -> int:
    t0 = time.time()

    parser = argparse.ArgumentParser(
        description="Generate ElevenLabs TTS audio for an existing Bible PAL story."
    )
    parser.add_argument("--story_id", type=int, required=True)
    parser.add_argument("--mode", type=str, required=True,
                        choices=["traditional", "creative"])
    parser.add_argument("--voice_key", type=str, default=None,
                        help="Override voice (must be from approved narrator pool)")
    parser.add_argument("--overwrite", action="store_true",
                        help="Overwrite existing audio files")
    args = parser.parse_args()

    sid = args.story_id
    mode = args.mode
    root = pathlib.Path(__file__).resolve().parents[2]
    outdir = root / "assets" / "stories" / mode / str(sid)

    print(f"=== Audio Generation for Story {sid} ({mode}) ===")

    # Load env
    load_env(root)

    # Check story directory exists
    if not outdir.exists():
        print(f"ABORT: story directory not found: {outdir}")
        return 1

    # Load metadata
    meta_file = outdir / f"meta_{sid}.json"
    if not meta_file.exists():
        print(f"ABORT: metadata not found: {meta_file}")
        return 1
    meta = json.loads(meta_file.read_text())

    # Check env vars
    api_key = os.environ.get("ELEVENLABS_API_KEY", "").strip()
    if not api_key:
        print("ABORT: ELEVENLABS_API_KEY is missing or empty")
        return 1

    # Read voice from metadata — every story MUST explicitly define its voice
    voice_key = args.voice_key or meta.get("storyVoiceKey") or meta.get("voiceKey")

    # Validate voice through the registry (banned/missing/unknown all fail)
    try:
        validate_story_voice(voice_key or "")
    except VoiceValidationError as exc:
        print(f"ABORT: {exc}")
        return 1

    voice_id = os.environ.get(voice_key, "").strip()
    if not voice_id:
        print(f"ABORT: {voice_key} env var is missing or empty in .env")
        return 1

    lane = meta.get("languageStyle", "WEB").lower()

    # Build list of text files -> audio files
    audio_jobs = []
    for length in ["short", "full", "long"]:
        txt_name = f"story_{sid}_{mode}_{lane}_{length}.txt"
        mp3_name = f"audio_{sid}_story_{length}.mp3"
        txt_path = outdir / txt_name
        if not txt_path.exists():
            print(f"WARNING: text file not found, skipping: {txt_name}")
            continue
        audio_jobs.append((txt_path, outdir / mp3_name, mp3_name))

    # Reflection
    refl_name = f"reflection_{sid}_{mode}_{lane}.txt"
    refl_mp3 = f"audio_{sid}_reflection.mp3"
    refl_path = outdir / refl_name
    if refl_path.exists():
        audio_jobs.append((refl_path, outdir / refl_mp3, refl_mp3))
    else:
        print(f"WARNING: reflection not found, skipping: {refl_name}")

    print(f"  Mood: {mood} | Kid: {is_kid}")
    print(f"  Voice: {voice_key} ({voice_id[:8]}...)")
    print(f"  Files to generate: {len(audio_jobs)}")
    print()

    # Generate audio
    for txt_path, mp3_path, mp3_name in audio_jobs:
        text = txt_path.read_text().strip()
        wc = len(text.split())
        print(f"  TTS: {txt_path.name} ({wc} words) -> {mp3_name}")

        if mp3_path.exists() and not args.overwrite:
            print(f"    Skipping (already exists: {mp3_path.stat().st_size:,} bytes)")
            continue

        size = tts(text, mp3_path, voice_id)
        print(f"    {size:,} bytes")

    # Update metadata with the voice keys used
    updated = False
    if meta.get("storyVoiceKey") != voice_key:
        meta["storyVoiceKey"] = voice_key
        updated = True
    if meta.get("reflectionVoiceKey") != voice_key:
        meta["reflectionVoiceKey"] = voice_key
        updated = True
    if updated:
        meta_file.write_text(json.dumps(meta, indent=2) + "\n")
        print(f"\n  Updated metadata storyVoiceKey/reflectionVoiceKey to {voice_key}")

    elapsed = time.time() - t0
    print(f"\nDONE. Audio for story {sid} ({mode}) generated in {elapsed:.1f}s.")

    # Summary
    print(f"\n=== Verification ===")
    for f in sorted(outdir.iterdir()):
        if f.suffix == ".mp3":
            print(f"  {f.name}: {f.stat().st_size:,} bytes")

    return 0


if __name__ == "__main__":
    sys.exit(main())
