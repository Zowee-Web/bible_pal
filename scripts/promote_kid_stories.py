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

# A kid story is surfaced in the app as soon as it is "created" = has rendered
# audio. Status (REVIEW/APPROVED/DONE) is internal authoring state; the app shows
# any non-terminal story that has audio (Adam 2026-06-15: visible as soon as
# created). REJECTED/SUPERSEDED are never surfaced.
TERMINAL_STATUSES = {"REJECTED", "SUPERSEDED"}
COVERED_STATUSES = {"APPROVED", "AUDIO_PENDING", "DONE"}
IN_PROGRESS_STATUSES = {"DRAFTED", "REVIEW", "NEEDS_REWRITE"}
HARD_STOP_STORIES = 150

# The app surfaces stories by MOOD (parable_service mood filter), so the kid
# canon needs coverage across all 8 moods, not just anchor coverage. Mirrors the
# adult manifest.json mood taxonomy; keep in sync if the app's moods change.
APP_MOODS = [
    "anxious", "brave_courage", "calm_peaceful", "encouraging",
    "grateful", "hurting", "joyful", "weary",
]


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

    # tallies; keys: "all" = full canon, "launch" = launch:true cutline
    tot = {"all": collections.Counter(), "launch": collections.Counter()}
    planned = {"all": 0, "launch": 0}
    state_mark = {"covered": "*", "in_progress": "~", "open": " "}
    for cat in reg["categories"]:
        cells = []
        for a in cat["anchors"]:
            state, _ = _anchor_status(a, by_anchor)
            scopes = ["all"] + (["launch"] if a.get("launch") else [])
            for sc in scopes:
                tot[sc][state] += 1
                tot[sc]["n"] += 1
                planned[sc] += len(a.get("targetLengths", []))
            cells.append((state, a))
        n_cov = sum(1 for st, _ in cells if st == "covered")
        n_prog = sum(1 for st, _ in cells if st == "in_progress")
        tag = "Complete" if n_cov == len(cells) else f"{n_cov}/{len(cells)}"
        prog = f" (+{n_prog} in progress)" if n_prog else ""
        print(f"{cat['name']:<22} {tag}{prog}")
        for st, a in cells:
            lmark = "L" if a.get("launch") else " "
            print(f"   [{state_mark[st]}]{lmark} {a['displayName']}")

    print()
    for sc, label in (("launch", "LAUNCH cutline"), ("all", "FULL canon")):
        t = tot[sc]
        n, cov, prog = t["n"], t["covered"], t["in_progress"]
        headroom = HARD_STOP_STORIES - planned[sc]
        over = "  *** OVER HARD STOP ***" if headroom < 0 else ""
        print(f"{label:<16} anchors {cov}/{n} covered ({prog} in progress, "
              f"{n - cov - prog} open) | planned stories {planned[sc]}/{HARD_STOP_STORIES} ({headroom} headroom){over}")
    print("  Legend: [*] covered  [~] in progress  [ ] open   |   L = launch-50 cutline")

    mood_report(kids, reg)


def mood_report(kids, reg):
    """Mood coverage: how the (built) kid anchors spread across the 8 app moods.

    Counted by DISTINCT ANCHOR, not story — David's short+full count as one
    courage anchor. Surfaces overfill (one mood hogging anchors) and empties
    (moods with no kid coverage), since the app serves by mood.
    """
    # manifestAnchorId -> registry anchorId
    rev = {}
    for cat in reg["categories"]:
        for a in cat["anchors"]:
            for mid in a.get("manifestAnchorIds", []):
                rev[mid] = a["anchorId"]

    # anchorId -> {"mood": str, "covered": bool}  (non-terminal stories only)
    anchors = {}
    for s in kids["stories"]:
        status = s.get("status")
        if status not in COVERED_STATUSES and status not in IN_PROGRESS_STATUSES:
            continue  # skip REJECTED / SUPERSEDED / PROPOSED
        aid = rev.get(s.get("scriptureAnchorId"))
        mood = s.get("mood")
        if not aid or not mood:
            continue
        rec = anchors.setdefault(aid, {"mood": mood, "covered": False})
        if status in COVERED_STATUSES:
            rec["covered"] = True

    # mood -> list of (anchorId, covered)
    by_mood = collections.defaultdict(list)
    for aid, rec in anchors.items():
        by_mood[rec["mood"]].append((aid, rec["covered"]))

    print()
    print("=== Mood coverage (app serves by mood; count = distinct anchors) ===")
    covered_moods = empty = 0
    for mood in APP_MOODS:
        entries = by_mood.get(mood, [])
        n = len(entries)
        ncov = sum(1 for _, c in entries if c)
        if ncov:
            covered_moods += 1
        if n == 0:
            empty += 1
            print(f"  {mood:<14} 0   EMPTY")
        else:
            names = ", ".join(a for a, _ in sorted(entries))
            tag = f"{ncov} covered" if ncov == n else f"{ncov} covered, {n - ncov} in progress"
            print(f"  {mood:<14} {n:<3} {tag}  ({names})")
    # any non-app moods slipped in?
    stray = sorted(set(by_mood) - set(APP_MOODS))
    if stray:
        print(f"  ! non-app moods in use (not searchable): {', '.join(stray)}")
    empties = [m for m in APP_MOODS if not by_mood.get(m)]
    inprog_only = sum(1 for m in APP_MOODS
                      if by_mood.get(m) and not any(c for _, c in by_mood[m]))
    print(f"Moods: {covered_moods} covered, {inprog_only} in-progress-only, "
          f"{empty} empty" + (f" ({', '.join(empties)})" if empties else ""))
    if anchors:
        hi = max(len(v) for v in by_mood.values())
        if hi >= 3 and empty:
            print(f"  note: heaviest mood has {hi} anchors while {empty} moods are empty "
                  f"— steer new anchors toward the empties.")


def is_promotable(s):
    """Surface in the app if it's a created story (has audio) and not terminal."""
    return bool(s.get("audioFilePath")) and s.get("status") not in TERMINAL_STATUSES


def validate(kids):
    """Sanity-check every story that will be surfaced in the app."""
    errs = []
    for s in kids["stories"]:
        if not is_promotable(s):
            continue
        path = os.path.join(STORIES, s["textFilePath"])
        if not os.path.exists(path):
            errs.append(f"{s['id']}: text file missing ({s['textFilePath']})")
        if not s.get("bibleSourceRef"):
            errs.append(f"{s['id']}: surfaced but no bibleSourceRef (kid stories must be Scripture-anchored)")
    return errs


def promote(write):
    kids = load(KIDS_MANIFEST)
    errs = validate(kids)
    if errs:
        print("VALIDATION ERRORS (fix before promoting):", file=sys.stderr)
        for e in errs:
            print("  - " + e, file=sys.stderr)
        return 1

    to_add = [s for s in kids["stories"] if is_promotable(s)]
    if not to_add:
        print("No kid stories with audio to surface.")
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

    print(f"Surface: +{added} new, ~{updated} updated (of {len(to_add)} created kid stories).")
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
