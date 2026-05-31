#!/usr/bin/env python3
"""
Backfill missing biblical_figure_registry.json entries from manifest.json.

Conservative repair: every traditional bibleStoryKey in the manifest must
have a corresponding registry entry, or the
biblical_figure_registry_test.dart cross-validation test fails. This
script adds a minimal stub for each missing key, using only data
already present in the manifest.

Stub shape (matches the precedent from 2026-05-09 batch):
    {
      "bibleStoryKey": "<from manifest>",
      "primaryFigure":  "<manifest.primaryCharacterDisplayName>",
      "secondaryFigures": [],
      "framingLines":   [],
      "bibleSourceRef": "<manifest.bibleSourceRef>",
      "_stub":          true,
      "_stubReason":    "Auto-generated <DATE> manifest backfill. ..."
    }

Guarantees:
- Existing entries are preserved untouched (we never modify, only append).
- The script is idempotent — re-running adds nothing once all keys are covered.
- New entries are inserted in alphabetical bibleStoryKey order at the end.
- A report of every new key is printed.

Usage:
    python3 scripts/backfill_figure_registry.py            # do the backfill
    python3 scripts/backfill_figure_registry.py --dry-run  # report only
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "assets" / "stories" / "manifest.json"
REGISTRY = ROOT / "assets" / "stories" / "biblical_figure_registry.json"

STUB_REASON_TEMPLATE = (
    "Auto-generated {date} manifest backfill. "
    "primaryFigure copied from manifest.primaryCharacterDisplayName. "
    "secondaryFigures and framingLines pending manual curation. "
    "App should treat _stub:true entries as placeholders (no Paths UI surface)."
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would be added, don't write")
    args = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text())
    registry = json.loads(REGISTRY.read_text())

    existing_keys: set[str] = {
        e["bibleStoryKey"] for e in registry["entries"]
    }

    # Collect missing keys + their best manifest source row (use first match)
    missing: dict[str, dict] = {}  # key -> manifest row
    for p in manifest["parables"]:
        if p.get("storytellingMode") != "traditional":
            continue
        key = p.get("bibleStoryKey")
        if not key:
            continue
        if key in existing_keys:
            continue
        if key in missing:
            continue
        missing[key] = p

    if not missing:
        print("Registry already in sync with manifest. No entries added.")
        return

    print(f"Manifest traditional keys missing from registry: {len(missing)}")
    print()

    # Build stubs
    today = date.today().isoformat()
    new_entries = []
    skipped = []
    for key in sorted(missing.keys()):
        row = missing[key]
        primary = (row.get("primaryCharacterDisplayName") or "").strip()
        if not primary:
            skipped.append((key, "missing primaryCharacterDisplayName"))
            continue
        stub = {
            "bibleStoryKey": key,
            "primaryFigure": primary,
            "secondaryFigures": [],
            "framingLines": [],
            "bibleSourceRef": row.get("bibleSourceRef", ""),
            "_stub": True,
            "_stubReason": STUB_REASON_TEMPLATE.format(date=today),
        }
        new_entries.append(stub)

    print(f"Stubs to add: {len(new_entries)}")
    if skipped:
        print(f"Skipped (insufficient data): {len(skipped)}")
        for k, why in skipped[:5]:
            print(f"  - {k}: {why}")
        if len(skipped) > 5:
            print(f"  ... and {len(skipped)-5} more")
        print()

    print("First 10 new keys:")
    for stub in new_entries[:10]:
        print(f"  + {stub['bibleStoryKey']}  → {stub['primaryFigure']}")
    if len(new_entries) > 10:
        print(f"  ... and {len(new_entries) - 10} more")
    print()

    if args.dry_run:
        print("(dry-run) No changes written.")
        return

    # Append + write back
    registry["entries"].extend(new_entries)

    # Update _stubsNote so the provenance trail is preserved
    note = (
        f"{today}: Manifest-sync backfill — appended {len(new_entries)} "
        "stub entries (each marked _stub:true) so every traditional "
        "bibleStoryKey in manifest.json has a registry entry. "
        f"Previous note: {registry.get('_stubsNote', '')}"
    ).strip()
    registry["_stubsNote"] = note

    REGISTRY.write_text(json.dumps(registry, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote {REGISTRY}")
    print(f"Registry entry count: {len(registry['entries'])}")


if __name__ == "__main__":
    main()
