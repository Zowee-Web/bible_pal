#!/usr/bin/env python3
"""
One-time migration: normalize 800-series legacy meta files to
schema-compatible archival format. NOT a production migration.

Usage:
    python3 scripts/migrate_800_meta.py --dry-run   # preview changes
    python3 scripts/migrate_800_meta.py              # apply changes
"""

import argparse
import json
import glob
import os
import sys
from collections import OrderedDict

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
TRADITIONAL_DIR = os.path.join(PROJECT_ROOT, 'assets', 'stories', 'traditional')
REGISTRY_PATH = os.path.join(PROJECT_ROOT, 'assets', 'stories',
                              'scripture_anchor_registry.json')

# ── Manual overrides for anchors absent from the registry ──────────────

MANUAL_OVERRIDES = {
    "Romans 8:28": {
        "scriptureAnchorId": "rom_8_28",
        "bibleStoryKey": "all_things_work_together",
    },
    "Psalm 100": {
        "scriptureAnchorId": "ps_100",
        "bibleStoryKey": "make_a_joyful_noise",
    },
    "Psalm 127:1-2": {
        "scriptureAnchorId": "ps_127_1_2",
        "bibleStoryKey": "unless_the_lord_builds",
    },
    "Psalm 19:1-6": {
        "scriptureAnchorId": "ps_19_1_6",
        "bibleStoryKey": "heavens_declare_gods_glory",
    },
}

# ── Human-readable titles keyed by bibleStoryKey ──────────────────────

TITLE_MAP = {
    "all_things_work_together": "All Things Work Together",
    "daniel_lions_den": "Daniel in the Lion's Den",
    "david_and_goliath": "David and Goliath",
    "elijah_at_horeb": "Elijah at Horeb",
    "gideons_three_hundred": "Gideon's Three Hundred",
    "god_is_our_refuge": "God Is Our Refuge",
    "hagar_in_wilderness": "Hagar in the Wilderness",
    "heavens_declare_gods_glory": "The Heavens Declare God's Glory",
    "jesus_calms_storm": "Jesus Calms the Storm",
    "joseph_interprets_pharaohs_dreams": "Joseph Interprets Pharaoh's Dreams",
    "lost_sheep": "The Lost Sheep",
    "make_a_joyful_noise": "Make a Joyful Noise",
    "mary_and_martha": "Mary and Martha",
    "moses_and_jethro": "Moses and Jethro",
    "peter_walks_on_water": "Peter Walks on Water",
    "prodigal_son": "The Prodigal Son",
    "queen_esther": "Queen Esther",
    "rest_for_the_weary": "Rest for the Weary",
    "road_to_emmaus": "The Road to Emmaus",
    "ruth_and_naomi": "Ruth and Naomi",
    "samuel_listens": "Samuel Listens",
    "the_lord_is_my_shepherd": "The Lord Is My Shepherd",
    "unless_the_lord_builds": "Unless the Lord Builds",
    "wings_like_eagles": "Wings Like Eagles",
    "woman_at_well": "The Woman at the Well",
}

# ── Canonical field order for consistent formatting ───────────────────

KEY_ORDER = [
    'schemaVersion', 'storyId', 'mode', 'kidFriendly', 'source',
    'languageStyle', 'mood', 'scriptureAnchor', 'scriptureAnchorId',
    'bibleStoryKey', 'title', 'lengths', 'voiceKey', 'storyVoiceKey',
    'reflectionVoiceKey', 'voiceKeys', 'createdByModel',
    'generationBatch', 'generationContractVersion',
    'reflectionQuestion', 'files', 'reflectionText',
    'reflectionSource', 'reflections', 'wordCountFlags',
    'boundaryValidation',
]


def normalize_ref(ref):
    """Normalize scripture reference: en-dash to hyphen."""
    return ref.replace('\u2013', '-').strip()


def load_registry():
    """Load scripture anchor registry; build bibleSourceRef -> entry lookup."""
    with open(REGISTRY_PATH, 'r') as f:
        data = json.load(f)
    lookup = {}
    for anchor in data.get('anchors', []):
        ref = normalize_ref(anchor['bibleSourceRef'])
        lookup[ref] = {
            'scriptureAnchorId': anchor['scriptureAnchorId'],
            'bibleStoryKey': anchor['bibleStoryKey'],
        }
    return lookup


def title_from_key(key):
    """Map bibleStoryKey to human-readable title."""
    if key in TITLE_MAP:
        return TITLE_MAP[key]
    return key.replace('_', ' ').title()


def canonical_order(meta):
    """Return meta dict with keys in canonical order."""
    ordered = OrderedDict()
    for key in KEY_ORDER:
        if key in meta:
            ordered[key] = meta[key]
    for key in meta:
        if key not in ordered:
            ordered[key] = meta[key]
    return dict(ordered)


