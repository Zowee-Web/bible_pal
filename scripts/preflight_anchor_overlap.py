#!/usr/bin/env python3
"""
preflight_anchor_overlap.py — deterministic scripture-overlap gate.

Answers one question before a story is assigned to an author:

    Does this proposed scripture range substantially overlap an already
    existing or already-reserved Bible PAL story?

COVERAGE AUTHORITY
  Reconstructed on EVERY invocation from `meta.scriptureAnchor` across all
  live Git worktrees, plus queued reservations. Deliberately NOT derived from:
    - assets/stories/anchor_coverage.json  (generated snapshot; observed stale)
    - meta.scriptureAnchorId               (absent on ~35% of metas; three
                                            different separator conventions)
  scripture_anchor_registry.json is advisory only and is never consulted here.

PARSING
  Reuses scripts/lib/bible_ref_parser.py unchanged (parse_bible_refs +
  extract_verses). This module adds ONLY a narrow pre-normalization layer for
  whitespace and book-name case, resolved against the bundled WEB Bible's own
  book names — no alias table is invented. Verse sets are built on WEB
  versification so comparison is deterministic.

  SUPPORTED multi-range forms (exactly what the existing parser accepts):
      "John 14:1-3, 18-19, 27"      comma pieces are VERSE-ONLY continuations
      "Matthew 13:24-30, 36-43"     inheriting the preceding book AND chapter
  NOT SUPPORTED (a comma piece may not restate a chapter):
      "Acts 12:6-19, 12:20-23"
      "Luke 1:1-4, 2:1-7"
  Unsupported forms are a parse failure. Under the coverage-integrity model
  below they produce ERROR/30 — never a guess and never a silent skip.

COVERAGE INTEGRITY (fail closed)
  BLOCK means "coverage was compared and a collision was found".
  ERROR means "the complete occupied universe could not be established".
  These are deliberately distinct. Any condition that prevents the gate from
  knowing the full occupied universe — malformed meta JSON, a meta missing
  storyId or scriptureAnchor, an existing anchor that cannot be parsed, or a
  story directory that cannot be enumerated — yields verdict ERROR with
  errorCode COVERAGE_INTEGRITY_FAILURE and exit 30. Never PASS, never WARN,
  and never disguised as an ordinary overlap BLOCK.

VERDICTS
  BLOCK  EXACT | CANDIDATE_CONTAINED | EXISTING_CONTAINED
         | sharedVerses >= 3 and maxSideCoverage >= 0.50
  WARN   sharedVerses >= 3 and maxSideCoverage >= 0.20
         | any single existing story shares >= 5 verses
         | cumulative union coverage of the candidate >= 0.60
  PASS   no shared verses, or a boundary-adjacent SEAM of <= 2 verses

  A SEAM is how legitimate "untold second half" episodes are preserved:
  consecutive episodes share a hinge verse or nothing. Percentage alone is the
  wrong discriminator — 2 Kings 2:1-12 vs 2:11-14 is a 2-verse seam that scores
  50%, and blocking it would be a false positive.

EXIT CODES
  0 PASS | 10 WARN | 20 BLOCK | 30 parse/IO/infrastructure failure
  Errors always fail closed. PASS is never returned on an error path.

Read-only: this script never writes to the repository.

Usage:
  python3 scripts/preflight_anchor_overlap.py --anchor "Acts 12:6-19"
  python3 scripts/preflight_anchor_overlap.py --anchor "Daniel 6" --story-id 1651
  python3 scripts/preflight_anchor_overlap.py --anchor "..." \
      --worktree /path/a --worktree /path/b \
      --reservations queue.json --approvals approvals.json
"""

from __future__ import annotations

import argparse
import glob
import io
import json
import os
import re
import stat
import subprocess
import sys
from contextlib import redirect_stderr
from datetime import datetime, timezone

GATE_VERSION = "1.0.0"
VERSIFICATION = "WEB"

EXIT_PASS, EXIT_WARN, EXIT_BLOCK, EXIT_ERROR = 0, 10, 20, 30

