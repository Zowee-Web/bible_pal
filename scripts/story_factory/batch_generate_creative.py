#!/usr/bin/env python3
"""
batch_generate_creative.py — Batch orchestrator for Bible PAL Creative Story Factory.

Generates one creative story per mood using the generate_creative_story.py pipeline.
Each story gets all 3 length variants + reflection + audio.

Engine: Gemma 7B via Ollama (local ONLY).

Usage:
    python3 scripts/story_factory/batch_generate_creative.py --lane web --voice_key VOICE_JAMES_HUSKY
    python3 scripts/story_factory/batch_generate_creative.py --lane web --voice_key VOICE_JAMES_HUSKY --dry-run
    python3 scripts/story_factory/batch_generate_creative.py --lane web --voice_key VOICE_JAMES_HUSKY --skip-audio

Requires: ELEVENLABS_API_KEY in .env (unless --skip-audio)
Requires: Ollama running locally with gemma:7b model
"""

import argparse
import json
import pathlib
import subprocess
import sys
import time

# ── Configuration ─────────────────────────────────────────────────────────

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
GENERATOR_SCRIPT = REPO_ROOT / "scripts" / "story_factory" / "generate_creative_story.py"
THEMES_FILE = REPO_ROOT / "used_creative_themes.json"

# 5 canonical moods (from mood_service.dart)
CANONICAL_MOODS = ["joyful", "weary", "anxious", "hurting", "neutral"]

# Curated theme suggestions per mood.
# Each theme is a short phrase describing the story's emotional/thematic focus.
# The batch runner picks the first unused theme for each mood.
THEME_SUGGESTIONS = {
    "joyful": [
        "finding unexpected joy in small acts of kindness",
        "a community garden that brings neighbors together",
        "a child who discovers the gift of gratitude",
        "two strangers who share a meal and find friendship",
        "an artist who paints hope for a weary town",
        "a baker whose bread feeds more than hunger",
        "a letter of encouragement that travels far",
        "a family tradition that reconnects generations",
    ],
    "weary": [
        "a tired traveler who finds rest in an unlikely place",
        "a farmer who waits patiently through a long dry season",
        "a nurse who cares for others while learning to accept care",
        "an old craftsman teaching patience to an eager apprentice",
        "a mother who finds strength in quiet evening moments",
        "a fisherman who learns that stillness is not emptiness",
        "a teacher at the end of a long year who finds renewal",
        "a lighthouse keeper who discovers rest in routine",
    ],
    "anxious": [
        "a potter who learns to trust the process of shaping clay",
        "a young musician facing stage fright before a recital",
        "a sailor navigating fog who finds calm in steady hands",
        "a child moving to a new town who finds belonging",
        "a gardener who learns not every seed sprouts on schedule",
        "a builder whose plans change but whose foundation holds",
        "a bird learning to fly after many failed attempts",
        "a shopkeeper who opens doors despite uncertain times",
    ],
    "hurting": [
        "a widow who plants a garden in memory of her husband",
        "a carpenter who repairs broken things and broken hearts",
        "an old friend who returns after years of silence",
        "a village that rebuilds after a storm with gentleness",
        "a child who learns that tears water the ground for growth",
        "a musician who finds a new song after losing their voice",
        "a shepherd who carries a lamb that cannot walk",
        "a candlemaker whose light persists through the longest night",
    ],
    "neutral": [
        "a walk through an ordinary morning that reveals small wonders",
        "a librarian who matches people with the stories they need",
        "a bridge builder who connects two villages across a river",
        "a clockmaker who finds meaning in keeping faithful time",
        "a beekeeper who tends hives and tends to neighbors",
        "an innkeeper who welcomes travelers without asking their story",
        "a weaver who sees patterns in everyday threads",
        "a mapmaker who charts paths others have walked",
    ],
}


def load_used_themes() -> set:
    """Load the set of already-used theme keys (mood:theme pairs)."""
    if not THEMES_FILE.exists():
        return set()
    return set(json.loads(THEMES_FILE.read_text()))


def find_next_story_id() -> int:
    """Find the next available story ID in the creative directory."""
    creative_dir = REPO_ROOT / "assets" / "stories" / "creative"
    if not creative_dir.exists():
        return 501  # Creative IDs start at 501
    existing = []
    for d in creative_dir.iterdir():
        if d.is_dir() and d.name.isdigit():
            existing.append(int(d.name))
    if not existing:
        return 501
    return max(existing) + 1


def pick_theme(mood: str, used: set) -> str | None:
    """Pick the first unused theme for the given mood."""
    suggestions = THEME_SUGGESTIONS.get(mood, [])
    for theme in suggestions:
        key = f"{mood}:{theme}"
        if key not in used:
            return theme
    return None


