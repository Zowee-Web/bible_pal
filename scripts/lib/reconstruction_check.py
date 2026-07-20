"""ADR-031 reconstruction diagnostics.

Detects whether a Traditional story file is a *reproduction* of its scripture
anchor rather than a retelling of it.

Three strictly separated tiers (ADR-031):

  1. RECONSTRUCTION  — deterministic fact. The complete normalized story token
                       sequence appears contiguously inside the normalized
                       approved-source token sequence. ADR-031 Level 1: a severe
                       editorial warning.
  2. Diagnostic      — longest uninterrupted source match, SequenceMatcher block
     metrics           coverage, unmatched story tokens. Prioritization only.
  3. Editorial       — whether the story is an adequate retelling. NEVER emitted
     conclusion        by this module. ADR-031 Level 2, a human judgement.

ERROR CLASSIFICATION
--------------------
Two distinct failure kinds, because a broken validator is not an editorial
finding:

  ContentUnavailable  — ADVISORY. Expected diagnostic-input problems: absent
                        file, invalid UTF-8, symlink entry, unparseable anchor.
                        Rendered as [UNRESOLVED]; exit code unaffected.
  InfrastructureError — BLOCKING. The machinery itself failed: corrupt index,
                        missing Git object, Git command failure, unreadable
                        canonical Bible source. Must not masquerade as a clean
                        advisory pass.

CONTENT AUTHORITY
-----------------
During pre-commit every byte used for validation must be what the prospective
commit would contain, so metadata AND prose are read from the Git index.
Manual full-corpus runs read the working tree.
"""

from __future__ import annotations

import difflib
import json
import posixpath
import re
import subprocess
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath
from typing import Optional

from .bible_ref_parser import parse_bible_refs, extract_verses

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
BIBLE_DIRNAME = posixpath.join("server", "data")

# Output-volume control only. NOT an acceptance boundary, NOT quality doctrine.
VERBOSE_LONG_RUN_DISPLAY_MIN = 50
VERBOSE_MAX_ROWS = 40

TRADITIONAL_PREFIX = "assets/stories/traditional"
NORMAL_FILE_MODE = "100644"
EXECUTABLE_FILE_MODE = "100755"
SYMLINK_MODE = "120000"
GITLINK_MODE = "160000"
TREE_MODE = "040000"
VALID_INDEX_MODES = {NORMAL_FILE_MODE, EXECUTABLE_FILE_MODE, SYMLINK_MODE,
                     GITLINK_MODE, TREE_MODE}
OBJECT_ID_RE = re.compile(r"^[0-9a-f]{40}$|^[0-9a-f]{64}$")

# Kid-lane consistency inputs (validated from the index during hook mode).
KID_MANIFEST_PATH = "assets/stories/kids_manifest.json"
KID_REGISTRY_PATH = "assets/stories/kid_anchor_registry.json"
META_SCHEMA_PATH = "assets/stories/meta.schema.json"

# ---------------------------------------------------------------------------
# TEMPORARY LEGACY COMPATIBILITY — NOT new authoring doctrine.
#
# 24 pre-existing declarations use an UNSUFFIXED length key (`short`/`full`/
# `long`) pointing at a `_kjv` filename. They are enumerated exactly so the
# exception cannot silently extend to new stories: a 25th such declaration is
# rejected. New content must use the `_kjv` key. Remove this list once the
# eight legacy directories are migrated.
# ---------------------------------------------------------------------------
LEGACY_UNSUFFIXED_KJV_ALLOWLIST = frozenset({
    ("1000", "short", "story_1000_traditional_kjv_short.txt"),
    ("1000", "full", "story_1000_traditional_kjv_full.txt"),
    ("1000", "long", "story_1000_traditional_kjv_long.txt"),
    ("1001", "short", "story_1001_traditional_kjv_short.txt"),
    ("1001", "full", "story_1001_traditional_kjv_full.txt"),
    ("1001", "long", "story_1001_traditional_kjv_long.txt"),
    ("1002", "short", "story_1002_traditional_kjv_short.txt"),
    ("1002", "full", "story_1002_traditional_kjv_full.txt"),
    ("1002", "long", "story_1002_traditional_kjv_long.txt"),
    ("1003", "short", "story_1003_traditional_kjv_short.txt"),
    ("1003", "full", "story_1003_traditional_kjv_full.txt"),
    ("1003", "long", "story_1003_traditional_kjv_long.txt"),
    ("1005", "short", "story_1005_traditional_kjv_short.txt"),
    ("1005", "full", "story_1005_traditional_kjv_full.txt"),
    ("1005", "long", "story_1005_traditional_kjv_long.txt"),
    ("1006", "short", "story_1006_traditional_kjv_short.txt"),
    ("1006", "full", "story_1006_traditional_kjv_full.txt"),
    ("1006", "long", "story_1006_traditional_kjv_long.txt"),
    ("1007", "short", "story_1007_traditional_kjv_short.txt"),
    ("1007", "full", "story_1007_traditional_kjv_full.txt"),
    ("1007", "long", "story_1007_traditional_kjv_long.txt"),
    ("1008", "short", "story_1008_traditional_kjv_short.txt"),
    ("1008", "full", "story_1008_traditional_kjv_full.txt"),
    ("1008", "long", "story_1008_traditional_kjv_long.txt"),
})


class ContentUnavailable(Exception):
    """ADVISORY: expected diagnostic-input problem. Renders as [UNRESOLVED]."""


class InfrastructureError(Exception):
    """BLOCKING: the validation machinery failed. Must not be treated as clean."""


class UnresolvedAnchor(ContentUnavailable):
    """The scripture anchor could not be resolved against canonical JSON."""


def require_ordinary_data_mode(source, rel: str, label: str) -> None:
    """Structural inputs must be ordinary regular files (mode 100644).

    MODE POLICY, applied consistently:
      metadata / schema / kid inputs -> BLOCK before any parsing. These drive
        validation itself; a symlink, gitlink or executable blob in their place
        is a structural defect, not content to interpret.
      story prose -> ADVISORY [UNRESOLVED] (handled in reconstruction_check),
        because a malformed story is an editorial input problem, not a broken
        gate.

    A type change (Git status T) is exactly how a regular file becomes a symlink
    or gitlink, which is why the snapshot admits T.
    """
    mode = source.mode(rel) if hasattr(source, "mode") else None
    if mode is None or mode == NORMAL_FILE_MODE:
        return
    if mode == SYMLINK_MODE:
        raise InfrastructureError(
            f"{rel} is a symlink (mode {mode}) in the prospective commit; "
            f"{label} inputs must be ordinary regular files and the symlink "
            f"target is never followed")
    if mode == GITLINK_MODE:
        raise InfrastructureError(
            f"{rel} is a gitlink/submodule entry (mode {mode}) in the "
            f"prospective commit; {label} inputs must be ordinary regular files")
    if mode == EXECUTABLE_FILE_MODE:
        raise InfrastructureError(
            f"{rel} has executable mode {mode} in the prospective commit; "
            f"{label} inputs are data and must be "
            f"{NORMAL_FILE_MODE}")
    raise InfrastructureError(
        f"{rel} has unsupported index mode {mode}; {label} inputs must be "
        f"ordinary regular files")


