#!/usr/bin/env python3
"""
audit_corpus_completeness.py — Bible PAL corpus gap auditor.

Walks every traditional story directory and reports the full presence/absence
matrix across the 12 file slots per story (text + audio × lane × length).
Output is purely file-system driven — meta `lengths`/`lanes` declarations are
NOT trusted, because stale metas were masking gaps in earlier audits.

For each missing slot, classifies the gap:

  lane_parity   — same length exists in the OTHER lane → mechanical translation
  audio_needs_text — text file exists but audio does not → render queue
  no_variant    — neither lane has this length → editorial decision (Bucket 3)
  orphan_audio  — audio file present without matching text (legacy)

USAGE
  python3 scripts/audit_corpus_completeness.py

OUTPUTS (reports/ is gitignored)
  reports/corpus_full_matrix.csv   — one row per story, all 12 slots
  reports/corpus_gaps_text.csv     — every missing text slot + classification
  reports/corpus_gaps_audio.csv    — every missing audio slot + classification
  reports/corpus_orphans.csv       — audio without text, or other weirdness
  stdout                           — bucket counts + headline numbers
"""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
TRAD_DIR = REPO_ROOT / "assets" / "stories" / "traditional"
REPORTS_DIR = REPO_ROOT / "reports"

LANES = ("web", "kjv")
LENGTHS = ("short", "full", "long")


def audio_suffix(lane: str) -> str:
    return "" if lane == "web" else "_kjv"


def text_path(sid: str, lane: str, length: str) -> Path:
    return TRAD_DIR / sid / f"story_{sid}_traditional_{lane}_{length}.txt"


def audio_path(sid: str, lane: str, length: str) -> Path:
    return TRAD_DIR / sid / f"audio_{sid}_story{audio_suffix(lane)}_{length}.mp3"


def load_meta(sid: str) -> dict:
    p = TRAD_DIR / sid / f"meta_{sid}.json"
    try:
        return json.loads(p.read_text())
    except Exception:
        return {}


def main() -> int:
    REPORTS_DIR.mkdir(exist_ok=True)
    story_dirs = sorted(d for d in TRAD_DIR.iterdir() if d.is_dir())

    matrix_rows: list[dict] = []
    text_gap_rows: list[dict] = []
    audio_gap_rows: list[dict] = []
    orphan_rows: list[dict] = []

    bucket_counts = {
        "lane_parity_text": {l: 0 for l in LENGTHS},
        "no_variant_text": {l: 0 for l in LENGTHS},
        "audio_needs_text": {f"{lane}_{ln}": 0 for lane in LANES for ln in LENGTHS},
        "orphan_audio": {f"{lane}_{ln}": 0 for lane in LANES for ln in LENGTHS},
    }

    short_only_stories: list[str] = []
    no_full_either: list[str] = []
    no_long_either: list[str] = []
    total = 0

    for d in story_dirs:
        sid = d.name
        if not (d / f"meta_{sid}.json").exists():
            continue
        total += 1
        meta = load_meta(sid)
        anchor = meta.get("scriptureAnchor") or ""
        title = meta.get("title") or ""
        mood = meta.get("mood") or ""

        presence: dict[str, bool] = {}
        for lane in LANES:
            for length in LENGTHS:
                t_exists = text_path(sid, lane, length).exists()
                a_exists = audio_path(sid, lane, length).exists()
                presence[f"text_{lane}_{length}"] = t_exists
                presence[f"audio_{lane}_{length}"] = a_exists

        row = {"story_id": sid, "anchor": anchor, "title": title, "mood": mood}
        for k, v in presence.items():
            row[k] = "Y" if v else ""
        matrix_rows.append(row)

        for lane in LANES:
            for length in LENGTHS:
                other = "kjv" if lane == "web" else "web"
                t = presence[f"text_{lane}_{length}"]
                a = presence[f"audio_{lane}_{length}"]
                t_other = presence[f"text_{other}_{length}"]

                if not t:
                    if t_other:
                        classification = "lane_parity"
                        bucket_counts["lane_parity_text"][length] += 1
                    elif presence[f"text_{lane}_short"] or presence[f"text_{other}_short"]:
                        if length == "short":
                            classification = "lane_parity"
                            bucket_counts["lane_parity_text"][length] += 1
                        else:
                            classification = "no_variant"
                            bucket_counts["no_variant_text"][length] += 1
                    else:
                        classification = "no_variant"
                        bucket_counts["no_variant_text"][length] += 1
                    text_gap_rows.append({
                        "story_id": sid,
                        "anchor": anchor,
                        "title": title,
                        "mood": mood,
                        "lane": lane,
                        "length": length,
                        "classification": classification,
                        "other_lane_has_text": "Y" if t_other else "",
                    })

                if not a:
                    if t:
                        bucket_counts["audio_needs_text"][f"{lane}_{length}"] += 1
                        audio_gap_rows.append({
                            "story_id": sid,
                            "anchor": anchor,
                            "title": title,
                            "mood": mood,
                            "lane": lane,
                            "length": length,
                            "classification": "audio_needs_text",
                            "text_present": "Y",
                        })
                elif not t:
                    bucket_counts["orphan_audio"][f"{lane}_{length}"] += 1
                    orphan_rows.append({
                        "story_id": sid,
                        "anchor": anchor,
                        "title": title,
                        "lane": lane,
                        "length": length,
                        "issue": "audio_without_text",
                    })

        has_any_short = any(presence[f"text_{l}_short"] for l in LANES)
        has_any_full = any(presence[f"text_{l}_full"] for l in LANES)
        has_any_long = any(presence[f"text_{l}_long"] for l in LANES)
        if has_any_short and not has_any_full and not has_any_long:
            short_only_stories.append(sid)
        elif has_any_short and not has_any_full:
            no_full_either.append(sid)
        elif has_any_short and not has_any_long:
            no_long_either.append(sid)

    matrix_cols = ["story_id", "anchor", "title", "mood"] + [
        f"{kind}_{lane}_{length}"
        for kind in ("text", "audio")
        for lane in LANES
        for length in LENGTHS
    ]
    write_csv(REPORTS_DIR / "corpus_full_matrix.csv", matrix_cols, matrix_rows)

    gap_cols = ["story_id", "anchor", "title", "mood", "lane", "length",
                "classification", "other_lane_has_text"]
    write_csv(REPORTS_DIR / "corpus_gaps_text.csv", gap_cols, text_gap_rows)

    audio_cols = ["story_id", "anchor", "title", "mood", "lane", "length",
                  "classification", "text_present"]
    write_csv(REPORTS_DIR / "corpus_gaps_audio.csv", audio_cols, audio_gap_rows)

    orphan_cols = ["story_id", "anchor", "title", "lane", "length", "issue"]
    write_csv(REPORTS_DIR / "corpus_orphans.csv", orphan_cols, orphan_rows)

    print_summary(total, bucket_counts, short_only_stories,
                  no_full_either, no_long_either)
    return 0


