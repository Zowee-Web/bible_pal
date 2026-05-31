#!/usr/bin/env python3
"""
Fix scripture_anchor_registry.json to satisfy
traditional_canonical_story_map_test and traditional_bible_story_test:

1. Disambiguate 3 duplicate scriptureAnchorIds by appending the
   bibleStoryKey suffix. Same scripture can legitimately back multiple
   distinct stories (e.g., Mark 4:35-41 covered by both jesus_calms_storm
   and jesus_calms_storm_who_then_is_this); each needs its own unique
   scriptureAnchorId.
2. Replace 2 invalid moodTags with valid ones from the locked 8-mood
   vocabulary:
     - "hopeful" → "encouraging"
     - "awed"    → "grateful"
3. Add 6 missing registry entries derived from manifest data so every
   manifest bibleStoryKey resolves in the registry.

Conservative: existing valid entries untouched. Idempotent: safe to
re-run once registry is in sync.
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "assets" / "stories" / "scripture_anchor_registry.json"
MANIFEST = ROOT / "assets" / "stories" / "manifest.json"

VALID_MOODS = {
    "joyful", "grateful", "anxious", "hurting", "weary",
    "brave_courage", "calm_peaceful", "encouraging",
}

MOOD_FIXES = {
    "hopeful": "encouraging",
    "awed":    "grateful",
}

# scriptureAnchorIds that have multiple entries (legitimate — same passage,
# different story keys). Each entry's ID gets disambiguated by appending
# the bibleStoryKey for uniqueness.
DISAMBIGUATE_IDS = {"ezra_3_10-13", "mark_4_35-41", "mark_5_25-34"}

# Missing registry entries (derived from manifest by inspection).
# Naming convention for scriptureAnchorId disambiguation: when the same
# scripture passage backs multiple distinct bibleStoryKeys (legitimate
# editorial pattern), prepend the bibleStoryKey to the scripture base so
# both entries get unique IDs while the verse-range hyphen stays at the
# end of the string (required by the format regex
# ^[a-z0-9]+(_[a-z0-9]+)*(-[a-z0-9]+)?$).
MISSING_ENTRIES = [
    {
        "scriptureAnchorId": "comfort_my_people_isaiah_40_1-11",
        "bibleStoryKey": "comfort_my_people",
        "bibleSourceRef": "Isaiah 40:1-11",
        "moodTags": ["encouraging"],
    },
    {
        "scriptureAnchorId": "esther_decision_4_1-17",
        "bibleStoryKey": "esther_decision",
        "bibleSourceRef": "Esther 4:1-17",
        "moodTags": ["brave_courage"],
    },
    {
        "scriptureAnchorId": "hannah_song_1_samuel_2_1-10",
        "bibleStoryKey": "hannah_song",
        "bibleSourceRef": "1 Samuel 2:1-10",
        "moodTags": ["grateful"],
    },
    {
        "scriptureAnchorId": "nehemiah_prays_nehemiah_1_1-11",
        "bibleStoryKey": "nehemiah_prays",
        "bibleSourceRef": "Nehemiah 1:1-11",
        "moodTags": ["hurting"],
    },
    {
        "scriptureAnchorId": "the_lord_is_my_light_psalm_27_1-14",
        "bibleStoryKey": "the_lord_is_my_light",
        "bibleSourceRef": "Psalm 27:1-14",
        "moodTags": ["calm_peaceful"],
    },
    {
        "scriptureAnchorId": "wearied_servant_prophet_isaiah_50_4-9",
        "bibleStoryKey": "wearied_servant_prophet",
        "bibleSourceRef": "Isaiah 50:4-9",
        "moodTags": ["weary"],
    },
]


def main():
    registry = json.loads(REGISTRY.read_text())
    anchors = registry["anchors"]

    # Index existing keys for idempotency
    existing_keys = {a["bibleStoryKey"] for a in anchors}

    # 1. Disambiguate duplicate scriptureAnchorIds
    disambiguated = 0
    for a in anchors:
        if a["scriptureAnchorId"] in DISAMBIGUATE_IDS:
            new_id = f"{a['scriptureAnchorId']}_{a['bibleStoryKey']}"
            if a["scriptureAnchorId"] != new_id:
                a["scriptureAnchorId"] = new_id
                disambiguated += 1

    # 2. Fix invalid moodTags
    mood_fixes_applied = 0
    for a in anchors:
        new_moods = []
        for m in a.get("moodTags", []):
            if m in MOOD_FIXES:
                new_moods.append(MOOD_FIXES[m])
                mood_fixes_applied += 1
            elif m in VALID_MOODS:
                new_moods.append(m)
            else:
                # Unknown mood not in our fix map — log but keep so we can see it
                print(f"  WARN: unknown mood {m!r} on {a['bibleStoryKey']}", )
                new_moods.append(m)
        a["moodTags"] = new_moods

    # 3. Add missing entries
    added = 0
    for entry in MISSING_ENTRIES:
        if entry["bibleStoryKey"] in existing_keys:
            continue
        anchors.append(entry)
        added += 1

    # Re-sort by scriptureAnchorId for stable diffs (optional but nice)
    anchors.sort(key=lambda a: a["scriptureAnchorId"])

    registry["anchors"] = anchors
    REGISTRY.write_text(json.dumps(registry, indent=2, ensure_ascii=False) + "\n")

    print(f"Disambiguated scriptureAnchorIds: {disambiguated}")
    print(f"Invalid moodTags fixed:           {mood_fixes_applied}")
    print(f"Missing entries added:            {added}")
    print(f"Total anchors now:                {len(anchors)}")


if __name__ == "__main__":
    main()