# ---------------------------------------------------------------- normalization
#
# FROZEN for Phase 1. Unicode/apostrophe policy changes are deliberately
# deferred (see the Phase-2 decision brief); altering this would move the
# corpus finding set.

_APOSTROPHES = {"’": "'", "‘": "'", "ʼ": "'"}
_DASHES = {"‐": "-", "‑": "-", "‒": "-", "–": "-",
           "—": "-", "―": "-", "−": "-"}


def normalize_tokens(text: str) -> list[str]:
    """Normalize prose into a word-token list.

    Lowercase; curly apostrophes -> straight; Unicode dashes -> hyphen; strip
    punctuation while preserving intra-word apostrophes; collapse whitespace.
    Word order preserved. No stemming, no synonym mapping.
    """
    if not text:
        return []
    for src, dst in _APOSTROPHES.items():
        text = text.replace(src, dst)
    for src, dst in _DASHES.items():
        text = text.replace(src, dst)
    text = text.lower()
    text = re.sub(r"[^a-z0-9' ]+", " ", text)
    text = re.sub(r"(?<![a-z0-9])'|'(?![a-z0-9])", " ", text)
    return text.split()


# ------------------------------------------------------------- repo-relative id


def repo_relative(path, repo_root: Path) -> Optional[str]:
    """Lexically normalize `path` to a repo-relative POSIX path, or None.

    Deliberately lexical: no Path.resolve(), so a working-tree symlink cannot
    redirect identity, and two distinct index paths never merge because their
    working-tree copies point at one target.
    """
    p = PurePosixPath(str(path).replace("\\", "/"))
    root = PurePosixPath(str(repo_root).replace("\\", "/"))
    if p.is_absolute():
        try:
            rel = p.relative_to(root)
        except ValueError:
            return None  # absolute path outside the approved repository root
        parts = rel.parts
    else:
        parts = p.parts
    out: list[str] = []
    for part in parts:
        if part in ("", "."):
            continue
        if part == "..":
            return None  # traversal is never normalized away silently
        out.append(part)
    return "/".join(out) if out else None


# ---------------------------------------------------------------- content sources


def _decode_utf8(data: bytes, label: str) -> str:
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError as e:
        raise ContentUnavailable(
            f"content is not valid UTF-8 ({label}): {e}") from e


class WorkingTreeSource:
    """Reads content from the working tree. Used by manual full-corpus runs."""

    name = "working-tree"

    def __init__(self, repo_root: Optional[Path] = None):
        self.repo_root = Path(repo_root or REPO_ROOT)

    def _abs(self, rel: str) -> Path:
        return self.repo_root / rel

    def exists(self, rel: str) -> bool:
        return self._abs(rel).is_file()

    def mode(self, rel: str) -> Optional[str]:
        p = self._abs(rel)
        if p.is_symlink():
            return SYMLINK_MODE
        return "100644" if p.exists() else None

    def read_bytes(self, rel: str) -> bytes:
        p = self._abs(rel)
        if p.is_symlink():
            raise ContentUnavailable(f"symlink entries are not supported: {rel}")
        try:
            return p.read_bytes()
        except FileNotFoundError as e:
            raise ContentUnavailable(f"file not found: {rel}") from e
        except OSError as e:
            raise ContentUnavailable(f"cannot read {rel}: {e}") from e

    def read_text(self, rel: str) -> str:
        return _decode_utf8(self.read_bytes(rel), rel)

    def read_json(self, rel: str):
        try:
            return json.loads(self.read_text(rel))
        except json.JSONDecodeError as e:
            raise ContentUnavailable(f"invalid JSON in {rel}: {e}") from e


