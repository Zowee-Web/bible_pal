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
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request

# Universal tail-pad applied to every generated mp3 to absorb the v3 TTS
# tail-clip bug (~200ms occasionally lost on the final word). 400ms is short
# enough that the listener perceives it as a natural breath after the close,
# long enough to fully buffer the file-boundary clip pattern. Confirmed
# 400ms after Adam A/B'd against 500 on Batch 19 — 500 was slightly too
# much, 400 lands invisibly. The remaining occasional tail-clips are
# ElevenLabs-side synthesis-drops that the prose rule
# (trailing-safety-phrase) addresses — see feedback_audio_end_clip.md.
TAIL_PAD_SECONDS = 0.4

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


def tts(text: str, outfile: pathlib.Path, voice_id: str,
        model_id: str, voice_settings: dict) -> int:
    """Generate TTS audio via ElevenLabs. Returns file size in bytes.

    `model_id` and `voice_settings` come from each story's meta
    (ttsModel / ttsVoiceSettings). Callers pass v2 defaults if the meta
    doesn't declare them.
    """
    api_key = os.environ["ELEVENLABS_API_KEY"]
    payload = json.dumps({
        "text": text,
        "model_id": model_id,
        "voice_settings": voice_settings,
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
    _apply_tail_pad(outfile, TAIL_PAD_SECONDS)
    return outfile.stat().st_size


def _apply_tail_pad(mp3_path: pathlib.Path, duration_seconds: float) -> None:
    """Append silence to the end of an mp3 via ffmpeg.

    Universal pipeline step. Protects against the v3 TTS tail-clip bug.
    Replaces the file in place once ffmpeg succeeds. Silently no-ops if
    ffmpeg is unavailable so the script remains usable in environments
    that don't have it installed.
    """
    if shutil.which("ffmpeg") is None:
        print(f"    Warning: ffmpeg not found; skipping tail-pad on {mp3_path.name}")
        return

    tmp_path = mp3_path.with_suffix(".padded.mp3")
    cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-i", str(mp3_path),
        "-af", f"apad=pad_dur={duration_seconds}",
        "-codec:a", "libmp3lame", "-b:a", "128k",
        str(tmp_path),
    ]
    try:
        subprocess.run(cmd, check=True)
        tmp_path.replace(mp3_path)
    except subprocess.CalledProcessError as exc:
        if tmp_path.exists():
            tmp_path.unlink()
        print(f"    Warning: ffmpeg pad failed on {mp3_path.name}: {exc}")


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
    parser.add_argument("--lane", type=str, default=None,
                        choices=["web", "kjv"],
                        help="Override translation lane (default: meta.languageStyle)")
    parser.add_argument("--lengths", type=str, default="short,full,long",
                        help="Comma-separated story lengths to generate audio for "
                             "(default: short,full,long). Use 'short' alone for Phase B "
                             "text-only Full/Long batches.")
    parser.add_argument("--skip-reflection", action="store_true",
                        help="Skip reflection audio generation.")
    parser.add_argument("--reflection-only", action="store_true",
                        help="Render only the reflection audio; skip all story lengths.")
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

    tts_model = meta.get("ttsModel", "eleven_turbo_v2_5")
    tts_voice_settings = meta.get(
        "ttsVoiceSettings",
        {"stability": 0.5, "similarity_boost": 0.75},
    )

    lane = (args.lane or meta.get("languageStyle", "WEB")).lower()

    # Build list of text files -> audio files.
    # WEB mp3s keep the canonical short-form name; KJV mp3s carry the lane suffix
    # so dual-lane stories produce both files without overwriting each other.
    requested_lengths = [] if args.reflection_only else [l.strip() for l in args.lengths.split(",") if l.strip()]
    audio_jobs = []
    for length in requested_lengths:
        txt_name = f"story_{sid}_{mode}_{lane}_{length}.txt"
        if lane == "web":
            mp3_name = f"audio_{sid}_story_{length}.mp3"
        else:
            mp3_name = f"audio_{sid}_story_{lane}_{length}.mp3"
        txt_path = outdir / txt_name
        if not txt_path.exists():
            print(f"WARNING: text file not found, skipping: {txt_name}")
            continue
        audio_jobs.append((txt_path, outdir / mp3_name, mp3_name))

    # Reflection — WEB keeps canonical name; KJV carries lane suffix
    # so dual-lane reflections produce both files without overwriting.
    refl_name = f"reflection_{sid}_{mode}_{lane}.txt"
    if lane == "web":
        refl_mp3 = f"audio_{sid}_reflection.mp3"
    else:
        refl_mp3 = f"audio_{sid}_reflection_{lane}.mp3"
    refl_path = outdir / refl_name
    if args.skip_reflection:
        pass
    elif refl_path.exists():
        audio_jobs.append((refl_path, outdir / refl_mp3, refl_mp3))
    else:
        print(f"WARNING: reflection not found, skipping: {refl_name}")

    print(f"  Mood: {meta.get('mood')} | Kid: {meta.get('kidFriendly', False)}")
    print(f"  Voice: {voice_key} ({voice_id[:8]}...)")
    print(f"  TTS model: {tts_model}")
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

        size = tts(text, mp3_path, voice_id, tts_model, tts_voice_settings)
        print(f"    {size:,} bytes")

    # Update metadata with the story voice key actually used, if it changed.
    # Reflections share the story narrator — do NOT write a separate
    # reflectionVoiceKey field (was creating drift; reflections are not a
    # separate voice system). Also strip any leaked reflectionVoiceKey
    # we read in, so post-run state stays clean.
    updated = False
    if meta.get("storyVoiceKey") != voice_key:
        meta["storyVoiceKey"] = voice_key
        updated = True
    if "reflectionVoiceKey" in meta:
        del meta["reflectionVoiceKey"]
        updated = True
    if updated:
        meta_file.write_text(json.dumps(meta, indent=2) + "\n")
        print(f"\n  Updated metadata storyVoiceKey to {voice_key}")

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
