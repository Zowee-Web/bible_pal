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
ANCHOR_REGISTRY = os.path.join(STORIES, "kid_anchor_registry.json")
APP_MANIFEST = os.path.join(STORIES, "manifest.json")

PROMOTE_STATUSES = {"DONE"}
COVERED_STATUSES = {"APPROVED", "AUDIO_PENDING", "DONE"}
IN_PROGRESS_STATUSES = {"DRAFTED", "REVIEW", "NEEDS_REWRITE"}
HARD_STOP_STORIES = 150


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


def _anchor_status(anchor, stories_by_manifest_anchor):
    """Return (state, best_story_status) for a registry anchor."""
    ids = anchor.get("manifestAnchorIds", [])
    matched = [s for aid in ids for s in stories_by_manifest_anchor.get(aid, [])]
    if not matched:
        return "open", None
    statuses = {s["status"] for s in matched}
    if statuses & COVERED_STATUSES:
        return "covered", "/".join(sorted(statuses & COVERED_STATUSES))
    if statuses & IN_PROGRESS_STATUSES:
        return "in_progress", "/".join(sorted(statuses & IN_PROGRESS_STATUSES))
    return "open", None  # only REJECTED stories point here


def report(kids):
    """Anchor-coverage map (the success metric): coverage against the planned canon."""
    try:
        reg = load(ANCHOR_REGISTRY)
    except FileNotFoundError:
        print("kid_anchor_registry.json not found; cannot compute coverage.")
        return

    # index kid-lane stories by their scriptureAnchorId
    by_anchor = collections.defaultdict(list)
    for s in kids["stories"]:
        if s.get("scriptureAnchorId"):
            by_anchor[s["scriptureAnchorId"]].append(s)

    target = reg["_meta"]["doctrine"]["targets"]
    print("=== Bible PAL Kids — anchor coverage ===")
    print(f"Plan: launch {target['launchAnchors']} / mature {target['matureAnchors']} "
          f"/ ceiling {target['ceilingAnchors']} anchors, hard stop {target['hardStopStories']} stories")
    print()

    total_anchors = covered = in_progress = 0
    planned_stories = 0
    state_mark = {"covered": "*", "in_progress": "~", "open": " "}
    for cat in reg["categories"]:
        cells = []
        for a in cat["anchors"]:
            total_anchors += 1
            planned_stories += len(a.get("targetLengths", []))
            state, _ = _anchor_status(a, by_anchor)
            covered += state == "covered"
            in_progress += state == "in_progress"
            cells.append((state, a))
        n_cov = sum(1 for st, _ in cells if st == "covered")
        n_prog = sum(1 for st, _ in cells if st == "in_progress")
        tag = "Complete" if n_cov == len(cells) else f"{n_cov}/{len(cells)}"
        prog = f" (+{n_prog} in progress)" if n_prog else ""
        print(f"{cat['name']:<22} {tag}{prog}")
        for st, a in cells:
            print(f"   [{state_mark[st]}] {a['displayName']}")

    print()
    print(f"Core anchors covered: {covered} / {total_anchors}"
          f"  ({in_progress} in progress, {total_anchors - covered - in_progress} open)")
    headroom = HARD_STOP_STORIES - planned_stories
    print(f"Planned stories at full coverage: {planned_stories} / {HARD_STOP_STORIES} hard stop "
          f"({headroom} headroom)" + ("  *** OVER HARD STOP ***" if headroom < 0 else ""))
    print("  Legend: [*] covered  [~] in progress  [ ] open")


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
