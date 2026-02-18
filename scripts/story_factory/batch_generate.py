#!/usr/bin/env python3
"""
batch_generate.py — Batch orchestrator for Bible PAL Traditional Story Factory.

Generates one story per mood using the existing generate_traditional_story.py
pipeline. Each story gets all 3 length variants + reflection + audio.

Usage:
    python3 scripts/story_factory/batch_generate.py --lane web --voice_key VOICE_JAMES_HUSKY
    python3 scripts/story_factory/batch_generate.py --lane web --voice_key VOICE_JAMES_HUSKY --dry-run

Requires: OPENAI_API_KEY and ELEVENLABS_API_KEY in .env
"""

import argparse
import json
import pathlib
import subprocess
import sys
import time

# ── Configuration ─────────────────────────────────────────────────────────

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
GENERATOR_SCRIPT = REPO_ROOT / "scripts" / "story_factory" / "generate_traditional_story.py"
ANCHORS_FILE = REPO_ROOT / "used_scripture_anchors.json"

# 5 canonical moods (from mood_service.dart)
CANONICAL_MOODS = ["joyful", "weary", "anxious", "hurting", "neutral"]

# Curated anchor suggestions per mood.
# The batch runner picks the first unused anchor for each mood.
# Add more anchors here as the library grows.
ANCHOR_SUGGESTIONS = {
    "joyful": [
        "Psalm 100",
        "Luke 15:11\u201332",
        "Psalm 150",
        "Zephaniah 3:17",
        "Psalm 30",
        "Luke 15:3\u20137",
        "Psalm 126",
        "John 15:9\u201311",
    ],
    "weary": [
        "Matthew 11:28\u201330",
        "Psalm 23",
        "Isaiah 40:28\u201331",
        "Psalm 62",
        "Matthew 14:13\u201321",
        "1 Kings 19:1\u20138",
        "Psalm 127:1\u20132",
        "Exodus 33:14",
    ],
    "anxious": [
        "Psalm 46",
        "Mark 4:35\u201341",
        "Philippians 4:6\u20137",
        "Matthew 6:25\u201334",
        "Psalm 56",
        "Isaiah 41:10",
        "Psalm 27",
        "Joshua 1:9",
    ],
    "hurting": [
        "Psalm 34:18",
        "John 11:1\u201344",
        "Psalm 147:3",
        "2 Corinthians 1:3\u20134",
        "Psalm 22:1\u201311",
        "Ruth 1:16\u201317",
        "Lamentations 3:22\u201323",
        "Isaiah 53:3\u20135",
    ],
    "neutral": [
        "Romans 8:28",
        "Ecclesiastes 3:1\u20138",
        "Proverbs 3:5\u20136",
        "Psalm 1",
        "Genesis 1:1\u20135",
        "Matthew 13:31\u201332",
        "Psalm 19:1\u20136",
        "Proverbs 16:9",
    ],
}


def load_used_anchors() -> set:
    """Load the set of already-used scripture anchors."""
    if not ANCHORS_FILE.exists():
        return set()
    return set(json.loads(ANCHORS_FILE.read_text()))


def find_next_story_id() -> int:
    """Find the next available story ID in the traditional directory."""
    trad_dir = REPO_ROOT / "assets" / "stories" / "traditional"
    if not trad_dir.exists():
        return 901  # Start batch IDs at 901
    existing = []
    for d in trad_dir.iterdir():
        if d.is_dir() and d.name.isdigit():
            existing.append(int(d.name))
    if not existing:
        return 901
    return max(existing) + 1


def pick_anchor(mood: str, used: set) -> str | None:
    """Pick the first unused anchor for the given mood."""
    suggestions = ANCHOR_SUGGESTIONS.get(mood, [])
    for anchor in suggestions:
        if anchor not in used:
            return anchor
    return None


