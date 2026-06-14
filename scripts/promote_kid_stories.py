#!/usr/bin/env python3
"""Promote DONE kid stories from kids_manifest.json into the app manifest.json.

The dedicated ages-4-9 kid lane is authored/tracked in
assets/stories/kids_manifest.json. The app reads assets/stories/manifest.json.
This script mirrors only status=="DONE" kid stories into manifest.json with
kidFriendly=true, so in-progress authoring state never leaks into the live
catalog.

Usage:
    python3 scripts/promote_kid_stories.py            # report only (dry run)
    python3 scripts/promote_kid_stories.py --report   # status/coverage table
    python3 scripts/promote_kid_stories.py --write     # apply promotions

Idempotent: re-running --write updates existing kid entries in place
(matched by storyId) rather than duplicating them.
"""
import argparse
import collections
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
STORIES = os.path.join(HERE, "..", "assets", "stories")
KIDS_MANIFEST = os.path.join(STORIES, "kids_manifest.json")
APP_MANIFEST = os.path.join(STORIES, "manifest.json")

PROMOTE_STATUSES = {"DONE"}


def load(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def app_story_id(kid):
    """Stable storyId used inside manifest.json for a promoted kid story."""
    return f"kidstory_{kid['id']}"


def to_manifest_entry(kid):
    """Map a kid-lane entry to the app manifest schema."""
    return {
        "storyId": app_story_id(kid),
        "title": kid["title"],
        "mood": kid.get("mood"),
        "emotionalTags": kid.get("emotionalTags", []),
        "storytellingMode": "traditional",
        "kidFriendly": True,
        "audioFilePath": kid.get("audioFilePath"),
        "textFilePath": kid["textFilePath"],
        "translationId": "WEB",
        "languageStyle": "WEB",
        "narratorVoiceKey": kid.get("narratorVoiceKey"),
        "storyLength": kid.get("lengthBucket"),
        "reflectionQuestion": kid.get("reflectionQuestion"),
        "bibleSourceRef": kid.get("bibleSourceRef"),
        "bibleStoryKey": kid.get("bibleStoryKey"),
        "themeTags": kid.get("themeTags", []),
        "kidLane": "dedicated-4-9",
    }


def report(kids):
    rows = kids["stories"]
    by_status = collections.Counter(s["status"] for s in rows)
    print(f"Kid lane: {len(rows)} stories")
    for status, n in sorted(by_status.items()):
        print(f"  {status:<14} {n}")
    print()
    # Anchor coverage / dedup view
    anchored = [s for s in rows if s.get("scriptureAnchorId")]
    dupes = [a for a, n in collections.Counter(
        s["scriptureAnchorId"] for s in anchored).items() if n > 1]
    print(f"Distinct anchors used: {len({s['scriptureAnchorId'] for s in anchored})}"
          f"  (no anchor: {len(rows) - len(anchored)})")
    if dupes:
        print(f"  Anchors used more than once: {', '.join(dupes)}")
    print()
    print(f"{'STATUS':<14}{'BUCKET':<8}{'WORDS':<14}TITLE")
    for s in sorted(rows, key=lambda r: (r["status"], r["id"])):
        w = f"{s.get('actualWords','?')}/{s.get('targetWords','?')}"
        print(f"{s['status']:<14}{s.get('lengthBucket',''):<8}{w:<14}{s['title']}")


def validate(kids):
    """Pre-promotion sanity checks for DONE stories."""
    errs = []
    for s in kids["stories"]:
        if s["status"] != "DONE":
            continue
        path = os.path.join(STORIES, s["textFilePath"])
        if not os.path.exists(path):
            errs.append(f"{s['id']}: text file missing ({s['textFilePath']})")
        if not s.get("audioFilePath"):
            errs.append(f"{s['id']}: DONE but no audioFilePath")
        if not s.get("bibleSourceRef"):
            errs.append(f"{s['id']}: DONE but no bibleSourceRef (kid stories must be Scripture-anchored)")
    return errs


def promote(write):
    kids = load(KIDS_MANIFEST)
    errs = validate(kids)
    if errs:
        print("VALIDATION ERRORS (fix before promoting):", file=sys.stderr)
        for e in errs:
            print("  - " + e, file=sys.stderr)
        return 1

    to_add = [s for s in kids["stories"] if s["status"] in PROMOTE_STATUSES]
    if not to_add:
        print("No kid stories at status DONE; nothing to promote.")
        return 0

    app = load(APP_MANIFEST)
    existing = {p["storyId"]: i for i, p in enumerate(app["parables"])}
    added = updated = 0
    for kid in to_add:
        entry = to_manifest_entry(kid)
        sid = entry["storyId"]
        if sid in existing:
            app["parables"][existing[sid]] = entry
            updated += 1
        else:
            app["parables"].append(entry)
            added += 1

    print(f"Promote: +{added} new, ~{updated} updated (of {len(to_add)} DONE).")
    if write:
        with open(APP_MANIFEST, "w", encoding="utf-8") as f:
            json.dump(app, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print(f"Wrote {APP_MANIFEST}")
    else:
        print("Dry run (pass --write to apply).")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--report", action="store_true", help="print status/coverage table")
    ap.add_argument("--write", action="store_true", help="apply promotions to manifest.json")
    args = ap.parse_args()

    if args.report:
        report(load(KIDS_MANIFEST))
        return 0
    return promote(write=args.write)


if __name__ == "__main__":
    sys.exit(main())
