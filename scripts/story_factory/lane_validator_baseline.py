#!/usr/bin/env python3
"""
lane_validator_baseline.py — Run validate_lane_identity() over the entire
existing Traditional adult-story corpus and emit a calibration baseline.

Outputs:
  - assets/diagnostics/lane_validator_baseline.csv  (one row per file)
  - assets/diagnostics/lane_validator_baseline.md   (per-batch summary)

The validator is WARN-only — this script writes baseline data only; it does
NOT modify, reject, or "fix" any story. Used to decide whether the validator
thresholds need tuning before any future promotion to BLOCKING.

KID stories are skipped (per scope decision in the Phase 5 plan).
"""

from __future__ import annotations

import argparse
import collections
import csv
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from claude_validator import validate_lane_identity


def is_kid_story(meta_path: pathlib.Path) -> bool:
    if not meta_path.exists():
        return False
    try:
        meta = json.loads(meta_path.read_text())
    except json.JSONDecodeError:
        return False
    return bool(meta.get("kidFriendly", False))


def story_files_iter(corpus_root: pathlib.Path):
    """Yield (story_id, lane, length, text_path) for each adult Traditional story file."""
    for story_dir in sorted(corpus_root.iterdir()):
        if not story_dir.is_dir():
            continue
        try:
            story_id = int(story_dir.name)
        except ValueError:
            continue
        meta_path = story_dir / f"meta_{story_id}.json"
        if is_kid_story(meta_path):
            continue
        for text_path in story_dir.glob(f"story_{story_id}_traditional_*.txt"):
            # Filename pattern: story_{id}_traditional_{lane}_{length}.txt
            stem = text_path.stem
            parts = stem.split("_")
            # ['story', id, 'traditional', lane, length]
            if len(parts) < 5:
                continue
            lane = parts[3]
            length = parts[4]
            if lane not in ("kjv", "web"):
                continue
            yield story_id, lane, length, text_path


def main() -> int:
    p = argparse.ArgumentParser(
        description="Baseline lane-identity validator against existing adult Traditional corpus."
    )
    p.add_argument(
        "--corpus",
        default="assets/stories/traditional",
        help="Corpus directory (relative to repo root).",
    )
    p.add_argument(
        "--outdir",
        default="assets/diagnostics",
        help="Output directory for csv/md.",
    )
    args = p.parse_args()

    root = pathlib.Path(__file__).resolve().parents[2]
    corpus = (root / args.corpus).resolve()
    outdir = (root / args.outdir).resolve()
    outdir.mkdir(parents=True, exist_ok=True)

    csv_path = outdir / "lane_validator_baseline.csv"
    md_path = outdir / "lane_validator_baseline.md"

    rows = []
    per_batch = collections.defaultdict(lambda: collections.Counter())
    cat_counter = collections.Counter()

    for story_id, lane, length, text_path in story_files_iter(corpus):
        text = text_path.read_text()
        violations = validate_lane_identity(text, lane)
        rows.append({
            "story_id": story_id,
            "lane": lane,
            "length": length,
            "violation_count": len(violations),
            "categories": ";".join(sorted({c for c, _ in violations})),
            "markers": ";".join(m for _, m in violations),
        })
        # Bucket by 10s for "batch" (rough proxy; real batch labels live in meta JSON)
        bucket = (story_id // 10) * 10
        per_batch[bucket][lane] += 1
        per_batch[bucket][f"{lane}_violations"] += len(violations)
        for cat, _ in violations:
            cat_counter[cat] += 1

    # Write CSV
    with csv_path.open("w", newline="") as fh:
        writer = csv.DictWriter(
            fh,
            fieldnames=["story_id", "lane", "length", "violation_count", "categories", "markers"],
        )
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {csv_path} ({len(rows)} rows)")

    # Write per-batch + category summary as markdown
    total_files = len(rows)
    files_with_violations = sum(1 for r in rows if r["violation_count"] > 0)
    pct = (files_with_violations / total_files * 100) if total_files else 0.0

    with md_path.open("w") as fh:
        fh.write("# Lane Validator Baseline\n\n")
        fh.write(f"**Generated:** {pathlib.Path(__file__).name}\n")
        fh.write(f"**Corpus:** {corpus.relative_to(root)}\n")
        fh.write(f"**Validator threshold (KJV archaic markers):** see KJV_MIN_ARCHAIC_MARKERS\n\n")
        fh.write("## Headline\n\n")
        fh.write(f"- Files scanned: **{total_files}**\n")
        fh.write(f"- Files with at least one violation: **{files_with_violations}** "
                 f"({pct:.1f}%)\n\n")
        fh.write("## Violations by category\n\n")
        fh.write("| Category | Count |\n|---|---|\n")
        for cat, n in cat_counter.most_common():
            fh.write(f"| {cat} | {n} |\n")
        fh.write("\n## Per-batch (10-story bucket) summary\n\n")
        fh.write("| Bucket | KJV files | KJV viol | WEB files | WEB viol |\n")
        fh.write("|---|---|---|---|---|\n")
        for bucket in sorted(per_batch.keys()):
            row = per_batch[bucket]
            fh.write(
                f"| {bucket}–{bucket+9} | {row['kjv']} | {row['kjv_violations']} | "
                f"{row['web']} | {row['web_violations']} |\n"
            )
        fh.write("\n## Notes\n\n")
        fh.write("- Validator is currently WARN-only; this baseline is "
                 "calibration data, NOT a list of stories to fix.\n")
        fh.write("- High KJV_TOO_FEW_ARCHAIC_MARKERS count is expected; many "
                 "legacy KJV stories rely on cadence/syntax rather than lexical "
                 "markers. Threshold tuning will follow batch-level review.\n")
        fh.write("- WEB violations (archaic bleed, contractions) are the more "
                 "actionable signal — those indicate genuine lane drift.\n")

    print(f"Wrote {md_path}")
    print()
    print(f"Total files scanned: {total_files}")
    print(f"Files with violations: {files_with_violations} ({pct:.1f}%)")
    print(f"Violations by category: {dict(cat_counter.most_common())}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