class GitIndexSource:
    """Reads content from the Git index — the bytes a commit would record.

    Never mutates the index. Index entries are enumerated once with
    `git ls-files -s -z`, giving both the mode (so symlinks and gitlinks can be
    rejected) and the blob sha (so content is fetched by object id rather than
    by re-resolving a path).

    A failure of Git itself, or a referenced blob that cannot be read, is an
    InfrastructureError (blocking) — never a clean advisory result.
    """

    name = "git-index"

    def __init__(self, repo_root: Optional[Path] = None):
        self.repo_root = Path(repo_root or REPO_ROOT)
        self._entries: Optional[dict[str, tuple[str, str]]] = None

    def _git(self, *args: str) -> subprocess.CompletedProcess:
        try:
            return subprocess.run(["git", *args], cwd=str(self.repo_root),
                                  capture_output=True, check=False)
        except OSError as e:
            raise InfrastructureError(f"git is unavailable: {e}") from e

    def entries(self) -> dict[str, tuple[str, str]]:
        """rel-path -> (mode, sha). Enumerated once; any anomaly BLOCKS.

        Strict parsing: a malformed record is never skipped, because silently
        continuing would make an unparseable index look like a smaller one.
        Validated per record: field count, mode, full 40/64-hex object id,
        stage number, decodable path, and path uniqueness. Stage != 0 means an
        unresolved merge, which blocks.
        """
        if self._entries is not None:
            return self._entries
        proc = self._git("ls-files", "-s", "-z")
        if proc.returncode != 0:
            err = proc.stderr.decode("utf-8", "replace").strip()
            raise InfrastructureError(
                f"cannot read the Git index (git ls-files failed): {err}")
        out: dict[str, tuple[str, str]] = {}
        for record in proc.stdout.split(b"\0"):
            if not record:
                continue
            if b"\t" not in record:
                raise InfrastructureError(
                    f"malformed Git index record (no TAB separator): {record!r}")
            meta_part, path_part = record.split(b"\t", 1)
            try:
                meta_text = meta_part.decode("utf-8")
            except UnicodeDecodeError as e:
                raise InfrastructureError(
                    f"undecodable Git index metadata: {meta_part!r} ({e})") from e
            fields = meta_text.split()
            if len(fields) != 3:
                raise InfrastructureError(
                    f"malformed Git index record (expected 3 metadata fields, "
                    f"got {len(fields)}): {meta_text!r}")
            mode, sha, stage = fields
            if mode not in VALID_INDEX_MODES:
                raise InfrastructureError(
                    f"unsupported Git index mode {mode!r} for {path_part!r}")
            if not OBJECT_ID_RE.match(sha):
                raise InfrastructureError(
                    f"malformed Git object id {sha!r} for {path_part!r}")
            if stage not in ("0", "1", "2", "3"):
                raise InfrastructureError(
                    f"malformed Git index stage {stage!r} for {path_part!r}")
            if stage != "0":
                raise InfrastructureError(
                    f"unresolved merge conflict in the Git index (stage {stage}): "
                    f"{path_part!r} — resolve the merge before committing")
            try:
                path = path_part.decode("utf-8")
            except UnicodeDecodeError as e:
                raise InfrastructureError(
                    f"unsupported path encoding in the Git index: "
                    f"{path_part!r} ({e})") from e
            if path in out:
                # Never last-wins: a duplicate means the index is not what we
                # think it is.
                raise InfrastructureError(
                    f"duplicate Git index entry for {path!r}")
            out[path] = (mode, sha)
        self._entries = out
        return self._entries

    def exists(self, rel: str) -> bool:
        return rel in self.entries()

    def mode(self, rel: str) -> Optional[str]:
        entry = self.entries().get(rel)
        return entry[0] if entry else None

    def read_bytes(self, rel: str) -> bytes:
        entry = self.entries().get(rel)
        if entry is None:
            raise ContentUnavailable(f"not present in the Git index: {rel}")
        mode, sha = entry
        if mode == SYMLINK_MODE:
            raise ContentUnavailable(
                f"symlink index entry (mode 120000) is not supported: {rel}")
        if mode == GITLINK_MODE:
            raise ContentUnavailable(
                f"gitlink index entry (mode 160000) is not supported: {rel}")
        if mode == EXECUTABLE_FILE_MODE:
            # Advisory: content is readable, but an executable story/metadata
            # blob is reported so it cannot pass as ordinary content unnoticed.
            pass
        elif mode != NORMAL_FILE_MODE:
            raise ContentUnavailable(f"unsupported index mode {mode}: {rel}")
        proc = self._git("cat-file", "blob", sha)
        if proc.returncode != 0:
            err = proc.stderr.decode("utf-8", "replace").strip()
            # The index names an object the repository cannot produce: this is
            # repository infrastructure failure, not a content problem.
            raise InfrastructureError(
                f"Git object {sha} for {rel} is missing or unreadable: {err}")
        return proc.stdout

    def read_text(self, rel: str) -> str:
        return _decode_utf8(self.read_bytes(rel), rel)

    def read_json(self, rel: str):
        try:
            return json.loads(self.read_text(rel))
        except json.JSONDecodeError as e:
            raise ContentUnavailable(f"invalid JSON in {rel}: {e}") from e


DEFAULT_SOURCE = WorkingTreeSource()


# ---------------------------------------------------------------- bible loading

_BIBLE_CACHE: dict[str, dict] = {}


def load_bible(lane: str, repo_root: Optional[Path] = None,
               canonical_root: Optional[Path] = None) -> dict:
    """Canonical Bible JSON — trusted repository reference data, not staged
    story content.

    Cache is keyed by (resolved canonical root, lane), so:
      * WEB and KJV never share an entry;
      * two different roots never share an entry;
      * a prior successful load cannot conceal a later missing/corrupt source.

    When `canonical_root` is given explicitly there is NO fallback to the module
    repository root — an explicit root that lacks the data is an infrastructure
    failure, not a silent redirect.
    """
    lane = lane.lower()
    explicit = canonical_root is not None
    root = Path(canonical_root) if explicit else Path(repo_root or REPO_ROOT)
    key = (str(root), lane)
    if key in _BIBLE_CACHE:
        return _BIBLE_CACHE[key]
    path = root / "server" / "data" / f"bible_{lane}.json"
    try:
        with path.open() as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        if explicit:
            raise InfrastructureError(
                f"canonical Bible source unavailable at the explicitly supplied "
                f"root ({path}): {e}") from e
        fallback = REPO_ROOT / "server" / "data" / f"bible_{lane}.json"
        fkey = (str(REPO_ROOT), lane)
        if fkey in _BIBLE_CACHE:
            return _BIBLE_CACHE[fkey]
        try:
            with fallback.open() as f:
                data = json.load(f)
        except (OSError, json.JSONDecodeError) as e2:
            raise InfrastructureError(
                f"canonical Bible source unavailable for lane {lane!r} "
                f"({path}; fallback {fallback}): {e2}") from e2
        _BIBLE_CACHE[fkey] = data
        return data
    _BIBLE_CACHE[key] = data
    return data




def resolve_source_tokens(anchor: str, lane: str,
                          bible: Optional[dict] = None,
                          repo_root: Optional[Path] = None) -> list[str]:
    """Resolve an anchor to normalized source tokens.

    Handles every shape lib.bible_ref_parser supports. An unparseable or
    unresolvable reference is ADVISORY (UnresolvedAnchor); unreadable canonical
    data is BLOCKING (raised by load_bible).
    """
    if not anchor or not anchor.strip():
        raise UnresolvedAnchor("empty anchor")
    data = bible if bible is not None else load_bible(lane, repo_root)
    try:
        refs = parse_bible_refs(anchor)
    except Exception as e:  # noqa: BLE001 - parser raises bare ValueError
        raise UnresolvedAnchor(f"unparseable reference: {e}") from e
    verses: list[tuple[int, int, str]] = []
    for ref in refs:
        try:
            verses.extend(extract_verses(data, ref))
        except Exception as e:  # noqa: BLE001
            raise UnresolvedAnchor(f"cannot resolve {ref}: {e}") from e
    if not verses:
        raise UnresolvedAnchor("reference resolved to zero verses")
    return normalize_tokens(" ".join(t for _, _, t in verses))


# ---------------------------------------------------------------- the test itself


def find_contiguous_span(source: list[str], story: list[str]) -> Optional[int]:
    """Source token offset where `story` appears contiguously, else None.

    Token arrays, not raw strings: a partial word can never satisfy the match.
    """
    n, m = len(source), len(story)
    if m == 0 or m > n:
        return None
    first = story[0]
    for i in range(n - m + 1):
        if source[i] == first and source[i:i + m] == story:
            return i
    return None


