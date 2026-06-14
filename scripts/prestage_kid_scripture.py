#!/usr/bin/env python3
"""
prestage_kid_scripture.py — pre-stage WEB scripture text for the kid lane's
Comfort & Bedtime anchors (type=comfort-ritual in kid_anchor_registry.json).

These anchors quote Scripture directly rather than retelling it, so their text
must be public-domain WEB verbatim. This script extracts that text through the
SAME canonical path backfill_scripture_text.py uses — bible_ref_parser — so the
output format is byte-identical to the adult per-story scripture files.

It does NOT create stories, reflections, audio, manifest entries, or registry
changes — only the verbatim scripture text files.

Output: assets/stories/kids/scripture/scripture_{anchorId}_web.txt

USAGE
  python3 scripts/prestage_kid_scripture.py            # write files
  python3 scripts/prestage_kid_scripture.py --dry-run  # print, don't write
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "scripts"))
from lib.bible_ref_parser import (  # noqa: E402
    parse_bible_ref,
    extract_verses,
    format_scripture_text,
)

WEB_BIBLE = REPO / "server" / "data" / "bible_web.json"
OUT_DIR = REPO / "assets" / "stories" / "kids" / "scripture"

# anchorId -> reference. Must match kid_anchor_registry.json Comfort & Bedtime
# scriptureRef values exactly.
COMFORT_ANCHORS = {
    "psalm_23": "Psalm 23",
    "lords_prayer": "Matthew 6:9-13",
    "beatitudes": "Matthew 5:1-12",
    "fruit_of_spirit": "Galatians 5:22-23",
}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true", help="print, do not write")
    args = ap.parse_args()

    bible = json.loads(WEB_BIBLE.read_text(encoding="utf-8"))
    if not args.dry_run:
        OUT_DIR.mkdir(parents=True, exist_ok=True)

    for anchor_id, ref_str in COMFORT_ANCHORS.items():
        ref = parse_bible_ref(ref_str)
        verses = extract_verses(bible, ref)
        text = format_scripture_text(ref, verses, "WEB")
        out = OUT_DIR / f"scripture_{anchor_id}_web.txt"
        if args.dry_run:
            print(f"--- {out.relative_to(REPO)} ---")
            print(text)
        else:
            out.write_text(text, encoding="utf-8")
            print(f"wrote {out.relative_to(REPO)} ({len(verses)} verses)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
