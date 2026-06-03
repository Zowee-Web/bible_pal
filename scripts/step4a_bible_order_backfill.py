#!/usr/bin/env python3
"""
Step 4A Commit 2 — bibleOrderIndex backfill.

Backfills `bibleOrderIndex` for manifest entries (and corresponding
meta_<sid>.json files) where:
  - `bibleSourceRef` is present
  - `bibleOrderIndex` is null
  - `bibleSourceRef` is NOT the placeholder "Lamentations 3:55-58"
    (those are an editorial 4B anchor-repair problem; skipped here)

Strategy (per Step 4A plan):
  1. If ANY variant of the sid already has `bibleOrderIndex` in the
     manifest, reuse that value (the "mixed sid" case — 10 sids).
  2. Else if the sid's meta_<sid>.json has `bibleOrderIndex`, reuse it.
  3. Else compute a new index:
       base = max_existing_index_for_book + 1000  (or 1 if no existing)
       index = base + chapter * 1000 + verse
     Backfilled entries sort cleanly AFTER curated entries within the
     book; ties broken by existing PathService logic.

All affected manifest entries for a sid get the same index. The
meta_<sid>.json field is updated (or added) to match.

Idempotent and reversible (git revert / re-run).
"""

from __future__ import annotations

import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
TRADITIONAL_DIR = REPO_ROOT / "assets" / "stories" / "traditional"
MANIFEST_PATH = REPO_ROOT / "assets" / "stories" / "manifest.json"
PLACEHOLDER_ANCHOR = "Lamentations 3:55-58"

sys.path.insert(0, str(REPO_ROOT / "scripts"))
from lib.bible_ref_parser import parse_bible_ref  # noqa: E402


def extract_sid(parable: dict) -> str | None:
    """Extract sid from a manifest entry. Long variants have empty
    audioFilePath, so fall back to textFilePath, scriptureTextFilePath,
    or storyId in that order."""
    for field in ("audioFilePath", "textFilePath",
                  "scriptureTextFilePath", "reflectionAudioPath"):
        v = parable.get(field) or ""
        if v:
            parts = v.split("/")
            if len(parts) >= 3 and parts[0] == "traditional":
                return parts[1]
    sid_parts = (parable.get("storyId") or "").split("_")
    if len(sid_parts) >= 2 and sid_parts[0] == "story" and sid_parts[1].isdigit():
        return sid_parts[1]
    return None


def book_slug(ref: str | None) -> str | None:
    if not ref:
        return None
    try:
        parsed = parse_bible_ref(ref)
    except Exception:
        return None
    return parsed.book.lower().replace(" ", "_")


def compute_new_index(ref: str, book_max: dict[str, int]) -> int | None:
    try:
        parsed = parse_bible_ref(ref)
    except Exception:
        return None
    slug = parsed.book.lower().replace(" ", "_")
    base = book_max[slug] + 1000 if slug in book_max else 1
    verse = parsed.start_verse if parsed.start_verse is not None else 1
    return base + parsed.start_chapter * 1000 + verse