@dataclass
class Metrics:
    longest_run: int = 0
    matched_words: int = 0
    unmatched_words: int = 0
    longest_run_source_offset: int = 0
    longest_run_story_offset: int = 0


def compute_metrics(source: list[str], story: list[str]) -> Metrics:
    """Diagnostic metrics only. These never determine pass/fail.

    difflib returns *a* set of matching blocks, not a guaranteed-maximal
    alignment, which is why the report says "SequenceMatcher block coverage"
    rather than "overlap", and "unmatched story tokens" rather than
    "connective narration".
    """
    if not story:
        return Metrics()
    sm = difflib.SequenceMatcher(None, source, story, autojunk=False)
    blocks = [b for b in sm.get_matching_blocks() if b.size > 0]
    matched = sum(b.size for b in blocks)
    longest = max(blocks, key=lambda b: b.size, default=None)
    return Metrics(
        longest_run=longest.size if longest else 0,
        matched_words=matched,
        unmatched_words=len(story) - matched,
        longest_run_source_offset=longest.a if longest else 0,
        longest_run_story_offset=longest.b if longest else 0,
    )


# Finding origins, so counts can reconcile after deduplication.
ORIGIN_METADATA = "metadata-derived"
ORIGIN_EXPLICIT = "explicit-staged-path"


@dataclass
class Finding:
    path: str                      # repo-relative POSIX path, the identity
    story_id: str
    lane: str
    length: str
    anchor: str
    story_words: int = 0
    source_words: int = 0
    reconstructible: bool = False
    source_offset: Optional[int] = None
    story_offset: Optional[int] = None
    metrics: Metrics = field(default_factory=Metrics)
    unresolved: Optional[str] = None
    content_source: str = "working-tree"
    origin: str = ORIGIN_METADATA
    # No approved narrative/non-narrative classification field exists in
    # meta.schema.json or the anchor registry, so this is always "unknown".
    anchor_category: str = "unknown"

    @property
    def block_coverage_ratio(self) -> float:
        if not self.story_words:
            return 0.0
        return self.metrics.matched_words / self.story_words


# ---------------------------------------------------------------- identity rules

CANONICAL_BASENAME_RE = re.compile(
    r"^story_(?P<id>\d+)_traditional_(?P<lane>web|kjv)_"
    r"(?P<length>short|full|long)\.txt$"
)

STORY_REL_PATH_RE = re.compile(
    r"^assets/stories/traditional/(?P<dir_id>\d+)/"
    r"story_(?P<id>\d+)_traditional_(?P<lane>web|kjv)_"
    r"(?P<length>short|full|long)\.txt$"
)

_LANE_SUFFIX = "_kjv"


def validate_story_text_value(meta_rel: str, meta: dict, key: str, value: str
                              ) -> tuple[Optional[str], Optional[str], str, str]:
    """Validate one `files.<key>.storyText` value BEFORE any read.

    Returns (story_rel_path, error, lane, length).

    Rejects absolute paths, any directory component, traversal, non-canonical
    basenames, identity disagreement, key/filename LENGTH disagreement, and
    illegal lane/key combinations.

    Documented legacy lane exception (and only this one): an UNSUFFIXED length
    key (`short`/`full`/`long`) may point at a `_kjv` filename. 24 such legacy
    declarations exist in the corpus and depend on filename lane. A `_kjv` key
    pointing at a `_web` filename is NOT allowed — that is a reverse mismatch.
    """
    if not isinstance(value, str) or not value:
        return None, "storyText is empty or not a string", "", ""
    if value != PurePosixPath(value.replace("\\", "/")).name:
        return None, f"storyText must be a bare filename, got {value!r}", "", ""
    if value.startswith("/") or value.startswith("\\") or ":" in value:
        return None, f"storyText must not be an absolute path: {value!r}", "", ""
    if "/" in value or "\\" in value or ".." in value:
        return None, (f"storyText must not contain a path separator or "
                      f"traversal: {value!r}"), "", ""

    m = CANONICAL_BASENAME_RE.match(value)
    if not m:
        return None, (f"storyText is not a canonical adult Traditional story "
                      f"filename: {value!r}"), "", ""

    file_lane, file_length = m.group("lane"), m.group("length")

    # Key length must equal filename length: `short` may not point at _full.
    if key.endswith(_LANE_SUFFIX):
        key_lane, key_length = "kjv", key[: -len(_LANE_SUFFIX)]
    else:
        key_lane, key_length = "web", key
    if key_length != file_length:
        return None, (f"files key {key!r} declares length {key_length!r} but "
                      f"filename declares {file_length!r}"), "", ""
    if key_lane == "kjv" and file_lane != "kjv":
        return None, (f"files key {key!r} is a KJV key but the filename is "
                      f"{file_lane.upper()}"), "", ""

    meta_dir = PurePosixPath(meta_rel).parent
    dir_id = meta_dir.name
    meta_id = str(meta.get("storyId", ""))
    file_id = m.group("id")
    if not (dir_id == meta_id == file_id):
        return None, (f"story id disagreement: directory={dir_id!r} "
                      f"metadata storyId={meta_id!r} filename={file_id!r}"), "", ""

    # An unsuffixed key pointing at a KJV filename is permitted ONLY for the 24
    # enumerated legacy declarations. Temporary compatibility, not doctrine.
    if key_lane == "web" and file_lane == "kjv":
        if (file_id, key, value) not in LEGACY_UNSUFFIXED_KJV_ALLOWLIST:
            return None, (
                f"unsuffixed files key {key!r} points at a KJV filename "
                f"{value!r}, which is only permitted for the 24 enumerated "
                f"legacy declarations; new content must use the {key}_kjv key"
            ), "", ""

    return str(meta_dir / value), None, file_lane, file_length


def story_files_from_meta_checked(
    meta_rel: str, meta: dict
) -> tuple[list[tuple[str, str, str, str]], list[Finding]]:
    """(accepted, rejected). Every storyText validated before any path is used."""
    out: list[tuple[str, str, str, str]] = []
    rejected: list[Finding] = []
    story_id = str(meta.get("storyId", ""))
    files = meta.get("files")
    if not isinstance(files, dict):
        return out, rejected
    anchor = meta.get("scriptureAnchor") or meta.get("bibleSourceRef") or ""
    meta_dir = str(PurePosixPath(meta_rel).parent)
    for key, entry in files.items():
        if not isinstance(entry, dict):
            continue
        story_text = entry.get("storyText")
        if not story_text:
            continue
        base_key = key[: -len(_LANE_SUFFIX)] if key.endswith(_LANE_SUFFIX) else key
        if base_key not in ("short", "full", "long"):
            continue
        rel, error, lane, length = validate_story_text_value(
            meta_rel, meta, key, story_text)
        if error:
            f = Finding(path=f"{meta_dir}/<rejected:{key}>", story_id=story_id,
                        lane="", length=base_key, anchor=anchor,
                        origin=ORIGIN_METADATA)
            f.unresolved = f"metadata storyText rejected: {error}"
            rejected.append(f)
            continue
        out.append((rel, story_id, lane, length))
    return out, rejected


