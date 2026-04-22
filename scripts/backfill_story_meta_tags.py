#!/usr/bin/env python3
"""
backfill_story_meta_tags.py — Backfill missing timelineEra and primaryCharacter
fields in Traditional story meta files.

Only patches MISSING fields. Never overwrites existing values.
Supports --dry-run mode.

Usage:
  python3 scripts/backfill_story_meta_tags.py --dry-run
  python3 scripts/backfill_story_meta_tags.py
"""

import argparse
import json
import glob
import os
import re
import sys

# ── Book → Timeline Era mapping ──────────────────────────────────────────

BOOK_TO_ERA = {
    # Patriarchs
    "genesis": "patriarchs",
    # Exodus / Wilderness
    "exodus": "exodus",
    "leviticus": "exodus",
    "numbers": "exodus",
    "deuteronomy": "exodus",
    # Conquest
    "joshua": "conquest",
    # Judges
    "judges": "judges",
    "ruth": "judges",
    # Kingdom (United + Divided)
    "1 samuel": "kingdom",
    "2 samuel": "kingdom",
    "1 kings": "kingdom",
    "2 kings": "kingdom",
    "1 chronicles": "kingdom",
    "2 chronicles": "kingdom",
    # Exile
    "daniel": "exile",
    "ezekiel": "exile",
    "lamentations": "exile",
    # Return
    "ezra": "return",
    "nehemiah": "return",
    "esther": "exile",
    # Wisdom / Poetry
    "job": "wisdom",
    "psalms": "wisdom",
    "psalm": "wisdom",
    "proverbs": "wisdom",
    "ecclesiastes": "wisdom",
    "song of solomon": "wisdom",
    # Prophets
    "isaiah": "prophets",
    "jeremiah": "prophets",
    "hosea": "prophets",
    "joel": "prophets",
    "amos": "prophets",
    "obadiah": "prophets",
    "jonah": "prophets",
    "micah": "prophets",
    "nahum": "prophets",
    "habakkuk": "prophets",
    "zephaniah": "prophets",
    "haggai": "prophets",
    "zechariah": "prophets",
    "malachi": "prophets",
    # Gospels
    "matthew": "jesus_ministry",
    "mark": "jesus_ministry",
    "luke": "jesus_ministry",
    "john": "jesus_ministry",
    # Early Church
    "acts": "early_church",
    "romans": "early_church",
    "1 corinthians": "early_church",
    "2 corinthians": "early_church",
    "galatians": "early_church",
    "ephesians": "early_church",
    "philippians": "early_church",
    "colossians": "early_church",
    "1 thessalonians": "early_church",
    "2 thessalonians": "early_church",
    "1 timothy": "early_church",
    "2 timothy": "early_church",
    "titus": "early_church",
    "philemon": "early_church",
    "hebrews": "early_church",
    "james": "early_church",
    "1 peter": "early_church",
    "2 peter": "early_church",
    "1 john": "early_church",
    "2 john": "early_church",
    "3 john": "early_church",
    "jude": "early_church",
    "revelation": "early_church",
}

# ── Known scripture anchor → character mapping ───────────────────────────
# For stories where the character is unambiguous from the anchor.
# Key = lowercase bibleStoryKey or partial anchor match.

