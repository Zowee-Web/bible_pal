#!/usr/bin/env python3
"""
Backfill scripture text files for all Traditional stories.

Scans all directories under assets/stories/traditional/ and processes every
meta_*.json found. Does NOT assume batch counts, ID ranges, or hardcode lists.

For each story:
  1. Reads scriptureAnchor from meta file
  2. Parses the reference
  3. Extracts verse text from bundled Bible JSON
  4. Writes scripture_{id}_{lang}.txt with reference header

Also updates manifest.json with scriptureTextFilePath for each traditional entry.

Usage:
  python3 scripts/backfill_scripture_text.py              # full run
  python3 scripts/backfill_scripture_text.py --dry-run     # preview only
  python3 scripts/backfill_scripture_text.py --story-id 1031  # single story

STRICT validation: fails loudly on ambiguous refs, logs all failures,
exits non-zero if any failures occur.
"""

import argparse
import glob
import json
import os
import sys
from datetime import datetime

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
sys.path.insert(0, SCRIPT_DIR)

from lib.bible_ref_parser import parse_bible_ref, parse_bible_refs, extract_verses, format_scripture_text

TRADITIONAL_DIR = os.path.join(PROJECT_ROOT, "assets", "stories", "traditional")
BIBLE_DATA_DIR = os.path.join(PROJECT_ROOT, "server", "data")
MANIFEST_PATH = os.path.join(PROJECT_ROOT, "assets", "stories", "manifest.json")
FAILURE_LOG = os.path.join(SCRIPT_DIR, "backfill_failures.log")


def load_bible(lang: str) -> dict:
    """Load bundled Bible JSON for a translation."""
    path = os.path.join(BIBLE_DATA_DIR, f"bible_{lang}.json")
    if not os.path.exists(path):
        print(f"ERROR: Bible data not found: {path}", file=sys.stderr)
        sys.exit(1)
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def discover_meta_files(story_id: int = None) -> list[str]:
    """
    Discover all meta files by scanning directories.
    Does NOT assume ID ranges or batch counts.
    """
    if story_id is not None:
        pattern = os.path.join(TRADITIONAL_DIR, str(story_id), f"meta_{story_id}.json")
        matches = glob.glob(pattern)
        if not matches:
            print(f"ERROR: No meta file found for story {story_id}", file=sys.stderr)
            sys.exit(1)
        return matches

    pattern = os.path.join(TRADITIONAL_DIR, "*", "meta_*.json")
    return sorted(glob.glob(pattern))


def get_lang_for_story(meta: dict) -> str:
    """Determine the translation language for a story."""
    lang = meta.get("primaryLanguageStyle", "").lower()
    if lang in ("web", "kjv"):
        return lang
    # Legacy stories (800-series) don't have primaryLanguageStyle
    # Default to WEB
    return "web"


