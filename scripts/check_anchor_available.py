#!/usr/bin/env python3
"""Anchor coverage tracker and duplicate guard for Traditional stories.

The meta_*.json files under assets/stories/traditional/<id>/ are the single
source of truth. assets/stories/anchor_coverage.json is a derived cache
rebuilt from those metas on demand.

Existing duplicates are tolerated (see the No-Duplicate Anchor Invariant in
docs/INVARIANTS.md). The guard's job is to prevent NEW duplicates from being
generated, not to litigate the legacy library.

Subcommands:
    rebuild   Scan every traditional/<id>/meta_<id>.json, derive
              scriptureAnchorId where missing, and write
              assets/stories/anchor_coverage.json. Records existing
              duplicates in the file under "duplicates" but does not fail.

    check     Test a candidate scriptureAnchorId or bibleStoryKey against
              the current set of used anchors. Prints "AVAILABLE" (exit 0)
              or "DUPLICATE ..." (exit 1). Used as a pre-generation guard.

Usage:
    python3 scripts/check_anchor_available.py rebuild
    python3 scripts/check_anchor_available.py check --anchor acts_9_1-22
    python3 scripts/check_anchor_available.py check --scripture "Acts 9:1-22"
    python3 scripts/check_anchor_available.py check --key saul_road_to_damascus
"""
import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TRADITIONAL_DIR = os.path.join(ROOT, "assets/stories/traditional")
COVERAGE_PATH = os.path.join(ROOT, "assets/stories/anchor_coverage.json")

# Canonical book abbreviations (matches existing scripture_anchor_registry.json).
BOOK_ABBREV = {
    "genesis": "gen", "exodus": "ex", "leviticus": "lev", "numbers": "num",
    "deuteronomy": "deut", "joshua": "josh", "judges": "judg", "ruth": "ruth",
    "1 samuel": "1sam", "2 samuel": "2sam", "1 kings": "1kgs", "2 kings": "2kgs",
    "1 chronicles": "1chr", "2 chronicles": "2chr", "ezra": "ezra",
    "nehemiah": "neh", "esther": "esth", "job": "job", "psalm": "ps",
    "psalms": "ps", "proverbs": "prov", "ecclesiastes": "eccl",
    "song of solomon": "song", "song of songs": "song", "isaiah": "isa",
    "jeremiah": "jer", "lamentations": "lam", "ezekiel": "ezek",
    "daniel": "dan", "hosea": "hos", "joel": "joel", "amos": "amos",
    "obadiah": "obad", "jonah": "jonah", "micah": "mic", "nahum": "nah",
    "habakkuk": "hab", "zephaniah": "zeph", "haggai": "hag",
    "zechariah": "zech", "malachi": "mal",
    "matthew": "matt", "mark": "mark", "luke": "luke", "john": "john",
    "acts": "acts", "romans": "rom", "1 corinthians": "1cor",
    "2 corinthians": "2cor", "galatians": "gal", "ephesians": "eph",
    "philippians": "phil", "colossians": "col",
    "1 thessalonians": "1thess", "2 thessalonians": "2thess",
    "1 timothy": "1tim", "2 timothy": "2tim", "titus": "titus",
    "philemon": "phlm", "hebrews": "heb", "james": "jas", "1 peter": "1pet",
    "2 peter": "2pet", "1 john": "1john", "2 john": "2john",
    "3 john": "3john", "jude": "jude", "revelation": "rev",
}


def normalize_anchor_id(anchor):
    """Convert a human scripture reference to a canonical scriptureAnchorId.

    Examples:
        "Acts 9:1-22"       -> "acts_9_1-22"
        "John 13:1-17"      -> "john_13_1-17"
        "1 Samuel 1:9-20"   -> "1sam_1_9-20"
        "Daniel 6"          -> "dan_6"
        "Esther 4-7"        -> "esth_4-7"
        "Psalm 23"          -> "ps_23"
    """
    if not anchor:
        return ""
    s = anchor.strip()
    # Pattern A: book + chapter + ":" + verse-range
    m = re.match(
        r"^(\d?\s*[A-Za-z][A-Za-z\s]*?)\s+(\d+):(\d+(?:-\d+)?)$",
        s,
    )
    if m:
        book_raw, ch, verses = m.group(1), m.group(2), m.group(3)
        book_key = re.sub(r"\s+", " ", book_raw.strip().lower())
        book_abbrev = BOOK_ABBREV.get(book_key, book_key.replace(" ", ""))
        return f"{book_abbrev}_{ch}_{verses}"
    # Pattern B: book + chapter (or chapter range) only
    m = re.match(
        r"^(\d?\s*[A-Za-z][A-Za-z\s]*?)\s+(\d+(?:-\d+)?)$",
        s,
    )
    if m:
        book_raw, ch = m.group(1), m.group(2)
        book_key = re.sub(r"\s+", " ", book_raw.strip().lower())
        book_abbrev = BOOK_ABBREV.get(book_key, book_key.replace(" ", ""))
        return f"{book_abbrev}_{ch}"
    return ""


def scan_traditional():
    """Walk traditional/<id>/meta_<id>.json and collect anchor entries."""
    entries = []
    if not os.path.isdir(TRADITIONAL_DIR):
        return entries
    for sid in sorted(os.listdir(TRADITIONAL_DIR)):
        story_dir = os.path.join(TRADITIONAL_DIR, sid)
        if not os.path.isdir(story_dir):
            continue
        meta_path = os.path.join(story_dir, f"meta_{sid}.json")
        if not os.path.exists(meta_path):
            continue
        try:
            with open(meta_path) as f:
                meta = json.load(f)
        except (OSError, json.JSONDecodeError) as exc:
            print(f"warn: could not read {meta_path}: {exc}", file=sys.stderr)
            continue
        anchor = meta.get("scriptureAnchor", "") or ""
        anchor_id = (
            meta.get("scriptureAnchorId")
            or normalize_anchor_id(anchor)
        )
        entries.append({
            "storyId": meta.get("storyId"),
            "bibleStoryKey": meta.get("bibleStoryKey", ""),
            "scriptureAnchor": anchor,
            "scriptureAnchorId": anchor_id,
        })
    return entries