# Reservation states that occupy coverage.
OCCUPYING_STATES = frozenset({"reserved", "authoring", "locked"})

# Queue states that are known NOT to occupy. This list is a closed vocabulary,
# not an "everything else" default: an unrecognised state used to be silently
# dropped, which meant any producer typo or any new lifecycle name became an
# invisible non-occupancy. The gate cannot tell a deliberately-free state from
# a state it has never heard of, so it must not guess.
NON_OCCUPYING_STATES = frozenset({"abandoned", "expired", "released"})

# The complete queue vocabulary. A state outside it is a hard GateError, never
# a silent PASS. Extending this set is a deliberate act, and adding a name here
# is a decision about whether that name reserves a passage.
KNOWN_QUEUE_STATES = OCCUPYING_STATES | NON_OCCUPYING_STATES

# An approval is a HUMAN act. Authorization is an ALLOWLIST, never a denylist:
# a denylist can only refuse identities someone thought of in advance, so any
# unknown or future model name would authorize itself. The security property is
#     approvedBy in AUTHORIZED_HUMAN_APPROVERS
# and nothing else. Extend deliberately via --approver / BIBLEPAL_OVERLAP_APPROVERS.
DEFAULT_AUTHORIZED_HUMAN_APPROVERS = frozenset({"owner"})

# Retained ONLY to enrich the rejection message. Never consulted for authorization.
_AGENT_IDENTITY_HINT = re.compile(
    r"(claude|codex|gpt|opus|sonnet|haiku|gemini|mistral|llama|assistant|agent|bot"
    r"|automation|autonomous|llm|\bai\b|model|system)",
    re.IGNORECASE,
)

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO_ROOT, "scripts"))

from lib.bible_ref_parser import parse_bible_refs, extract_verses  # noqa: E402


class GateError(Exception):
    """Any condition that must fail closed (exit 30)."""


class CoverageIntegrityError(GateError):
    """The complete occupied scripture universe could not be established.

    Distinct from an overlap BLOCK: a BLOCK is a successful comparison that
    found a collision; this is the gate admitting it cannot safely compare.
    """

    def __init__(self, failures):
        self.failures = list(failures)
        n = len(self.failures)
        first = self.failures[0]["condition"] if self.failures else "unknown"
        super().__init__(
            f"coverage integrity failure: {n} condition(s), first: {first}"
        )


def _integrity(condition, *, worktree=None, file=None, story_id=None,
               raw_anchor=None, detail=None):
    """One structured integrity failure. Carries locators, never file contents."""
    rec = {"condition": condition}
    if worktree is not None:
        rec["worktree"] = os.path.basename(worktree.rstrip(os.sep)) or worktree
    if file is not None:
        rec["file"] = os.path.relpath(file, worktree) if worktree else os.path.basename(file)
    if story_id is not None:
        rec["storyId"] = story_id
    if raw_anchor is not None:
        rec["rawAnchor"] = str(raw_anchor)[:200]
    if detail is not None:
        rec["detail"] = str(detail)[:300]
    return rec


# --------------------------------------------------------------------------
# Normalization + verse sets
# --------------------------------------------------------------------------

