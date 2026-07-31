#!/usr/bin/env python3
"""
Repopulate manifest audioFilePath / reflectionAudioPath for entries whose
audio already exists on disk.

Background
----------
Stories were registered in manifest.json with canonical audio paths before their
audio was rendered. A manifest-integrity test requires that a non-empty
audioFilePath resolve to a real file, so scripts/clear_dangling_audio_paths.py
blanked those paths (see commit 14440867, 2026-05-30). The audio was rendered
afterwards, but nothing ever relinked it — leaving fully narrated variants
unreachable, because the app only offers a variant whose audioFilePath is
non-empty.

This script performs that relink and nothing else. It never renders, replaces or
touches an MP3, never edits metadata, and never overwrites a path that is
already populated.

Safety rules
------------
* Dry-run by default; --write is required to mutate.
* Only entries whose audioFilePath is blank are considered.
* A path is written only when its target file exists, is tracked by git, is
  non-empty, and decodes cleanly under ffmpeg.
* audioFilePath and reflectionAudioPath are populated independently; either may
  be skipped if its own target fails a check.
* KID-TEXT GUARD (unconditional): an entry whose textFilePath points at
  kid-specific prose (``*_kid.txt``) is ALWAYS skipped, reported as
  SKIPPED_KID_TEXT_AUDIO_MISMATCH, and left completely unchanged. Several
  stories carry kid prose that differs substantially from the adult text while
  only adult narration has been recorded; linking those would show one wording
  and speak another.

  This tool deliberately does not attempt to detect or link kid narration, even
  if a kid-named MP3 appears on disk. It only knows the adult-style path
  convention, so "finding" kid audio could not change which file it links —
  it would still write the adult path. Kid-specific prose requires a separate,
  dedicated Kid Mode audio-linking workflow with an explicitly approved
  story-audio and reflection-audio naming convention. Until that exists, the
  safe outcome is for the variant to remain unavailable.
* Entry order and every unrelated field are preserved, as is the manifest's
  UTF-8 formatting (indent=2, ensure_ascii=False, trailing newline).

Exit codes
----------
0  success (including a no-op run, and including runs with kid skips)
1  a blocking problem: a proposed target is missing, untracked, empty,
   undecodable, or an entry is too ambiguous to resolve

Usage
-----
    python3 scripts/backfill_existing_audio_paths.py                      # dry run
    python3 scripts/backfill_existing_audio_paths.py --write
    python3 scripts/backfill_existing_audio_paths.py --ids 1019,1032
    python3 scripts/backfill_existing_audio_paths.py --reflection-only
    python3 scripts/backfill_existing_audio_paths.py --reflection-only --write

Modes
-----
default            Repairs entries whose audioFilePath is blank, populating both
                   audioFilePath and reflectionAudioPath.
--reflection-only  Repairs entries whose story audio is ALREADY linked but whose
                   reflectionAudioPath is blank, populating only that field.
                   Restricted to numeric traditional entries; the legacy
                   parable_* corpus uses a different convention and is excluded.

Both modes share the same safety gates and the same unconditional kid-text guard.
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import subprocess
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS_DIR = REPO_ROOT / "assets" / "stories"
MANIFEST_PATH = ASSETS_DIR / "manifest.json"

SKIP_KID = "SKIPPED_KID_TEXT_AUDIO_MISMATCH"


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------
def tracked_files(root: pathlib.Path) -> set[str]:
    """Paths git tracks under assets/stories, as repo-relative strings."""
    result = subprocess.run(
        ["git", "-C", str(root), "ls-files", "assets/stories"],
        capture_output=True, text=True,
    )
    return set(result.stdout.splitlines())


def decodes(path: pathlib.Path) -> bool:
    """True when ffmpeg decodes the whole file without emitting an error."""
    result = subprocess.run(
        ["ffmpeg", "-hide_banner", "-v", "error", "-i", str(path), "-f", "null", "-"],
        capture_output=True, text=True,
    )
    return not result.stderr.strip()


def story_id_of(entry: dict) -> str | None:
    """The numeric story id embedded in a manifest storyId, e.g. '1019'."""
    parts = entry.get("storyId", "").split("_")
    return parts[1] if len(parts) > 1 and parts[1].isdigit() else None


def lane_of(entry: dict) -> str | None:
    """'web' or 'kjv', taken from the entry's own languageStyle."""
    style = entry.get("languageStyle")
    if style == "WEB":
        return "web"
    if style == "KJV":
        return "kjv"
    return None


def is_kid_text(entry: dict) -> bool:
    """True when the entry's displayed prose is a kid-specific variant."""
    return (entry.get("textFilePath") or "").endswith("_kid.txt")


def canonical_paths(mode: str, sid: str, lane: str, length: str) -> tuple[str, str]:
    """Manifest-relative (story, reflection) audio paths for a variant."""
    suffix = "_kjv" if lane == "kjv" else ""
    story = f"{mode}/{sid}/audio_{sid}_story{suffix}_{length}.mp3"
    reflection = f"{mode}/{sid}/audio_{sid}_reflection{suffix}.mp3"
    return story, reflection


def check_target(assets: pathlib.Path, tracked: set[str], rel: str) -> str | None:
    """None when the file passes every gate, else a human-readable reason."""
    abs_path = assets / rel
    if not abs_path.exists():
        return f"missing: {rel}"
    if f"assets/stories/{rel}" not in tracked:
        return f"untracked: {rel}"
    if abs_path.stat().st_size == 0:
        return f"empty: {rel}"
    if not decodes(abs_path):
        return f"undecodable: {rel}"
    return None