# ---------------------------------------------------------------- analysis


def analyze_story_rel(rel: str, story_id: str, lane: str, length: str,
                      anchor: str, source, origin: str = ORIGIN_METADATA,
                      repo_root: Optional[Path] = None) -> Finding:
    """Analyze one repo-relative story path against its canonical anchor."""
    f = Finding(path=rel, story_id=story_id, lane=lane, length=length,
                anchor=anchor, origin=origin)
    f.content_source = getattr(source, "name", "unknown")
    try:
        mode = source.mode(rel)
    except Exception:  # noqa: BLE001 - mode probing must never crash analysis
        mode = None
    if mode == EXECUTABLE_FILE_MODE:
        # ADVISORY, and NOT analyzed as ordinary prose: an executable story blob
        # is not ordinary data, so reporting a reconstruction verdict for it
        # would describe content that should not be there in that form. Rendered
        # for declared and undeclared stories alike, via the normal [UNRESOLVED]
        # path, so it can never depend on bucket output to become visible.
        f.unresolved = (
            f"story blob has executable mode {EXECUTABLE_FILE_MODE}; ordinary "
            f"story prose must be {NORMAL_FILE_MODE} — not analyzed as content")
        return f
    try:
        text = source.read_text(rel)
    except ContentUnavailable as e:
        f.unresolved = str(e)
        return f
    story = normalize_tokens(text)
    f.story_words = len(story)
    try:
        src_tokens = resolve_source_tokens(anchor, lane, repo_root=repo_root)
    except UnresolvedAnchor as e:
        f.unresolved = str(e)
        return f
    f.source_words = len(src_tokens)
    offset = find_contiguous_span(src_tokens, story)
    if offset is not None:
        f.reconstructible = True
        f.source_offset = offset
        f.story_offset = 0
    f.metrics = compute_metrics(src_tokens, story)
    return f


def analyze_meta(meta_rel: str, meta: dict, source,
                 repo_root: Optional[Path] = None) -> list[Finding]:
    """Analyze every adult Traditional story declared by one meta."""
    if meta.get("kidFriendly"):
        return []
    if meta.get("mode") not in (None, "traditional"):
        return []
    anchor = meta.get("scriptureAnchor") or meta.get("bibleSourceRef") or ""
    declared, rejected = story_files_from_meta_checked(meta_rel, meta)
    findings: list[Finding] = list(rejected)
    for rel, story_id, lane, length in declared:
        if not source.exists(rel):
            # Declared but absent from the prospective commit: the existing
            # missing-file warning policy covers this; not a reconstruction fact.
            continue
        findings.append(analyze_story_rel(rel, story_id, lane, length, anchor,
                                          source, ORIGIN_METADATA, repo_root))
    return findings


def analyze_explicit_story_path(rel_or_path, source,
                                repo_root: Optional[Path] = None
                                ) -> Optional[Finding]:
    """Analyze one explicitly supplied story path (may be undeclared).

    Identity is anchored to the approved repository root by lexical
    normalization — an absolute path outside it is rejected, and a path that
    merely *contains* `/assets/stories/traditional/` is not accepted.
    """
    root = Path(repo_root or REPO_ROOT)
    rel = repo_relative(rel_or_path, root)
    if rel is None:
        f = Finding(path=str(rel_or_path), story_id="", lane="", length="",
                    anchor="", origin=ORIGIN_EXPLICIT)
        f.unresolved = ("path is not inside the approved repository root, or "
                        "contains traversal")
        return f

    m = STORY_REL_PATH_RE.match(rel)
    if not m:
        f = Finding(path=rel, story_id="", lane="", length="", anchor="",
                    origin=ORIGIN_EXPLICIT)
        f.unresolved = ("path does not match the adult Traditional story shape "
                        "assets/stories/traditional/<id>/"
                        "story_<id>_traditional_<web|kjv>_<short|full|long>.txt")
        return f
    if m.group("dir_id") != m.group("id"):
        f = Finding(path=rel, story_id=m.group("id"), lane=m.group("lane"),
                    length=m.group("length"), anchor="", origin=ORIGIN_EXPLICIT)
        f.unresolved = (f"story id {m.group('id')} does not match its directory "
                        f"{m.group('dir_id')}")
        return f

    story_id, lane, length = m.group("id"), m.group("lane"), m.group("length")
    f = Finding(path=rel, story_id=story_id, lane=lane, length=length,
                anchor="", origin=ORIGIN_EXPLICIT)
    f.content_source = getattr(source, "name", "unknown")

    if not source.exists(rel):
        f.unresolved = "not present in the prospective commit"
        return f

    meta_rel = f"{PurePosixPath(rel).parent}/meta_{story_id}.json"
    if not source.exists(meta_rel):
        f.unresolved = f"sibling metadata not found: meta_{story_id}.json"
        return f
    try:
        meta = source.read_json(meta_rel)
    except ContentUnavailable as e:
        f.unresolved = f"sibling metadata unreadable: {e}"
        return f
    if not isinstance(meta, dict):
        f.unresolved = "sibling metadata is not a JSON object"
        return f
    if meta.get("kidFriendly"):
        return None
    meta_id = str(meta.get("storyId", ""))
    if meta_id and meta_id != story_id:
        f.unresolved = (f"story id disagreement: filename={story_id!r} "
                        f"metadata storyId={meta_id!r}")
        return f
    anchor = meta.get("scriptureAnchor") or meta.get("bibleSourceRef") or ""
    if not anchor:
        f.unresolved = "sibling metadata declares no scripture anchor"
        return f
    return analyze_story_rel(rel, story_id, lane, length, anchor, source,
                             ORIGIN_EXPLICIT, repo_root)


def analyze_explicit_story_paths(paths, source,
                                 repo_root: Optional[Path] = None
                                 ) -> list[Finding]:
    out: list[Finding] = []
    for p in paths:
        finding = analyze_explicit_story_path(p, source, repo_root)
        if finding is not None:
            out.append(finding)
    return out


