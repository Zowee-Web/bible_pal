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

CONTENT AUTHORITY
  Default: the working tree.
  --reconstruction-from-index: every metadata and story byte is read from the
  Git INDEX — the bytes a prospective commit would contain. The pre-commit hook
  uses this so a partially staged file is judged on its staged content.

ERROR CLASSIFICATION
  Editorial/diagnostic problems are ADVISORY (exit unaffected): reconstruction
  findings, [UNRESOLVED] inputs, invalid UTF-8 story content, unparseable
  anchors, rejected metadata storyText values.
  Machinery failures BLOCK (non-zero): staged metadata schema failure,
  --strict-bucket failure, Git enumeration/index/object failure, unreadable
  canonical Bible data, missing dependency, unexpected internal exception.
  A broken validator must never masquerade as a clean advisory pass.

USAGE
  python3 scripts/validate_corpus.py                  # full corpus
  python3 scripts/validate_corpus.py --paths a.json b.json   # specific metas
  python3 scripts/validate_corpus.py --strict-bucket  # promote WARN to FAIL

EMERGENCY BYPASS
  git commit --no-verify           # standard git flag, skips the hook

Exit codes:
  0 — clean, or only WARN/advisory findings (default mode)
  1 — schema FAIL (always), any FAIL in --strict-bucket mode, or an
      infrastructure failure
  2 — missing dependency (jsonschema)
