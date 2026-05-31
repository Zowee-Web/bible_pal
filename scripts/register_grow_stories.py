#!/usr/bin/env python3
"""
Register the 25 GROW stories' new Full/Long files in meta_*.json and manifest.json.

For each of the 25 stories:
  - Update meta lengths array (add full/long as needed)
  - Update meta files dict (add full/long WEB + KJV entries)
  - Add manifest entries for each new (story × length × lane) combo,
    cloning from the existing short entry of the same lane

Idempotent: re-running on already-registered stories is a no-op.
"""

from __future__ import annotations
import argparse
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TRAD = ROOT / "assets" / "stories" / "traditional"
MANIFEST = ROOT / "assets" / "stories" / "manifest.json"

# Default: the 25 Phase 2 GROW story IDs
GROW_IDS = [1036, 1037, 1038, 1112, 1114, 1117, 1118, 1129, 1131, 1140, 1142,
            1145, 1148, 1162, 1164, 1165, 1181, 1188, 1198, 1208, 1209, 1219,
            1227, 1446, 1450]

# Tier 1 NEXT (12 stories, 2026-05-30)
TIER1_IDS = [1019, 1032, 1055, 1111, 1113, 1123, 1160, 1172, 1216, 1265,
             1505, 1511]

# Tier 2 NEXT (10 stories, 2026-05-30)
TIER2_IDS = [1051, 1151, 1178, 1191, 1210, 1221, 1263, 1264, 1286, 1346]

# Tier 3 (5 stories, 2026-05-30 → 2026-05-31) — careful-review set.
# From 6 candidates: 4 GROW shipped Full+Long dual-lane (1212, 1228, 1230,
# 1506), 1 MAYBE re-triaged to GROW-Full-only (1194 — assembly arc only,
# no Long), 1 SKIP held Short-only (1224 — Pauline doxology, marked
# editorialNotes Short-canonical).
TIER3_IDS = [1194, 1212, 1228, 1230, 1506]


def update_meta(sid: int) -> tuple[list[str], list[str]]:
    """Update meta_<sid>.json. Returns (lengths_added, file_keys_added)."""
    meta_path = TRAD / str(sid) / f"meta_{sid}.json"
    meta = json.loads(meta_path.read_text())

    story_dir = TRAD / str(sid)
    added_lengths = []
    added_keys = []

    # Determine which length files actually exist on disk
    has_web_full = (story_dir / f"story_{sid}_traditional_web_full.txt").exists()
    has_web_long = (story_dir / f"story_{sid}_traditional_web_long.txt").exists()
    has_kjv_full = (story_dir / f"story_{sid}_traditional_kjv_full.txt").exists()
    has_kjv_long = (story_dir / f"story_{sid}_traditional_kjv_long.txt").exists()

    lengths = meta.get("lengths", [])
    if has_web_full and "full" not in lengths:
        lengths.append("full")
        added_lengths.append("full")
    if has_web_long and "long" not in lengths:
        lengths.append("long")
        added_lengths.append("long")
    # Preserve ordering: short, full, long
    order = {"short": 0, "full": 1, "long": 2}
    meta["lengths"] = sorted(set(lengths), key=lambda x: order.get(x, 99))

    files = meta.get("files", {})

    # WEB Full
    if has_web_full and "full" not in files:
        files["full"] = {"storyText": f"story_{sid}_traditional_web_full.txt"}
        added_keys.append("full")
    # WEB Long
    if has_web_long and "long" not in files:
        files["long"] = {"storyText": f"story_{sid}_traditional_web_long.txt"}
        added_keys.append("long")
    # KJV Full
    if has_kjv_full and "full_kjv" not in files:
        files["full_kjv"] = {"storyText": f"story_{sid}_traditional_kjv_full.txt"}
        added_keys.append("full_kjv")
    elif has_kjv_full and "storyText" not in files.get("full_kjv", {}):
        files["full_kjv"]["storyText"] = f"story_{sid}_traditional_kjv_full.txt"
        added_keys.append("full_kjv (storyText)")
    # KJV Long
    if has_kjv_long and "long_kjv" not in files:
        files["long_kjv"] = {"storyText": f"story_{sid}_traditional_kjv_long.txt"}
        added_keys.append("long_kjv")

    meta["files"] = files

    meta_path.write_text(json.dumps(meta, indent=2, ensure_ascii=False) + "\n")
    return (added_lengths, added_keys)


