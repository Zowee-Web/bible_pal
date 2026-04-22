#!/usr/bin/env python3
"""
Programmatic sanity check for PALs Paths deduplication.
Reads the real manifest.json and simulates the PathService dedupe logic.
"""

import json
import os
import sys


def load_manifest():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    manifest_path = os.path.join(project_root, "assets", "stories", "manifest.json")
    with open(manifest_path, "r") as f:
        return json.load(f)


def dedupe_key(story):
    """Match PathService._dedupeKey logic."""
    bsk = story.get("bibleStoryKey", "")
    if bsk:
        return bsk
    ref = story.get("bibleSourceRef", "")
    if ref:
        return ref
    return story.get("storyId", "")


def pick_representative(variants):
    """Match PathService._pickRepresentative logic."""
    if len(variants) == 1:
        return variants[0]
    web = [v for v in variants if v.get("languageStyle") == "WEB"]
    pool = web if web else variants
    for pref in ["short", "full", "long"]:
        match = [v for v in pool if v.get("storyLength") == pref]
        if match:
            return match[0]
    return pool[0]


def deduplicate(stories):
    """Match PathService._deduplicateStories logic."""
    groups = {}
    order = []
    for s in stories:
        key = dedupe_key(s)
        if key not in groups:
            groups[key] = []
            order.append(key)
        groups[key].append(s)

    result = []
    for key in order:
        result.append(pick_representative(groups[key]))
    return result


def report_character(stories, char_id, label):
    """Report raw vs deduped for a character path."""
    # Filter traditional only
    matches = [
        s for s in stories
        if s.get("storytellingMode") == "traditional"
        and s.get("primaryCharacterId") == char_id
    ]

    deduped = deduplicate(matches)

    print(f"\n{'='*60}")
    print(f"  {label} (primaryCharacterId: {char_id})")
    print(f"{'='*60}")
    print(f"  Raw variant count:   {len(matches)}")
    print(f"  Deduped story count: {len(deduped)}")
    print()

    if not deduped:
        print("  (no stories)")
        return

    for i, s in enumerate(deduped, 1):
        sid = s.get("storyId", "?")
        title = s.get("title", "?")
        lang = s.get("languageStyle", "?")
        length = s.get("storyLength", "?")
        ref = s.get("bibleSourceRef", "—")
        key = dedupe_key(s)

        # Count how many variants exist for this story
        all_variants = [
            m for m in matches if dedupe_key(m) == key
        ]
        variant_labels = [
            f"{v.get('languageStyle','?')}/{v.get('storyLength','?')}"
            for v in all_variants
        ]

        print(f"  {i}. {title}")
        print(f"     ID: {sid}")
        print(f"     Ref: {ref}")
        print(f"     Representative: {lang}/{length}")
        print(f"     All variants ({len(all_variants)}): {', '.join(variant_labels)}")
        print()


def main():
    manifest = load_manifest()
    stories = manifest.get("parables", [])
    print(f"Loaded {len(stories)} total manifest entries")
    traditional = [s for s in stories if s.get("storytellingMode") == "traditional"]
    print(f"Traditional entries: {len(traditional)}")

    # Character paths to check
    checks = [
        ("jonah", "Jonah"),
        ("paul", "Paul"),
        ("mary", "Mary"),
        ("david", "David"),
        ("moses", "Moses"),
        ("prodigal_son", "Prodigal Son (parable)"),
        ("lost_sheep", "Lost Sheep (parable)"),
    ]

    for char_id, label in checks:
        report_character(stories, char_id, label)

    # Jesus life path (special — uses curated sequence, but let's check raw)
    print(f"\n{'='*60}")
    print(f"  Jesus (raw character count, NOT curated path)")
    print(f"{'='*60}")
    jesus_matches = [
        s for s in traditional
        if s.get("primaryCharacterId") == "jesus"
    ]
    jesus_deduped = deduplicate(jesus_matches)
    print(f"  Raw variant count:   {len(jesus_matches)}")
    print(f"  Deduped story count: {len(jesus_deduped)}")
    print(f"  (Jesus Life path uses a curated subset of these)")
    print()
    for i, s in enumerate(jesus_deduped, 1):
        title = s.get("title", "?")
        ref = s.get("bibleSourceRef", "—")
        lang = s.get("languageStyle", "?")
        length = s.get("storyLength", "?")
        print(f"  {i}. {title} | {ref} | {lang}/{length}")

    # Summary
    print(f"\n{'='*60}")
    print(f"  SUMMARY")
    print(f"{'='*60}")
    all_deduped = deduplicate(traditional)
    print(f"  Total traditional variants: {len(traditional)}")
    print(f"  Total unique stories:       {len(all_deduped)}")
    print(f"  Dedup ratio:                {len(traditional)}/{len(all_deduped)} = {len(traditional)/max(len(all_deduped),1):.1f}x")


if __name__ == "__main__":
    main()
