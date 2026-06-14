#!/usr/bin/env python3
"""
Promote on-disk Traditional stories into manifest.json + the scripture anchor
registry, and backfill each story's meta `scriptureAnchorId`.

R2-served delivery: the remote catalog is derived from manifest.json
(scripts/upload_r2_catalog.sh), so a manifest entry is all that's required for
the app to serve a story remotely. No pubspec entry is added.

For each story id this script:
  1. derives scriptureAnchorId from the meta's scriptureAnchor
     ("Deuteronomy 30:11-20" -> "deuteronomy_30_11-20"), matching the
     registry's existing full-book-name convention;
  2. writes scriptureAnchorId into meta_{id}.json if absent;
  3. appends one registry entry per story (moodTags = [meta.mood], satisfying
     the traditional_bible_story_test mood<->anchor invariant);
  4. appends one manifest entry per (length x lane), field-for-field matching
     the canonical recent entry shape (story 1521), reading the per-lane
     reflection file for the lane-specific reflectionQuestion.

Conservative + idempotent: skips any manifest storyId or registry anchorId
that already exists; re-running after a successful promotion is a no-op.
Dry-run by default; pass --write to apply. Formatting uses indent=2,
ensure_ascii=True (a byte-identical round-trip for both JSON files), so the
diff is limited to appended entries.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STORIES = ROOT / "assets" / "stories"
MANIFEST = STORIES / "manifest.json"
REGISTRY = STORIES / "scripture_anchor_registry.json"

IDS = list(range(1552, 1562))
TRANS_SUFFIX = re.compile(r"\s*\((?:WEB|KJV|ASV|YLT|DRA)\)\s*$")
LANES = [("web", "WEB"), ("kjv", "KJV")]


def anchor_id(ref: str) -> str:
    """'2 Samuel 12:1-13' -> '2_samuel_12_1-13' (registry convention)."""
    return ref.strip().lower().replace(":", " ").replace(" ", "_")


def read_reflection(story_dir: Path, sid: int, lane: str) -> str:
    p = story_dir / f"reflection_{sid}_traditional_{lane}.txt"
    return p.read_text(encoding="utf-8").strip()


def manifest_entry(meta: dict, sid: int, length: str, lane: str, trans: str,
                   reflection_q: str) -> dict:
    suffix = "" if lane == "web" else "_kjv"
    audio = (f"traditional/{sid}/audio_{sid}_story_{length}.mp3" if lane == "web"
             else f"traditional/{sid}/audio_{sid}_story_kjv_{length}.mp3")
    refl_audio = (f"traditional/{sid}/audio_{sid}_reflection.mp3" if lane == "web"
                  else f"traditional/{sid}/audio_{sid}_reflection_kjv.mp3")
    voice = meta["storyVoiceKey"]
    # canonical field order matches story 1521's manifest entry
    return {
        "storyId": f"story_{sid}_{meta['mood']}_{length}_traditional{suffix}",
        "title": meta["title"],
        "mood": meta["mood"],
        "emotionalTags": meta.get("emotionalTags", []),
        "storytellingMode": "traditional",
        "kidFriendly": meta["kidFriendly"],
        "textFilePath": f"traditional/{sid}/story_{sid}_traditional_{lane}_{length}.txt",
        "translationId": trans,
        "languageStyle": trans,
        "narratorVoiceKey": voice,
        "storyLength": length,
        "bibleSourceRef": meta["scriptureAnchor"],
        "bibleStoryKey": meta["bibleStoryKey"],
        "audioFilePath": audio,
        "reflectionAudioPath": refl_audio,
        "primaryCharacterId": meta["primaryCharacterId"],
        "primaryCharacterDisplayName": meta["primaryCharacterDisplayName"],
        "bibleOrderIndex": meta["bibleOrderIndex"],
        "timelineEra": meta["timelineEra"],
        "themeTags": meta.get("themeTags", []),
        "reflectionQuestion": reflection_q,
        "shortScripture": meta.get("shortScripture", False),
        "mode": "traditional",
        "scriptureAnchor": meta["scriptureAnchor"],
        "storyVoiceKey": voice,
        "scriptureTextFilePath": f"traditional/{sid}/scripture_{sid}_{lane}.txt",
    }


def dump(path: Path, obj, write: bool):
    out = json.dumps(obj, indent=2, ensure_ascii=True)
    if not out.endswith("\n"):
        out += "\n"
    if write:
        path.write_text(out, encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true", help="apply changes")
    args = ap.parse_args()

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    existing_story_ids = {p["storyId"] for p in manifest["parables"]}
    existing_anchor_ids = {a["scriptureAnchorId"] for a in registry["anchors"]}

    new_manifest, new_registry, meta_patches = [], [], []
    for sid in IDS:
        d = STORIES / "traditional" / str(sid)
        meta_path = d / f"meta_{sid}.json"
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
        aid = anchor_id(meta["scriptureAnchor"])

        # 1. meta scriptureAnchorId backfill
        if meta.get("scriptureAnchorId") != aid:
            meta_patches.append((sid, meta.get("scriptureAnchorId"), aid))
            # preserve key position: insert right after scriptureAnchor
            rebuilt = {}
            for k, v in meta.items():
                rebuilt[k] = v
                if k == "scriptureAnchor":
                    rebuilt["scriptureAnchorId"] = aid
            if "scriptureAnchorId" not in rebuilt:
                rebuilt["scriptureAnchorId"] = aid
            dump(meta_path, rebuilt, args.write)

        # 2. registry entry
        if aid not in existing_anchor_ids:
            new_registry.append({
                "scriptureAnchorId": aid,
                "bibleStoryKey": meta["bibleStoryKey"],
                "bibleSourceRef": meta["scriptureAnchor"],
                "moodTags": [meta["mood"]],
            })
            existing_anchor_ids.add(aid)

        # 3. manifest entries (length x lane)
        for length in meta["lengths"]:
            for lane, trans in LANES:
                refl_q = read_reflection(d, sid, lane)
                e = manifest_entry(meta, sid, length, lane, trans, refl_q)
                if e["storyId"] in existing_story_ids:
                    continue
                new_manifest.append(e)
                existing_story_ids.add(e["storyId"])

    manifest["parables"].extend(new_manifest)
    registry["anchors"].extend(new_registry)
    dump(MANIFEST, manifest, args.write)
    dump(REGISTRY, registry, args.write)

    mode = "APPLIED" if args.write else "DRY-RUN (use --write to apply)"
    print(f"=== promote_traditional_stories {mode} ===")
    print(f"meta scriptureAnchorId backfilled: {len(meta_patches)}")
    for sid, old, new in meta_patches:
        print(f"  {sid}: {old!r} -> {new!r}")
    print(f"registry entries added: {len(new_registry)}")
    for r in new_registry:
        print(f"  {r['scriptureAnchorId']:<26} moodTags={r['moodTags']}")
    print(f"manifest entries added: {len(new_manifest)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
