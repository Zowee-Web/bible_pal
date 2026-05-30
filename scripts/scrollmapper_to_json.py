#!/usr/bin/env python3
"""
Convert scrollmapper Bible JSON to Bible PAL's target structure.

Input format (scrollmapper):
    {"translation": "...", "books": [
        {"name": "Genesis", "chapters": [
            {"chapter": 1, "verses": [{"verse": 1, "text": "..."}, ...]},
            ...
        ]},
        ...
    ]}

Output format (Bible PAL):
    {"translation": "...", "books": {
        "Genesis": {"1": {"1": "...", ...}, ...},
        ...
    }}
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


# Map scrollmapper book names → Bible PAL canonical (matches story metas + WEB)
NAME_MAP = {
    "I Samuel": "1 Samuel", "II Samuel": "2 Samuel",
    "I Kings": "1 Kings", "II Kings": "2 Kings",
    "I Chronicles": "1 Chronicles", "II Chronicles": "2 Chronicles",
    "I Corinthians": "1 Corinthians", "II Corinthians": "2 Corinthians",
    "I Thessalonians": "1 Thessalonians", "II Thessalonians": "2 Thessalonians",
    "I Timothy": "1 Timothy", "II Timothy": "2 Timothy",
    "I Peter": "1 Peter", "II Peter": "2 Peter",
    "I John": "1 John", "II John": "2 John", "III John": "3 John",
    "Psalms": "Psalm",
    "Revelation of John": "Revelation",
}


def convert(input_path: Path, output_path: Path, translation_label: str) -> None:
    src = json.loads(input_path.read_text())
    books_out: dict[str, dict[str, dict[str, str]]] = {}

    for book in src["books"]:
        raw_name = book["name"]
        name = NAME_MAP.get(raw_name, raw_name)
        chapters_out: dict[str, dict[str, str]] = {}
        for ch in book["chapters"]:
            ch_num = str(ch["chapter"])
            verses_out: dict[str, str] = {}
            for v in ch["verses"]:
                v_num = str(v["verse"])
                verses_out[v_num] = v["text"].strip()
            chapters_out[ch_num] = verses_out
        books_out[name] = chapters_out

    output = {
        "translation": translation_label,
        "books": books_out,
    }

    output_path.write_text(json.dumps(output, indent=2, ensure_ascii=False))

    total_ch = sum(len(c) for c in books_out.values())
    total_v = sum(len(v) for c in books_out.values() for v in c.values())
    print(f"Wrote {output_path}")
    print(f"  Books:    {len(books_out)}")
    print(f"  Chapters: {total_ch}")
    print(f"  Verses:   {total_v}")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: scrollmapper_to_json.py <input.json> <output.json> <translation_label>", file=sys.stderr)
        sys.exit(1)
    convert(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3])
