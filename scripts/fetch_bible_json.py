#!/usr/bin/env python3
"""
Fetch public-domain Bible text (WEB) from bible-api.com and save as JSON.

Output: server/data/bible_web.json

Structure:
{
  "translation": "WEB",
  "books": {
    "Genesis": {
      "1": { "1": "In the beginning...", "2": "..." },
      ...
    }
  }
}

Only fetches the 24 books referenced by Bible PAL traditional stories.
"""

import json
import os
import sys
import time
import urllib.request
import urllib.error

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
OUTPUT_DIR = os.path.join(PROJECT_ROOT, "server", "data")

# Books referenced by current traditional stories
BOOKS = [
    "Genesis", "Exodus", "Numbers", "Joshua", "Judges", "Ruth",
    "1 Samuel", "2 Samuel", "1 Kings", "2 Kings",
    "Nehemiah", "Esther", "Job", "Psalms",
    "Isaiah", "Jeremiah",
    "Daniel", "Jonah",
    "Matthew", "Mark", "Luke", "John",
    "Acts", "Romans",
]

# bible-api.com uses these abbreviations
BOOK_ABBREVS = {
    "Genesis": "Genesis",
    "Exodus": "Exodus",
    "Numbers": "Numbers",
    "Joshua": "Joshua",
    "Judges": "Judges",
    "Ruth": "Ruth",
    "1 Samuel": "1Samuel",
    "2 Samuel": "2Samuel",
    "1 Kings": "1Kings",
    "2 Kings": "2Kings",
    "Nehemiah": "Nehemiah",
    "Esther": "Esther",
    "Job": "Job",
    "Psalms": "Psalms",
    "Isaiah": "Isaiah",
    "Jeremiah": "Jeremiah",
    "Daniel": "Daniel",
    "Jonah": "Jonah",
    "Matthew": "Matthew",
    "Mark": "Mark",
    "Luke": "Luke",
    "John": "John",
    "Acts": "Acts",
    "Romans": "Romans",
}

# Number of chapters per book (for fetching)
CHAPTER_COUNTS = {
    "Genesis": 50, "Exodus": 40, "Numbers": 36, "Joshua": 24,
    "Judges": 21, "Ruth": 4, "1 Samuel": 31, "2 Samuel": 24,
    "1 Kings": 22, "2 Kings": 25, "Nehemiah": 13, "Esther": 10,
    "Job": 42, "Psalms": 150, "Isaiah": 66, "Jeremiah": 52,
    "Daniel": 12, "Jonah": 4, "Matthew": 28, "Mark": 16,
    "Luke": 24, "John": 21, "Acts": 28, "Romans": 16,
}

# Chapters actually needed (to avoid fetching all 150 Psalms etc.)
# We only fetch chapters that our stories reference
NEEDED_CHAPTERS = {
    "Genesis": [1, 6, 12, 18, 21, 22, 28, 32, 37, 41, 45],
    "Exodus": [2, 3, 14, 16, 18],
    "Numbers": [13],
    "Joshua": [1, 3],
    "Judges": [6, 7],
    "Ruth": [1, 2],
    "1 Samuel": [3, 16, 17, 18],
    "2 Samuel": [9],
    "1 Kings": [3, 17, 18, 19],
    "2 Kings": [5, 6],
    "Nehemiah": [2],
    "Esther": [4, 5, 6, 7],
    "Job": [1, 42],
    "Psalms": [19, 23, 46, 100, 121, 127, 139],
    "Isaiah": [6, 40],
    "Jeremiah": [18],
    "Daniel": [3, 6],
    "Jonah": [1],
    "Matthew": [2, 6, 11, 14],
    "Mark": [4],
    "Luke": [2, 5, 10, 12, 15, 17, 19, 24],
    "John": [4, 21],
    "Acts": [3],
    "Romans": [8],
}


def fetch_chapter(book_abbrev: str, chapter: int, translation: str = "web", max_retries: int = 3) -> dict:
    """Fetch a single chapter from bible-api.com. Returns {verse_num: text}."""
    url = f"https://bible-api.com/{book_abbrev}+{chapter}?translation={translation}"
    for attempt in range(max_retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "BiblePAL/1.0"})
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            verses = {}
            for v in data.get("verses", []):
                verse_num = str(v["verse"])
                text = v["text"].strip()
                verses[verse_num] = text
            return verses
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < max_retries - 1:
                wait = 5 * (attempt + 1)
                print(f"rate limited, waiting {wait}s...", end=" ", flush=True)
                time.sleep(wait)
                continue
            print(f"  ERROR fetching {book_abbrev} {chapter}: {e}", file=sys.stderr)
            return {}
        except (urllib.error.URLError, json.JSONDecodeError) as e:
            print(f"  ERROR fetching {book_abbrev} {chapter}: {e}", file=sys.stderr)
            return {}
    return {}


def main():
    translation = sys.argv[1] if len(sys.argv) > 1 else "web"
    trans_upper = translation.upper()
    output_path = os.path.join(OUTPUT_DIR, f"bible_{translation}.json")

    print(f"Fetching {trans_upper} Bible text for {len(NEEDED_CHAPTERS)} books...")
    print(f"Output: {output_path}")
    print()

    # Resume from existing file if present
    bible = {"translation": trans_upper, "books": {}}
    if os.path.exists(output_path):
        with open(output_path, "r", encoding="utf-8") as f:
            bible = json.load(f)
        print(f"Resuming from existing file ({len(bible['books'])} books loaded)")
        print()
    total_chapters = sum(len(chs) for chs in NEEDED_CHAPTERS.values())
    fetched = 0

    for book in BOOKS:
        if book not in NEEDED_CHAPTERS:
            continue
        abbrev = BOOK_ABBREVS[book]
        chapters = NEEDED_CHAPTERS[book]

        # Use "Psalm" as the key (matches bibleSourceRef format) but "Psalms" for API
        book_key = "Psalm" if book == "Psalms" else book
        bible["books"][book_key] = {}

        for ch in chapters:
            fetched += 1
            ch_str = str(ch)
            # Skip if already fetched
            if book_key in bible["books"] and ch_str in bible["books"][book_key] and bible["books"][book_key][ch_str]:
                print(f"  [{fetched}/{total_chapters}] {book} {ch}... cached ({len(bible['books'][book_key][ch_str])} verses)")
                continue
            print(f"  [{fetched}/{total_chapters}] {book} {ch}...", end=" ", flush=True)
            verses = fetch_chapter(abbrev, ch, translation)
            if verses:
                bible["books"][book_key][str(ch)] = verses
                print(f"{len(verses)} verses")
                # Save incrementally
                with open(output_path, "w", encoding="utf-8") as f:
                    json.dump(bible, f, indent=2, ensure_ascii=False)
            else:
                print("FAILED")
            time.sleep(1.0)  # Rate limit — be respectful

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(bible, f, indent=2, ensure_ascii=False)

    total_verses = sum(
        len(verses)
        for book_data in bible["books"].values()
        for verses in book_data.values()
    )
    print(f"\nDone. {len(bible['books'])} books, {total_verses} total verses.")
    print(f"Saved to {output_path}")


if __name__ == "__main__":
    main()
