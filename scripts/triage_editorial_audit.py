#!/usr/bin/env python3
"""
First-pass triage for reports/editorial_length_audit.csv.

For each short-only / short+full row, count the available WEB scripture
words behind the anchor and emit GROW / SKIP / MAYBE with a one-line
reason. Output: reports/editorial_length_audit_triaged.csv.

Heuristic axes:
  - scripture word count behind the anchor (load-bearing signal)
  - anchor type: single verse, short passage, narrative chapter, psalm
  - whether the row is asking for Full+Long or Long-only

Rules (informed by Adam's memory):
  - Psalms: keep at Short unless the passage itself is large
    (feedback_psalm_word_floor — never extend with framing)
  - Single-verse anchors (<50 scripture words): SKIP — risks padding
  - 50-300 words: SKIP for Full+Long, MAYBE for Long-only
  - 300-600 words: MAYBE
  - 600+ words: GROW (Full or Full+Long)

These are recommendations only. Adam overrides.
"""

from __future__ import annotations

import csv
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from lib.bible_ref_parser import parse_bible_refs, extract_verses  # noqa: E402

import json

CSV_IN = ROOT / "reports" / "editorial_length_audit.csv"
CSV_OUT = ROOT / "reports" / "editorial_length_audit_triaged.csv"
BIBLE_WEB = ROOT / "server" / "data" / "bible_web.json"


def count_scripture_words(bible: dict, anchor: str) -> int | None:
    try:
        refs = parse_bible_refs(anchor)
    except ValueError:
        return None
    total = 0
    for r in refs:
        try:
            verses = extract_verses(bible, r)
        except ValueError:
            return None
        for _ch, _v, text in verses:
            total += len(text.split())
    return total


def triage(needs: str, words: int | None, anchor: str, mood: str) -> tuple[str, str]:
    if words is None:
        return ("MAYBE", "manual: could not parse anchor")

    is_psalm = anchor.lower().startswith("psalm ")
    if is_psalm:
        if words >= 500:
            return ("GROW", f"Psalm w/ {words} scripture words — long enough to carry Full")
        else:
            return ("SKIP", f"Psalm w/ {words} scripture words — psalm-floor rule, keep Short")

    if words < 50:
        return ("SKIP", f"only {words} scripture words — single-verse risk of padding")

    if needs == "long":
        # Already has Short + Full, only Long missing
        if words >= 700:
            return ("GROW", f"{words} scripture words — supports Long")
        if words >= 350:
            return ("MAYBE", f"{words} scripture words — Long marginal")
        return ("SKIP", f"{words} scripture words — Long would require padding")

    # Default: needs == 'full+long' (or empty)
    if words >= 600:
        return ("GROW", f"{words} scripture words — Full + Long both supported")
    if words >= 300:
        return ("MAYBE", f"{words} scripture words — Full likely, Long marginal")
    if words >= 150:
        return ("MAYBE", f"{words} scripture words — Full only, SKIP Long")
    return ("SKIP", f"{words} scripture words — risks padding")


def main():
    if not CSV_IN.exists():
        print(f"Missing input CSV: {CSV_IN}", file=sys.stderr)
        sys.exit(1)
    bible = json.loads(BIBLE_WEB.read_text())

    rows_out = []
    counts = {"GROW": 0, "MAYBE": 0, "SKIP": 0}

    with CSV_IN.open() as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames or []
        if "scripture_words" not in fieldnames:
            fieldnames = (
                fieldnames[: fieldnames.index("recommendation")]
                + ["scripture_words"]
                + fieldnames[fieldnames.index("recommendation") :]
            )
        for row in reader:
            anchor = row.get("anchor", "")
            needs = row.get("needs", "")
            mood = row.get("mood", "")
            words = count_scripture_words(bible, anchor) if anchor else None
            row["scripture_words"] = words if words is not None else ""
            if not anchor or not needs:
                row["recommendation"] = row.get("recommendation", "")
                rows_out.append(row)
                continue
            rec, reason = triage(needs, words, anchor, mood)
            if not row.get("recommendation"):
                row["recommendation"] = rec
                # Only set notes if empty; preserve any manual notes
                if not row.get("notes"):
                    row["notes"] = reason
                counts[rec] += 1
            rows_out.append(row)

    with CSV_OUT.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows_out)

    print(f"Wrote {CSV_OUT}")
    print(f"  GROW:  {counts['GROW']}")
    print(f"  MAYBE: {counts['MAYBE']}")
    print(f"  SKIP:  {counts['SKIP']}")
    print(f"  Total triaged: {sum(counts.values())} of {len(rows_out)} rows")


if __name__ == "__main__":
    main()