def main():
    parser = argparse.ArgumentParser(description="Backfill scripture text files")
    parser.add_argument("--dry-run", action="store_true", help="Preview only, don't write files")
    parser.add_argument("--story-id", type=int, help="Process a single story")
    args = parser.parse_args()

    # Load Bible data
    print("Loading Bible data...")
    bibles = {}
    for lang in ("web", "kjv"):
        bible_path = os.path.join(BIBLE_DATA_DIR, f"bible_{lang}.json")
        if os.path.exists(bible_path):
            bibles[lang] = load_bible(lang)
            print(f"  {lang.upper()}: {len(bibles[lang]['books'])} books loaded")
        else:
            print(f"  {lang.upper()}: not found (skipping)")

    if not bibles:
        print("ERROR: No Bible data files found", file=sys.stderr)
        sys.exit(1)

    # Discover meta files
    meta_files = discover_meta_files(args.story_id)
    print(f"\nFound {len(meta_files)} traditional meta files")
    print()

    success_count = 0
    failure_count = 0
    skip_count = 0
    failures = []

    for meta_path in meta_files:
        with open(meta_path, "r", encoding="utf-8") as f:
            meta = json.load(f)

        sid = meta.get("storyId", "?")
        ref_str = meta.get("scriptureAnchor", "")
        primary_lang = get_lang_for_story(meta)
        story_dir = os.path.dirname(meta_path)

        # Build list of languages to generate: primary + any additional lanes
        lanes = meta.get("lanes", [])
        langs_to_generate = [primary_lang]
        for lane in lanes:
            lane_lower = lane.lower()
            if lane_lower in ("web", "kjv") and lane_lower != primary_lang:
                langs_to_generate.append(lane_lower)

        if not ref_str:
            print(f"  {sid}: SKIP (no scriptureAnchor)")
            skip_count += 1
            continue

        for lang in langs_to_generate:
            if lang not in bibles:
                msg = f"Bible data for {lang.upper()} not available"
                print(f"  {sid}: FAIL — {msg}")
                failures.append((sid, ref_str, msg))
                failure_count += 1
                continue

            try:
                refs = parse_bible_refs(ref_str)
                # Concatenate verses from all sub-refs in order
                all_verses: list[tuple[int, int, str]] = []
                for sub_ref in refs:
                    all_verses.extend(extract_verses(bibles[lang], sub_ref))
                # Use the first ref for display (concise header). If multi-ref,
                # the header reflects the original combined string.
                if len(refs) == 1:
                    text = format_scripture_text(refs[0], all_verses, lang.upper())
                else:
                    # Multi-range: use the original ref_str in header
                    text_lines = [f"{ref_str} ({lang.upper()})", ""]
                    for ch, v, t in all_verses:
                        text_lines.append(f"{v} {t}")
                    text = "\n".join(text_lines) + "\n"

                output_file = f"scripture_{sid}_{lang}.txt"
                output_path = os.path.join(story_dir, output_file)

                if args.dry_run:
                    print(f"  {sid}: OK — {ref_str} ({lang.upper()}, {len(all_verses)} verses) → {output_file}")
                else:
                    with open(output_path, "w", encoding="utf-8") as f:
                        f.write(text)
                    print(f"  {sid}: WROTE {output_file} ({len(all_verses)} verses)")

                success_count += 1

            except ValueError as e:
                msg = str(e)
                print(f"  {sid}: FAIL — {msg}")
                failures.append((sid, ref_str, msg))
                failure_count += 1

    # Update manifest if not dry run
    if not args.dry_run and success_count > 0:
        print("\nUpdating manifest.json...")
        update_manifest(bibles)

    # Summary
    print(f"\n{'=' * 50}")
    print(f"SUMMARY {'(DRY RUN)' if args.dry_run else ''}")
    print(f"  Success: {success_count}")
    print(f"  Failed:  {failure_count}")
    print(f"  Skipped: {skip_count}")
    print(f"  Total:   {success_count + failure_count + skip_count}")

    # Write failure log
    if failures:
        with open(FAILURE_LOG, "w", encoding="utf-8") as f:
            f.write(f"Backfill failures — {datetime.now().isoformat()}\n\n")
            for sid, ref_str, msg in failures:
                f.write(f"Story {sid} | ref: {ref_str} | error: {msg}\n")
        print(f"\n  Failure log written to: {FAILURE_LOG}")
        print(f"\n  EXITING WITH ERROR — {failure_count} failures detected")
        sys.exit(1)
    else:
        # Clean up old failure log
        if os.path.exists(FAILURE_LOG):
            os.remove(FAILURE_LOG)
        print("\n  All references processed successfully.")


def update_manifest(bibles: dict):
    """Add scriptureTextFilePath to traditional entries in manifest.json."""
    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    updated = 0
    for entry in manifest.get("parables", []):
        if entry.get("storytellingMode") != "traditional":
            continue

        # Derive the scripture text file path from existing fields
        # storyId format: "story_1031_weary_short_kid_traditional"
        # We need the numeric ID from the entry
        sid_str = entry.get("storyId", "")
        # Extract numeric ID from textFilePath which is like "traditional/1031/story_..."
        text_path = entry.get("textFilePath", "")
        if not text_path:
            continue

        # Parse story dir from textFilePath
        parts = text_path.split("/")
        if len(parts) < 2:
            continue
        numeric_id = parts[1]  # e.g. "1031"

        lang = entry.get("languageStyle", "WEB").lower()
        if lang not in bibles:
            lang = "web"

        scripture_file = f"scripture_{numeric_id}_{lang}.txt"
        scripture_path = f"traditional/{numeric_id}/{scripture_file}"

        # Check if file exists; fall back to WEB if KJV file not found
        full_path = os.path.join(PROJECT_ROOT, "assets", "stories", scripture_path)
        if not os.path.exists(full_path) and lang != "web":
            scripture_file = f"scripture_{numeric_id}_web.txt"
            scripture_path = f"traditional/{numeric_id}/{scripture_file}"
            full_path = os.path.join(PROJECT_ROOT, "assets", "stories", scripture_path)

        if os.path.exists(full_path):
            entry["scriptureTextFilePath"] = scripture_path
            updated += 1

    with open(MANIFEST_PATH, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"  Updated {updated} manifest entries with scriptureTextFilePath")


if __name__ == "__main__":
    main()
