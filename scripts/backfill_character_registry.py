#!/usr/bin/env python3
"""
Backfill missing character_registry.json entries from manifest.json.

Conservative repair: every primaryCharacterId referenced by a manifest
entry must exist as a key in `assets/stories/character_registry.json`,
or `manifest_annotation_integrity_test::primaryCharacterId integrity`
fails. This script adds minimal entries for missing IDs using only data
already present in the manifest.

Entry shape (matches existing registry):
    {
      "displayName": "<from manifest.primaryCharacterDisplayName>",
      "descriptor":  ""
    }

Convention follows the 2026-05-09 `_stub: true` backfill pattern from
biblical_figure_registry.json (commit 40cbea8).

Guarantees:
- Existing entries preserved untouched.
- Idempotent: re-running once registry is in sync adds nothing.
- A summary report of every new key added is printed.

Usage:
    python3 scripts/backfill_character_registry.py
    python3 scripts/backfill_character_registry.py --dry-run
"""

from __future__ import annotations

import argparse
import json
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "assets" / "stories" / "manifest.json"
REGISTRY = ROOT / "assets" / "stories" / "character_registry.json"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text())
    registry = json.loads(REGISTRY.read_text())

    characters = registry["characters"]
    existing_ids = set(characters.keys())

    # Walk manifest and collect missing primaryCharacterIds.
    missing: dict[str, str] = {}  # id -> displayName
    for p in manifest["parables"]:
        cid = (p.get("primaryCharacterId") or "").strip()
        if not cid or cid == "jesus":
            continue  # jesus is reserved-not-listed per SPEC 50.3
        if cid in existing_ids or cid in missing:
            continue
        display = (p.get("primaryCharacterDisplayName") or "").strip()
        if not display:
            # No data to backfill safely — skip
            continue
        missing[cid] = display

    if not missing:
        print("Character registry already in sync with manifest. Nothing to add.")
        return

    print(f"Missing primaryCharacterIds in registry: {len(missing)}")
    print()
    print("New entries to add:")
    for cid in sorted(missing.keys()):
        print(f"  + {cid:<35s} {missing[cid]}")
    print()

    if args.dry_run:
        print("(dry-run) No changes written.")
        return

    today = date.today().isoformat()
    for cid in sorted(missing.keys()):
        characters[cid] = {
            "displayName": missing[cid],
            "descriptor": "",
            "_stub": True,
            "_stubReason": (
                f"Auto-generated {today} manifest backfill. "
                "displayName from manifest.primaryCharacterDisplayName. "
                "descriptor pending manual curation."
            ),
        }

    REGISTRY.write_text(json.dumps(registry, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote {REGISTRY}")
    print(f"Character registry total: {len(characters)}")


if __name__ == "__main__":
    main()