def main() -> int:
    print("Step 4A Commit 2 — bibleOrderIndex backfill")
    print(f"  repo: {REPO_ROOT}")
    print()

    # Load manifest, group by sid
    with MANIFEST_PATH.open() as f:
        manifest = json.load(f)

    by_sid: dict[str, list[dict]] = defaultdict(list)
    for p in manifest["parables"]:
        sid = extract_sid(p)
        if sid:
            by_sid[sid].append(p)

    # Per-book max existing index (across the whole manifest)
    book_max: dict[str, int] = {}
    for p in manifest["parables"]:
        idx = p.get("bibleOrderIndex")
        ref = p.get("bibleSourceRef")
        if idx is None or ref is None:
            continue
        slug = book_slug(ref)
        if slug is None:
            continue
        if idx > book_max.get(slug, -1):
            book_max[slug] = idx

    # Find sids needing backfill (and skip placeholder-anchored entries)
    needs_backfill_sids: list[str] = []
    skipped_placeholder = 0
    for sid, entries in by_sid.items():
        for p in entries:
            ref = p.get("bibleSourceRef")
            if not ref:
                continue
            if p.get("bibleOrderIndex") is not None:
                continue
            if ref == PLACEHOLDER_ANCHOR:
                skipped_placeholder += 1
                continue
            needs_backfill_sids.append(sid)
            break  # found at least one missing variant; sid in scope

    needs_backfill_sids = sorted(set(needs_backfill_sids))
    print(f"Sids needing backfill:    {len(needs_backfill_sids)}")
    print(f"Placeholder-anchored entries skipped (4B): {skipped_placeholder}")
    print()

    # Resolve target index per sid (priority: manifest variant > meta file > formula)
    sid_target: dict[str, int] = {}
    source_counts: Counter = Counter()
    for sid in needs_backfill_sids:
        entries = by_sid[sid]
        # 1: existing index in any manifest variant
        existing_manifest = [
            p["bibleOrderIndex"] for p in entries
            if p.get("bibleOrderIndex") is not None
        ]
        if existing_manifest:
            # Use the most common value if multiple variants disagree (shouldn't happen, defensive)
            sid_target[sid] = Counter(existing_manifest).most_common(1)[0][0]
            source_counts["from_existing_manifest_variant"] += 1
            continue
        # 2: existing index in meta_<sid>.json
        meta_path = TRADITIONAL_DIR / sid / f"meta_{sid}.json"
        if meta_path.is_file():
            with meta_path.open() as f:
                meta = json.load(f)
            meta_idx = meta.get("bibleOrderIndex")
            if meta_idx is not None:
                sid_target[sid] = meta_idx
                source_counts["from_meta_file"] += 1
                continue
        # 3: compute new index
        ref = None
        for p in entries:
            if p.get("bibleSourceRef") and p["bibleSourceRef"] != PLACEHOLDER_ANCHOR:
                ref = p["bibleSourceRef"]
                break
        if ref is None:
            continue
        new_idx = compute_new_index(ref, book_max)
        if new_idx is None:
            print(f"  WARN: could not parse ref for sid {sid}: {ref!r}")
            continue
        sid_target[sid] = new_idx
        source_counts["computed_new"] += 1

    print("Index source breakdown:")
    for src, n in source_counts.most_common():
        print(f"  {src}: {n}")
    print()

    # Apply manifest updates
    manifest_updates = 0
    per_book_deltas: Counter = Counter()
    for p in manifest["parables"]:
        sid = extract_sid(p)
        if sid is None or sid not in sid_target:
            continue
        ref = p.get("bibleSourceRef")
        if not ref or ref == PLACEHOLDER_ANCHOR:
            continue
        if p.get("bibleOrderIndex") is not None:
            continue
        p["bibleOrderIndex"] = sid_target[sid]
        manifest_updates += 1
        slug = book_slug(ref) or "unknown"
        per_book_deltas[slug] += 1

    if manifest_updates > 0:
        with MANIFEST_PATH.open("w") as f:
            json.dump(manifest, f, indent=2)
            f.write("\n")

    # Apply meta file updates (only for sids in sid_target)
    meta_updates = 0
    for sid, target in sid_target.items():
        meta_path = TRADITIONAL_DIR / sid / f"meta_{sid}.json"
        if not meta_path.is_file():
            continue
        with meta_path.open() as f:
            meta = json.load(f)
        if meta.get("bibleOrderIndex") == target:
            continue
        meta["bibleOrderIndex"] = target
        with meta_path.open("w") as f:
            json.dump(meta, f, indent=2)
            f.write("\n")
        meta_updates += 1

    print("Per-book deltas (manifest entries gaining bibleOrderIndex):")
    for slug, n in per_book_deltas.most_common():
        print(f"  {slug}: +{n}")
    print()
    print(f"Manifest entries updated: {manifest_updates}")
    print(f"Meta files updated:       {meta_updates}")
    print(f"Sids backfilled:          {len(sid_target)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