KNOWN_CHARACTERS = {
    # Patriarchs
    "genesis 1": ("god", "God"),
    "genesis 6": ("noah", "Noah"),
    "genesis 12": ("abraham", "Abraham"),
    "genesis 18": ("abraham", "Abraham"),
    "genesis 22": ("abraham", "Abraham"),
    "genesis 28": ("jacob", "Jacob"),
    "genesis 32": ("jacob", "Jacob"),
    "genesis 37": ("joseph", "Joseph"),
    "genesis 41": ("joseph", "Joseph"),
    "genesis 45": ("joseph", "Joseph"),
    "genesis 21": ("hagar", "Hagar"),
    # Exodus
    "exodus 2": ("moses", "Moses"),
    "exodus 3": ("moses", "Moses"),
    "exodus 14": ("moses", "Moses"),
    "exodus 16": ("moses", "Moses"),
    "exodus 18": ("moses", "Moses"),
    # Joshua / Judges
    "joshua 1": ("joshua", "Joshua"),
    "joshua 3": ("joshua", "Joshua"),
    "joshua 6": ("joshua", "Joshua"),
    "judges 6": ("gideon", "Gideon"),
    "judges 7": ("gideon", "Gideon"),
    "ruth 1": ("ruth", "Ruth"),
    "ruth 2": ("ruth", "Ruth"),
    # Samuel / Kings
    "1 samuel 3": ("samuel", "Samuel"),
    "1 samuel 16": ("david", "David"),
    "1 samuel 17": ("david", "David"),
    "1 samuel 18": ("david", "David"),
    "2 samuel 9": ("david", "David"),
    "1 kings 3": ("solomon", "Solomon"),
    "1 kings 17": ("elijah", "Elijah"),
    "1 kings 18": ("elijah", "Elijah"),
    "1 kings 19": ("elijah", "Elijah"),
    "2 kings 5": ("naaman", "Naaman"),
    "2 kings 6": ("elisha", "Elisha"),
    "2 chronicles 20": ("jehoshaphat", "Jehoshaphat"),
    # Exile
    "esther 4": ("esther", "Esther"),
    "nehemiah 2": ("nehemiah", "Nehemiah"),
    "daniel 3": ("shadrach", "Shadrach, Meshach, and Abednego"),
    "daniel 6": ("daniel", "Daniel"),
    # Wisdom
    "job 1": ("job", "Job"),
    "job 42": ("job", "Job"),
    # Prophets
    "isaiah 6": ("isaiah", "Isaiah"),
    "isaiah 40": ("isaiah", "Isaiah"),
    "jeremiah 18": ("jeremiah", "Jeremiah"),
    "jonah 1": ("jonah", "Jonah"),
    "jonah 3": ("jonah", "Jonah"),
    # Gospels — Jesus life events
    "matthew 2": ("jesus", "Jesus"),
    "matthew 3": ("jesus", "Jesus"),
    "matthew 4": ("jesus", "Jesus"),
    "matthew 8": ("jesus", "Jesus"),
    "matthew 14": ("jesus", "Jesus"),
    "matthew 17": ("jesus", "Jesus"),
    "matthew 21": ("jesus", "Jesus"),
    "mark 2": ("jesus", "Jesus"),
    "mark 4": ("jesus", "Jesus"),
    "mark 5": ("jesus", "Jesus"),
    "mark 10": ("jesus", "Jesus"),
    "mark 14": ("jesus", "Jesus"),
    "luke 1": ("mary", "Mary"),
    "luke 2": ("jesus", "Jesus"),
    "luke 5": ("jesus", "Jesus"),
    "luke 7": ("jesus", "Jesus"),
    "luke 8": ("jesus", "Jesus"),
    "luke 12": ("jesus", "Jesus"),
    "luke 17": ("jesus", "Jesus"),
    "luke 19": ("jesus", "Jesus"),
    "luke 22": ("jesus", "Jesus"),
    "luke 23": ("jesus", "Jesus"),
    "luke 24": ("jesus", "Jesus"),
    "john 4": ("jesus", "Jesus"),
    "john 5": ("jesus", "Jesus"),
    "john 8": ("jesus", "Jesus"),
    "john 9": ("jesus", "Jesus"),
    "john 11": ("jesus", "Jesus"),
    "john 13": ("jesus", "Jesus"),
    "john 20": ("jesus", "Jesus"),
    "john 21": ("jesus", "Jesus"),
    # Gospels — Parables (use story character, not Jesus)
    "luke 10:25": ("good_samaritan", "Good Samaritan"),
    "luke 15:3": ("lost_sheep", "Lost Sheep"),
    "luke 15:11": ("prodigal_son", "Prodigal Son"),
    # Acts
    "acts 3": ("peter", "Peter"),
    "acts 9": ("paul", "Paul"),
    "acts 12": ("peter", "Peter"),
    "acts 16": ("paul", "Paul"),
    "acts 27": ("paul", "Paul"),
    # Teaching / Epistle passages
    "romans 8": ("paul", "Paul"),
    # Psalms
    "psalm 23": ("david", "David"),
    "psalm 19": ("david", "David"),
    "psalm 46": ("psalmist", "The Psalmist"),
    "psalm 100": ("psalmist", "The Psalmist"),
    "psalm 121": ("psalmist", "The Psalmist"),
    "psalm 127": ("psalmist", "The Psalmist"),
    "psalm 139": ("david", "David"),
    "numbers 13": ("caleb", "Caleb"),
}

# Normalize "Matthew 11:28-30" → "matthew 11"
ANCHOR_PATTERN = re.compile(r"^(\d?\s*\w+)\s+(\d+)")


def extract_book_chapter(anchor: str) :
    """Extract (book, 'book chapter') from a scripture anchor string."""
    anchor = anchor.strip()
    m = ANCHOR_PATTERN.match(anchor)
    if m:
        book = m.group(1).strip().lower()
        chapter = m.group(2).strip()
        return book, f"{book} {chapter}"
    return anchor.lower(), anchor.lower()


def derive_era(anchor: str) :
    """Derive timelineEra from scripture anchor."""
    book, _ = extract_book_chapter(anchor)
    # Try exact book match
    if book in BOOK_TO_ERA:
        return BOOK_TO_ERA[book]
    # Try with leading number variations
    for key in BOOK_TO_ERA:
        if book.startswith(key) or key.startswith(book):
            return BOOK_TO_ERA[key]
    return None


def derive_character(anchor: str) :
    """Derive (primaryCharacterId, primaryCharacterDisplayName) from anchor."""
    _, book_chapter = extract_book_chapter(anchor)

    # Try most specific match first (e.g., "luke 10:25" for parables)
    anchor_lower = anchor.lower()
    for key in sorted(KNOWN_CHARACTERS.keys(), key=len, reverse=True):
        if anchor_lower.startswith(key):
            return KNOWN_CHARACTERS[key]

    # Then try book+chapter
    if book_chapter in KNOWN_CHARACTERS:
        return KNOWN_CHARACTERS[book_chapter]

    return None