def migrate_one(meta, registry):
    """Apply migration rules to one meta dict.
    Returns (meta, changes_list, manual_override_ref_or_None)."""
    changes = []
    override_used = None

    # schemaVersion
    if 'schemaVersion' not in meta:
        meta['schemaVersion'] = 2
        changes.append('added schemaVersion=2')

    # kidFriendly
    if 'kidFriendly' not in meta:
        meta['kidFriendly'] = False
        changes.append('added kidFriendly=false')

    # source marker
    if meta.get('source') != 'legacy_inferred':
        meta['source'] = 'legacy_inferred'
        changes.append('added source=legacy_inferred')

    # mood: neutral -> calm_peaceful
    if meta.get('mood') == 'neutral':
        meta['mood'] = 'calm_peaceful'
        changes.append('remapped mood: neutral -> calm_peaceful')

    # scripture anchor lookup
    anchor = normalize_ref(meta.get('scriptureAnchor', ''))
    need_id = 'scriptureAnchorId' not in meta
    need_key = 'bibleStoryKey' not in meta

    if need_id or need_key:
        entry = registry.get(anchor)
        is_manual = False
        if not entry and anchor in MANUAL_OVERRIDES:
            entry = MANUAL_OVERRIDES[anchor]
            is_manual = True
        if entry:
            if is_manual:
                override_used = anchor
            tag = ' (manual override)' if is_manual else ''
            if need_id:
                meta['scriptureAnchorId'] = entry['scriptureAnchorId']
                changes.append(
                    f'added scriptureAnchorId={entry["scriptureAnchorId"]}{tag}')
            if need_key:
                meta['bibleStoryKey'] = entry['bibleStoryKey']
                changes.append(
                    f'added bibleStoryKey={entry["bibleStoryKey"]}{tag}')
        else:
            changes.append(f'WARNING: no match for anchor "{anchor}"')

    # title
    if 'title' not in meta:
        key = meta.get('bibleStoryKey', '')
        if key:
            meta['title'] = title_from_key(key)
            changes.append(f'added title="{meta["title"]}"')
        else:
            changes.append('WARNING: cannot infer title (no bibleStoryKey)')

    # voice keys — copy voiceKey; do not delete or rename voiceKey
    voice = meta.get('voiceKey', '')
    if voice:
        if 'storyVoiceKey' not in meta:
            meta['storyVoiceKey'] = voice
            changes.append(f'added storyVoiceKey={voice}')
        if 'reflectionVoiceKey' not in meta:
            meta['reflectionVoiceKey'] = voice
            changes.append(f'added reflectionVoiceKey={voice}')

    return meta, changes, override_used


def main():
    parser = argparse.ArgumentParser(
        description='Normalize 800-series meta files to archival format')
    parser.add_argument('--dry-run', action='store_true',
                        help='Preview changes without writing files')
    args = parser.parse_args()

    registry = load_registry()
    pattern = os.path.join(TRADITIONAL_DIR,
                           '8[0-9][0-9]', 'meta_8[0-9][0-9].json')
    paths = sorted(glob.glob(pattern))

    if not paths:
        print('ERROR: no 800-series meta files found')
        sys.exit(1)

    files_changed = 0
    files_unchanged = 0
    moods_remapped = []
    overrides_used = []
    anchor_map = {}

    for path in paths:
        with open(path, 'r') as f:
            original = f.read()
        meta = json.loads(original)
        sid = meta.get('storyId', '?')

        ref = normalize_ref(meta.get('scriptureAnchor', ''))
        anchor_map.setdefault(ref, []).append(sid)

        meta, changes, override = migrate_one(meta, registry)
        if override:
            overrides_used.append((sid, override))
        if any('remapped mood' in c for c in changes):
            moods_remapped.append(sid)

        meta = canonical_order(meta)
        output = json.dumps(meta, indent=2, ensure_ascii=False) + '\n'

        if output != original:
            files_changed += 1
            rel = os.path.relpath(path, PROJECT_ROOT)
            print(f'  {rel} ({sid}):')
            for c in changes:
                print(f'    - {c}')
            if not args.dry_run:
                with open(path, 'w') as f:
                    f.write(output)
        else:
            files_unchanged += 1

    # ── Summary ───────────────────────────────────────────────────────
    print()
    print('=' * 60)
    label = 'DRY-RUN ' if args.dry_run else ''
    print(f'{label}MIGRATION SUMMARY')
    print('=' * 60)
    print(f'Files changed:   {files_changed}')
    print(f'Files unchanged: {files_unchanged}')
    print(f'Total:           {files_changed + files_unchanged}')

    if moods_remapped:
        print(f'\nMoods remapped (neutral -> calm_peaceful):')
        for s in moods_remapped:
            print(f'  - Story {s}')

    if overrides_used:
        print(f'\nManual scripture overrides used:')
        for s, ref in overrides_used:
            print(f'  - Story {s}: {ref}')

    dupes = {k: v for k, v in anchor_map.items() if len(v) > 1}
    if dupes:
        print(f'\nDuplicate scripture anchors detected:')
        for ref, sids in sorted(dupes.items()):
            print(f'  - {ref}: stories {", ".join(str(s) for s in sids)}')

    if args.dry_run:
        print('\n(No files were modified -- dry run)')


if __name__ == '__main__':
    main()