def load_bible(path: str | None = None) -> dict:
    p = path or os.path.join(REPO_ROOT, "server", "data", "bible_web.json")
    try:
        with open(p, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        raise GateError(f"cannot read WEB Bible data at {p}: {exc}") from exc


def normalize_reference(raw: str, bible: dict) -> str:
    """Collapse whitespace and repair book-name case.

    The canonical spelling is taken from the bundled Bible's own book keys, so
    no alias table is invented here. Everything else is left untouched for the
    real parser to handle (dashes, comma lists, chapter-only, ...).
    """
    if raw is None or not str(raw).strip():
        raise GateError("empty scripture reference")

    ref = re.sub(r"\s+", " ", str(raw).strip())

    # Leading book token: optional ordinal prefix, then alphabetic words.
    m = re.match(r"^([1-3]?\s*[A-Za-z][A-Za-z.]*(?:\s+[A-Za-z][A-Za-z.]*)*)(\s+\d.*)$", ref)
    if not m:
        return ref  # let the parser produce the precise error

    book_raw, remainder = m.group(1), m.group(2)
    key = re.sub(r"\s+", " ", book_raw).strip().lower().rstrip(".")

    for canonical in bible.get("books", {}):
        if canonical.lower() == key:
            return f"{canonical}{remainder}"

    return ref


def verse_set(reference: str, bible: dict) -> set[tuple[str, int, int]]:
    """Parsed reference -> {(book, chapter, verse)} on WEB versification."""
    normalized = normalize_reference(reference, bible)
    out: set[tuple[str, int, int]] = set()
    try:
        # extract_verses narrates intentionally-absent verses on stderr
        # (e.g. WEB omits Acts 8:37). Keep stdout JSON clean.
        sink = io.StringIO()
        with redirect_stderr(sink):
            for ref in parse_bible_refs(normalized):
                for chapter, verse, _text in extract_verses(bible, ref):
                    out.add((ref.book, chapter, verse))
    except ValueError as exc:
        raise GateError(f"unparseable reference {reference!r}: {exc}") from exc
    if not out:
        raise GateError(f"reference {reference!r} resolved to zero verses")
    return out


def _ordered(vs: set[tuple[str, int, int]]) -> list[tuple[str, int, int]]:
    return sorted(vs)


def is_boundary_adjacent(
    shared: set[tuple[str, int, int]],
    a: set[tuple[str, int, int]],
    b: set[tuple[str, int, int]],
) -> bool:
    """True when the shared block sits at a range edge on BOTH sides.

    A genuine second-half episode touches its neighbour at a hinge: the shared
    verses are a suffix of one range and a prefix of the other. A duplicate
    retelling overlaps in the middle or engulfs the other range.
    """
    if not shared:
        return False
    sa, sb, ss = _ordered(a), _ordered(b), _ordered(shared)

    # Shared block must be contiguous within each side's own ordering.
    for side in (sa, sb):
        idx = [i for i, v in enumerate(side) if v in shared]
        if idx != list(range(idx[0], idx[0] + len(idx))):
            return False
        if idx[0] != 0 and idx[-1] != len(side) - 1:
            return False  # sits in the middle of this side
    return ss[0] in (sa[0], sb[0]) or ss[-1] in (sa[-1], sb[-1])


def are_adjacent(a: set, b: set) -> bool:
    """Zero shared verses but contiguous in the same book+chapter."""
    if a & b:
        return False
    sa, sb = _ordered(a), _ordered(b)
    for hi, lo in ((sa[-1], sb[0]), (sb[-1], sa[0])):
        if hi[0] == lo[0] and hi[1] == lo[1] and lo[2] == hi[2] + 1:
            return True
    return False


def classify(cand: set, exist: set) -> str:
    shared = cand & exist
    if not shared:
        return "ADJACENT" if are_adjacent(cand, exist) else "DISJOINT"
    if cand == exist:
        return "EXACT"
    if cand < exist:
        return "CANDIDATE_CONTAINED"
    if exist < cand:
        return "EXISTING_CONTAINED"
    if len(shared) <= 2 and is_boundary_adjacent(shared, cand, exist):
        return "SEAM"
    return "PARTIAL"


# --------------------------------------------------------------------------
# Coverage universe
# --------------------------------------------------------------------------

def discover_worktrees(repo_root: str) -> list[str]:
    try:
        proc = subprocess.run(
            ["git", "worktree", "list", "--porcelain"],
            cwd=repo_root, capture_output=True, text=True, timeout=60,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise GateError(f"git worktree enumeration failed: {exc}") from exc
    if proc.returncode != 0:
        raise GateError(f"git worktree enumeration failed: {proc.stderr.strip()}")

    paths = [ln[len("worktree "):].strip()
             for ln in proc.stdout.splitlines() if ln.startswith("worktree ")]
    if not paths:
        raise GateError("git reported zero worktrees")

    # Primary checkout first so first-seen-wins dedup is deterministic.
    root = os.path.realpath(repo_root)
    paths.sort(key=lambda p: (os.path.realpath(p) != root, p))
    return paths


def _scandir(path, worktree, failures):
    """Enumerate a directory, surfacing IO failure instead of collapsing to [].

    glob.glob() returns an empty list on EACCES, which is indistinguishable
    from "legitimately empty" — that is the B4 fail-open. os.scandir raises.
    """
    try:
        with os.scandir(path) as it:
            return sorted(it, key=lambda e: e.name)
    except OSError as exc:
        failures.append(_integrity("story directory could not be enumerated",
                                   worktree=worktree, file=path, detail=exc.strerror))
        return None


def harvest(worktrees: list[str]) -> tuple[dict, list[dict], list[str], list[dict]]:
    """Collect storyId -> record across worktrees.

    Reads the WORKING TREE (not the index) so untracked new story directories
    in other lanes are visible. Every discovered meta must parse, carry a valid
    storyId, and carry a non-empty scriptureAnchor. A meta that fails any of
    these is an integrity failure, never a silent skip: dropping it would
    shrink the occupied universe and could turn a real collision into a PASS.
    """
    universe: dict[int, dict] = {}
    conflicts: list[dict] = []
    scanned: list[str] = []
    failures: list[dict] = []

    for wt in worktrees:
        base = os.path.join(wt, "assets", "stories", "traditional")
        # F3: os.path.exists() conflates "absent" with "unreachable" — on an
        # unreadable parent it returns False and the worktree's coverage
        # silently vanishes. Only FileNotFoundError may mean "this worktree
        # legitimately has no Traditional story area"; every other OSError is
        # a coverage-integrity failure (ERROR/30), never a silent skip.
        try:
            st = os.stat(base)
        except FileNotFoundError:
            continue  # worktree legitimately carries no story area
        except OSError as exc:
            failures.append(_integrity("story area could not be reached",
                                       worktree=wt, file=base,
                                       detail=exc.strerror))
            continue
        if not stat.S_ISDIR(st.st_mode):
            failures.append(_integrity("story area is not a directory",
                                       worktree=wt, file=base))
            continue

        story_dirs = _scandir(base, wt, failures)
        if story_dirs is None:
            continue  # enumeration failed; NOT counted as scanned

        enumerated_ok = True
        for entry in story_dirs:
            if not entry.is_dir():
                continue
            meta_entries = _scandir(entry.path, wt, failures)
            if meta_entries is None:
                enumerated_ok = False
                continue
            for me in meta_entries:
                if not (me.name.startswith("meta_") and me.name.endswith(".json")):
                    continue

                try:
                    with open(me.path, encoding="utf-8") as fh:
                        meta = json.load(fh)
                except OSError as exc:
                    failures.append(_integrity("meta file unreadable", worktree=wt,
                                               file=me.path, detail=exc.strerror))
                    continue
                except json.JSONDecodeError as exc:
                    failures.append(_integrity("meta file is not valid JSON",
                                               worktree=wt, file=me.path,
                                               detail=f"line {exc.lineno}"))
                    continue

                if not isinstance(meta, dict):
                    failures.append(_integrity("meta root is not an object",
                                               worktree=wt, file=me.path))
                    continue

                sid = meta.get("storyId")
                if not isinstance(sid, int) or isinstance(sid, bool):
                    failures.append(_integrity("meta missing or invalid storyId",
                                               worktree=wt, file=me.path))
                    continue

                anchor = meta.get("scriptureAnchor")
                if not isinstance(anchor, str) or not anchor.strip():
                    failures.append(_integrity("meta missing or empty scriptureAnchor",
                                               worktree=wt, file=me.path, story_id=sid))
                    continue
                anchor = anchor.strip()

                if sid not in universe:
                    universe[sid] = {
                        "storyId": sid, "anchor": anchor,
                        "origin": f"worktree:{os.path.basename(wt)}",
                        "state": "materialized", "path": me.path,
                    }
                elif universe[sid]["anchor"] != anchor:
                    conflicts.append({
                        "storyId": sid,
                        "firstAnchor": universe[sid]["anchor"],
                        "firstOrigin": universe[sid]["origin"],
                        "conflictingAnchor": anchor,
                        "conflictingOrigin": f"worktree:{os.path.basename(wt)}",
                    })

        # Only claim a worktree was scanned once its story area truly enumerated.
        if enumerated_ok:
            scanned.append(wt)

    return universe, conflicts, scanned, failures


def load_reservations(path: str | None) -> list[dict]:
    """Small decoupled interface for the concurrently-built ID reservation
    service. Accepts {"reservations":[...]} or a bare list. Each entry needs
    storyId, proposedAnchor, state. Only OCCUPYING_STATES reserve coverage.

    A state outside KNOWN_QUEUE_STATES fails closed rather than being dropped:
    silently ignoring an unrecognised state is indistinguishable from declaring
    the passage free, which is the one answer the gate must never guess."""
    if not path:
        return []
    if not os.path.exists(path):
        raise GateError(f"reservations file not found: {path}")
    try:
        with open(path, encoding="utf-8") as fh:
            raw = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        raise GateError(f"unreadable reservations file {path}: {exc}") from exc

    entries = raw.get("reservations", []) if isinstance(raw, dict) else raw
    if not isinstance(entries, list):
        raise GateError("reservations payload must be a list")

    out = []
    for e in entries:
        if not isinstance(e, dict):
            raise GateError("reservation entry must be an object")
        sid, anchor = e.get("storyId"), (e.get("proposedAnchor") or "").strip()
        state = (e.get("state") or "").strip().lower()
        if sid is None or not anchor or not state:
            raise GateError(f"reservation entry missing storyId/proposedAnchor/state: {e}")
        if state not in KNOWN_QUEUE_STATES:
            # Fail closed. A dropped row is an invisible occupancy, and the
            # gate has no basis for deciding that an unfamiliar state is free.
            raise GateError(
                f"unknown reservation queue state {state!r} for story {sid}; "
                f"known states: {sorted(KNOWN_QUEUE_STATES)}"
            )
        out.append({"storyId": sid, "anchor": anchor, "state": state,
                    "origin": "queue", "path": path})
    return out


def load_approvals(path: str | None) -> list[dict]:
    """Owner-controlled intentional-overlap records. An absent file simply
    means no approvals exist — that is not an error."""
    if not path or not os.path.exists(path):
        return []
    try:
        with open(path, encoding="utf-8") as fh:
            raw = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        raise GateError(f"unreadable approvals file {path}: {exc}") from exc

    entries = raw.get("approvals", []) if isinstance(raw, dict) else raw
    if not isinstance(entries, list):
        raise GateError("approvals payload must be a list")
    return [e for e in entries if isinstance(e, dict)]


def select_approval(approvals, normalized_anchor, bible,
                    authorized_approvers=DEFAULT_AUTHORIZED_HUMAN_APPROVERS):
    """Return (approval, rejections). Never invents permission.

    Authorization is an explicit human allowlist. The old agent-name pattern
    survives only to make the rejection message more informative — it grants
    nothing and refuses nothing on its own.
    """
    rejections = []
    for idx, ap in enumerate(approvals):
        who = str(ap.get("approvedBy") or "").strip()
        ident = f"approvals[{idx}]"
        if not who:
            rejections.append({"approval": ident, "reason": "missing approvedBy"})
            continue
        if who not in authorized_approvers:
            hint = (" (identity resembles an AI agent; agents may never "
                    "self-approve overlap)") if _AGENT_IDENTITY_HINT.search(who) else ""
            rejections.append({
                "approval": ident,
                "reason": f"approvedBy {who!r} is not an authorized human "
                          f"approver{hint}; authorized: {sorted(authorized_approvers)}",
            })
            continue
        try:
            ap_anchor = normalize_reference(ap.get("candidateAnchor") or "", bible)
        except GateError:
            rejections.append({"approval": ident, "reason": "unparseable candidateAnchor"})
            continue
        if ap_anchor != normalized_anchor:
            continue
        if not isinstance(ap.get("acknowledgedStoryIds"), list) or \
           ap.get("maxPermittedSharedVerses") is None or \
           ap.get("maxPermittedCandidateCoverage") is None or \
           not str(ap.get("reason") or "").strip():
            rejections.append({
                "approval": ident,
                "reason": "incomplete approval: needs acknowledgedStoryIds, "
                          "maxPermittedSharedVerses, maxPermittedCandidateCoverage, reason",
            })
            continue
        return ap, rejections
    return None, rejections


# --------------------------------------------------------------------------
# Evaluation
# --------------------------------------------------------------------------

def evaluate(candidate_anchor, *, story_id=None, repo_root=REPO_ROOT,
             worktrees=None, reservations_path=None, approvals_path=None,
             bible_path=None,
             authorized_approvers=DEFAULT_AUTHORIZED_HUMAN_APPROVERS):
    bible = load_bible(bible_path)
    normalized = normalize_reference(candidate_anchor, bible)
    cand = verse_set(normalized, bible)

    wts = worktrees if worktrees is not None else discover_worktrees(repo_root)
    universe, conflicts, scanned, integrity_failures = harvest(wts)

    reservations = load_reservations(reservations_path)
    occupying = [r for r in reservations if r["state"] in OCCUPYING_STATES]
    for r in occupying:
        if r["storyId"] not in universe:
            universe[r["storyId"]] = {
                "storyId": r["storyId"], "anchor": r["anchor"],
                "origin": "queue", "state": r["state"], "path": r["path"],
            }

    matches, warnings, cumulative_shared = [], [], set()
    shared_by_story: dict[int, set] = {}

    for sid, rec in sorted(universe.items()):
        if story_id is not None and sid == story_id:
            continue  # a story never overlaps itself
        try:
            exist = verse_set(rec["anchor"], bible)
        except GateError:
            # HARD integrity failure: an unparseable existing anchor could hide
            # exactly the coverage the candidate collides with. The gate cannot
            # know, so it must not guess. (Was advisory; policy rejected.)
            integrity_failures.append(_integrity(
                "existing scriptureAnchor cannot be parsed",
                worktree=None, file=rec.get("path"),
                story_id=sid, raw_anchor=rec["anchor"]))
            continue

        shared = cand & exist
        if not shared:
            continue
        cumulative_shared |= shared
        shared_by_story[sid] = shared

        n = len(shared)
        cand_cov, exist_cov = n / len(cand), n / len(exist)
        max_side = max(cand_cov, exist_cov)
        cls = classify(cand, exist)

        if cls in ("EXACT", "CANDIDATE_CONTAINED", "EXISTING_CONTAINED"):
            verdict, reason = "BLOCK", cls
        elif n >= 3 and max_side >= 0.50:
            verdict, reason = "BLOCK", "sharedVerses>=3 and maxSideCoverage>=0.50"
        elif cls == "SEAM":
            verdict, reason = "PASS", "boundary-adjacent seam of <=2 verses"
        elif n >= 5:
            verdict, reason = "WARN", "single existing story shares >=5 verses"
        elif n >= 3 and max_side >= 0.20:
            verdict, reason = "WARN", "sharedVerses>=3 and maxSideCoverage>=0.20"
        else:
            verdict, reason = "PASS", "incidental overlap below all thresholds"

        matches.append({
            "existingStoryId": sid,
            "existingAnchor": rec["anchor"],
            "existingVerseCount": len(exist),
            "origin": rec["origin"],
            "state": rec["state"],
            "sharedVerses": n,
            "sharedVerseList": [f"{b} {c}:{v}" for b, c, v in _ordered(shared)],
            "candidateCoverage": round(cand_cov, 4),
            "existingCoverage": round(exist_cov, 4),
            "maxSideCoverage": round(max_side, 4),
            "jaccard": round(n / len(cand | exist), 4),
            "classification": cls,
            "boundaryAdjacent": is_boundary_adjacent(shared, cand, exist),
            "verdict": verdict,
            "reason": reason,
        })

    def _cumulative(union: set, excluded: list | None = None) -> dict:
        cov = len(union) / len(cand)
        note = ""
        if excluded:
            note = (f" (excludes owner-approved coverage from stories "
                    f"{sorted(excluded)})")
        return {
            "unionSharedVerses": len(union),
            "candidateCoverageByUnion": round(cov, 4),
            "verdict": "WARN" if cov >= 0.60 else "PASS",
            "reason": ("cumulative union coverage >=0.60 across multiple existing "
                       "stories" if cov >= 0.60
                       else "below cumulative threshold") + note,
        }

    cumulative = _cumulative(cumulative_shared)

    # Coverage integrity gates everything: if the occupied universe is not
    # fully established, no PASS/WARN/BLOCK verdict is trustworthy.
    if integrity_failures:
        raise CoverageIntegrityError(integrity_failures)

    approvals = load_approvals(approvals_path)
    approval, rejections = select_approval(approvals, normalized, bible,
                                           authorized_approvers)
    for r in rejections:
        warnings.append({"code": "APPROVAL_REJECTED", **r})

    blocking = [m["existingStoryId"] for m in matches if m["verdict"] == "BLOCK"]
    exception = {"required": bool(blocking), "applied": False,
                 "approvalId": None, "reason": None}

    if blocking and approval is not None:
        ack = set(approval["acknowledgedStoryIds"])
        max_shared = max((m["sharedVerses"] for m in matches if m["verdict"] == "BLOCK"), default=0)
        max_cand_cov = max((m["candidateCoverage"] for m in matches if m["verdict"] == "BLOCK"), default=0.0)
        unack = [s for s in blocking if s not in ack]
        if unack:
            exception["reason"] = f"approval does not acknowledge blocking stories {unack}"
        elif max_shared > approval["maxPermittedSharedVerses"]:
            exception["reason"] = (f"actual shared verses {max_shared} exceeds approved "
                                   f"{approval['maxPermittedSharedVerses']}")
        elif max_cand_cov > approval["maxPermittedCandidateCoverage"]:
            exception["reason"] = (f"actual candidate coverage {max_cand_cov} exceeds approved "
                                   f"{approval['maxPermittedCandidateCoverage']}")
        else:
            exception.update({"applied": True,
                              "approvalId": approval.get("approvalId") or approval.get("candidateAnchor"),
                              "reason": approval.get("reason")})
            for m in matches:
                if m["verdict"] == "BLOCK":
                    m["verdict"] = "PASS"
                    m["reason"] = "owner-approved intentional overlap within bounds"
            blocking = []
            # The cumulative clause exists to catch UNAPPROVED composite
            # duplication. Coverage the owner explicitly acknowledged must not
            # be re-counted against the same candidate.
            residual = set()
            for s_id, sh in shared_by_story.items():
                if s_id not in ack:
                    residual |= sh
            cumulative = _cumulative(residual, excluded=sorted(ack))

    if conflicts:
        for c in conflicts:
            warnings.append({"code": "WORKTREE_ANCHOR_CONFLICT", **c})
        verdict = "BLOCK"
    elif blocking:
        verdict = "BLOCK"
    elif any(m["verdict"] == "WARN" for m in matches) or cumulative["verdict"] == "WARN":
        verdict = "WARN"
    else:
        verdict = "PASS"

    report = {
        "gateVersion": GATE_VERSION,
        "evaluatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "versification": VERSIFICATION,
        "candidate": {
            "proposedStoryId": story_id,
            "rawReference": candidate_anchor,
            "normalizedReference": normalized,
            "verseCount": len(cand),
            "parseStatus": "OK",
        },
        "universe": {
            "worktreesScanned": len(scanned),
            "worktreePaths": scanned,
            "distinctStories": len(universe),
            "queuedReservations": len(reservations),
            "occupyingReservations": len(occupying),
            "sourcesRefused": [
                "assets/stories/anchor_coverage.json (generated snapshot, not authoritative)",
                "meta.scriptureAnchorId (absent/inconsistent across corpus)",
                "assets/stories/scripture_anchor_registry.json (advisory only)",
            ],
        },
        "matches": sorted(matches, key=lambda m: (-m["sharedVerses"], m["existingStoryId"])),
        "cumulative": cumulative,
        "exception": exception,
        "verdict": verdict,
        "blockingStoryIds": sorted(blocking),
        "warnings": warnings,
    }
    return report


def main(argv=None):
    ap = argparse.ArgumentParser(description="Scripture-overlap preflight gate")
    ap.add_argument("--anchor", required=True, help='e.g. "Acts 12:6-19"')
    ap.add_argument("--story-id", type=int, default=None,
                    help="proposed story id; excluded from self-comparison")
    ap.add_argument("--worktree", action="append", default=None,
                    help="explicit worktree root (repeatable); default: git worktree list")
    ap.add_argument("--reservations", default=None, help="reservation queue JSON")
    ap.add_argument("--approvals", default=None,
                    help="owner-controlled overlap approvals JSON (absent = none)")
    ap.add_argument("--bible", default=None, help="override WEB Bible JSON path")
    ap.add_argument("--repo-root", default=REPO_ROOT)
    ap.add_argument("--approver", action="append", default=None,
                    help="additional authorized HUMAN approver identity "
                         "(repeatable); default allowlist is {'owner'}. Also "
                         "honours BIBLEPAL_OVERLAP_APPROVERS (comma-separated).")
    args = ap.parse_args(argv)

    approvers = set(DEFAULT_AUTHORIZED_HUMAN_APPROVERS)
    env_extra = os.environ.get("BIBLEPAL_OVERLAP_APPROVERS", "")
    approvers.update(x.strip() for x in env_extra.split(",") if x.strip())
    if args.approver:
        approvers.update(args.approver)

    try:
        report = evaluate(
            args.anchor, story_id=args.story_id, repo_root=args.repo_root,
            worktrees=args.worktree, reservations_path=args.reservations,
            approvals_path=args.approvals, bible_path=args.bible,
            authorized_approvers=frozenset(approvers),
        )
    except CoverageIntegrityError as exc:
        json.dump({
            "gateVersion": GATE_VERSION,
            "evaluatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "candidate": {"rawReference": args.anchor, "parseStatus": "OK"},
            "verdict": "ERROR",
            "errorCode": "COVERAGE_INTEGRITY_FAILURE",
            "integrityFailures": exc.failures,
            "error": str(exc),
            "note": "fail-closed: the occupied scripture universe could not be "
                    "fully established; PASS/WARN/BLOCK would be untrustworthy",
        }, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return EXIT_ERROR
    except GateError as exc:
        json.dump({
            "gateVersion": GATE_VERSION,
            "evaluatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "candidate": {"rawReference": args.anchor, "parseStatus": "FAILED"},
            "verdict": "ERROR", "error": str(exc),
            "note": "fail-closed: PASS is never returned on an error path",
        }, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return EXIT_ERROR
    except Exception as exc:  # noqa: BLE001 — any surprise must still fail closed
        json.dump({
            "gateVersion": GATE_VERSION, "verdict": "ERROR",
            "error": f"{type(exc).__name__}: {exc}",
            "note": "fail-closed: PASS is never returned on an error path",
        }, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return EXIT_ERROR

    json.dump(report, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return {"PASS": EXIT_PASS, "WARN": EXIT_WARN, "BLOCK": EXIT_BLOCK}[report["verdict"]]


if __name__ == "__main__":
    sys.exit(main())