def run_generator(
    story_id: int,
    anchor: str,
    mood: str,
    lane: str,
    voice_key: str,
    batch: str,
) -> tuple[bool, float]:
    """Run generate_traditional_story.py for one story. Returns (success, elapsed_seconds)."""
    cmd = [
        sys.executable,
        str(GENERATOR_SCRIPT),
        "--story_id", str(story_id),
        "--anchor", anchor,
        "--mood", mood,
        "--lane", lane,
        "--voice_key", voice_key,
        "--batch", batch,
    ]
    start = time.time()
    result = subprocess.run(cmd, capture_output=False)
    elapsed = time.time() - start
    return result.returncode == 0, elapsed


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Batch-generate Traditional Bible PAL stories for all moods."
    )
    parser.add_argument("--lane", type=str, required=True, choices=["web", "kjv"],
                        help="Language lane (web = modern, kjv = classic)")
    parser.add_argument("--voice_key", type=str, required=True,
                        help="Env var name for ElevenLabs voice, e.g. VOICE_JAMES_HUSKY")
    parser.add_argument("--batch", type=str, default="PAL_TRADITIONAL_BATCH",
                        help="Generation batch label")
    parser.add_argument("--moods", type=str, nargs="*", default=None,
                        help="Subset of moods to generate (default: all 5)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print plan without generating anything")
    args = parser.parse_args()

    moods = args.moods if args.moods else CANONICAL_MOODS
    for m in moods:
        if m not in CANONICAL_MOODS:
            print(f"ERROR: Unknown mood {m!r}. Valid: {CANONICAL_MOODS}")
            return 1

    used_anchors = load_used_anchors()
    next_id = find_next_story_id()

    # Build generation plan
    plan = []
    for i, mood in enumerate(moods):
        anchor = pick_anchor(mood, used_anchors)
        if anchor is None:
            print(f"WARNING: No unused anchors for mood {mood!r} — skipping")
            continue
        story_id = next_id + i
        plan.append({"story_id": story_id, "mood": mood, "anchor": anchor})
        # Mark anchor as "planned" so subsequent moods don't pick it
        used_anchors.add(anchor)

    if not plan:
        print("No stories to generate (all anchors exhausted).")
        return 1

    # Print plan
    print(f"\n{'='*60}")
    print(f"  Bible PAL Batch Generation Plan")
    print(f"  Lane: {args.lane} | Voice: {args.voice_key} | Batch: {args.batch}")
    print(f"{'='*60}")
    for entry in plan:
        print(f"  [{entry['story_id']}] {entry['mood']:10s} -> {entry['anchor']}")
    print(f"{'='*60}\n")

    if args.dry_run:
        print("DRY RUN — no stories generated.")
        return 0

    # Execute
    results = []
    total_start = time.time()

    for entry in plan:
        print(f"\n{'─'*60}")
        print(f"  Generating story {entry['story_id']} ({entry['mood']}) ...")
        print(f"  Anchor: {entry['anchor']}")
        print(f"{'─'*60}\n")

        success, elapsed = run_generator(
            story_id=entry["story_id"],
            anchor=entry["anchor"],
            mood=entry["mood"],
            lane=args.lane,
            voice_key=args.voice_key,
            batch=args.batch,
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
    print(f"\n{'='*60}")
    print(f"  BATCH SUMMARY")
    print(f"{'='*60}")
    successes = sum(1 for r in results if r["success"])
    failures = sum(1 for r in results if not r["success"])
    for r in results:
        status = "OK" if r["success"] else "FAIL"
        print(f"  [{status}] {r['story_id']} {r['mood']:10s} {r['anchor']:30s} ({r['elapsed']}s)")
    print(f"{'─'*60}")
    print(f"  Total: {successes} succeeded, {failures} failed, {total_elapsed:.1f}s elapsed")
    print(f"{'='*60}\n")

    # Write summary JSON
    summary_file = REPO_ROOT / "scripts" / "story_factory" / "batch_summary.json"
    summary = {
        "batch": args.batch,
        "lane": args.lane,
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