def dedupe_findings(findings: list[Finding]) -> list[Finding]:
    """Collapse duplicates per repo-relative path.

    Identity is the lexical repo-relative path, so distinct index paths are
    never merged because their working-tree copies symlink to one target.

    Not first-wins: an explicit/index-derived finding is preferred over a
    metadata-derived one for the same path. Conflicting identities collapse to
    an [UNRESOLVED] describing the conflict rather than silently choosing.
    """
    order: list[str] = []
    groups: dict[str, list[Finding]] = {}
    for f in findings:
        key = f.path
        if key not in groups:
            groups[key] = []
            order.append(key)
        groups[key].append(f)

    out: list[Finding] = []
    for key in order:
        group = groups[key]
        if len(group) == 1:
            out.append(group[0])
            continue
        # Records collapse ONLY when their complete semantic identity agrees:
        # story id, lane, length, anchor, AND resolution state. Anything else
        # is a conflict, never a silent preference.
        semantics = {(g.story_id, g.lane, g.length, g.anchor,
                      bool(g.unresolved)) for g in group}
        if len(semantics) > 1:
            details = sorted(
                f"{sid or '?'}/{ln or '?'}/{lg or '?'} anchor={anc!r} "
                f"{'unresolved' if unres else 'resolved'}"
                for sid, ln, lg, anc, unres in semantics)
            conflict = Finding(path=key, story_id="", lane="", length="",
                               anchor=group[0].anchor, origin=group[0].origin)
            conflict.unresolved = (
                "conflicting records for the same path: " + "; ".join(details))
            out.append(conflict)
            continue
        preferred = next((g for g in group if g.origin == ORIGIN_EXPLICIT),
                         group[0])
        out.append(preferred)
    return out


def undeclared_story_files(traditional_dir: Optional[Path] = None) -> list[str]:
    """Story files on disk but absent from any meta.files map (drift inventory).

    Discovered independently of readable metadata: a directory with missing or
    malformed metadata still contributes its on-disk story files.
    """
    root = Path(traditional_dir or (REPO_ROOT / "assets" / "stories" / "traditional"))
    if not root.is_dir():
        return []
    declared: set[str] = set()
    on_disk: set[str] = set()
    # Symlink safety: this inventory walks the WORKING TREE, so a symlinked
    # directory, metadata file, or story file could otherwise pull external
    # content in. Every entry is lstat-checked before descent or read.
    for story_dir in sorted(p for p in root.iterdir()
                            if p.is_dir() and not p.is_symlink()):
        meta_path = story_dir / f"meta_{story_dir.name}.json"
        meta = None
        if meta_path.is_symlink():
            meta = None  # never read a symlinked metadata file
        elif meta_path.is_file():
            try:
                with meta_path.open() as fh:
                    meta = json.load(fh)
            except (OSError, json.JSONDecodeError):
                meta = None  # malformed: directory still contributes below

        # Kid-lane directories are out of scope for the ADULT Traditional drift
        # inventory. This check must precede the disk glob, or 240 kid story
        # files leak into the adult count.
        if isinstance(meta, dict) and meta.get("kidFriendly"):
            continue

        # Disk discovery is independent of metadata readability: a directory
        # with missing or malformed metadata still contributes its files.
        for p in story_dir.glob("story_*_traditional_*.txt"):
            if p.is_symlink():
                continue  # a symlinked story never enters the inventory
            if CANONICAL_BASENAME_RE.match(p.name):
                on_disk.add(f"{story_dir.name}/{p.name}")

        if not isinstance(meta, dict):
            continue
        meta_rel = f"{TRADITIONAL_PREFIX}/{story_dir.name}/{meta_path.name}"
        accepted, _ = story_files_from_meta_checked(meta_rel, meta)
        for rel, _sid, _lane, _len in accepted:
            declared.add("/".join(rel.split("/")[-2:]))
    return sorted(on_disk - declared)


# ---------------------------------------------------------------- reporting


def format_reconstruction(f: Finding, rel: str) -> str:
    """Severe editorial warning. Never prints the matched passage text."""
    return (
        f"[RECONSTRUCTION] {rel}\n"
        f"  storyId {f.story_id} | lane {f.lane.upper()} | length {f.length}\n"
        f"  anchor: {f.anchor} | anchorCategory: {f.anchor_category}\n"
        f"  story {f.story_words}w | source {f.source_words}w\n"
        f"  contiguous match: source[{f.source_offset}:"
        f"{(f.source_offset or 0) + f.story_words}] "
        f"<- story[{f.story_offset}:{f.story_words}]\n"
        f"  reconstructible: YES\n"
        f"  ADR-031 Level 1 — severe editorial warning; human review required."
    )


def format_unresolved(f: Finding, rel: str) -> str:
    return (
        f"[UNRESOLVED] {rel}\n"
        f"  storyId {f.story_id} | lane {f.lane.upper()} | length {f.length}\n"
        f"  anchor: {f.anchor!r} | origin: {f.origin}\n"
        f"  reason: {f.unresolved}\n"
        f"  not evaluated — no pass/fail inferred."
    )


# ---------------------------------------------------------------- change snapshot
#
# ONE authoritative, separately checked enumeration of the staged change set.
# The hook runs `git diff --cached --name-status -z --diff-filter=ACMRDT` once,
# writes it to a temp file outside the repository, and hands the file to Python.
# Nothing re-queries Git per path.

CANONICAL_META_RE = re.compile(
    r"^assets/stories/traditional/(?P<dir_id>\d+)/meta_(?P<id>\d+)\.json$")
STORY_DIR_JSON_RE = re.compile(
    r"^assets/stories/traditional/(?P<dir_id>\d+)/(?P<name>[^/]+\.json)$")
STORY_DIR_ANY_RE = re.compile(
    r"^assets/stories/traditional/(?P<dir_id>\d+)/(?P<name>[^/]+)$")


@dataclass
class Change:
    status: str            # A, C###, M, R###, D, T
    path: str              # destination path (or the deleted path)
    src: Optional[str] = None   # rename/copy source

    @property
    def kind(self) -> str:
        return self.status[0]


