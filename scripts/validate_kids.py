#!/usr/bin/env python3
"""
validate_kids.py — Bible PAL kid-lane registry/manifest consistency gate.

Protects the Kids MAP (assets/stories/kid_anchor_registry.json) and the kid
authoring manifest (assets/stories/kids_manifest.json) BEFORE content starts,
so the discoverability mess the adult corpus grew into can't take root here.

Checks
------
  REGISTRY self-integrity (FAIL):
    - anchorId unique; targetLengths subset of {short, full, long}
    - tier in {core, secondary}; launch/longEligible are booleans
    - sibling references resolve to a real anchorId
    - no manifestAnchorId claimed by two anchors

  A) Anchor resolution (FAIL):
     every kids_manifest scriptureAnchorId (when set) resolves to an anchor
     via that anchor's manifestAnchorIds.

  B) Shippable mapping (FAIL):
     every DONE / APPROVED / AUDIO_PENDING kid story resolves to a planned
     anchor (a non-null scriptureAnchorId that resolves).

  C) Length within plan:
     for each anchor, the canonical length of every fulfilling (non-REJECTED)
     story must be in  targetLengths  (plus 'long' iff longEligible).
     FAIL when the offending story is shippable; WARN when it is still
     in-progress legacy content (NEEDS_REWRITE / REVIEW / DRAFTED).

Length normalization
--------------------
kids_manifest carries legacy time-based buckets; the registry/doctrine use the
short/full/long axis. We bridge by word-band so good content validates and
genuine drift surfaces:
    short, 3min            -> short
    full,  5min            -> full
    long,  10min, 15min, 20min -> long
Any other bucket is an unknown-length FAIL. Stories still on time-buckets also
raise a soft WARN recommending migration to short/full/long.

USAGE
  python3 scripts/validate_kids.py            # full kid lane
  python3 scripts/validate_kids.py --strict   # promote WARN to FAIL

Exit codes:
  0 — clean, or only WARN findings (default mode)
  1 — any FAIL (always), or any WARN in --strict mode
  2 — missing/unreadable input file
"""
from __future__ import annotations

import argparse
import collections
import json
import sys
from pathlib import Path

STORIES = Path(__file__).resolve().parent.parent / "assets" / "stories"
KIDS_MANIFEST = STORIES / "kids_manifest.json"
ANCHOR_REGISTRY = STORIES / "kid_anchor_registry.json"

SHIPPABLE = {"DONE", "APPROVED", "AUDIO_PENDING"}
# Terminal/non-counting: excluded from coverage and from the length check.
# REJECTED = wrong approach; SUPERSEDED = right approach, replaced by a newer telling.
TERMINAL = {"REJECTED", "SUPERSEDED"}
AXIS = {"short", "full", "long"}
TIERS = {"core", "secondary"}

# legacy time-bucket -> canonical short/full/long axis (by word band)
BUCKET_AXIS = {
    "short": "short", "3min": "short",
    "full": "full", "5min": "full",
    "long": "long", "10min": "long", "15min": "long", "20min": "long",
}
LEGACY_BUCKETS = {"3min", "5min", "10min", "15min", "20min"}


