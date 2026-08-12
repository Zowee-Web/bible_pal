#!/usr/bin/env python3
"""PR-time enforcement of the Catalog Currency invariant (docs/INVARIANTS.md).

Compares the BASE branch's assets/stories/manifest.json against the CURRENT
one SEMANTICALLY and enforces the catalog-generation bump rules:

  1. Formatting differences are ignored (JSON is parsed, then compared).
  2. Semantic content = the complete manifest JSON with ONLY the top-level
     "version" field excluded. Array ordering IS semantic content, and so
     are JSON TYPES: comparison happens on a canonical JSON serialization
     (sorted object keys, compact separators, arrays in order), so
     true vs 1 vs 1.0 are DIFFERENT semantic content — Python's
     True == 1 == 1.0 container equality can never mask a type change.
     Non-standard JSON constants (NaN/Infinity/-Infinity) are rejected at
     load time (Dart's jsonDecode rejects them too).
  3. The current version must always be a positive integer (bool is not
     an integer for this purpose).
  4. If semantic content is unchanged:  currentVersion >= baseVersion.
  5. If semantic content changed:       currentVersion >  baseVersion.
  6. Initial migration: ONLY a base manifest whose top-level "version" key
     is genuinely ABSENT is treated as generation 0 (so the historical
     no-version -> 6 transition passes). A base that CONTAINS "version"
     with an invalid value (bool, string, float, zero, negative, null, …)
     fails CLOSED — a corrupt base can never be laundered into a
     generation-0 migration.

The GitHub workflow supplies an explicit, trustworthy base revision — the
pull_request event context on PRs, and the pushed ref's previous tip
(`github.event.before`) on protected-branch pushes/merges. This script
never guesses HEAD^. BOTH paths are gated: a PR check alone would leave
the merge/push path unprotected, so a manifest could still reach a
protected branch without a generation bump (direct push, admin merge, or
a PR whose base advanced after the check ran).

Usage:
    python3 scripts/check_manifest_version_bump.py \
        --base  <path to base manifest.json> \
        --current assets/stories/manifest.json

    python3 scripts/check_manifest_version_bump.py \
        --no-base --current assets/stories/manifest.json

Exit code 0 = contract satisfied, 1 = violation (message on stderr).
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

# Shared strictness with the publisher's comprehensive validator: the
# same loads_strict rejects NaN/Infinity/-Infinity at parse time.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from validate_catalog_manifest import loads_strict  # noqa: E402


def is_valid_version(value) -> bool:
    """Positive integer only. bool is an int subclass in Python — exclude it."""
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


def semantic_content(manifest: dict) -> dict:
    """The manifest with only the top-level version field excluded."""
    content = dict(manifest)
    content.pop("version", None)
    return content


def canonical_semantic(manifest: dict) -> str:
    """Canonical JSON serialization of the semantic content: deterministic
    key order, compact separators, array order preserved, NaN/Infinity
    refused. Comparing these strings preserves JSON TYPES — Python object
    equality would treat True == 1 == 1.0 as unchanged content."""
    return json.dumps(
        semantic_content(manifest),
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    )


def check(base: dict, current: dict) -> tuple[bool, str]:
    """Returns (ok, message). Pure so tests can drive it directly."""
    current_version = current.get("version")
    if not is_valid_version(current_version):
        return (
            False,
            "current manifest version must be a positive integer, got "
            f"{current_version!r} ({type(current_version).__name__})",
        )

    if "version" in base:
        base_version = base["version"]
        if not is_valid_version(base_version):
            return (
                False,
                "base manifest CONTAINS a \"version\" key but its value is "
                f"invalid: {base_version!r} ({type(base_version).__name__}). "
                "Only a base with NO version key is the pre-migration "
                "generation-0 shape; an invalid present version fails "
                "closed.",
            )
    else:
        # One-time migration: only a base whose "version" key is genuinely
        # ABSENT is generation 0 (the pre-migration manifest shape).
        base_version = 0

    content_changed = canonical_semantic(base) != canonical_semantic(current)

    if content_changed:
        if current_version > base_version:
            return (
                True,
                "OK: semantic content changed and version bumped "
                f"({base_version} -> {current_version})",
            )
        return (
            False,
            "manifest semantic content changed but the catalog generation "
            f"was not bumped (base {base_version}, current {current_version}). "
            "Increment the top-level \"version\" in "
            "assets/stories/manifest.json.",
        )

    if current_version >= base_version:
        return (
            True,
            "OK: semantic content unchanged, version "
            f"{base_version} -> {current_version} (>= base allowed)",
        )
    return (
        False,
        "catalog generation must never decrease: base "
        f"{base_version}, current {current_version}",
    )


def _load(path: str) -> dict:
    with open(path, encoding="utf-8") as f:
        data = loads_strict(f.read())
    if not isinstance(data, dict):
        raise ValueError(f"{path}: manifest root must be a JSON object")
    return data


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Enforce the manifest catalog-generation bump contract."
    )
    parser.add_argument("--base",
                        help="Path to the base revision's manifest.json")
    parser.add_argument("--no-base", action="store_true",
                        help="The base revision genuinely has no "
                             "assets/stories/manifest.json (new file). Only "
                             "the current manifest's version validity is "
                             "checked.")
    parser.add_argument("--current", required=True,
                        help="Path to the current manifest.json")
    args = parser.parse_args(argv)

    if args.no_base == bool(args.base):
        print("FAIL: pass exactly one of --base or --no-base",
              file=sys.stderr)
        return 1

    if args.no_base:
        # Nothing to compare against, but the generation must still be a
        # positive integer — an unversioned or corrupt new manifest can
        # never enter a protected branch.
        try:
            current = _load(args.current)
        except Exception as e:  # noqa: BLE001
            print(f"FAIL: cannot load current manifest: {e}",
                  file=sys.stderr)
            return 1
        version = current.get("version")
        if not is_valid_version(version):
            print("FAIL: base revision has no manifest, so the new manifest "
                  "must carry a positive integer catalog generation; got "
                  f"{version!r} ({type(version).__name__})", file=sys.stderr)
            return 1
        print(f"OK: new manifest carries catalog generation {version}")
        return 0

    try:
        base = _load(args.base)
    except Exception as e:  # noqa: BLE001 — any unreadable base is fatal
        print(f"FAIL: cannot load base manifest: {e}", file=sys.stderr)
        return 1
    try:
        current = _load(args.current)
    except Exception as e:  # noqa: BLE001
        print(f"FAIL: cannot load current manifest: {e}", file=sys.stderr)
        return 1

    ok, message = check(base, current)
    if ok:
        print(message)
        return 0
    print(f"FAIL: {message}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