def parse_change_snapshot(data: bytes) -> list[Change]:
    """Parse `git diff --cached --name-status -z` output.

    Records are NUL-delimited. A/M/D/T records are STATUS, PATH. R/C records
    carry STATUS, SRC, DST — both are preserved. T (type change) is how a
    regular file becomes a symlink or gitlink, so it must never be filtered out.

    Path boundaries are exact: nothing is split on newlines or whitespace, so
    filenames containing spaces, tabs, newlines or glob characters survive.
    """
    tokens = [t for t in data.split(b"\0") if t != b""]
    out: list[Change] = []
    i = 0
    while i < len(tokens):
        try:
            status = tokens[i].decode("utf-8")
        except UnicodeDecodeError as e:
            raise InfrastructureError(
                f"undecodable status field in the staged-change snapshot: "
                f"{tokens[i]!r} ({e})") from e
        i += 1
        if not status:
            continue
        takes_two = status[0] in ("R", "C")
        need = 2 if takes_two else 1
        if i + need > len(tokens):
            raise InfrastructureError(
                f"truncated staged-change snapshot after status {status!r}")
        try:
            paths = [tokens[i + k].decode("utf-8") for k in range(need)]
        except UnicodeDecodeError as e:
            raise InfrastructureError(
                f"undecodable path in the staged-change snapshot ({e})") from e
        i += need
        if takes_two:
            out.append(Change(status=status, path=paths[1], src=paths[0]))
        else:
            out.append(Change(status=status, path=paths[0]))
    return out


# ------------------------------------------------------- staged path classification


@dataclass
class Classification:
    canonical_metas: list[str] = field(default_factory=list)
    story_paths: list[str] = field(default_factory=list)
    bad_metadata_paths: list[tuple[str, str]] = field(default_factory=list)
    deletions: list[Change] = field(default_factory=list)
    kid_paths: list[str] = field(default_factory=list)
    schema_changed: bool = False
    touched_dirs: list[str] = field(default_factory=list)
    # Rename/copy SOURCES and deleted paths. Audit/history only: these are not
    # current content and are never validated or analyzed as such.
    historical_paths: list[str] = field(default_factory=list)


def classify_changes(changes: list[Change]) -> Classification:
    """Classify the staged change set by ACTUAL path.

    CURRENT CONTENT vs HISTORY. Only paths the prospective commit actually
    contains are treated as content to validate:

      A / M / T -> the path is current content.
      R / C     -> only the DESTINATION is current content; the source is kept
                   in `historical_paths` for audit and is never validated.
      D         -> the path belongs to deletion classification only; it is
                   never validated, analyzed, or reported as a missing file.

    Getting this wrong would validate a file the commit does not contain and
    report it as missing, which is a false finding about a correct commit.

    A non-canonical metadata-like path (meta_bad.json, meta_999.json in
    directory 123, meta_123.extra.json, names with spaces/tabs/newlines/glob
    characters) is recorded as itself. It is NEVER replaced by a derived
    canonical sibling, so it can never cause a different file to be validated.
    """
    c = Classification()
    seen_meta: set[str] = set()
    seen_story: set[str] = set()
    seen_dir: set[str] = set()
    seen_hist: set[str] = set()
    per_dir_meta_like: dict[str, set[str]] = {}

    for ch in changes:
        # Paths that are NOT current content in the prospective commit.
        for h in filter(None, ((ch.src,) if ch.kind in ("R", "C") else ())):
            if h not in seen_hist:
                seen_hist.add(h)
                c.historical_paths.append(h)
        if ch.kind == "D":
            c.deletions.append(ch)
            if ch.path not in seen_hist:
                seen_hist.add(ch.path)
                c.historical_paths.append(ch.path)
            # A deleted path is classified ONLY as a deletion.
            continue

        for p in (ch.path,):
            if p in (KID_MANIFEST_PATH, KID_REGISTRY_PATH):
                if p not in c.kid_paths:
                    c.kid_paths.append(p)
            if p == META_SCHEMA_PATH:
                c.schema_changed = True
            if not p.startswith(TRADITIONAL_PREFIX + "/"):
                continue
            m_any = STORY_DIR_ANY_RE.match(p)
            if m_any and m_any.group("dir_id") not in seen_dir:
                seen_dir.add(m_any.group("dir_id"))
                c.touched_dirs.append(m_any.group("dir_id"))

            m_json = STORY_DIR_JSON_RE.match(p)
            if m_json and m_json.group("name").startswith("meta"):
                per_dir_meta_like.setdefault(
                    m_json.group("dir_id"), set()).add(m_json.group("name"))
                m_canon = CANONICAL_META_RE.match(p)
                if m_canon and m_canon.group("dir_id") == m_canon.group("id"):
                    if p not in seen_meta:
                        seen_meta.add(p)
                        c.canonical_metas.append(p)
                else:
                    reason = ("metadata basename is not canonical for its "
                              f"directory; expected meta_{m_json.group('dir_id')}"
                              ".json")
                    c.bad_metadata_paths.append((p, reason))
            elif p.endswith(".json") and p.startswith(TRADITIONAL_PREFIX + "/"):
                pass  # non-metadata JSON in a story dir: not our concern

            if STORY_REL_PATH_RE.match(p) or "/story_" in p:
                if p.endswith(".txt") and p not in seen_story:
                    seen_story.add(p)
                    c.story_paths.append(p)

    # A rename/copy SOURCE is not current content, but moving a required input
    # away still changes what the commit contains, so the corresponding gate
    # must still run. This adds no path to canonical_metas or story_paths.
    for h in c.historical_paths:
        if h in (KID_MANIFEST_PATH, KID_REGISTRY_PATH) and h not in c.kid_paths:
            c.kid_paths.append(h)
        if h == META_SCHEMA_PATH:
            c.schema_changed = True

    for dir_id, names in per_dir_meta_like.items():
        if len(names) > 1:
            c.bad_metadata_paths.append((
                f"{TRADITIONAL_PREFIX}/{dir_id}",
                f"multiple competing metadata-like files staged in one "
                f"directory: {sorted(names)}"))
    return c


# ------------------------------------------------------- final-index deletion review
#
# ADVISORY for this pass. Deletions are OBSERVED and classified against the
# final index state; no new blocking policy is introduced here. Promotion of any
# class to blocking is deferred to ADR-032.

DELETION_REVIEW_MARKER = "[DELETION-REVIEW]"


@dataclass
class DeletionReview:
    path: str
    category: str
    detail: str


