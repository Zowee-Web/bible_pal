#!/usr/bin/env python3
"""
Backfill manifest `bibleSourceRef` from each story's scripture text file.

Source of truth: the first line of the per-story scripture text file
(e.g. "Joshua 6:1-21 (WEB)"), which the app already serves verbatim in the
Scripture Sources bottom sheet (SPEC Feature 12). A batch (story IDs
1492-1521) was written with a placeholder `bibleSourceRef` of
"Lamentations 3:55-58" while every other field (bibleStoryKey, character,
title, scripture text, per-story meta.json, anchor registry) is correct.
This realigns the one corrupted manifest field to the on-disk truth.

Conservative: only rewrites entries whose current bibleSourceRef differs
from the scripture-file ref. Idempotent: a clean run reports 0 changes.
Formatting: re-dumps with indent=2, ensure_ascii=True, which is a
byte-identical round-trip for this manifest, so the diff is limited to the
changed lines.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STORIES = ROOT / "assets" / "stories"
MANIFEST = STORIES / "manifest.json"

TRANS_SUFFIX = re.compile(r"\s*\((?:WEB|KJV|ASV|YLT|DRA)\)\s*$")


def true_ref(scripture_rel_path: str) -> str | None:
    """Return the bare scripture reference from a scripture file's first line."""
    if not scripture_rel_path:
        return None
    p = Path(scripture_rel_path)
    if not p.is_absolute():
        # paths in manifest are relative to assets/stories
        p = STORIES / scripture_rel_path.replace("assets/stories/", "")
    if not p.exists():
        return None
    first = p.open(encoding="utf-8").readline().strip()
    return TRANS_SUFFIX.sub("", first).strip() or None


def main() -> int:
    raw = MANIFEST.read_text(encoding="utf-8")
    data = json.loads(raw)
    parables = data["parables"]

    changes = []
    missing = []
    for entry in parables:
        sref = entry.get("scriptureTextFilePath")
        ref = true_ref(sref)
        if ref is None:
            if sref:
                missing.append(entry["storyId"])
            continue
        cur = entry.get("bibleSourceRef")
        if cur != ref:
            changes.append((entry["storyId"], cur, ref))
            entry["bibleSourceRef"] = ref

    if changes:
        out = json.dumps(data, indent=2, ensure_ascii=True)
        if not out.endswith("\n"):
            out += "\n"
        MANIFEST.write_text(out, encoding="utf-8")

    print(f"manifest entries: {len(parables)}")
    print(f"bibleSourceRef rewritten: {len(changes)}")
    print(f"scripture file missing (skipped): {len(missing)}")
    for sid, old, new in sorted(changes):
        print(f"  {sid}: {old!r} -> {new!r}")
    if missing:
        print("MISSING scripture files:")
        for sid in sorted(missing):
            print(f"  {sid}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
