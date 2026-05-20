#!/usr/bin/env python3
"""
backfill_life_situation_tags.py — Apply the v1 Life Situation Tags seed map
to per-story meta files.

Reads scripts/life_situation_seed_map.json and patches each referenced
meta_{id}.json with `primaryLifeSituationTags` and
`secondaryLifeSituationTags` fields.

Patch-only: never overwrites existing values. If a meta already has either
field, the script reports it as already-tagged and leaves it alone. This
mirrors the discipline of scripts/backfill_story_meta_tags.py.

Validates that every tag in the seed map appears in
assets/stories/life_situation_tags_registry.json before writing anything.
A seed-map tag that's only in scripts/life_situation_tags_drafts.json
will fail validation — drafts are not committable.

Usage:
  python3 scripts/backfill_life_situation_tags.py --dry-run
  python3 scripts/backfill_life_situation_tags.py
"""

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
REGISTRY = REPO_ROOT / "assets" / "stories" / "life_situation_tags_registry.json"
SEED_MAP = REPO_ROOT / "scripts" / "life_situation_seed_map.json"
STORIES_DIR = REPO_ROOT / "assets" / "stories" / "traditional"

MAX_PRIMARY = 2
MAX_SECONDARY = 3


def load_registry():
    with REGISTRY.open() as f:
        data = json.load(f)
    return {t["tagId"] for t in data["tags"]}


def load_seed_map():
    with SEED_MAP.open() as f:
        data = json.load(f)
    return data["entries"]


def validate_seed_against_registry(seed_map, allowed):
    """Fail-fast: every tag used in the seed map must be in the registry."""
    errors = []
    for story_id, entry in seed_map.items():
        primary = entry.get("primary", [])
        secondary = entry.get("secondary", [])

        if len(primary) > MAX_PRIMARY:
            errors.append(
                f"story {story_id}: primary has {len(primary)} tags (max {MAX_PRIMARY})"
            )
        if len(secondary) > MAX_SECONDARY:
            errors.append(
                f"story {story_id}: secondary has {len(secondary)} tags (max {MAX_SECONDARY})"
            )

        overlap = set(primary) & set(secondary)
        if overlap:
            errors.append(
                f"story {story_id}: tags appear in both primary and secondary: {sorted(overlap)}"
            )

        for tag in primary + secondary:
            if tag not in allowed:
                errors.append(
                    f"story {story_id}: tag '{tag}' not in registry "
                    f"(may be in drafts — drafts are NOT committable)"
                )

        if len(set(primary)) != len(primary):
            errors.append(f"story {story_id}: duplicate tag in primary")
        if len(set(secondary)) != len(secondary):
            errors.append(f"story {story_id}: duplicate tag in secondary")

    return errors


def find_meta_path(story_id):
    return STORIES_DIR / story_id / f"meta_{story_id}.json"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would change without writing anything",
    )
    args = parser.parse_args()

    allowed = load_registry()
    seed_map = load_seed_map()

    errors = validate_seed_against_registry(seed_map, allowed)
    if errors:
        print("Seed map validation FAILED:", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        sys.exit(1)

    print(f"Seed map: {len(seed_map)} stories, all tags valid against registry.")
    print()

    patched = []
    already_tagged = []
    missing = []

    for story_id, entry in sorted(seed_map.items(), key=lambda kv: int(kv[0])):
        meta_path = find_meta_path(story_id)
        if not meta_path.exists():
            missing.append(story_id)
            continue

        with meta_path.open() as f:
            meta = json.load(f)

        has_primary = "primaryLifeSituationTags" in meta
        has_secondary = "secondaryLifeSituationTags" in meta

        if has_primary or has_secondary:
            already_tagged.append(story_id)
            continue

        new_meta = dict(meta)
        new_meta["primaryLifeSituationTags"] = entry["primary"]
        new_meta["secondaryLifeSituationTags"] = entry["secondary"]

        if args.dry_run:
            patched.append(
                (story_id, entry["primary"], entry["secondary"], "WOULD PATCH")
            )
        else:
            with meta_path.open("w", encoding="utf-8") as f:
                json.dump(new_meta, f, indent=2, ensure_ascii=False)
                f.write("\n")
            patched.append((story_id, entry["primary"], entry["secondary"], "PATCHED"))

    for story_id, primary, secondary, status in patched:
        print(f"  [{status}] {story_id}: primary={primary} secondary={secondary}")

    print()
    print(f"Summary:")
    print(f"  Patched:        {len(patched)}")
    print(f"  Already tagged: {len(already_tagged)}")
    print(f"  Missing meta:   {len(missing)}")

    if already_tagged:
        print(f"\n  Already-tagged story IDs: {already_tagged}")
    if missing:
        print(f"\n  Missing meta IDs: {missing}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