def run_generator(
    story_id: int,
    theme: str,
    mood: str,
    lane: str,
    voice_key: str,
    batch: str,
    skip_audio: bool = False,
) -> tuple[bool, float]:
    """Run generate_creative_story.py for one story. Returns (success, elapsed_seconds)."""
    cmd = [
        sys.executable,
        str(GENERATOR_SCRIPT),
        "--story_id", str(story_id),
        "--theme", theme,
        "--mood", mood,
        "--lane", lane,
        "--voice_key", voice_key,
        "--batch", batch,
    ]
    if skip_audio:
        cmd.append("--skip-audio")
    start = time.time()
    result = subprocess.run(cmd, capture_output=False)
    elapsed = time.time() - start
    return result.returncode == 0, elapsed


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Batch-generate Creative Bible PAL stories for all moods."
    )
    parser.add_argument("--lane", type=str, required=True, choices=["web", "kjv"],
                        help="Language lane (web = modern, kjv = classic)")
    parser.add_argument("--voice_key", type=str, required=True,
                        help="Env var name for ElevenLabs voice, e.g. VOICE_JAMES_HUSKY")
    parser.add_argument("--batch", type=str, default="PAL_CREATIVE_BATCH",
                        help="Generation batch label")
    parser.add_argument("--moods", type=str, nargs="*", default=None,
                        help="Subset of moods to generate (default: all 5)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print plan without generating anything")
    parser.add_argument("--skip-audio", action="store_true",
                        help="Skip TTS audio generation (text only)")
    args = parser.parse_args()

    moods = args.moods if args.moods else CANONICAL_MOODS
    for m in moods:
        if m not in CANONICAL_MOODS:
            print(f"ERROR: Unknown mood {m!r}. Valid: {CANONICAL_MOODS}")
            return 1

    used_themes = load_used_themes()
    next_id = find_next_story_id()

    # Build generation plan
    plan = []
    for i, mood in enumerate(moods):
        theme = pick_theme(mood, used_themes)
        if theme is None:
            print(f"WARNING: No unused themes for mood {mood!r} — skipping")
            continue
        story_id = next_id + i
        plan.append({"story_id": story_id, "mood": mood, "theme": theme})
        # Mark theme as "planned" so subsequent moods don't pick it
        used_themes.add(f"{mood}:{theme}")

    if not plan:
        print("No stories to generate (all themes exhausted).")
        return 1

    # Print plan
    print(f"\n{'='*70}")
    print(f"  Bible PAL Creative Batch Generation Plan")
    print(f"  Engine: Gemma 7B via Ollama (local)")
    print(f"  Lane: {args.lane} | Voice: {args.voice_key} | Batch: {args.batch}")
    if args.skip_audio:
        print(f"  Audio: SKIPPED (--skip-audio)")
    print(f"{'='*70}")
    for entry in plan:
        print(f"  [{entry['story_id']}] {entry['mood']:10s} -> {entry['theme'][:55]}")
    print(f"{'='*70}\n")

    if args.dry_run:
        print("DRY RUN — no stories generated.")
        return 0

    # Execute
    results = []
    total_start = time.time()

    for entry in plan:
        print(f"\n{'─'*70}")
        print(f"  Generating creative story {entry['story_id']} ({entry['mood']}) ...")
        print(f"  Theme: {entry['theme']}")
        print(f"{'─'*70}\n")

        success, elapsed = run_generator(
            story_id=entry["story_id"],
            theme=entry["theme"],
            mood=entry["mood"],
            lane=args.lane,
            voice_key=args.voice_key,
            batch=args.batch,
            skip_audio=args.skip_audio,
        )
        results.append({
            **entry,
            "success": success,
            "elapsed": round(elapsed, 1),
        })

        status = "OK" if success else "FAILED"
        print(f"\n  -> {status} ({elapsed:.1f}s)")

    total_elapsed = time.time() - total_start

    # Summary report
    print(f"\n{'='*70}")
    print(f"  CREATIVE BATCH SUMMARY")
    print(f"{'='*70}")
    successes = sum(1 for r in results if r["success"])
    failures = sum(1 for r in results if not r["success"])
    for r in results:
        status = "OK" if r["success"] else "FAIL"
        theme_short = r["theme"][:40] + "…" if len(r["theme"]) > 40 else r["theme"]
        print(f"  [{status}] {r['story_id']} {r['mood']:10s} {theme_short:42s} ({r['elapsed']}s)")
    print(f"{'─'*70}")
    print(f"  Total: {successes} succeeded, {failures} failed, {total_elapsed:.1f}s elapsed")
    print(f"{'='*70}\n")

    # Write summary JSON
    summary_file = REPO_ROOT / "scripts" / "story_factory" / "creative_batch_summary.json"
    summary = {
        "batch": args.batch,
        "lane": args.lane,
        "engine": "gemma:7b",
        "voiceKey": args.voice_key,
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "results": results,
        "totals": {
            "succeeded": successes,
            "failed": failures,
            "elapsedSeconds": round(total_elapsed, 1),
        },
    }
    summary_file.write_text(json.dumps(summary, indent=2) + "\n")
    print(f"Summary written to {summary_file}")

    return 1 if failures > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
