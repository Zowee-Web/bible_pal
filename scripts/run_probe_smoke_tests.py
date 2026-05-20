#!/usr/bin/env python3
"""
run_probe_smoke_tests.py — deterministic regression check for the Life
Situation Tags v1 Mode B keyword-overlap CLI.

Reads scripts/probe_smoke_tests.txt, runs each probe against the same
retrieval functions used by scripts/query_life_situation_tags.py, and
verifies the result matches the declared expectation. Exits non-zero on
any failure.

Usage:
  python3 scripts/run_probe_smoke_tests.py
  python3 scripts/run_probe_smoke_tests.py --fixture path/to/other.txt

This is NOT a natural-language test. It catches changes in retrieval
behavior when the registry, seed map, or CLI tokenization changes.
A passing run means "behavior is unchanged since the fixture was last
reviewed," not "the system understands these queries."
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import List, Optional, Tuple

REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = REPO_ROOT / "scripts"
DEFAULT_FIXTURE = SCRIPTS_DIR / "probe_smoke_tests.txt"

# Reuse the production retrieval functions so this stays in lockstep with
# the CLI a user actually invokes.
sys.path.insert(0, str(SCRIPTS_DIR))
from query_life_situation_tags import load_registry, load_stories, run_mode_b  # noqa: E402


class _ProbeArgs:
    """Stand-in matching the attribute surface run_mode_b reads."""

    def __init__(self, probe: str):
        self.probe = probe
        self.verbose = False


def parse_fixture(path: Path) -> List[Tuple[int, str, str]]:
    entries: List[Tuple[int, str, str]] = []
    for line_no, raw in enumerate(path.read_text().splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "|" not in line:
            print(
                f"WARN: line {line_no} missing '|' separator: {raw!r}",
                file=sys.stderr,
            )
            continue
        query, expectation = (s.strip() for s in line.split("|", 1))
        if not query or not expectation:
            print(
                f"WARN: line {line_no} has empty query or expectation: {raw!r}",
                file=sys.stderr,
            )
            continue
        entries.append((line_no, query, expectation))
    return entries


def evaluate(
    expectation: str, returned_ids: List[str]
) -> Tuple[bool, str]:
    if expectation == "NO_MATCH":
        if returned_ids:
            return False, f"expected NO_MATCH, got {returned_ids}"
        return True, "no matches (as expected)"

    if expectation.startswith("MUST_INCLUDE:"):
        wanted = {x.strip() for x in expectation.split(":", 1)[1].split(",") if x.strip()}
        got = set(returned_ids)
        missing = wanted - got
        if missing:
            return (
                False,
                f"missing {sorted(missing)} (got {returned_ids[:10]}"
                f"{'…' if len(returned_ids) > 10 else ''})",
            )
        return True, f"includes {sorted(wanted)}"

    if expectation.startswith("MUST_EXCLUDE:"):
        unwanted = {x.strip() for x in expectation.split(":", 1)[1].split(",") if x.strip()}
        got = set(returned_ids)
        present = unwanted & got
        if present:
            return (
                False,
                f"unwanted ids appeared: {sorted(present)} (got {returned_ids[:10]}"
                f"{'…' if len(returned_ids) > 10 else ''})",
            )
        return True, f"excludes {sorted(unwanted)}"

    return False, f"unknown expectation syntax: {expectation!r}"


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--fixture",
        type=Path,
        default=DEFAULT_FIXTURE,
        help=f"Fixture file path (default: {DEFAULT_FIXTURE.relative_to(REPO_ROOT)})",
    )
    args = parser.parse_args()

    if not args.fixture.exists():
        print(f"ERROR: fixture not found: {args.fixture}", file=sys.stderr)
        sys.exit(2)

    entries = parse_fixture(args.fixture)
    if not entries:
        print(f"ERROR: no probe entries parsed from {args.fixture}", file=sys.stderr)
        sys.exit(2)

    # Load corpus once.
    registry, _banned = load_registry()
    stories = load_stories()

    print(
        f"Running {len(entries)} probe smoke test(s) "
        f"against {len(stories)} tagged stor{'y' if len(stories) == 1 else 'ies'}...\n"
    )

    failures: List[Tuple[int, str, str, str]] = []
    for line_no, query, expectation in entries:
        results = run_mode_b(_ProbeArgs(query), stories, registry)
        returned_ids = [r["storyId"] for r in results]
        passed, msg = evaluate(expectation, returned_ids)
        flag = "PASS" if passed else "FAIL"
        print(f"  [{flag}] L{line_no}: {query!r} → {msg}")
        if not passed:
            failures.append((line_no, query, expectation, msg))

    print()
    print(
        f"Summary: {len(entries) - len(failures)}/{len(entries)} passed"
    )
    if failures:
        print("\nFailures:")
        for line_no, query, expectation, msg in failures:
            print(f"  L{line_no}: {query!r}")
            print(f"    expected: {expectation}")
            print(f"    got:      {msg}")
        sys.exit(1)


if __name__ == "__main__":
    main()
