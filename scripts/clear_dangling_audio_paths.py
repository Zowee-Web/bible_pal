#!/usr/bin/env python3
"""
Clear dangling audioFilePath references in manifest.json.

The manifest_integrity_test contract is: if audioFilePath is set
(non-empty), the file must exist. The register_grow_stories.py script
used during Tier 0/1/2 created canonical-but-not-yet-rendered paths
proactively; since audio render remains gated, the test fails on those.

This script sets audioFilePath to "" for any manifest entry where the
referenced .mp3 does not exist on disk. Existing valid paths are
preserved. The fix is reversible — once audio is rendered, a follow-up
script can repopulate audioFilePath from the canonical convention.

Usage:
    python3 scripts/clear_dangling_audio_paths.py
    python3 scripts/clear_dangling_audio_paths.py --dry-run
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets" / "stories"
MANIFEST = ASSETS / "manifest.json"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text())
    parables = manifest.get("parables", [])

    cleared = []
    for entry in parables:
        audio = entry.get("audioFilePath", "") or ""
        if not audio:
            continue
        on_disk = ASSETS / audio
        if on_disk.exists():
            continue
        # Dangling path — clear it
        cleared.append(
            (entry.get("storyId", "?"), audio)
        )
        if not args.dry_run:
            entry["audioFilePath"] = ""

    print(f"Dangling audioFilePath references: {len(cleared)}")
    by_story = {}
    for sid, path in cleared:
        # Extract story id token
        token = sid.split("_")[1] if "_" in sid else sid
        by_story.setdefault(token, []).append(path)
    print(f"Across {len(by_story)} unique story IDs")
    if cleared[:5]:
        print("\nFirst 5 examples:")
        for sid, path in cleared[:5]:
            print(f"  {sid}: {path}")

    if args.dry_run:
        print("\n(dry-run) No changes written.")
        return

    MANIFEST.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    print(f"\nWrote {MANIFEST}")


if __name__ == "__main__":
    main()
