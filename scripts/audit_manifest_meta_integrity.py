#!/usr/bin/env python3
"""Audit 1:1 integrity between manifest.json and on-disk meta_<id>.json files.

Reports three categories:
  1. Manifest IDs missing a meta_<id>.json on disk
  2. Disk meta_<id>.json files not referenced by the live manifest
     (excluding IDs allowlisted in _ARCHIVED_IDS.json)
  3. Title / bibleStoryKey / scripture-reference mismatches between a
     manifest variant row and its meta file

Reads (never writes):
  - assets/stories/manifest.json
  - assets/stories/traditional/<id>/meta_<id>.json
  - assets/stories/traditional/_ARCHIVED_IDS.json

Exit code 0 = clean, 1 = integrity violations found.

Usage:
  python3 scripts/audit_manifest_meta_integrity.py
  python3 scripts/audit_manifest_meta_integrity.py --verbose
"""
import argparse
import json
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST_PATH = os.path.join(ROOT, "assets", "stories", "manifest.json")
TRADITIONAL_DIR = os.path.join(ROOT, "assets", "stories", "traditional")
ARCHIVED_PATH = os.path.join(TRADITIONAL_DIR, "_ARCHIVED_IDS.json")

STORY_ID_RE = re.compile(r"^story_(\d+)_")


def load_json(path):
    with open(path) as f:
        return json.load(f)


def manifest_traditional_by_id(manifest):
    """Return {numeric_id: [variant_entry, ...]} for storytellingMode=traditional."""
    by_id = defaultdict(list)
    unparseable = []
    for entry in manifest.get("parables", []):
        if entry.get("storytellingMode") != "traditional":
            continue
        sid = entry.get("storyId", "")
        m = STORY_ID_RE.match(sid)
        if not m:
            unparseable.append(sid)
            continue
        by_id[int(m.group(1))].append(entry)
    return by_id, unparseable


def disk_meta_ids():
    """Return {numeric_id: meta_dict} for every meta_<id>.json under traditional/."""
    out = {}
    malformed = []
    if not os.path.isdir(TRADITIONAL_DIR):
        return out, malformed
    for d in sorted(os.listdir(TRADITIONAL_DIR)):
        full = os.path.join(TRADITIONAL_DIR, d)
        if not os.path.isdir(full):
            continue
        try:
            nid = int(d)
        except ValueError:
            continue
        meta_path = os.path.join(full, f"meta_{d}.json")
        if not os.path.exists(meta_path):
            malformed.append(f"{d}: directory exists but meta_{d}.json missing")
            continue
        try:
            out[nid] = load_json(meta_path)
        except (OSError, json.JSONDecodeError) as exc:
            malformed.append(f"{d}: meta unreadable ({exc})")
    return out, malformed


def archived_ids():
    if not os.path.exists(ARCHIVED_PATH):
        return set()
    data = load_json(ARCHIVED_PATH)
    return set(data.get("archivedIds", []))


def find_consistency_mismatches(manifest_by_id, metas):
    """Compare title / bibleStoryKey / scripture reference for every shared ID."""
    mismatches = []
    for nid in sorted(set(manifest_by_id) & set(metas)):
        meta = metas[nid]
        meta_title = meta.get("title")
        meta_key = meta.get("bibleStoryKey")
        meta_anchor = meta.get("scriptureAnchor") or meta.get("bibleSourceRef")
        for entry in manifest_by_id[nid]:
            sid = entry.get("storyId", "?")
            if meta_title and entry.get("title") and entry["title"] != meta_title:
                mismatches.append(
                    (nid, sid, "title", meta_title, entry["title"])
                )
            if (
                meta_key
                and entry.get("bibleStoryKey")
                and entry["bibleStoryKey"] != meta_key
            ):
                mismatches.append(
                    (nid, sid, "bibleStoryKey", meta_key, entry["bibleStoryKey"])
                )
            entry_anchor = entry.get("bibleSourceRef") or entry.get("scriptureAnchor")
            if meta_anchor and entry_anchor and entry_anchor != meta_anchor:
                mismatches.append(
                    (nid, sid, "scriptureAnchor", meta_anchor, entry_anchor)
                )
    return mismatches


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0])
    parser.add_argument(
        "--verbose", action="store_true", help="Print every offending ID"
    )
    args = parser.parse_args()

    manifest = load_json(MANIFEST_PATH)
    by_id, unparseable = manifest_traditional_by_id(manifest)
    metas, malformed = disk_meta_ids()
    archived = archived_ids()

    manifest_ids = set(by_id)
    disk_ids = set(metas)

    missing_meta = sorted(manifest_ids - disk_ids)
    orphans_all = sorted(disk_ids - manifest_ids)
    unallowlisted_orphans = sorted(set(orphans_all) - archived)
    mismatches = find_consistency_mismatches(by_id, metas)

    total_variants = sum(len(v) for v in by_id.values())
    print("=" * 60)
    print(" Manifest ↔ Meta Integrity Audit")
    print("=" * 60)
    print(f"Manifest variant rows (Traditional):     {total_variants}")
    print(f"Manifest unique numeric IDs:             {len(manifest_ids)}")
    print(f"Disk meta_<id>.json files:               {len(disk_ids)}")
    print(f"Archived (allowlisted) IDs:              {len(archived)}")
    print()
    print(f"Missing meta (in manifest, not on disk): {len(missing_meta)}")
    print(f"Orphan meta (on disk, not in manifest):  {len(orphans_all)}")
    print(f"  ├─ allowlisted as archived:            "
          f"{len(orphans_all) - len(unallowlisted_orphans)}")
    print(f"  └─ UNRESOLVED orphans:                 {len(unallowlisted_orphans)}")
    print(f"Title / key / anchor mismatches:         {len(mismatches)}")
    print(f"Unparseable manifest storyIds:           {len(unparseable)}")
    print(f"Malformed disk dirs:                     {len(malformed)}")

    if args.verbose or missing_meta:
        if missing_meta:
            print("\nMissing meta IDs:")
            for nid in missing_meta:
                print(f"  {nid}")
    if args.verbose or unallowlisted_orphans:
        if unallowlisted_orphans:
            print("\nUnresolved orphan meta IDs (add to _ARCHIVED_IDS.json or "
                  "include in manifest):")
            for nid in unallowlisted_orphans:
                print(f"  {nid}")
    if args.verbose or mismatches:
        if mismatches:
            print("\nField mismatches:")
            for nid, sid, field, meta_val, entry_val in mismatches:
                print(f"  {nid} {sid}  {field}: meta={meta_val!r} "
                      f"manifest={entry_val!r}")
    if args.verbose or unparseable:
        if unparseable:
            print("\nUnparseable manifest storyIds:")
            for sid in unparseable:
                print(f"  {sid}")
    if args.verbose or malformed:
        if malformed:
            print("\nMalformed disk entries:")
            for line in malformed:
                print(f"  {line}")

    fail = bool(
        missing_meta or unallowlisted_orphans or mismatches or unparseable or malformed
    )
    print()
    print("RESULT:", "FAIL" if fail else "PASS")
    sys.exit(1 if fail else 0)


if __name__ == "__main__":
    main()