# --------------------------------------------------------------------------
# core
# --------------------------------------------------------------------------
def plan(manifest: dict, assets: pathlib.Path, tracked: set[str],
         ids: set[str] | None = None, reflection_only: bool = False) -> dict:
    """Decide, without mutating anything, what should change and why."""
    updates, skipped_kid, errors, considered = [], [], [], 0

    for index, entry in enumerate(manifest.get("parables", [])):
        if reflection_only:
            # Companion mode: story audio is already linked, only the
            # reflection path is missing. Populate that field alone.
            if not entry.get("audioFilePath"):
                continue
            if entry.get("reflectionAudioPath"):
                continue
            want_story = False
            want_reflection = True
        else:
            # Default: repair variants whose story audio was unlinked. An entry
            # that already has story audio is left alone even if its reflection
            # path is blank — that is what --reflection-only covers.
            if entry.get("audioFilePath"):
                continue
            want_story = True
            want_reflection = not entry.get("reflectionAudioPath")

        sid = story_id_of(entry)
        if sid is None:
            continue                      # legacy non-numeric ids are out of scope
        if ids is not None and sid not in ids:
            continue

        mode = entry.get("storytellingMode") or "traditional"
        if reflection_only and mode != "traditional":
            continue                      # other modes use different conventions

        considered += 1
        lane = lane_of(entry)
        length = entry.get("storyLength")

        if lane is None or length not in ("short", "full", "long"):
            errors.append({
                "storyId": entry.get("storyId"),
                "reason": f"ambiguous variant: languageStyle={entry.get('languageStyle')!r} "
                          f"storyLength={length!r}",
            })
            continue

        if is_kid_text(entry):
            # Unconditional: this tool only knows the adult-style path
            # convention, so it can never link kid narration correctly.
            skipped_kid.append({
                "storyId": entry.get("storyId"),
                "textFilePath": entry.get("textFilePath"),
                "reason": "kid-specific prose; needs a dedicated Kid Mode linking workflow",
            })
            continue

        story_rel, reflection_rel = canonical_paths(mode, sid, lane, length)

        if reflection_only:
            existing = entry.get("audioFilePath")
            if not (assets / existing).exists():
                errors.append({
                    "storyId": entry.get("storyId"),
                    "reason": f"existing audioFilePath does not resolve: {existing}",
                })
                continue

        fields = {}
        for field, rel, wanted in (
            ("audioFilePath", story_rel, want_story),
            ("reflectionAudioPath", reflection_rel, want_reflection),
        ):
            if not wanted:
                continue                  # never overwrite an existing value
            problem = check_target(assets, tracked, rel)
            if problem:
                errors.append({"storyId": entry.get("storyId"), "reason": problem})
            else:
                fields[field] = rel

        if fields:
            updates.append({"index": index, "storyId": entry.get("storyId"),
                            "sid": sid, "lane": lane, "length": length,
                            "fields": fields})

    return {"updates": updates, "skipped_kid": skipped_kid,
            "errors": errors, "considered": considered}


def apply(manifest: dict, updates: list[dict]) -> int:
    """Write planned fields in place. Returns the number of fields set."""
    written = 0
    for update in updates:
        entry = manifest["parables"][update["index"]]
        for field, value in update["fields"].items():
            if entry.get(field):
                continue                  # defensive: never overwrite
            entry[field] = value
            written += 1
    return written


def report(result: dict, write: bool, mode_label: str = "default") -> None:
    updates, skipped, errors = result["updates"], result["skipped_kid"], result["errors"]
    fields = sum(len(u["fields"]) for u in updates)
    stories = sorted({u["sid"] for u in updates})

    print("=" * 66)
    print("  Manifest audio-path backfill — " + mode_label + " — "
          + ("WRITE" if write else "DRY RUN"))
    print("=" * 66)
    print(f"  blank entries considered : {result['considered']}")
    print(f"  entries to relink        : {len(updates)}")
    print(f"  fields to populate       : {fields}")
    print(f"  distinct stories         : {len(stories)}")
    for field in ("audioFilePath", "reflectionAudioPath"):
        print(f"    {field:<22}: {sum(1 for u in updates if field in u['fields'])}")
    for key, label in (("lane", "by lane"), ("length", "by length")):
        counts: dict[str, int] = {}
        for u in updates:
            counts[u[key]] = counts.get(u[key], 0) + 1
        print(f"  {label:<24}: " + ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))

    print(f"\n  {SKIP_KID}: {len(skipped)}")
    for item in skipped:
        print(f"    - {item['storyId']}  ({item['textFilePath']})")

    print(f"\n  blocking errors          : {len(errors)}")
    for item in errors:
        print(f"    - {item['storyId']}: {item['reason']}")
    print("=" * 66)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--write", action="store_true",
                        help="apply changes (default is a dry run)")
    parser.add_argument("--ids", help="comma-separated story ids to limit the run to")
    parser.add_argument("--reflection-only", action="store_true",
                        help="repair only blank reflectionAudioPath on entries whose "
                             "story audio is already linked")
    args = parser.parse_args(argv)

    ids = {i.strip() for i in args.ids.split(",") if i.strip()} if args.ids else None

    raw = MANIFEST_PATH.read_text(encoding="utf-8")
    manifest = json.loads(raw)
    tracked = tracked_files(REPO_ROOT)

    result = plan(manifest, ASSETS_DIR, tracked, ids, args.reflection_only)
    report(result, args.write, "reflection-only" if args.reflection_only else "default")

    if result["errors"]:
        print("\nAborted: blocking errors above. Nothing was written.")
        return 1

    if not args.write:
        print("\nDry run only. Re-run with --write to apply.")
        return 0

    if not result["updates"]:
        print("\nNo-op: every eligible entry is already linked.")
        return 0

    written = apply(manifest, result["updates"])
    MANIFEST_PATH.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(f"\nWrote {written} field(s) to {MANIFEST_PATH.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
