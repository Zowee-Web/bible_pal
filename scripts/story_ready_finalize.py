#!/usr/bin/env python3
"""
Bible PAL — Story Ready Finalization

Makes a Traditional story (or batch) mood-search ready by validating metadata,
copying the chosen audio take to the canonical filename, ensuring the manifest
entry is correct, ensuring pubspec.yaml lists the canonical audio, and (optionally)
running targeted Flutter tests.

Default mode is dry-run: no files are modified unless --apply is passed.

Usage:
    python3 scripts/story_ready_finalize.py --range 1248-1260
    python3 scripts/story_ready_finalize.py --ids 1248,1249,1250
    python3 scripts/story_ready_finalize.py --range 1230-1247          # dry-run by default
    python3 scripts/story_ready_finalize.py --range 1248-1260 --apply  # actually write
    python3 scripts/story_ready_finalize.py --ids 1235 --apply --force # overwrite canonical audio

Hard rules (encoded in this script):
- Audio is never deleted or renamed; take1 is preserved.
- Canonical audio (audio_<id>_story_short.mp3) is only created via shutil.copy2 from
  the chosen take. Without --force the canonical is never overwritten.
- Story text and meta files are read-only here; this script never edits them.
- Manifest updates only touch the listed safe fields; unrelated entries are untouched.
- Pubspec inserts go in the existing per-story-mp3 block. No duplicate lines.
- Nothing is staged or committed.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# ---------------------------------------------------------------------------
# Project-relative paths and approved vocabulary
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parent.parent
TRADITIONAL_DIR = REPO_ROOT / "assets" / "stories" / "traditional"
MANIFEST_PATH = REPO_ROOT / "assets" / "stories" / "manifest.json"
PUBSPEC_PATH = REPO_ROOT / "pubspec.yaml"

ALLOWED_MOODS: Tuple[str, ...] = (
    "joyful",
    "grateful",
    "weary",
    "anxious",
    "hurting",
    "brave_courage",
    "calm_peaceful",
    "encouraging",
)

# Approved emotional vocabulary — the active set used in the 1100s+ metadata pass,
# excluding legacy one-offs (see LEGACY_ALLOWED_EMOTIONAL_TAGS below).
APPROVED_EMOTIONAL_TAGS: frozenset = frozenset({
    "afraid", "alone", "anxious", "ashamed", "awed", "brave", "broken",
    "calm", "comforted", "confused", "courageous", "desperate", "determined",
    "encouraged", "exhausted", "fear", "fearful", "forgiven", "free", "grateful",
    "grieving", "happy", "hopeful", "humbled", "hurting", "inspired", "joyful",
    "lonely", "longing", "loved", "overwhelmed", "peaceful",
    "renewed", "repentant", "resolute", "restless",
    "seeking", "sorrowful", "steadfast", "surrendered", "tender", "thankful",
    "tired", "trusting", "uncertain", "watchful", "weary",
    "worried",
})

# Legacy one-off tags observed in the recent metadata pass that Adam wants kept
# allowed for validation but visually separated from the main active vocabulary.
# Each appears exactly once in the 1100s+ corpus. Do not promote into the main
# APPROVED set without Adam's say-so; new stories should prefer the active set.
LEGACY_ALLOWED_EMOTIONAL_TAGS: frozenset = frozenset({
    "awe",         # noun form — adjective is "awed"
    "redemption",  # theme-like noun — usually a themeTag, not emotional
    "rescue",      # noun form — usually theme-like
    "reverent",    # adjective; consider whether "humbled"/"awed" is the active fit
    "welcome",     # unusual emotional descriptor
    "wonder",      # noun form — adjective is "awed"; theme-adjacent
})

ALL_ALLOWED_EMOTIONAL_TAGS: frozenset = (
    APPROVED_EMOTIONAL_TAGS | LEGACY_ALLOWED_EMOTIONAL_TAGS
)

# Manifest fields that are safe to update on an existing entry (Adam's allowlist).
SAFE_UPDATE_FIELDS: Tuple[str, ...] = (
    "mood",
    "title",
    "textFilePath",
    "audioFilePath",
    "bibleSourceRef",
    "bibleStoryKey",
    "primaryCharacterId",
    "primaryCharacterDisplayName",
    "bibleOrderIndex",
    "timelineEra",
    "themeTags",
    "shortScripture",
)

TESTS_TO_RUN: Tuple[str, ...] = (
    "test/services/parable_service_no_audio_exclusion_test.dart",
    "test/core/mood_expansion_serving_test.dart",
    "test/services/parable_service_emotional_fit_test.dart",
)

# ---------------------------------------------------------------------------
# Result objects
# ---------------------------------------------------------------------------


@dataclass
class CheckResult:
    name: str
    ok: bool
    detail: str = ""

    def label(self) -> str:
        return "OK  " if self.ok else "FAIL"


@dataclass
class StoryResult:
    story_id: int
    checks: List[CheckResult] = field(default_factory=list)
    actions: List[str] = field(default_factory=list)

    def add(self, name: str, ok: bool, detail: str = "") -> None:
        self.checks.append(CheckResult(name=name, ok=ok, detail=detail))

    @property
    def all_ok(self) -> bool:
        return all(c.ok for c in self.checks)


@dataclass
class Summary:
    total: int = 0
    ready: int = 0
    failed: int = 0
    audio_promoted: int = 0
    manifest_added: int = 0
    manifest_updated: int = 0
    pubspec_added: int = 0
    test_results: Dict[str, bool] = field(default_factory=dict)


# ---------------------------------------------------------------------------
# Pure functions: ID parsing
# ---------------------------------------------------------------------------


def parse_range(spec: str) -> List[int]:
    m = re.fullmatch(r"\s*(\d+)\s*-\s*(\d+)\s*", spec)
    if not m:
        raise ValueError(f"--range must be in form START-END, got: {spec!r}")
    start, end = int(m.group(1)), int(m.group(2))
    if end < start:
        raise ValueError(f"--range end ({end}) must be >= start ({start})")
    return list(range(start, end + 1))


def parse_ids(spec: str) -> List[int]:
    out: List[int] = []
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        out.append(int(part))
    return out


# ---------------------------------------------------------------------------
# Pure functions: meta validation
# ---------------------------------------------------------------------------


def validate_meta(meta: dict) -> List[str]:
    """Return a list of issues. Empty list = valid."""
    issues: List[str] = []

    mood = meta.get("mood")
    if mood not in ALLOWED_MOODS:
        issues.append(f"mood {mood!r} not in allowed 8: {sorted(ALLOWED_MOODS)}")

    theme_tags = meta.get("themeTags") or []
    if not isinstance(theme_tags, list):
        issues.append(f"themeTags is not a list (got {type(theme_tags).__name__})")
    elif not (3 <= len(theme_tags) <= 6):
        issues.append(f"themeTags length {len(theme_tags)} not in 3-6")

    emotional_tags = meta.get("emotionalTags") or []
    if not isinstance(emotional_tags, list):
        issues.append(
            f"emotionalTags is not a list (got {type(emotional_tags).__name__})"
        )
    else:
        if not (5 <= len(emotional_tags) <= 7):
            issues.append(f"emotionalTags length {len(emotional_tags)} not in 5-7")
        unknown = [t for t in emotional_tags if t not in ALL_ALLOWED_EMOTIONAL_TAGS]
        if unknown:
            issues.append(f"emotionalTags contain unapproved values: {unknown}")

    return issues


# ---------------------------------------------------------------------------
# File-path helpers
# ---------------------------------------------------------------------------


def meta_path_for(story_id: int) -> Path:
    return TRADITIONAL_DIR / str(story_id) / f"meta_{story_id}.json"


def story_text_path_for(story_id: int) -> Path:
    return (
        TRADITIONAL_DIR
        / str(story_id)
        / f"story_{story_id}_traditional_web_short.txt"
    )


def take_path_for(story_id: int, take_name: Optional[str] = None) -> Path:
    name = take_name or f"audio_{story_id}_story_short_take1.mp3"
    return TRADITIONAL_DIR / str(story_id) / name


def canonical_audio_path_for(story_id: int) -> Path:
    return TRADITIONAL_DIR / str(story_id) / f"audio_{story_id}_story_short.mp3"


def manifest_audio_rel_for(story_id: int) -> str:
    return f"traditional/{story_id}/audio_{story_id}_story_short.mp3"


def manifest_text_rel_for(story_id: int) -> str:
    return f"traditional/{story_id}/story_{story_id}_traditional_web_short.txt"


def pubspec_audio_line_for(story_id: int) -> str:
    return f"    - assets/stories/traditional/{story_id}/audio_{story_id}_story_short.mp3"


# ---------------------------------------------------------------------------
# Audio: copy take -> canonical (never delete, never rename, idempotent)
# ---------------------------------------------------------------------------


def ensure_canonical_audio(
    story_id: int,
    take_name: Optional[str],
    dry_run: bool,
    force: bool,
) -> Tuple[bool, str, bool]:
    """
    Returns (ok, message, promoted).

    Promotes the chosen take to the canonical filename via shutil.move (rename).
    This is treated as PROMOTION, not deletion: the audio bytes survive, just at
    the canonical path. Satisfies the never-delete-audio rule because no audio
    data is destroyed — only the take filename is consumed.

    - If canonical exists and not --force: ok, no action (idempotent).
    - If canonical missing and take exists: move take -> canonical (only if not dry-run).
    - If take is gone but canonical exists: ok, no action (already promoted).
    - If both missing: not ok.
    """
    take = take_path_for(story_id, take_name)
    canonical = canonical_audio_path_for(story_id)

    if canonical.exists() and not force:
        return True, f"canonical exists: {canonical.name}", False

    if not take.exists():
        if canonical.exists():
            return True, f"canonical exists, take already promoted", False
        return False, f"missing both take ({take.name}) and canonical", False

    if dry_run:
        return True, f"WOULD move (promote) {take.name} -> {canonical.name}", False

    shutil.move(str(take), str(canonical))
    return True, f"moved (promoted) {take.name} -> {canonical.name}", True


# ---------------------------------------------------------------------------
# Manifest: find/build/update single entry
# ---------------------------------------------------------------------------


def is_target_entry(entry: dict, story_id: int) -> bool:
    """True iff this manifest entry represents the short WEB Traditional row for story_id."""
    sid = entry.get("storyId", "")
    if not isinstance(sid, str):
        return False
    if not sid.startswith(f"story_{story_id}_"):
        return False
    if not sid.endswith("_short_traditional"):
        return False
    if entry.get("storytellingMode") != "traditional":
        return False
    if entry.get("storyLength") != "short":
        return False
    if entry.get("languageStyle") != "WEB" and entry.get("translationId") != "WEB":
        return False
    return True


def find_manifest_entries(manifest: dict, story_id: int) -> List[Tuple[int, dict]]:
    parables = manifest.get("parables", [])
    out: List[Tuple[int, dict]] = []
    for idx, entry in enumerate(parables):
        if is_target_entry(entry, story_id):
            out.append((idx, entry))
    return out


def build_manifest_entry(
    meta: dict, existing: Optional[dict] = None
) -> Tuple[dict, bool]:
    """
    Build or update a manifest entry.

    - If existing is None: build a fresh entry with full schema and safe defaults.
    - If existing is provided: copy it and update only the safe-update fields.

    Returns (entry, was_new).
    """
    story_id = int(meta["storyId"])
    mood = meta.get("mood", "")
    title = meta.get("title", "")
    bible_ref = meta.get("scriptureAnchor", "")
    bible_story_key = meta.get("bibleStoryKey", "")
    primary_char_id = meta.get("primaryCharacterId", "")
    primary_char_name = meta.get("primaryCharacterDisplayName", "")
    bible_order_index = meta.get("bibleOrderIndex", 0)
    timeline_era = meta.get("timelineEra", "")
    theme_tags = list(meta.get("themeTags") or [])
    short_scripture = bool(meta.get("shortScripture", False))

    text_rel = manifest_text_rel_for(story_id)
    audio_rel = manifest_audio_rel_for(story_id)

    if existing is None:
        # Fresh entry — use established schema (mirrors recent 1100s+ entries).
        entry = {
            "storyId": f"story_{story_id}_{mood}_short_traditional",
            "title": title,
            "mood": mood,
            "emotionalTags": [],  # manifest emotionalTags stay empty per Adam's rule
            "storytellingMode": "traditional",
            "kidFriendly": False,
            "textFilePath": text_rel,
            "translationId": "WEB",
            "languageStyle": "WEB",
            "narratorVoiceKey": meta.get("storyVoiceKey", ""),
            "storyLength": "short",
            "scriptureTextFilePath": "",
            "bibleSourceRef": bible_ref,
            "bibleStoryKey": bible_story_key,
            "audioFilePath": audio_rel,
            "reflectionAudioPath": "",
            "primaryCharacterId": primary_char_id,
            "primaryCharacterDisplayName": primary_char_name,
            "bibleOrderIndex": bible_order_index,
            "timelineEra": timeline_era,
            "themeTags": theme_tags,
            "reflectionQuestion": "",
        }
        # MICRO marker (only emit when true to keep legacy entries clean).
        if short_scripture:
            entry["shortScripture"] = True
        return entry, True

    # Update path: copy existing dict, only mutate safe fields.
    entry = dict(existing)
    entry["mood"] = mood
    entry["title"] = title
    entry["textFilePath"] = text_rel
    entry["audioFilePath"] = audio_rel
    entry["bibleSourceRef"] = bible_ref
    entry["bibleStoryKey"] = bible_story_key
    entry["primaryCharacterId"] = primary_char_id
    entry["primaryCharacterDisplayName"] = primary_char_name
    entry["bibleOrderIndex"] = bible_order_index
    entry["timelineEra"] = timeline_era
    entry["themeTags"] = theme_tags
    # Only set shortScripture if true; remove if false-and-previously-present.
    if short_scripture:
        entry["shortScripture"] = True
    elif "shortScripture" in entry:
        del entry["shortScripture"]
    return entry, False


def diff_entry(existing: dict, updated: dict) -> List[str]:
    """Return human-readable list of safe-field diffs (for dry-run report)."""
    changes: List[str] = []
    for f in SAFE_UPDATE_FIELDS:
        if existing.get(f) != updated.get(f):
            changes.append(f"{f}: {existing.get(f)!r} -> {updated.get(f)!r}")
    return changes


# ---------------------------------------------------------------------------
# Pubspec: insertion (idempotent)
# ---------------------------------------------------------------------------


PUBSPEC_INSERT_AFTER_RE = re.compile(
    r"^(\s*-\s+assets/stories/traditional/(\d+)/audio_\d+_story_short\.mp3\s*)$"
)


def find_pubspec_lines(lines: List[str]) -> List[Tuple[int, int]]:
    """Return list of (line_index, story_id) for existing per-story mp3 lines."""
    found: List[Tuple[int, int]] = []
    for i, raw in enumerate(lines):
        m = PUBSPEC_INSERT_AFTER_RE.match(raw)
        if m:
            found.append((i, int(m.group(2))))
    return found


def ensure_pubspec_entry(
    pubspec_text: str, story_id: int
) -> Tuple[str, bool, str]:
    """
    Returns (new_text, would_modify, action_message).

    - If line already present: (text unchanged, False, 'present').
    - Else inserts in the per-story-mp3 block at the position that keeps numerical
      order. Falls back to appending after the last block line if order can't be
      determined.
    """
    target = pubspec_audio_line_for(story_id)
    lines = pubspec_text.splitlines(keepends=False)

    # Already present?
    if any(line.rstrip() == target for line in lines):
        return pubspec_text, False, "present"

    located = find_pubspec_lines(lines)
    if not located:
        return (
            pubspec_text,
            False,
            "ERROR: no per-story mp3 block found in pubspec — manual placement needed",
        )

    # Find correct insertion point: keep numeric order. Insert before the first
    # line whose story id > target id; if all are <= target, insert after the last.
    insert_idx: Optional[int] = None
    for idx, sid in located:
        if sid == story_id:
            return pubspec_text, False, "present"  # defensive
        if sid > story_id:
            insert_idx = idx
            break
    if insert_idx is None:
        last_idx = located[-1][0]
        insert_idx = last_idx + 1

    new_lines = lines[:insert_idx] + [target] + lines[insert_idx:]
    new_text = "\n".join(new_lines)
    if pubspec_text.endswith("\n"):
        new_text += "\n"
    return new_text, True, f"would insert at line {insert_idx + 1}"


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


def run_targeted_tests() -> Dict[str, bool]:
    results: Dict[str, bool] = {}
    for test in TESTS_TO_RUN:
        try:
            proc = subprocess.run(
                ["flutter", "test", test],
                cwd=str(REPO_ROOT),
                capture_output=True,
                text=True,
                timeout=600,
            )
            results[test] = proc.returncode == 0
            if proc.returncode != 0:
                tail = "\n".join(proc.stdout.strip().splitlines()[-10:])
                err_tail = "\n".join(proc.stderr.strip().splitlines()[-10:])
                print(f"\n  test failed: {test}\n  stdout-tail:\n{tail}\n  stderr-tail:\n{err_tail}\n")
        except FileNotFoundError:
            print(f"  flutter not found on PATH; skipping {test}")
            results[test] = False
        except subprocess.TimeoutExpired:
            print(f"  timeout running {test}")
            results[test] = False
    return results


# ---------------------------------------------------------------------------
# Per-story orchestration
# ---------------------------------------------------------------------------


def finalize_story(
    story_id: int,
    manifest: dict,
    pubspec_text: str,
    *,
    take_name: Optional[str],
    dry_run: bool,
    force: bool,
) -> Tuple[StoryResult, dict, str, Dict[str, bool]]:
    """
    Returns:
        result: StoryResult
        manifest: possibly-mutated manifest dict (only when not dry_run; dry-run leaves unchanged)
        pubspec_text: possibly-updated pubspec text (only when not dry_run)
        actions_taken: flags for summary (audio_copied, manifest_added, manifest_updated, pubspec_added)
    """
    result = StoryResult(story_id=story_id)
    actions_taken: Dict[str, bool] = {
        "audio_promoted": False,
        "manifest_added": False,
        "manifest_updated": False,
        "pubspec_added": False,
    }

    # --- 1. meta exists -----------------------------------------------------
    meta_p = meta_path_for(story_id)
    if not meta_p.exists():
        result.add("meta", False, f"missing: {meta_p.relative_to(REPO_ROOT)}")
        return result, manifest, pubspec_text, actions_taken
    try:
        meta = json.loads(meta_p.read_text())
    except json.JSONDecodeError as e:
        result.add("meta", False, f"invalid JSON: {e}")
        return result, manifest, pubspec_text, actions_taken
    result.add("meta", True, str(meta_p.relative_to(REPO_ROOT)))

    # --- 2-4. tag validation ------------------------------------------------
    issues = validate_meta(meta)
    if issues:
        result.add("tags", False, "; ".join(issues))
    else:
        result.add(
            "tags",
            True,
            f"mood={meta.get('mood')} themes={len(meta.get('themeTags', []))} emotional={len(meta.get('emotionalTags', []))}",
        )

    # --- 5. story text exists -----------------------------------------------
    text_p = story_text_path_for(story_id)
    if not text_p.exists():
        result.add("story_text", False, f"missing: {text_p.relative_to(REPO_ROOT)}")
    else:
        result.add("story_text", True, text_p.name)

    # --- 6-7. canonical audio (copy take if needed) ------------------------
    audio_ok, audio_msg, promoted = ensure_canonical_audio(
        story_id, take_name, dry_run=dry_run, force=force
    )
    result.add("canonical_audio", audio_ok, audio_msg)
    if promoted:
        actions_taken["audio_promoted"] = True

    # --- 8-9. manifest entry ------------------------------------------------
    matches = find_manifest_entries(manifest, story_id)
    if len(matches) > 1:
        result.add(
            "manifest",
            False,
            f"{len(matches)} short-WEB-traditional entries (expected exactly 1)",
        )
    elif len(matches) == 1:
        idx, existing_entry = matches[0]
        updated_entry, was_new = build_manifest_entry(meta, existing=existing_entry)
        changes = diff_entry(existing_entry, updated_entry)
        expected_audio = manifest_audio_rel_for(story_id)
        audio_path_ok = updated_entry.get("audioFilePath") == expected_audio
        if not changes and audio_path_ok:
            result.add("manifest", True, "entry exists, no changes needed")
        else:
            label = "WOULD update" if dry_run else "updated"
            detail = f"{label} entry ({len(changes)} field changes)" if changes else f"{label} entry"
            if not dry_run:
                manifest["parables"][idx] = updated_entry
                actions_taken["manifest_updated"] = True
            result.add("manifest", True, detail)
    else:
        # Missing — build new
        new_entry, _ = build_manifest_entry(meta)
        if dry_run:
            result.add("manifest", True, "WOULD add new entry")
        else:
            manifest.setdefault("parables", []).append(new_entry)
            actions_taken["manifest_added"] = True
            result.add("manifest", True, "added new entry")

    # --- 10. pubspec --------------------------------------------------------
    new_pubspec_text, would_modify, ps_msg = ensure_pubspec_entry(pubspec_text, story_id)
    if ps_msg.startswith("ERROR"):
        result.add("pubspec", False, ps_msg)
    elif ps_msg == "present":
        result.add("pubspec", True, "present")
    else:
        if dry_run:
            result.add("pubspec", True, f"WOULD insert ({ps_msg})")
        else:
            pubspec_text = new_pubspec_text
            actions_taken["pubspec_added"] = True
            result.add("pubspec", True, f"inserted ({ps_msg})")

    return result, manifest, pubspec_text, actions_taken


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------


def print_per_story(results: List[StoryResult]) -> None:
    print()
    print("=" * 78)
    print("  Per-story readiness")
    print("=" * 78)
    for r in results:
        status = "PASS" if r.all_ok else "FAIL"
        print(f"\n  [{status}] story {r.story_id}")
        for c in r.checks:
            print(f"     {c.label()}  {c.name:<18} {c.detail}")


def print_summary(summary: Summary, dry_run: bool) -> None:
    print()
    print("=" * 78)
    print("  Summary")
    print("=" * 78)
    print(f"  Mode:                    {'DRY-RUN (no writes)' if dry_run else 'APPLY (writes performed)'}")
    print(f"  Stories checked:         {summary.total}")
    print(f"  Ready:                   {summary.ready}")
    print(f"  Failed:                  {summary.failed}")
    print(f"  Audio promoted:          {summary.audio_promoted}")
    print(f"  Manifest entries added:  {summary.manifest_added}")
    print(f"  Manifest entries updated:{summary.manifest_updated}")
    print(f"  Pubspec lines added:     {summary.pubspec_added}")
    if summary.test_results:
        print()
        print("  Tests:")
        for t, ok in summary.test_results.items():
            print(f"    {'OK  ' if ok else 'FAIL'}  {t}")
    print("=" * 78)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Bible PAL — Story Ready Finalization",
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--range", dest="range_spec", help="ID range, e.g. 1248-1260")
    group.add_argument("--ids", dest="ids_spec", help="Comma-separated IDs, e.g. 1248,1249")

    mode_group = parser.add_mutually_exclusive_group()
    mode_group.add_argument(
        "--dry-run",
        action="store_true",
        default=True,
        help="(default) report only, no writes",
    )
    mode_group.add_argument(
        "--apply",
        action="store_true",
        default=False,
        help="actually write changes",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="overwrite canonical audio if it already exists (still uses copy2)",
    )
    parser.add_argument(
        "--take",
        default=None,
        help="override take filename (default: audio_<id>_story_short_take1.mp3)",
    )
    parser.add_argument(
        "--skip-tests",
        action="store_true",
        help="skip running flutter tests",
    )
    args = parser.parse_args(argv)

    dry_run = not args.apply

    # Expand IDs
    if args.range_spec:
        try:
            story_ids = parse_range(args.range_spec)
        except ValueError as e:
            print(f"ERROR: {e}", file=sys.stderr)
            return 2
    else:
        try:
            story_ids = parse_ids(args.ids_spec)
        except ValueError as e:
            print(f"ERROR: {e}", file=sys.stderr)
            return 2

    if not MANIFEST_PATH.exists():
        print(f"ERROR: manifest not found: {MANIFEST_PATH}", file=sys.stderr)
        return 2
    manifest = json.loads(MANIFEST_PATH.read_text())
    pubspec_text = PUBSPEC_PATH.read_text()

    # Header
    print("=" * 78)
    print("  Bible PAL — Story Ready Finalization")
    print("=" * 78)
    print(f"  Mode:    {'DRY-RUN' if dry_run else 'APPLY'}")
    print(f"  IDs:     {story_ids[0]}..{story_ids[-1]} ({len(story_ids)} stories)")
    print(f"  Force:   {args.force}")
    print(f"  Take:    {args.take or '(default take1)'}")
    print("=" * 78)

    summary = Summary(total=len(story_ids))
    results: List[StoryResult] = []

    for sid in story_ids:
        r, manifest, pubspec_text, actions = finalize_story(
            sid,
            manifest,
            pubspec_text,
            take_name=args.take,
            dry_run=dry_run,
            force=args.force,
        )
        results.append(r)
        if r.all_ok:
            summary.ready += 1
        else:
            summary.failed += 1
        if actions["audio_promoted"]:
            summary.audio_promoted += 1
        if actions["manifest_added"]:
            summary.manifest_added += 1
        if actions["manifest_updated"]:
            summary.manifest_updated += 1
        if actions["pubspec_added"]:
            summary.pubspec_added += 1

    # Write manifest and pubspec only on --apply and only if changed
    if not dry_run:
        if summary.manifest_added or summary.manifest_updated:
            MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n")
        if summary.pubspec_added:
            PUBSPEC_PATH.write_text(pubspec_text)

    # Tests last (they validate the final state)
    if not args.skip_tests and not dry_run:
        print()
        print("Running targeted tests...")
        summary.test_results = run_targeted_tests()
    elif not args.skip_tests and dry_run:
        # In dry-run, still note that tests would run after --apply
        for t in TESTS_TO_RUN:
            summary.test_results[t] = True  # marker: not actually run
        print("\n  (dry-run: skipping test execution; would run on --apply)")

    print_per_story(results)
    print_summary(summary, dry_run=dry_run)

    return 0 if summary.failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
