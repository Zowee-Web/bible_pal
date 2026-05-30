#!/usr/bin/env python3
"""
USFM to JSON converter for Bible PAL scripture text backfill.

Parses USFM files from eBible.org WEB distribution and emits JSON matching
the existing bundled-Bible structure:

    {
      "translation": "WEB",
      "books": {
        "Genesis": { "1": { "1": "verse text", ... }, ... },
        ...
      }
    }

Only Protestant canon (66 books) is included. Apocrypha files are skipped.

USFM markers handled:
  \\c N            -> chapter marker
  \\v N text       -> verse marker
  \\w word|strong="X"\\w*  -> extract "word" only
  \\f ... \\f*     -> footnote, fully stripped
  \\fe ... \\fe*   -> end footnote, stripped
  \\x ... \\x*     -> cross-reference, stripped
  \\+wh ... \\+wh* -> Hebrew word (nested), stripped
  \\p, \\q1-4, \\b, \\m -> paragraph/poetry markers, stripped
  \\h, \\toc, \\mt, \\id, \\ide, \\rem -> metadata, stripped
  \\s, \\r          -> section/reference headings, stripped
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

# USFM file code -> canonical book name (matches existing JSON)
BOOK_CODES = {
    "GEN": "Genesis", "EXO": "Exodus", "LEV": "Leviticus", "NUM": "Numbers",
    "DEU": "Deuteronomy", "JOS": "Joshua", "JDG": "Judges", "RUT": "Ruth",
    "1SA": "1 Samuel", "2SA": "2 Samuel", "1KI": "1 Kings", "2KI": "2 Kings",
    "1CH": "1 Chronicles", "2CH": "2 Chronicles", "EZR": "Ezra", "NEH": "Nehemiah",
    "EST": "Esther", "JOB": "Job", "PSA": "Psalm", "PRO": "Proverbs",
    "ECC": "Ecclesiastes", "SNG": "Song of Solomon", "ISA": "Isaiah",
    "JER": "Jeremiah", "LAM": "Lamentations", "EZK": "Ezekiel", "DAN": "Daniel",
    "HOS": "Hosea", "JOL": "Joel", "AMO": "Amos", "OBA": "Obadiah",
    "JON": "Jonah", "MIC": "Micah", "NAM": "Nahum", "HAB": "Habakkuk",
    "ZEP": "Zephaniah", "HAG": "Haggai", "ZEC": "Zechariah", "MAL": "Malachi",
    "MAT": "Matthew", "MRK": "Mark", "LUK": "Luke", "JHN": "John",
    "ACT": "Acts", "ROM": "Romans", "1CO": "1 Corinthians", "2CO": "2 Corinthians",
    "GAL": "Galatians", "EPH": "Ephesians", "PHP": "Philippians", "COL": "Colossians",
    "1TH": "1 Thessalonians", "2TH": "2 Thessalonians", "1TI": "1 Timothy",
    "2TI": "2 Timothy", "TIT": "Titus", "PHM": "Philemon", "HEB": "Hebrews",
    "JAS": "James", "1PE": "1 Peter", "2PE": "2 Peter", "1JN": "1 John",
    "2JN": "2 John", "3JN": "3 John", "JUD": "Jude", "REV": "Revelation",
}


def clean_verse_text(text: str) -> str:
    """Strip USFM inline markup, leaving plain readable text."""
    # Remove footnotes (\f ... \f*) including content
    text = re.sub(r"\\f\s.*?\\f\*", "", text, flags=re.DOTALL)
    text = re.sub(r"\\fe\s.*?\\fe\*", "", text, flags=re.DOTALL)
    # Remove cross-references (\x ... \x*)
    text = re.sub(r"\\x\s.*?\\x\*", "", text, flags=re.DOTALL)
    # Remove nested \+wh ... \+wh* (Hebrew/Greek embedded raw words)
    text = re.sub(r"\\\+wh\s+[^\\]*\\\+wh\*", "", text)
    # Replace nested \+w word|strong="X"\+w* with just "word" (run first — inner)
    text = re.sub(r"\\\+w\s+([^|\\]+?)(?:\|[^\\]*)?\\\+w\*", r"\1", text)
    # Replace \w word|strong="X"\w* with just "word"
    text = re.sub(r"\\w\s+([^|\\]+?)(?:\|[^\\]*)?\\w\*", r"\1", text)
    # Strip other paragraph/poetry/formatting markers (no content to keep)
    text = re.sub(r"\\(?:p|m|b|q[1-9]?|li[1-9]?|pi[1-9]?|nb|cl|cls|sp|s[1-9]?|r|rem|d|periph|qa|qm[1-9]?|qr|qc|qac|qs|qt|tr|th[1-9]?|tc[1-9]?|toc[1-3]?|mt[1-9]?|ms[1-9]?|mr|imt[1-9]?|imte[1-9]?|imt|is[1-9]?|ip|ipi|im|imi|ipq|imq|ipr|iq[1-9]?|ib|ili[1-9]?|iot|io[1-9]?|iex|imte|iqt|ide|h|id|sts)\b\s?", " ", text)
    # Strip any remaining \\char ... \\char* style runs
    text = re.sub(r"\\[a-zA-Z]+\*?\s?", " ", text)
    # Normalize whitespace
    text = re.sub(r"\s+", " ", text).strip()
    return text


def parse_usfm_file(path: Path) -> tuple[str, dict[str, dict[str, str]]] | None:
    """Parse one USFM file. Returns (book_name, {chapter: {verse: text}}) or None to skip."""
    # Extract book code from filename, e.g. "02-GENeng-web.usfm" -> "GEN"
    name = path.stem  # "02-GENeng-web"
    m = re.match(r"\d+-([A-Z0-9]+)eng-web", name)
    if not m:
        return None
    code = m.group(1)
    if code not in BOOK_CODES:
        # Apocrypha or front/back matter — skip silently
        return None

    book_name = BOOK_CODES[code]
    text = path.read_text(encoding="utf-8")

    # Split on chapter markers
    chapters_raw = re.split(r"\\c\s+(\d+)", text)
    # chapters_raw[0] is everything before the first chapter (intros, etc)
    # then alternating: chapter_num, chapter_text, chapter_num, chapter_text, ...

    result: dict[str, dict[str, str]] = {}
    for i in range(1, len(chapters_raw), 2):
        ch_num = chapters_raw[i].strip()
        ch_text = chapters_raw[i + 1] if i + 1 < len(chapters_raw) else ""

        verses: dict[str, str] = {}
        # Split chapter on verse markers
        verses_raw = re.split(r"\\v\s+(\d+(?:[a-z])?)", ch_text)
        # verses_raw[0] = pre-verse text (section headings etc); ignore
        for j in range(1, len(verses_raw), 2):
            v_num = verses_raw[j].strip()
            v_text = verses_raw[j + 1] if j + 1 < len(verses_raw) else ""
            cleaned = clean_verse_text(v_text)
            if cleaned:
                # Strip any letter suffix in verse num (1a, 1b -> 1)
                v_num_int = re.match(r"\d+", v_num).group(0)
                if v_num_int in verses:
                    # Merge sub-verses (1a + 1b -> "1")
                    verses[v_num_int] = verses[v_num_int] + " " + cleaned
                else:
                    verses[v_num_int] = cleaned

        if verses:
            result[ch_num] = verses

    return book_name, result


def main():
    if len(sys.argv) < 3:
        print("Usage: usfm_to_json.py <usfm_dir> <output.json> [translation_label]", file=sys.stderr)
        sys.exit(1)

    usfm_dir = Path(sys.argv[1])
    output_path = Path(sys.argv[2])
    translation_label = sys.argv[3] if len(sys.argv) > 3 else "WEB"

    if not usfm_dir.is_dir():
        print(f"Not a directory: {usfm_dir}", file=sys.stderr)
        sys.exit(1)

    books: dict[str, dict[str, dict[str, str]]] = {}
    total_chapters = 0
    total_verses = 0
    skipped = 0

    for usfm_path in sorted(usfm_dir.glob("*.usfm")):
        result = parse_usfm_file(usfm_path)
        if result is None:
            skipped += 1
            continue
        book_name, chapters = result
        if book_name in books:
            print(f"WARNING: duplicate book {book_name} from {usfm_path.name}", file=sys.stderr)
        books[book_name] = chapters
        total_chapters += len(chapters)
        total_verses += sum(len(v) for v in chapters.values())
        print(f"  {usfm_path.name:30s} -> {book_name:20s}  ({len(chapters)} ch, {sum(len(v) for v in chapters.values())} v)")

    output = {
        "translation": translation_label,
        "books": books,
    }

    output_path.write_text(json.dumps(output, indent=2, ensure_ascii=False))
    print()
    print(f"Wrote {output_path}")
    print(f"  Books:    {len(books)}")
    print(f"  Chapters: {total_chapters}")
    print(f"  Verses:   {total_verses}")
    print(f"  Skipped:  {skipped} (apocrypha/paratext)")


if __name__ == "__main__":
    main()
