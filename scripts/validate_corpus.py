#!/usr/bin/env python3
"""
validate_corpus.py — Bible PAL meta + bucket validator.

Runs two CI checks against every traditional story:

  1) Schema validation. Each assets/stories/traditional/{sid}/meta_{sid}.json
     is validated against assets/stories/meta.schema.json (Draft 2020-12).
     Schema is strict (additionalProperties: false) — its job is to catch
     silent leak fields like the reflectionVoiceKey incident that leaked
     into ~167 metas before an ad-hoc audit found it.

  2) Bucket-gate word count. For each meta, every length declared in
     `meta.lengths` is checked:
       short : 300-500 words
       full  : 501-900 words
       long  : 901-1500 words
     Carve-outs (documented in feedback_length_buckets.md):
       - shortScripture: true → MICRO legacy, skip band check
       - scriptureAnchor starts with "Psalm" → short floor (300) is waived

Schema failures are [FAIL] and contribute to a non-zero exit code.
Bucket failures and missing-file findings are [WARN] only — they print
but do NOT change the exit code. (Phase-1 policy: schema blocks now;
bucket goes blocking later via --strict-bucket once legacy drift is
reconciled.)

USAGE
  python3 scripts/validate_corpus.py                  # full corpus
  python3 scripts/validate_corpus.py --paths a.json b.json   # specific metas
  python3 scripts/validate_corpus.py --strict-bucket  # promote WARN to FAIL

EMERGENCY BYPASS
  git commit --no-verify           # standard git flag, skips the hook

Exit codes:
  0 — clean, or only WARN findings (default mode)
  1 — schema FAIL (always), or any FAIL in --strict-bucket mode
  2 — missing dependency (jsonschema)
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    from jsonschema import Draft202012Validator
except ImportError:
    print("Missing dependency: pip install jsonschema", file=sys.stderr)
    sys.exit(2)


REPO_ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATH = REPO_ROOT / "assets" / "stories" / "meta.schema.json"
TRADITIONAL_DIR = REPO_ROOT / "assets" / "stories" / "traditional"

BUCKETS = {
    "short": (300, 500),
    "full": (501, 900),
    "long": (901, 1500),
}


def load_schema() -> dict:
    with SCHEMA_PATH.open() as f:
        return json.load(f)


def discover_metas() -> list[Path]:
    return sorted(TRADITIONAL_DIR.glob("*/meta_*.json"))


def relpath(p: Path) -> str:
    try:
        return str(p.relative_to(REPO_ROOT))
    except ValueError:
        return str(p)


def word_count(path: Path) -> int:
    return len(path.read_text().split())


def schema_check(validator: Draft202012Validator, meta: dict) -> list[str]:
    errors = []
    for err in validator.iter_errors(meta):
        loc = ".".join(str(p) for p in err.absolute_path) or "<root>"
        errors.append(f"{loc}: {err.message}")
    return errors


def bucket_check(meta_path: Path, meta: dict) -> tuple[list[str], list[str]]:
    """Returns (bucket_warnings, missing_file_warnings)."""
    bucket_warns: list[str] = []
    missing_warns: list[str] = []

    lengths = meta.get("lengths") or []
    files = meta.get("files") or {}
    anchor = meta.get("scriptureAnchor", "") or ""
    is_psalm = anchor.strip().lower().startswith("psalm")
    is_short_scripture = bool(meta.get("shortScripture"))

    for L in lengths:
        if L not in BUCKETS:
            continue
        file_entry = files.get(L)
        if not isinstance(file_entry, dict):
            missing_warns.append(
                f"{L}: files.{L} entry missing or not an object"
            )
            continue
        story_text_name = file_entry.get("storyText")
        if not story_text_name:
            missing_warns.append(
                f"{L}: files.{L}.storyText is absent"
            )
            continue
        prose_path = meta_path.parent / story_text_name
        if not prose_path.is_file():
            missing_warns.append(
                f"{L}: files.{L}.storyText points to {story_text_name} (not on disk)"
            )
            continue

        wc = word_count(prose_path)
        floor, ceiling = BUCKETS[L]

        carved_out = False
        carve_reason = ""
        if L == "short":
            if is_short_scripture:
                carved_out = True
                carve_reason = "shortScripture:true (MICRO legacy)"
            elif is_psalm and wc < floor:
                # Psalm-floor carve-out: floor waived, ceiling still enforced
                carved_out = True
                carve_reason = f"Psalm anchor {anchor!r} (short floor waived)"

        if carved_out:
            # Carved-out shorts still must respect the ceiling for non-MICRO
            if not is_short_scripture and wc > ceiling:
                bucket_warns.append(
                    f"{L}: {wc} words, above {ceiling} ceiling "
                    f"(carve-out {carve_reason} only waives the floor)"
                )
            continue

        if wc < floor:
            extra = ""
            if L == "short" and is_psalm:
                extra = f" (anchor {anchor!r} qualifies for Psalm carve-out)"
            bucket_warns.append(
                f"{L}: {wc} words, below {floor} floor{extra}"
            )
        elif wc > ceiling:
            bucket_warns.append(
                f"{L}: {wc} words, above {ceiling} ceiling"
            )

    return bucket_warns, missing_warns


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate Bible PAL traditional story metas + bucket gate."
    )
    parser.add_argument(
        "--paths",
        nargs="+",
        help="Specific meta files to validate. Default: full corpus.",
    )
    parser.add_argument(
        "--strict-bucket",
        action="store_true",
        help="Promote bucket warnings and missing-file warnings to FAIL "
        "(contributes to exit code). Default: warn-only.",
    )
    args = parser.parse_args()

    schema = load_schema()
    validator = Draft202012Validator(schema)

    if args.paths:
        metas = [Path(p).resolve() for p in args.paths]
    else:
        metas = discover_metas()

    schema_fail_count = 0
    bucket_warn_count = 0
    missing_warn_count = 0
    metas_checked = 0

    for meta_path in metas:
        if not meta_path.is_file():
            print(f"[FAIL] {relpath(meta_path)}\n  io: file not found")
            schema_fail_count += 1
            continue
        try:
            with meta_path.open() as f:
                meta = json.load(f)
        except json.JSONDecodeError as e:
            print(f"[FAIL] {relpath(meta_path)}\n  io: invalid JSON ({e})")
            schema_fail_count += 1
            continue

        metas_checked += 1
        schema_errors = schema_check(validator, meta)
        bucket_warns, missing_warns = bucket_check(meta_path, meta)

        if schema_errors:
            schema_fail_count += 1
            print(f"[FAIL] {relpath(meta_path)}")
            print("  schema:")
            for e in schema_errors:
                print(f"    - {e}")

        warn_level = "FAIL" if args.strict_bucket else "WARN"
        if bucket_warns or missing_warns:
            print(f"[{warn_level}] {relpath(meta_path)}")
            if bucket_warns:
                print("  bucket:")
                for w in bucket_warns:
                    print(f"    - {w}")
                bucket_warn_count += len(bucket_warns)
            if missing_warns:
                print("  missing-file:")
                for w in missing_warns:
                    print(f"    - {w}")
                missing_warn_count += len(missing_warns)

    print()
    print(f"Checked: {metas_checked} metas")
    print(f"  schema FAIL: {schema_fail_count}")
    print(f"  bucket {'FAIL' if args.strict_bucket else 'WARN'}: {bucket_warn_count}")
    print(f"  missing-file {'FAIL' if args.strict_bucket else 'WARN'}: {missing_warn_count}")

    if schema_fail_count > 0:
        return 1
    if args.strict_bucket and (bucket_warn_count > 0 or missing_warn_count > 0):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
