#!/usr/bin/env python3
"""
Step 4A — Timeline era remap.

Remaps 5 off-vocabulary timelineEra values in per-story meta files and the
runtime manifest.json into the locked 12-era vocabulary used by PathService
(lib/services/path_service.dart -> TimelineEraParse).

Mapping (with biblical-chronology justification):
  early_monarchy   -> kingdom   (Saul/David/early-Samuel narratives — pre-split united kingdom)
  divided_monarchy -> kingdom   (1-2 Kings narratives after Solomon; locked vocab uses one kingdom era)
  pre_exile        -> prophets  (Jeremiah/Huldah/Josiah-era — prophetic-voice narratives leading up to Babylon)
  babylonian_exile -> exile     (Daniel + Lamentations + fall-of-Jerusalem narratives)
  persian_exile    -> return    (Esther/Ezra/Nehemiah + post-Babylonian Persian-period narratives)

Idempotent and reversible. Walks all per-story meta_<sid>.json files and the
top-level manifest.json. Reports counts of changes per mapping. Safe to re-run.
"""

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
TRADITIONAL_DIR = REPO_ROOT / "assets" / "stories" / "traditional"
MANIFEST_PATH = REPO_ROOT / "assets" / "stories" / "manifest.json"

ERA_REMAP: dict[str, str] = {
    "early_monarchy": "kingdom",
    "divided_monarchy": "kingdom",
    "pre_exile": "prophets",
    "babylonian_exile": "exile",
    "persian_exile": "return",
}


def remap_meta_files() -> Counter:
    """Walk per-story meta_<sid>.json; rewrite timelineEra in place where it
    matches an off-vocab value. Returns a Counter of (old, new) remap edges."""
    edges: Counter = Counter()
    for sid_dir in sorted(TRADITIONAL_DIR.iterdir()):
        if not sid_dir.is_dir():
            continue
        sid = sid_dir.name
        meta_path = sid_dir / f"meta_{sid}.json"
        if not meta_path.is_file():
            continue
        with meta_path.open() as f:
            meta = json.load(f)
        era = meta.get("timelineEra")
        if era in ERA_REMAP:
            new_era = ERA_REMAP[era]
            meta["timelineEra"] = new_era
            with meta_path.open("w") as f:
                json.dump(meta, f, indent=2)
                f.write("\n")
            edges[(era, new_era)] += 1
    return edges


def remap_manifest() -> Counter:
    """Rewrite manifest.json parable entries with off-vocab timelineEra values.
    Returns a Counter of (old, new) remap edges."""
    edges: Counter = Counter()
    with MANIFEST_PATH.open() as f:
        manifest = json.load(f)
    for entry in manifest.get("parables", []):
        era = entry.get("timelineEra")
        if era in ERA_REMAP:
            new_era = ERA_REMAP[era]
            entry["timelineEra"] = new_era
            edges[(era, new_era)] += 1
    if edges:
        with MANIFEST_PATH.open("w") as f:
            json.dump(manifest, f, indent=2)
            f.write("\n")
    return edges


def main() -> int:
    print("Step 4A — Timeline era remap")
    print(f"  repo: {REPO_ROOT}")
    print()

    print("Walking per-story meta files...")
    meta_edges = remap_meta_files()
    if meta_edges:
        for (old, new), n in sorted(meta_edges.items()):
            print(f"  meta:  {old:18s} -> {new:10s}  ({n} files)")
    else:
        print("  meta:  no off-vocab values found (idempotent re-run)")

    print()
    print("Rewriting manifest.json parable entries...")
    manifest_edges = remap_manifest()
    if manifest_edges:
        for (old, new), n in sorted(manifest_edges.items()):
            print(f"  manifest: {old:18s} -> {new:10s}  ({n} entries)")
    else:
        print("  manifest: no off-vocab values found (idempotent re-run)")

    print()
    print(f"Total per-story metas rewritten: {sum(meta_edges.values())}")
    print(f"Total manifest entries rewritten: {sum(manifest_edges.values())}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