def find_duplicates(entries):
    by_anchor = {}
    by_key = {}
    for e in entries:
        aid = e["scriptureAnchorId"]
        if aid:
            by_anchor.setdefault(aid, []).append(e)
        bk = e["bibleStoryKey"]
        if bk:
            by_key.setdefault(bk, []).append(e)
    dup_anchors = {k: v for k, v in by_anchor.items() if len(v) > 1}
    dup_keys = {k: v for k, v in by_key.items() if len(v) > 1}
    return dup_anchors, dup_keys


def report_duplicates(dup_anchors, dup_keys):
    if dup_anchors:
        print("Duplicate scriptureAnchorId values:")
        for aid, items in sorted(dup_anchors.items()):
            ids = ", ".join(str(x["storyId"]) for x in items)
            print(f"  '{aid}'  ->  storyIds: {ids}")
    if dup_keys:
        print("Duplicate bibleStoryKey values:")
        for bk, items in sorted(dup_keys.items()):
            ids = ", ".join(str(x["storyId"]) for x in items)
            print(f"  '{bk}'  ->  storyIds: {ids}")


def build_payload(entries, dup_anchors, dup_keys):
    unique_anchors = len({
        e["scriptureAnchorId"] for e in entries if e["scriptureAnchorId"]
    })
    duplicates = {
        "byScriptureAnchorId": {
            aid: [
                {
                    "storyId": e["storyId"],
                    "bibleStoryKey": e["bibleStoryKey"],
                    "scriptureAnchor": e["scriptureAnchor"],
                }
                for e in items
            ]
            for aid, items in sorted(dup_anchors.items())
        },
        "byBibleStoryKey": {
            bk: [
                {
                    "storyId": e["storyId"],
                    "scriptureAnchor": e["scriptureAnchor"],
                    "scriptureAnchorId": e["scriptureAnchorId"],
                }
                for e in items
            ]
            for bk, items in sorted(dup_keys.items())
        },
    }
    return {
        "version": 1,
        "lastUpdated": datetime.now(timezone.utc)
        .strftime("%Y-%m-%dT%H:%M:%SZ"),
        "summary": {
            "scanned": len(entries),
            "uniqueScriptureAnchorIds": unique_anchors,
            "duplicateScriptureAnchorIdCount": len(dup_anchors),
            "duplicateBibleStoryKeyCount": len(dup_keys),
        },
        "usedAnchors": entries,
        "duplicates": duplicates,
    }


def cmd_rebuild(_args):
    entries = scan_traditional()
    dup_anchors, dup_keys = find_duplicates(entries)
    payload = build_payload(entries, dup_anchors, dup_keys)
    with open(COVERAGE_PATH, "w") as f:
        json.dump(payload, f, indent=2)
        f.write("\n")

    summary = payload["summary"]
    print(f"Traditional stories scanned: {summary['scanned']}")
    print(f"Unique scriptureAnchorId values: "
          f"{summary['uniqueScriptureAnchorIds']}")
    print(f"Duplicate scriptureAnchorId count: "
          f"{summary['duplicateScriptureAnchorIdCount']}")
    print(f"Duplicate bibleStoryKey count: "
          f"{summary['duplicateBibleStoryKeyCount']}")
    if dup_anchors or dup_keys:
        print()
        print("Existing duplicates recorded in coverage file (tolerated as "
              "legacy/current-library reality per the No-Duplicate Anchor "
              "Invariant in docs/INVARIANTS.md). New stories must still pass "
              "the `check` guard.")
    print(f"Coverage written: {COVERAGE_PATH}")


def cmd_check(args):
    entries = scan_traditional()
    target_anchor = args.anchor or normalize_anchor_id(args.scripture or "")
    target_key = args.key
    if not target_anchor and not target_key:
        sys.exit("Pass --anchor, --scripture, or --key")
    for e in entries:
        if target_anchor and e["scriptureAnchorId"] == target_anchor:
            print(
                f"DUPLICATE — scriptureAnchorId '{target_anchor}' "
                f"already used by storyId {e['storyId']} "
                f"({e['bibleStoryKey']})"
            )
            sys.exit(1)
        if target_key and e["bibleStoryKey"] == target_key:
            print(
                f"DUPLICATE — bibleStoryKey '{target_key}' "
                f"already used by storyId {e['storyId']} "
                f"({e['scriptureAnchor']})"
            )
            sys.exit(1)
    print("AVAILABLE")
    sys.exit(0)


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0])
    sub = p.add_subparsers(dest="cmd", required=True)

    p_rebuild = sub.add_parser(
        "rebuild",
        help="Rebuild assets/stories/anchor_coverage.json from meta files",
    )
    p_rebuild.set_defaults(func=cmd_rebuild)

    p_check = sub.add_parser(
        "check",
        help="Check whether an anchor / bibleStoryKey is available",
    )
    p_check.add_argument(
        "--anchor", help="scriptureAnchorId, e.g. acts_9_1-22"
    )
    p_check.add_argument(
        "--scripture",
        help="Raw scriptureAnchor like 'Acts 9:1-22' (will be normalized)",
    )
    p_check.add_argument("--key", help="bibleStoryKey")
    p_check.set_defaults(func=cmd_check)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