def load(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        print(f"Missing input: {path}", file=sys.stderr)
        sys.exit(2)
    except json.JSONDecodeError as e:
        print(f"Invalid JSON in {path}: {e}", file=sys.stderr)
        sys.exit(2)


def index_registry(reg, fails):
    """Return (anchor_by_id, manifest_id -> anchorId). Append registry FAILs."""
    anchors = [a for c in reg["categories"] for a in c["anchors"]]
    by_id = {}
    rev = {}
    prod_ids = {}
    for a in anchors:
        aid = a["anchorId"]
        if aid in by_id:
            fails.append(f"registry: duplicate anchorId '{aid}'")
        by_id[aid] = a
        pid = a.get("productionId")
        if pid is not None:
            if not isinstance(pid, int) or pid < 1801:
                fails.append(f"registry: anchor '{aid}' productionId {pid!r} must be an int >= 1801")
            elif pid in prod_ids:
                fails.append(f"registry: productionId {pid} on both '{prod_ids[pid]}' and '{aid}'")
            else:
                prod_ids[pid] = aid
        bad = set(a.get("targetLengths", [])) - AXIS
        if bad:
            fails.append(f"registry: anchor '{aid}' targetLengths not in {sorted(AXIS)}: {sorted(bad)}")
        if a.get("tier") not in TIERS:
            fails.append(f"registry: anchor '{aid}' tier '{a.get('tier')}' not in {sorted(TIERS)}")
        for field in ("launch", "longEligible"):
            if field in a and not isinstance(a[field], bool):
                fails.append(f"registry: anchor '{aid}' {field} must be boolean")
        for mid in a.get("manifestAnchorIds", []):
            if mid in rev:
                fails.append(f"registry: manifestAnchorId '{mid}' claimed by both "
                             f"'{rev[mid]}' and '{aid}'")
            rev[mid] = aid
    # sibling references resolve (second pass; needs full by_id)
    for a in anchors:
        sib = a.get("sibling")
        if sib and sib not in by_id:
            fails.append(f"registry: anchor '{a['anchorId']}' sibling '{sib}' does not resolve")
    return by_id, rev


def main() -> int:
    ap = argparse.ArgumentParser(description="Kid-lane registry/manifest consistency gate.")
    ap.add_argument("--strict", action="store_true", help="promote WARN to FAIL")
    args = ap.parse_args()

    reg = load(ANCHOR_REGISTRY)
    kids = load(KIDS_MANIFEST)

    fails: list[str] = []
    warns: list[str] = []

    by_id, rev = index_registry(reg, fails)

    # collect canonical lengths fulfilling each anchor (non-REJECTED stories)
    anchor_lengths: dict[str, list[tuple[str, str, bool]]] = collections.defaultdict(list)

    for s in kids["stories"]:
        sid = s.get("id", "<no-id>")
        status = s.get("status", "<no-status>")
        aid_src = s.get("scriptureAnchorId")
        shippable = status in SHIPPABLE

        anchor_id = rev.get(aid_src) if aid_src else None

        # A) anchor resolution
        if aid_src and anchor_id is None:
            fails.append(f"A: story '{sid}' scriptureAnchorId '{aid_src}' "
                         f"resolves to no registry anchor")
        # B) shippable mapping
        if shippable and anchor_id is None:
            fails.append(f"B: {status} story '{sid}' does not map to a planned anchor "
                         f"(scriptureAnchorId={aid_src!r})")

        # D) storyNumber must match the anchor's registry productionId
        sn = s.get("storyNumber")
        if sn is not None and anchor_id is not None:
            pid = by_id[anchor_id].get("productionId")
            if pid != sn:
                fails.append(f"D: story '{sid}' storyNumber {sn} != anchor "
                             f"'{anchor_id}' productionId {pid!r}")

        # length normalization
        bucket = s.get("lengthBucket")
        axis = BUCKET_AXIS.get(bucket)
        if axis is None:
            fails.append(f"C: story '{sid}' has unknown lengthBucket '{bucket}'")
        else:
            if bucket in LEGACY_BUCKETS and status not in TERMINAL:
                warns.append(f"legacy-bucket: story '{sid}' uses '{bucket}' "
                             f"(migrate to {axis})")
            if anchor_id and status not in TERMINAL:
                anchor_lengths[anchor_id].append((sid, axis, shippable))

    # C) length within plan
    for anchor_id, entries in anchor_lengths.items():
        a = by_id[anchor_id]
        allowed = set(a.get("targetLengths", []))
        if a.get("longEligible"):
            allowed.add("long")
        for sid, axis, shippable in entries:
            if axis not in allowed:
                msg = (f"C: story '{sid}' length '{axis}' exceeds anchor "
                       f"'{anchor_id}' plan {sorted(allowed)}"
                       + ("" if a.get("longEligible") else " (not longEligible)"))
                (fails if shippable else warns).append(msg)

    # report
    for w in warns:
        print(f"[WARN] {w}")
    for f in fails:
        print(f"[FAIL] {f}")

    n_anchors = sum(len(c["anchors"]) for c in reg["categories"])
    print()
    print(f"Checked: {n_anchors} registry anchors, {len(kids['stories'])} kid stories")
    print(f"  FAIL: {len(fails)}")
    print(f"  WARN{' (strict→FAIL)' if args.strict else ''}: {len(warns)}")

    if fails:
        return 1
    if warns and args.strict:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