def manifest_entry_for(sid: int, lane: str, length: str, all_entries: list[dict]) -> dict | None:
    """
    Build a new manifest entry for a (story, lane, length) by cloning the existing
    short entry of the same lane (or, if KJV short doesn't exist, the WEB short).
    Returns None if no template entry can be found.
    """
    # Find existing entry of same lane + short
    template = None
    for e in all_entries:
        if f"/{sid}/" in e.get("textFilePath", "") and e.get("languageStyle") == lane and e.get("storyLength") == "short":
            template = e
            break
    # Fallback to WEB short if KJV not present
    if template is None and lane == "KJV":
        for e in all_entries:
            if f"/{sid}/" in e.get("textFilePath", "") and e.get("languageStyle") == "WEB" and e.get("storyLength") == "short":
                template = e
                break
    if template is None:
        return None

    new_entry = dict(template)

    # Adjust storyId
    sid_str = new_entry["storyId"]
    # Pattern: story_<id>_<mood>_short_traditional[_kjv]
    if lane == "KJV":
        new_id = re.sub(r"_short(_traditional)(_kjv)?$", f"_{length}\\1_kjv", sid_str)
        # If the WEB template was used, we still want _kjv suffix
        if not new_id.endswith("_kjv"):
            new_id += "_kjv"
    else:
        new_id = re.sub(r"_short(_traditional)(_kjv)?$", f"_{length}\\1", sid_str)
        if new_id.endswith("_kjv"):
            new_id = new_id[:-4]
    new_entry["storyId"] = new_id

    new_entry["storyLength"] = length
    new_entry["translationId"] = lane
    new_entry["languageStyle"] = lane

    # Adjust text file path
    lane_token = "kjv" if lane == "KJV" else "web"
    new_entry["textFilePath"] = f"traditional/{sid}/story_{sid}_traditional_{lane_token}_{length}.txt"

    # Adjust scripture path
    new_entry["scriptureTextFilePath"] = f"traditional/{sid}/scripture_{sid}_{lane_token}.txt"

    # Audio path: only set if the .mp3 already exists on disk. The
    # manifest_integrity_test contract treats a non-empty audioFilePath as
    # a guarantee the file exists; canonical-but-not-yet-rendered paths
    # would fail that contract. Leave empty until the render pipeline
    # populates it.
    if lane == "KJV":
        canonical_audio = f"traditional/{sid}/audio_{sid}_story_kjv_{length}.mp3"
    else:
        canonical_audio = f"traditional/{sid}/audio_{sid}_story_{length}.mp3"
    audio_file = ROOT / "assets" / "stories" / canonical_audio
    new_entry["audioFilePath"] = canonical_audio if audio_file.exists() else ""

    # Clear reflectionAudioPath since audio isn't generated for new variants
    new_entry["reflectionAudioPath"] = ""

    return new_entry


def update_manifest(ids: list[int]):
    manifest = json.loads(MANIFEST.read_text())
    parables = manifest.get("parables", [])

    # Index existing entries
    existing_keys = set()
    for e in parables:
        existing_keys.add((e.get("textFilePath", ""), e.get("languageStyle", "")))

    added = []
    for sid in ids:
        story_dir = TRAD / str(sid)
        for lane in ("WEB", "KJV"):
            for length in ("short", "full", "long"):
                lane_token = "kjv" if lane == "KJV" else "web"
                text_path = f"traditional/{sid}/story_{sid}_traditional_{lane_token}_{length}.txt"
                file_on_disk = story_dir / f"story_{sid}_traditional_{lane_token}_{length}.txt"
                if not file_on_disk.exists():
                    continue
                key = (text_path, lane)
                if key in existing_keys:
                    continue
                new_entry = manifest_entry_for(sid, lane, length, parables)
                if new_entry is None:
                    print(f"  WARN: no template for {sid} {lane} {length}", file=sys.stderr)
                    continue
                parables.append(new_entry)
                existing_keys.add(key)
                added.append((sid, lane, length))

    manifest["parables"] = parables
    MANIFEST.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    return added


def main():
    parser = argparse.ArgumentParser(description="Register Full/Long story files in meta + manifest")
    parser.add_argument("--set", choices=["grow", "tier1", "tier2", "tier3"], default="grow",
                        help="Which set of story IDs to register (default: grow)")
    parser.add_argument("--ids", nargs="+", type=int,
                        help="Override with explicit story IDs (overrides --set)")
    args = parser.parse_args()

    if args.ids:
        ids = args.ids
    elif args.set == "tier1":
        ids = TIER1_IDS
    elif args.set == "tier2":
        ids = TIER2_IDS
    elif args.set == "tier3":
        ids = TIER3_IDS
    else:
        ids = GROW_IDS

    print(f"Updating meta files for {len(ids)} stories ({args.set if not args.ids else 'explicit'})...")
    meta_summary = []
    for sid in ids:
        try:
            lengths_added, keys_added = update_meta(sid)
            if lengths_added or keys_added:
                meta_summary.append((sid, lengths_added, keys_added))
                print(f"  {sid}: +lengths={lengths_added} +keys={keys_added}")
            else:
                print(f"  {sid}: no-op (already registered)")
        except Exception as e:
            print(f"  {sid}: ERROR {e}", file=sys.stderr)
            sys.exit(1)

    print(f"\nMeta updates: {len(meta_summary)} stories modified")

    print("\nUpdating manifest.json...")
    added = update_manifest(ids)
    print(f"\nManifest entries added: {len(added)}")
    by_lane_len = {}
    for sid, lane, length in added:
        by_lane_len[(lane, length)] = by_lane_len.get((lane, length), 0) + 1
    for (lane, length), n in sorted(by_lane_len.items()):
        print(f"  {lane} {length}: {n}")


if __name__ == "__main__":
    main()