def write_csv(path: Path, cols: list[str], rows: list[dict]) -> None:
    with path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        for r in rows:
            w.writerow({c: r.get(c, "") for c in cols})


def print_summary(total, bucket_counts, short_only, no_full, no_long) -> None:
    print(f"\nBible PAL corpus gap audit — {total} stories\n")

    print("BUCKET 1 — Lane parity gaps (other lane has same length → mechanical translation)")
    for ln in LENGTHS:
        print(f"  missing text @ {ln:5s}: {bucket_counts['lane_parity_text'][ln]:4d}")
    total_parity = sum(bucket_counts["lane_parity_text"].values())
    print(f"  TOTAL parity translations needed: {total_parity}\n")

    print("BUCKET 2 — Audio gaps (text exists, audio missing → render queue)")
    a_total = 0
    for lane in LANES:
        for ln in LENGTHS:
            n = bucket_counts["audio_needs_text"][f"{lane}_{ln}"]
            a_total += n
            print(f"  missing audio @ {lane:3s} {ln:5s}: {n:4d}")
    print(f"  TOTAL audios to render NOW: {a_total}\n")

    print("BUCKET 3 — Variant adoption (editorial: should this anchor grow?)")
    print(f"  short-only stories (no Full or Long in either lane): {len(short_only)}")
    print(f"  has Long but no Full:  {len(no_full)}")
    print(f"  has Full but no Long:  {len(no_long)}\n")

    print("ORPHANS — audio file without matching text (legacy/manual)")
    o_total = sum(bucket_counts["orphan_audio"].values())
    for lane in LANES:
        for ln in LENGTHS:
            n = bucket_counts["orphan_audio"][f"{lane}_{ln}"]
            if n:
                print(f"  orphan @ {lane:3s} {ln:5s}: {n:4d}")
    print(f"  TOTAL orphans: {o_total}\n")

    print("Reports written to reports/:")
    print("  - corpus_full_matrix.csv  (one row per story, all 12 slots)")
    print("  - corpus_gaps_text.csv    (every missing text + classification)")
    print("  - corpus_gaps_audio.csv   (every missing audio + classification)")
    print("  - corpus_orphans.csv      (audio without text)")


if __name__ == "__main__":
    sys.exit(main())