# Gospel teaching passages that are NOT parables — Jesus is the speaker
# AND the narrative figure. These get Jesus as character.
GOSPEL_TEACHING = {
    "matthew 5", "matthew 6", "matthew 7",  # Sermon on the Mount
    "matthew 11",  # Come to me all who are weary
    "luke 12",  # Do not worry
}


def process_meta(filepath: str, dry_run: bool) :
    """Process a single meta file. Returns change dict or None."""
    with open(filepath, "r", encoding="utf-8") as f:
        meta = json.load(f)

    anchor = meta.get("scriptureAnchor", "")
    story_id = meta.get("storyId", os.path.basename(filepath))
    changes = {}
    ambiguous = []

    # --- timelineEra ---
    if not meta.get("timelineEra"):
        era = derive_era(anchor)
        if era:
            changes["timelineEra"] = era
        else:
            ambiguous.append(f"timelineEra: cannot derive from '{anchor}'")

    # --- primaryCharacterId / primaryCharacterDisplayName ---
    if not meta.get("primaryCharacterId"):
        char = derive_character(anchor)
        if char:
            changes["primaryCharacterId"] = char[0]
            changes["primaryCharacterDisplayName"] = char[1]
        else:
            # Check if it's a gospel teaching passage
            _, book_chapter = extract_book_chapter(anchor)
            if book_chapter in GOSPEL_TEACHING:
                changes["primaryCharacterId"] = "jesus"
                changes["primaryCharacterDisplayName"] = "Jesus"
            else:
                ambiguous.append(
                    f"primaryCharacter: cannot derive from '{anchor}'"
                )

    if not changes and not ambiguous:
        return None

    result = {
        "storyId": story_id,
        "title": meta.get("title", "—"),
        "anchor": anchor,
        "changes": changes,
        "ambiguous": ambiguous,
    }

    if changes and not dry_run:
        meta.update(changes)
        with open(filepath, "w", encoding="utf-8") as f:
            json.dump(meta, f, indent=2, ensure_ascii=False)
            f.write("\n")

    return result


def main():
    parser = argparse.ArgumentParser(
        description="Backfill missing timelineEra and primaryCharacter in meta files"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would change without writing files",
    )
    parser.add_argument(
        "--path",
        default="assets/stories/traditional",
        help="Path to scan (default: assets/stories/traditional)",
    )
    args = parser.parse_args()

    base_path = args.path
    if not os.path.isabs(base_path):
        script_dir = os.path.dirname(os.path.abspath(__file__))
        project_root = os.path.dirname(script_dir)
        base_path = os.path.join(project_root, base_path)

    pattern = os.path.join(base_path, "*", "meta_*.json")
    files = sorted(glob.glob(pattern))

    if not files:
        print(f"No meta files found in {base_path}")
        sys.exit(1)

    mode = "DRY RUN" if args.dry_run else "LIVE"
    print(f"\n=== BACKFILL META TAGS ({mode}) ===\n")

    updated = []
    ambiguous_list = []
    scanned = 0

    for filepath in files:
        scanned += 1
        result = process_meta(filepath, args.dry_run)
        if result:
            if result["changes"]:
                updated.append(result)
            if result["ambiguous"]:
                ambiguous_list.append(result)

    # --- Report ---
    print(f"Scanned: {scanned} meta files\n")

    if updated:
        print(f"{'Updated' if not args.dry_run else 'Would update'}: "
              f"{len(updated)} files\n")
        print(f"{'ID':<6} {'Title':<40} {'Anchor':<25} {'Changes'}")
        print("-" * 110)
        for r in updated:
            changes_str = ", ".join(
                f"{k}={v}" for k, v in r["changes"].items()
            )
            print(
                f"{r['storyId']:<6} {r['title'][:39]:<40} "
                f"{r['anchor'][:24]:<25} {changes_str}"
            )
    else:
        print("No files needed updating.\n")

    if ambiguous_list:
        print(f"\n⚠ AMBIGUOUS — needs manual review ({len(ambiguous_list)}):\n")
        for r in ambiguous_list:
            for a in r["ambiguous"]:
                print(f"  {r['storyId']} ({r['title']}): {a}")

    # --- Post-run validation ---
    print("\n--- POST-RUN VALIDATION ---")
    missing_era = 0
    missing_char = 0
    for filepath in files:
        with open(filepath, "r") as f:
            meta = json.load(f)
        if not meta.get("timelineEra"):
            missing_era += 1
        if not meta.get("primaryCharacterId"):
            missing_char += 1

    print(f"Still missing timelineEra: {missing_era}")
    print(f"Still missing primaryCharacterId: {missing_char}")
    print()

    sys.exit(0)


if __name__ == "__main__":
    main()