"""

from __future__ import annotations

import argparse
import json
import sys
import traceback
from pathlib import Path, PurePosixPath

try:
    from jsonschema import Draft202012Validator
    from jsonschema.exceptions import SchemaError
except ImportError:
    print("Missing dependency: pip install jsonschema", file=sys.stderr)
    sys.exit(2)

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib import reconstruction_check  # noqa: E402
from lib.reconstruction_check import (  # noqa: E402
    ContentUnavailable, InfrastructureError, require_ordinary_data_mode,
)

REPO_ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATH = REPO_ROOT / "assets" / "stories" / "meta.schema.json"
TRADITIONAL_DIR = REPO_ROOT / "assets" / "stories" / "traditional"
TRADITIONAL_PREFIX = "assets/stories/traditional"

BUCKETS = {
    "short": (300, 500),
    "full": (501, 900),
    "long": (901, 1500),
}


def load_schema(source=None) -> dict:
    """Load meta.schema.json.

    In hook (index) mode the STAGED schema governs the prospective commit, so a
    dirty unstaged schema cannot change the result. Any failure to obtain or
    parse it is INFRASTRUCTURE (blocking): validation cannot proceed without a
    schema, and a deletion must not be silently reinterpreted here.
    """
    if source is None or getattr(source, "name", "") != "git-index":
        try:
            with SCHEMA_PATH.open() as f:
                return json.load(f)
        except (OSError, json.JSONDecodeError) as e:
            raise InfrastructureError(f"cannot load {SCHEMA_PATH}: {e}") from e
    rel = reconstruction_check.META_SCHEMA_PATH
    if not source.exists(rel):
        raise InfrastructureError(
            f"{rel} is absent from the Git index; the prospective commit has no "
            f"schema to validate against")
    require_ordinary_data_mode(source, rel, "schema")
    try:
        return source.read_json(rel)
    except ContentUnavailable as e:
        raise InfrastructureError(f"staged schema unusable: {e}") from e


def run_kid_gate_from_index(source, kid_paths: list[str],
                            deleted_paths: frozenset) -> int:
    """Validate the FINAL-INDEX kid manifest/registry using existing doctrine.

    Parity approach: validate_kids.py reads its two inputs from module-level
    constants and its consistency logic lives inside main(). Rather than
    reimplementing that doctrine (which would drift), the staged blobs are
    materialized to a temp directory OUTSIDE the repository and the module's own
    constants are pointed at them, so validate_kids.main() runs unmodified over
    index content. validate_kids.py itself is not edited.

    A DELETION of one input is advisory (ADR-032 deferred) and is reported as a
    [DELETION-REVIEW] by the caller. It must NEVER short-circuit validation of
    the input that survives: an executable, unreadable or malformed surviving
    file is an independent blocking defect, and returning early on the deletion
    would hide it behind an advisory exit 0. Every surviving required input is
    therefore validated on its own — presence, ordinary mode, UTF-8, JSON —
    before any advisory success is returned.

    Pair consistency (validate_kids.main) runs only when BOTH inputs survive;
    with one intentionally deleted the pair no longer exists to check.
    """
    import importlib
    import tempfile

    needed = [reconstruction_check.KID_MANIFEST_PATH,
              reconstruction_check.KID_REGISTRY_PATH]
    blobs = {}
    status = 0
    surviving = []

    for rel in needed:
        if not source.exists(rel):
            if rel in deleted_paths:
                # Removed BY THIS prospective commit: advisory, and NOT a
                # reason to stop checking the other input.
                continue
            # Absent from the final index with no recognized deletion in this
            # snapshot: the baseline itself is unverifiable. Distinct from
            # "deleted by this commit", and silently returning 0 here would let
            # kid changes land against a corpus that cannot be validated.
            print(f"[INFRASTRUCTURE-FAILURE] required kid input unexpectedly "
                  f"absent from the index")
            print(f"  {rel} is not in the prospective commit and this commit "
                  f"does not delete it")
            print("  The kid baseline cannot be verified; this is not a "
                  "deletion and is not adjudicated by ADR-032.")
            status = 1
            continue
        surviving.append(rel)

    # Whether the existing pair-consistency validator will run at all.
    pair_will_run = len(surviving) == len(needed)

    for rel in surviving:
        try:
            require_ordinary_data_mode(source, rel, "kid")
        except InfrastructureError as e:
            print(f"[INFRASTRUCTURE-FAILURE] kid input is not ordinary data")
            print(f"  {e}")
            status = 1
            continue
        try:
            text = source.read_text(rel)
        except ContentUnavailable as e:
            print(f"[FAIL] {rel}\n  kid-gate: {e}")
            status = 1
            continue
        if not pair_will_run:
            # JSON validity of a survivor is only unchecked when the pair does
            # not run, because validate_kids.main() detects malformed input
            # itself. Checking it here unconditionally would preempt that
            # module and discard its own exit-code vocabulary (2 = unreadable
            # input), so this fills exactly the gap and nothing more.
            try:
                json.loads(text)
            except json.JSONDecodeError as e:
                print(f"[FAIL] {rel}\n  kid-gate: invalid JSON: {e}")
                status = 1
                continue
        blobs[rel] = text

    if status != 0:
        return status
    if len(blobs) != len(needed):
        # One input is intentionally deleted. Every survivor has been validated
        # independently above; pair consistency is not applicable.
        return 0

    with tempfile.TemporaryDirectory(prefix="biblepal_kidgate_") as td:
        tmp = Path(td)
        manifest = tmp / "kids_manifest.json"
        registry = tmp / "kid_anchor_registry.json"
        manifest.write_text(blobs[reconstruction_check.KID_MANIFEST_PATH],
                            encoding="utf-8")
        registry.write_text(blobs[reconstruction_check.KID_REGISTRY_PATH],
                            encoding="utf-8")
        vk = importlib.import_module("validate_kids")
        saved = (vk.KIDS_MANIFEST, vk.ANCHOR_REGISTRY, sys.argv)
        try:
            vk.KIDS_MANIFEST = manifest
            vk.ANCHOR_REGISTRY = registry
            sys.argv = ["validate_kids.py"]
            return vk.main()
        except SystemExit as e:  # validate_kids exits 2 on unreadable input
            return int(e.code or 0)
        finally:
            vk.KIDS_MANIFEST, vk.ANCHOR_REGISTRY, sys.argv = saved


def discover_metas() -> list[str]:
    """Repo-relative meta paths for the full corpus."""
    return sorted(
        f"{TRADITIONAL_PREFIX}/{p.parent.name}/{p.name}"
        for p in TRADITIONAL_DIR.glob("*/meta_*.json")
    )


def relpath(p) -> str:
    """Already repo-relative; kept for output symmetry."""
    return str(p)


def schema_check(validator: Draft202012Validator, meta: dict) -> list[str]:
    errors = []
    for err in validator.iter_errors(meta):
        loc = ".".join(str(p) for p in err.absolute_path) or "<root>"
        errors.append(f"{loc}: {err.message}")
    return errors


def bucket_check(meta_rel: str, meta: dict, source
                 ) -> tuple[list[str], list[str]]:
    """Returns (bucket_warnings, missing_file_warnings).

    Validates EVERY accepted story-bearing declaration — short/full/long and
    short_kjv/full_kjv/long_kjv — using the single authoritative traversal in
    story_files_from_meta_checked(), so identity rules are never duplicated.

    SAFETY ORDER — a raw storyText value is never joined and read:
      1. metadata already parsed from the authoritative content source
      2. validate storyText (canonical, contained, identity-consistent)
      3. resolve the repo-relative path only after validation passes
      4. read content through the same source
      5. word-count the decoded text

    Psalm and shortScripture carve-outs are preserved unchanged.
    """
    bucket_warns: list[str] = []
    missing_warns: list[str] = []

    anchor = meta.get("scriptureAnchor", "") or ""
    is_psalm = anchor.strip().lower().startswith("psalm")
    is_short_scripture = bool(meta.get("shortScripture"))

    accepted, rejected = reconstruction_check.story_files_from_meta_checked(
        meta_rel, meta)
    for f in rejected:
        missing_warns.append(f"storyText rejected — {f.unresolved}")

    seen_paths: set[str] = set()
    for rel, _sid, lane, length in accepted:
        if length not in BUCKETS:
            continue
        if rel in seen_paths:
            continue  # never count one physical path twice
        seen_paths.add(rel)
        label = f"{length}_kjv" if lane == "kjv" else length

        if not source.exists(rel):
            missing_warns.append(
                f"{label}: {rel.split('/')[-1]} is not present in the "
                f"prospective commit")
            continue
        mode = source.mode(rel)
        if mode == reconstruction_check.SYMLINK_MODE:
            missing_warns.append(f"{label}: symlink entry is not supported")
            continue
        if mode == reconstruction_check.GITLINK_MODE:
            missing_warns.append(f"{label}: gitlink entry is not supported")
            continue
        if mode == reconstruction_check.EXECUTABLE_FILE_MODE:
            missing_warns.append(
                f"{label}: executable mode {mode} (expected "
                f"{reconstruction_check.NORMAL_FILE_MODE})")
        try:
            text = source.read_text(rel)
        except ContentUnavailable as e:
            missing_warns.append(f"{label}: unreadable — {e}")
            continue

        wc = len(text.split())
        floor, ceiling = BUCKETS[length]

        carved_out = False
        carve_reason = ""
        if length == "short":
            if is_short_scripture:
                carved_out = True
                carve_reason = "shortScripture:true (MICRO legacy)"
            elif is_psalm and wc < floor:
                carved_out = True
                carve_reason = f"Psalm anchor {anchor!r} (short floor waived)"

        if carved_out:
            if not is_short_scripture and wc > ceiling:
                bucket_warns.append(
                    f"{label}: {wc} words, above {ceiling} ceiling "
                    f"(carve-out {carve_reason} only waives the floor)")
            continue

        if wc < floor:
            extra = ""
            if length == "short" and is_psalm:
                extra = f" (anchor {anchor!r} qualifies for Psalm carve-out)"
            bucket_warns.append(f"{label}: {wc} words, below {floor} floor{extra}")
        elif wc > ceiling:
            bucket_warns.append(f"{label}: {wc} words, above {ceiling} ceiling")

    return bucket_warns, missing_warns


def _report_reconstruction(findings: list, verbose: bool,
                           counts: dict,
                           undeclared: list | None = None,
                           errors: list | None = None,
                           content_source: str = "working-tree") -> None:
    """Print the ADR-031 advisory report.

    ADVISORY ONLY. Never contributes to the exit code, never edits a file, and
    never emits an editorial verdict about whether a story is an adequate
    retelling — that is ADR-031 Level 2, a human judgement.
    """
    recon = [f for f in findings if f.reconstructible]
    unresolved = [f for f in findings if f.unresolved]
    evaluated = [f for f in findings if not f.unresolved]

    print()
    print("=" * 70)
    print("ADR-031 RECONSTRUCTION DIAGNOSTIC (advisory — does not affect exit code)")
    print(f"content source: {content_source}")
    print("=" * 70)

    for path, err in (errors or []):
        print()
        print(f"[RECONSTRUCTION-ERROR] {path}")
        print(f"  {err}")
        print("  Tool failure on this input — no reconstruction conclusion drawn.")

    for f in recon:
        print()
        print(reconstruction_check.format_reconstruction(f, relpath(f.path)))

    for f in unresolved:
        print()
        print(reconstruction_check.format_unresolved(f, relpath(f.path)))

    if verbose:
        ranked = sorted(
            (f for f in evaluated if not f.reconstructible),
            key=lambda f: (-f.metrics.longest_run, -f.block_coverage_ratio),
        )
        # Display cutoff below is OUTPUT-VOLUME CONTROL ONLY. Not an acceptance
        # boundary; it carries no quality meaning.
        shown = [f for f in ranked
                 if f.metrics.longest_run
                 >= reconstruction_check.VERBOSE_LONG_RUN_DISPLAY_MIN]
        capped = shown[: reconstruction_check.VERBOSE_MAX_ROWS]
        print()
        print("-" * 70)
        print("DIAGNOSTIC METRICS — prioritization only, no acceptance threshold")
        print(f"(display cutoff: longest run >= "
              f"{reconstruction_check.VERBOSE_LONG_RUN_DISPLAY_MIN}w, "
              f"max {reconstruction_check.VERBOSE_MAX_ROWS} rows — "
              f"output-volume control, not a quality boundary)")
        print("-" * 70)
        for f in capped:
            print(f"[LONG-RUN] {f.story_id} {f.lane} {f.length:5s} "
                  f"run {f.metrics.longest_run:4d}w | "
                  f"SequenceMatcher block coverage "
                  f"{f.metrics.matched_words}/{f.story_words} "
                  f"({f.block_coverage_ratio * 100:5.1f}%) | "
                  f"unmatched story tokens {f.metrics.unmatched_words:4d} | "
                  f"{f.anchor}")
        if len(shown) > len(capped):
            print(f"  ... {len(shown) - len(capped)} further rows suppressed "
                  f"by the display cap (not adjudicated).")

    undeclared = undeclared or []
    if undeclared:
        print()
        print("-" * 70)
        print("INVENTORY — metadata drift, NOT reconstruction findings")
        print("-" * 70)
        print(f"matching story files present on disk but undeclared in "
              f"meta.files: {len(undeclared)}")
        print("These are NOT evaluated by the default scan and are NOT counted "
              "as findings.")
        print("Supply them via --reconstruction-story-paths to analyze them.")
        if verbose:
            cap = reconstruction_check.VERBOSE_MAX_ROWS
            for p in undeclared[:cap]:
                print(f"  [UNDECLARED] {p}")
            if len(undeclared) > cap:
                print(f"  ... {len(undeclared) - cap} further undeclared paths "
                      f"(display cap — inventory, not findings).")

    # All counts below are computed AFTER deduplication, so metadata + explicit
    # never exceeds total.
    print()
    print("Reconstruction summary (all counts post-deduplication):")
    print(f"  metadata-derived evaluated:          {counts['metadata']}")
    print(f"  explicit staged paths evaluated:     {counts['explicit']}")
    print(f"  duplicates collapsed:                {counts['duplicates']}")
    print(f"  total story files evaluated:         {len(evaluated)}")
    print(f"  [RECONSTRUCTION]:                    {len(recon)}")
    print(f"  [UNRESOLVED]:                        {len(unresolved)}")
    if errors:
        print(f"  [RECONSTRUCTION-ERROR]:              {len(errors)} "
              f"(tool failures — not clean results)")
    if undeclared:
        print(f"  undeclared on disk (inventory only): {len(undeclared)}")
    print("  anchorCategory:                      unknown for all files "
          "(no approved classification field exists)")
    print("  These are review triggers, not quality scores. No story is "
          "adjudicated defective by this tool.")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate Bible PAL traditional story metas + bucket gate."
    )
    parser.add_argument("--paths", nargs="+",
                        help="Specific meta files to validate. Default: full corpus.")
    parser.add_argument("--strict-bucket", action="store_true",
                        help="Promote bucket warnings and missing-file warnings "
                             "to FAIL (contributes to exit code). Default: warn-only.")
    parser.add_argument("--reconstruction", action="store_true",
                        help="Run the ADR-031 reconstruction diagnostic. "
                             "ADVISORY — never affects the exit code.")
    parser.add_argument("--reconstruction-verbose", action="store_true",
                        help="Also print longest-run and block-coverage "
                             "diagnostics. No acceptance threshold.")
    parser.add_argument("--reconstruction-story-paths", nargs="+", default=[],
                        metavar="PATH",
                        help="Explicit adult Traditional story paths to analyze, "
                             "even if absent from their meta's files map.")
    parser.add_argument("--index-change-snapshot", metavar="FILE",
                        help="Path to the ONE authoritative NUL-delimited "
                             "`git diff --cached --name-status -z "
                             "--diff-filter=ACMRDT` snapshot. Presence of this "
                             "flag selects HOOK MODE, which never performs "
                             "full-corpus discovery.")
    parser.add_argument("--reconstruction-from-index", action="store_true",
                        help="Read ALL metadata and story bytes from the Git "
                             "index (what a commit would contain) instead of the "
                             "working tree. Used by the pre-commit hook.")
    args = parser.parse_args()

    hook_mode = bool(args.index_change_snapshot)
    if args.reconstruction_from_index or hook_mode:
        source = reconstruction_check.GitIndexSource(REPO_ROOT)
    else:
        source = reconstruction_check.WorkingTreeSource(REPO_ROOT)

    classification = None
    deletion_reviews: list = []
    deletion_structural: list = []
    bad_meta_paths: list = []
    kid_status = 0

    if hook_mode:
        # Probe index integrity FIRST and report it under its own headline.
        # Otherwise an index-wide failure (an unresolved merge, a corrupt index)
        # would surface as whatever happened to read the index first — usually
        # "schema unavailable" — which names the wrong cause.
        try:
            source.entries()
        except InfrastructureError as e:
            print("[INFRASTRUCTURE-FAILURE] the Git index could not be read")
            print(f"  {e}")
            print("  Blocking: exit code 1.", file=sys.stderr)
            return 1

    try:
        # Schema loading and validator construction sit INSIDE the structured
        # error boundary: a missing/corrupt staged schema is infrastructure.
        schema = load_schema(source if hook_mode else None)
        # The schema must itself be a VALID Draft 2020-12 schema. Without this,
        # something like {"type": 7} constructs a validator that silently
        # accepts everything, so a schema-only commit could disable metadata
        # validation for the whole corpus while every gate still reported clean.
        try:
            Draft202012Validator.check_schema(schema)
        except SchemaError as e:
            print("[INFRASTRUCTURE-FAILURE] staged metadata schema is invalid")
            print(f"  {reconstruction_check.META_SCHEMA_PATH} is not a valid "
                  f"JSON Schema (Draft 2020-12): {e.message}")
            if list(e.absolute_path):
                print(f"  at: {'/'.join(str(p) for p in e.absolute_path)}")
            print("  No metadata can be validated against it.")
            print("  Blocking: exit code 1.", file=sys.stderr)
            return 1
        validator = Draft202012Validator(schema)
    except InfrastructureError as e:
        print("[INFRASTRUCTURE-FAILURE] schema unavailable")
        print(f"  {e}")
        print("  Blocking: exit code 1.", file=sys.stderr)
        return 1
    except Exception:
        print("[INTERNAL-ERROR] schema/validator construction failed")
        traceback.print_exc()
        return 1

    if hook_mode:
        # HOOK MODE CONTRACT: validate ONLY what the snapshot represents plus
        # required final-index siblings. discover_metas() is never reachable
        # here, so zero accepted arguments can never become a corpus sweep.
        try:
            snap_bytes = Path(args.index_change_snapshot).read_bytes()
        except OSError as e:
            print("[INFRASTRUCTURE-FAILURE] staged-change snapshot unreadable")
            print(f"  {e}")
            print("  Blocking: exit code 1.", file=sys.stderr)
            return 1
        try:
            changes = reconstruction_check.parse_change_snapshot(snap_bytes)
            classification = reconstruction_check.classify_changes(changes)
            deletion_reviews, deletion_structural = (
                reconstruction_check.review_deletions(classification, source))
        except InfrastructureError as e:
            print("[INFRASTRUCTURE-FAILURE] staged-change snapshot unusable")
            print(f"  {e}")
            print("  Blocking: exit code 1.", file=sys.stderr)
            return 1
        bad_meta_paths = classification.bad_metadata_paths
        # Only metadata that exists in the FINAL index is validated. Presence is
        # decided from the already-captured index map — no per-path Git probe,
        # so a Git failure can never be mistaken for ordinary absence.
        metas = [m for m in classification.canonical_metas if source.exists(m)]
        # Siblings required by staged stories.
        for sp in classification.story_paths:
            m = reconstruction_check.STORY_REL_PATH_RE.match(sp)
            if not m:
                continue
            sib = (f"{reconstruction_check.TRADITIONAL_PREFIX}/"
                   f"{m.group('dir_id')}/meta_{m.group('dir_id')}.json")
            if sib not in metas and source.exists(sib):
                metas.append(sib)
        story_paths = classification.story_paths
        if classification.kid_paths:
            try:
                kid_status = run_kid_gate_from_index(
                    source, classification.kid_paths,
                    frozenset(d.path for d in classification.deletions))
            except InfrastructureError as e:
                print("[INFRASTRUCTURE-FAILURE] kid gate could not read the index")
                print(f"  {e}")
                print("  Blocking: exit code 1.", file=sys.stderr)
                return 1
            except Exception:
                # The kid gate imports and drives another module. An unexpected
                # failure there (missing module, changed API) must block with a
                # labelled diagnostic, not escape as a bare traceback.
                print("[INTERNAL-ERROR] the kid gate failed unexpectedly")
                traceback.print_exc()
                print("  Blocking: exit code 1.", file=sys.stderr)
                return 1
    elif args.paths:
        metas = []
        for p in args.paths:
            rel = reconstruction_check.repo_relative(p, REPO_ROOT)
            metas.append(rel if rel is not None else str(p))
        story_paths = args.reconstruction_story_paths
    elif args.reconstruction_story_paths:
        # Explicit-path mode (the hook supplies exactly what is staged). Do NOT
        # fall back to a full-corpus disk sweep: that would validate metadata
        # the prospective commit does not touch, and in index mode would report
        # every unstaged meta as absent.
        metas = []
        story_paths = args.reconstruction_story_paths
    else:
        metas = discover_metas()
        story_paths = args.reconstruction_story_paths

    schema_fail_count = 0
    bucket_warn_count = 0
    missing_warn_count = 0
    metas_checked = 0
    recon_findings: list = []
    recon_errors: list = []

    try:
        for meta_rel in metas:
            if not source.exists(meta_rel):
                print(f"[FAIL] {meta_rel}\n  io: not present in the "
                      f"{source.name} content source")
                schema_fail_count += 1
                continue
            try:
                # Metadata drives validation, so a symlink/gitlink/executable
                # blob in its place is a structural failure, not content to
                # interpret. Checked BEFORE parsing; the target is never read.
                require_ordinary_data_mode(source, meta_rel, "metadata")
            except InfrastructureError as e:
                print(f"[FAIL] {meta_rel}\n  structural: {e}")
                schema_fail_count += 1
                continue
            try:
                meta = source.read_json(meta_rel)
            except ContentUnavailable as e:
                print(f"[FAIL] {meta_rel}\n  io: {e}")
                schema_fail_count += 1
                continue
            if not isinstance(meta, dict):
                print(f"[FAIL] {meta_rel}\n  io: metadata is not a JSON object")
                schema_fail_count += 1
                continue

            metas_checked += 1
            schema_errors = schema_check(validator, meta)
            bucket_warns, missing_warns = bucket_check(meta_rel, meta, source)

            if schema_errors:
                schema_fail_count += 1
                print(f"[FAIL] {meta_rel}")
                print("  schema:")
                for e in schema_errors:
                    print(f"    - {e}")

            warn_level = "FAIL" if args.strict_bucket else "WARN"
            if bucket_warns or missing_warns:
                print(f"[{warn_level}] {meta_rel}")
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

            if args.reconstruction:
                try:
                    recon_findings.extend(reconstruction_check.analyze_meta(
                        meta_rel, meta, source, REPO_ROOT))
                except ContentUnavailable as e:
                    recon_errors.append((meta_rel, f"advisory input error: {e}"))

        if args.reconstruction:
            explicit = reconstruction_check.analyze_explicit_story_paths(
                story_paths, source, REPO_ROOT)
            before = len(recon_findings) + len(explicit)
            merged = reconstruction_check.dedupe_findings(recon_findings + explicit)
            counts = {
                "metadata": len([f for f in merged
                                 if f.origin == reconstruction_check.ORIGIN_METADATA
                                 and not f.unresolved]),
                "explicit": len([f for f in merged
                                 if f.origin == reconstruction_check.ORIGIN_EXPLICIT
                                 and not f.unresolved]),
                "duplicates": before - len(merged),
            }
            # HOOK MODE: no working-tree inventory. undeclared_story_files()
            # walks the whole corpus on disk, which would report unstaged files
            # the prospective commit does not touch and let an unrelated
            # working-tree edit change hook output. Manual full-corpus mode
            # still reports it.
            undeclared = ([] if (args.paths or hook_mode)
                          else reconstruction_check.undeclared_story_files())
            _report_reconstruction(merged, args.reconstruction_verbose, counts,
                                   undeclared, recon_errors, source.name)

    except InfrastructureError as e:
        # BLOCKING. The machinery failed; no clean result can be claimed.
        print()
        print("[INFRASTRUCTURE-FAILURE] validation could not be completed")
        print(f"  {e}")
        print("  This is NOT an editorial finding and NOT a clean pass.")
        print("  Blocking: exit code 1.", file=sys.stderr)
        return 1
    except Exception:  # noqa: BLE001 - unexpected internal programming error
        print()
        print("[INTERNAL-ERROR] unexpected exception in the validator")
        traceback.print_exc()
        print("  This is NOT an editorial finding and NOT a clean pass.")
        print("  Blocking: exit code 1.", file=sys.stderr)
        return 1

    for path, reason in bad_meta_paths:
        print()
        print(f"[METADATA-PATH-REVIEW] {path}")
        print(f"  {reason}")
        print("  This exact staged path was classified; no other file was "
              "validated in its place.")
        print("  ADVISORY under current policy — exit code unaffected.")

    for r in deletion_reviews:
        print()
        print(reconstruction_check.format_deletion_review(r))

    # A deletion stays advisory, but a structural defect found while classifying
    # it is independent and blocks. Printed after the advisory reviews so both
    # are visible: the deletion is not the failure, and the failure is not a
    # new deletion policy.
    for problem in deletion_structural:
        print()
        print("[INFRASTRUCTURE-FAILURE] final-index metadata is not ordinary data")
        print(f"  {problem}")
        print("  The deletion above remains ADVISORY; this is a separate, "
              "independent defect.")

    print()
    print(f"Checked: {metas_checked} metas")
    print(f"  schema FAIL: {schema_fail_count}")
    print(f"  bucket {'FAIL' if args.strict_bucket else 'WARN'}: {bucket_warn_count}")
    print(f"  missing-file {'FAIL' if args.strict_bucket else 'WARN'}: {missing_warn_count}")

    if deletion_structural:
        print("  Blocking: exit code 1.", file=sys.stderr)
        return 1
    if kid_status != 0:
        return kid_status
    if schema_fail_count > 0:
        return 1
    if args.strict_bucket and (bucket_warn_count > 0 or missing_warn_count > 0):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