def review_deletions(classification: Classification,
                     source) -> tuple[list[DeletionReview], list[str]]:
    """Describe the FINAL-INDEX consequence of every staged deletion.

    Returns (reviews, structural_errors).

    The deletion itself is always ADVISORY (ADR-032 deferred). But classifying a
    deletion requires reading the final-index metadata, and metadata that is not
    an ordinary regular file must never be parsed to produce that classification.
    Those defects are returned separately as BLOCKING structural errors, so a
    deletion can never suppress an independent problem: the advisory review is
    still emitted, and the structural failure still blocks.
    """
    reviews: list[DeletionReview] = []
    structural: list[str] = []
    if not classification.deletions:
        return reviews, structural
    entries = source.entries() if hasattr(source, "entries") else {}

    def in_final_index(path: str) -> bool:
        return path in entries

    for ch in classification.deletions:
        path = ch.path
        if path == KID_MANIFEST_PATH:
            reviews.append(DeletionReview(
                path, "kid-manifest-deleted",
                "the kid manifest is removed by this commit"))
            continue
        if path == KID_REGISTRY_PATH:
            reviews.append(DeletionReview(
                path, "kid-registry-deleted",
                "the kid anchor registry is removed by this commit"))
            continue
        if not path.startswith(TRADITIONAL_PREFIX + "/"):
            continue

        m_dir = STORY_DIR_ANY_RE.match(path)
        dir_id = m_dir.group("dir_id") if m_dir else None
        if dir_id is None:
            continue
        story_dir = f"{TRADITIONAL_PREFIX}/{dir_id}"
        meta_rel = f"{story_dir}/meta_{dir_id}.json"
        siblings = [p for p in entries
                    if p.startswith(story_dir + "/")
                    and CANONICAL_BASENAME_RE.match(p.split("/")[-1] or "")]

        if CANONICAL_META_RE.match(path):
            if siblings:
                reviews.append(DeletionReview(
                    path, "metadata-deleted-stories-remain",
                    f"canonical metadata is deleted while {len(siblings)} story "
                    f"blob(s) remain in the final index: "
                    f"{sorted(s.split('/')[-1] for s in siblings)}"))
            else:
                reviews.append(DeletionReview(
                    path, "complete-directory-removal",
                    "metadata and all canonical story blobs are removed together"))
            continue

        if CANONICAL_BASENAME_RE.match(path.split("/")[-1] or ""):
            if not in_final_index(meta_rel):
                reviews.append(DeletionReview(
                    path, "story-deleted-with-metadata",
                    "story and its canonical metadata are removed together"))
                continue
            try:
                # SAME policy as every other metadata read: only an ordinary
                # regular file may be parsed as metadata. Checked BEFORE
                # read_json, because GitIndexSource will happily read an
                # executable blob, which would let a deletion classification be
                # derived from metadata that ordinary validation would reject.
                # A symlink/gitlink target is never followed.
                require_ordinary_data_mode(source, meta_rel, "metadata")
            except InfrastructureError as e:
                structural.append(str(e))
                reviews.append(DeletionReview(
                    path, "story-deleted-metadata-not-ordinary-data",
                    f"story deleted; final-index metadata is not an ordinary "
                    f"regular file, so the deletion could not be classified "
                    f"against it: {e}"))
                continue
            try:
                meta = source.read_json(meta_rel)
            except ContentUnavailable as e:
                reviews.append(DeletionReview(
                    path, "story-deleted-metadata-unreadable",
                    f"story deleted; final-index metadata could not be read: {e}"))
                continue
            declared, _ = story_files_from_meta_checked(meta_rel, meta)
            still_declared = any(rel == path for rel, _, _, _ in declared)
            if still_declared:
                reviews.append(DeletionReview(
                    path, "declared-story-deleted",
                    "story deleted while final-index metadata still declares it"))
            else:
                reviews.append(DeletionReview(
                    path, "declaration-removed-consistently",
                    "story deleted and the final-index metadata no longer "
                    "declares it"))
            continue

        reviews.append(DeletionReview(
            path, "other-traditional-deletion",
            "a non-canonical file under a story directory was deleted"))
    return reviews, structural


def format_deletion_review(r: DeletionReview) -> str:
    return (
        f"{DELETION_REVIEW_MARKER} {r.path}\n"
        f"  category: {r.category}\n"
        f"  final-index state: {r.detail}\n"
        f"  ADVISORY under current policy — exit code unaffected.\n"
        f"  Whether any of these classes should block is deferred to ADR-032."
    )


# ---------------------------------------------------------------- relevance gate
#
# The pre-commit hook must decide "is anything I validate present in this
# snapshot?" WITHOUT a second Git enumeration and WITHOUT importing jsonschema.
#
# A shell `tr '\0' '\n' | grep` pipeline cannot do this safely: a literal
# newline inside an irrelevant filename forges what looks like a separate,
# relevant line. Example, one single irrelevant path:
#
#     docs/nope\nassets/stories/meta.schema.json
#
# After `tr` that is two lines and grep matches the second. The snapshot is
# therefore parsed here with true NUL-record semantics, where a newline is just
# an ordinary byte inside one path.

RELEVANT_EXACT_PATHS = (KID_MANIFEST_PATH, KID_REGISTRY_PATH, META_SCHEMA_PATH)


def path_is_relevant(path: str) -> bool:
    """True if this exact path is something the corpus gate validates."""
    return (path.startswith(TRADITIONAL_PREFIX + "/")
            or path in RELEVANT_EXACT_PATHS)


def snapshot_is_relevant(data: bytes) -> bool:
    """Decide relevance from the ONE authoritative snapshot.

    Both sides of a rename/copy are considered: moving a required input away is
    as relevant as moving one in. Statuses are decoded via the same parser used
    for classification, so R/C token counts cannot desynchronize the two.
    """
    for ch in parse_change_snapshot(data):
        for p in filter(None, (ch.path, ch.src)):
            if path_is_relevant(p):
                return True
    return False


def _relevance_main(argv: list[str]) -> int:
    """CLI: exit 0 = relevant, 1 = irrelevant, 2 = snapshot unusable (block).

    Deliberately importable and runnable without jsonschema, so the hook's
    relevance decision never depends on a validation-only dependency.
    """
    import sys as _sys
    if len(argv) != 2 or argv[0] != "--relevance-check":
        print("usage: reconstruction_check.py --relevance-check SNAPSHOT",
              file=_sys.stderr)
        return 2
    try:
        with open(argv[1], "rb") as fh:
            data = fh.read()
    except OSError as e:
        print(f"staged-change snapshot unreadable: {e}", file=_sys.stderr)
        return 2
    try:
        return 0 if snapshot_is_relevant(data) else 1
    except InfrastructureError as e:
        print(f"staged-change snapshot unusable: {e}", file=_sys.stderr)
        return 2


if __name__ == "__main__":
    import sys as _sys
    _sys.exit(_relevance_main(_sys.argv[1:]))
