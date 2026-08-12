#!/usr/bin/env python3
"""Comprehensive catalog validation — the publisher's single source of truth.

Mirrors the EFFECTIVE runtime acceptance contract of the app so that
scripts/upload_r2_catalog.sh classifies local, staged, remote, and post-PUT
catalogs with exactly one validation path:

  - CatalogService._validateDecoded / _validateEntryContract /
    _classifyVersion (lib/services/catalog_service.dart): object root,
    positive non-boolean integer version, non-empty parables list within
    the entry cap, byte-size cap, and the ACTIVE CATALOG CONTRACT —
    non-blank identity fields, unique story ids, active storytelling mode,
    EXACT (never case-normalized) translationId/languageStyle, supported
    storyLength bucket, and safe normalized relative asset paths that
    cannot escape the asset root.
  - Parable.fromJson (lib/models/parable.dart): required fields
    storyId/title/mood/storytellingMode must be strings; every optional
    field must match the exact shape fromJson casts to (String?, int?,
    bool?, List<String>?, Map?, ISO-8601 date string), where a JSON float
    or bool is NEVER acceptable for an int field and unknown extra fields
    are ignored — exactly like the Dart `as` casts.

A catalog that fails ANY of these checks would be rejected (or crash the
parse) at runtime, so the publisher must never treat it as a confirmed
remote state nor stage it for upload.

ACCEPTANCE-PRESERVING DESIGN RULE: if this validator returns success, the
Dart runtime MUST accept the catalog's shape/types. Where Python is more
permissive than Dart, this validator is deliberately NARROWER:
  - integers must fit the signed 64-bit Dart int range (a JSON integer
    outside it decodes as double in Dart and the `as int` cast throws);
  - the non-standard JSON constants NaN/Infinity/-Infinity are rejected
    anywhere in the document (Dart's jsonDecode rejects them; Python's
    json.loads accepts them by default) — see loads_strict();
  - generatedAt accepts only the canonical ISO instant grammar that Dart's
    DateTime.parse accepts and Dart's toIso8601String produces (the
    current corpus contains no generatedAt values at all), NOT Python's
    broader fromisoformat grammar;
  - translation ids are matched with case normalization ONLY (ASCII,
    no whitespace/control trimming) — the publisher may reject values
    Dart's trim() would accept, never the reverse.

If Parable.fromJson or the registry allowlist ever changes, update this
file in the same commit (enforced socially + by the publisher regression
suite in scripts/tests/test_upload_r2_catalog_publisher.py).

Usage:
    python3 scripts/validate_catalog_manifest.py FILE \
        [--max-bytes N] [--max-entries N] [--report]

Default output on success: one line "VERSION ENTRY_COUNT SEMANTIC_SHA256".
--report additionally prints human-readable gate lines first.
Failures print reasons to stderr and exit 1.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime

DEFAULT_MAX_BYTES = 5 * 1024 * 1024
DEFAULT_MAX_ENTRIES = 5000

# Dart ints are signed 64-bit. A JSON integer outside this range decodes as
# a double in the Dart VM, so every int-typed field must fit it — and the
# catalog version additionally has to survive Bash integer comparison in
# upload_r2_catalog.sh.
INT64_MIN = -(2 ** 63)
INT64_MAX = 2 ** 63 - 1

# generatedAt grammar: canonical ISO instant only — full calendar date,
# literal 'T', HH:MM:SS, optional 1-6 digit fraction, optional 'Z' or
# ±HH:MM offset. This is exactly what Dart's toIso8601String() produces
# and a strict subset of what Dart's DateTime.parse accepts. It is
# intentionally NARROWER than Python's datetime.fromisoformat (which also
# accepts ISO week dates, arbitrary date/time separators, and offsets with
# a seconds component — forms Dart rejects).
#
# ASCII-only, full-string parity notes (publisher ⊆ Dart runtime):
#   - explicit [0-9], NEVER \d — Python \d matches Unicode decimal digits
#     (e.g. Arabic-Indic), which Dart's parser rejects, and Python's int()
#     would happily convert them;
#   - matched with fullmatch(), NEVER match()+$ — $ can match before a
#     trailing newline, so "…T12:00:00\n" would slip through.
_GENERATED_AT_RE = re.compile(
    r"([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})"
    r"(?:\.[0-9]{1,6})?(?:Z|[+-][0-9]{2}:[0-9]{2})?"
)


# UTF-8 BOM. Catalog JSON must NOT carry one.
#
# Explicit shared policy, mirrored by CatalogService.utf8Bom /
# startsWithUtf8Bom. It is NOT left to either runtime's default, because
# they disagree: Dart's utf8.decode (and File.readAsString) SILENTLY
# DISCARD a leading BOM, while Python keeps U+FEFF and json.loads then
# fails. Unaddressed, the same bytes would be accepted by the app and
# rejected by the publisher. JSON does not need a BOM (RFC 8259) and the
# publisher owns the bytes it uploads, so both sides reject it.
#
# Only a LEADING BOM is rejected; U+FEFF inside legitimate story text is
# untouched.
UTF8_BOM = b"\xef\xbb\xbf"


def starts_with_utf8_bom(raw: bytes) -> bool:
    """True when `raw` begins with a UTF-8 BOM. Mirrors
    CatalogService.startsWithUtf8Bom."""
    return raw.startswith(UTF8_BOM)


def _reject_constant(token: str):
    raise ValueError(
        f"non-standard JSON constant {token!r} is not valid JSON "
        "(Dart's jsonDecode rejects it)")


def loads_strict(text: str):
    """json.loads that fails closed on NaN/Infinity/-Infinity anywhere in
    the document — including inside ignored/unknown fields."""
    return json.loads(text, parse_constant=_reject_constant)

# ── ACTIVE CATALOG CONTRACT ────────────────────────────────────────────
# One explicit contract, enforced with equivalent semantics on both sides:
# here and in CatalogService (lib/services/catalog_service.dart, the
# `activeStorytellingModes` / `activeLanguageStyles` / `activeStoryLengths`
# constants and `_validateEntryContract`). A candidate catalog becomes
# TRUSTED only after satisfying all of it. Change one side and you MUST
# change the other in the same commit.

# Mirror of lib/core/bible_translation_registry.dart. That registry is the
# SINGLE SOURCE OF TRUTH; if it ever changes, update this set in the same
# commit.
#
# EXACT MATCH ONLY — no case folding, no trimming. Parable.fromJson maps
# any languageStyle that is not literally "KJV" to "WEB", so a lowercase
# "kjv" would be silently re-interpreted as a DIFFERENT translation and a
# KJV story would be served with WEB diction. A non-canonical value is a
# defect, never something to normalize away.
ALLOWED_TRANSLATIONS = {"WEB", "KJV", "ASV", "YLT", "DRA"}

# languageStyle is the presentation diction and the app can only represent
# these two. Anything else is silently coerced by Parable.fromJson.
ACTIVE_LANGUAGE_STYLES = {"WEB", "KJV"}

# Creative was retired 2026-05-13; the active catalog is Traditional only.
# The field survives solely for backward parsing of legacy entries, so a
# published catalog carrying anything else is rejected.
ACTIVE_STORYTELLING_MODES = {"traditional"}

# StoryLengthBucket (lib/core/story_length_bucket.dart).
ACTIVE_STORY_LENGTHS = {"short", "full", "long"}

# Identity + serving anchors that must be present and non-blank.
_REQUIRED_NONBLANK = ("storyId", "title", "mood", "storytellingMode")

# textFilePath is the one path without which a story cannot be served at
# all. The audio/scripture/reflection paths are optional, and may be an
# EMPTY string for lane entries whose media is not rendered yet — but any
# non-empty value must be a safe relative path.
_REQUIRED_PATHS = ("textFilePath",)
_OPTIONAL_PATHS = (
    "audioFilePath", "scriptureTextFilePath", "reflectionAudioPath",
)

# EXPLICIT identity-blank contract, shared verbatim with
# CatalogService.identityBlankCodePoints (lib/services/catalog_service.dart).
#
# Neither str.strip() nor Dart's String.trim() may be used for this: they
# disagree. Dart's trim follows Unicode White_Space PLUS U+FEFF; Python's
# strip follows str.isspace(), which includes the C1 separators
# U+001C-U+001F but NOT U+FEFF. Relying on either default would let a
# catalog whose title is a lone U+FEFF pass the publisher and fail the app
# — or the reverse for U+001C. This set is the explicit UNION of both, so
# the two validators reach the identical verdict on every input.
IDENTITY_BLANK_CODE_POINTS = frozenset({
    0x0009,  # TAB
    0x000A,  # LF
    0x000B,  # VT
    0x000C,  # FF
    0x000D,  # CR
    0x001C,  # FILE SEPARATOR      (Python-only blank)
    0x001D,  # GROUP SEPARATOR     (Python-only blank)
    0x001E,  # RECORD SEPARATOR    (Python-only blank)
    0x001F,  # UNIT SEPARATOR      (Python-only blank)
    0x0020,  # SPACE
    0x0085,  # NEL
    0x00A0,  # NBSP
    0x1680,  # OGHAM SPACE MARK
    0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005,
    0x2006, 0x2007, 0x2008, 0x2009, 0x200A,
    0x200B,  # ZERO WIDTH SPACE
    0x200C,  # ZERO WIDTH NON-JOINER
    0x200D,  # ZERO WIDTH JOINER
    0x2028,  # LINE SEPARATOR
    0x2029,  # PARAGRAPH SEPARATOR
    0x202F,  # NARROW NBSP
    0x205F,  # MEDIUM MATHEMATICAL SPACE
    0x2060,  # WORD JOINER
    0x3000,  # IDEOGRAPHIC SPACE
    0x180E,  # MONGOLIAN VOWEL SEPARATOR
    0xFEFF,  # ZERO WIDTH NO-BREAK SPACE / BOM  (Dart-only blank)
})


def is_blank_identity(value: str) -> bool:
    """True when `value` carries no identity content: empty, or composed
    entirely of IDENTITY_BLANK_CODE_POINTS. Mirrors
    CatalogService.isBlankIdentity."""
    if not value:
        return True
    return all(ord(ch) in IDENTITY_BLANK_CODE_POINTS for ch in value)


# Safe relative asset path: POSIX-relative, ASCII, no leading/trailing or
# doubled separators, no drive letters, no backslashes, no whitespace or
# control characters. Combined with the explicit "." / ".." segment check
# below this makes escaping the asset root impossible.
_SAFE_PATH_RE = re.compile(r"[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)*")


def is_safe_relative_asset_path(value: str) -> bool:
    """True when `value` is a normalized relative path that cannot escape
    the asset root. Mirrors CatalogService._isSafeRelativeAssetPath.

    No strip()/trim() comparison: the character class already excludes
    every whitespace, control and zero-width code point, so leading and
    trailing blanks are rejected by the same rule in both languages with
    no runtime-dependent behaviour."""
    if not value:
        return False
    if not _SAFE_PATH_RE.fullmatch(value):
        return False
    return all(seg not in (".", "..") for seg in value.split("/"))

# Parable.fromJson contract (lib/models/parable.dart). Required fields are
# cast `as String` (throw on missing/None/non-string). Optional fields are
# cast to the nullable type below; a wrong-typed value throws at runtime.
_REQUIRED_STR = ("storyId", "title", "mood", "storytellingMode")
_OPTIONAL_STR = (
    "storyLength", "translationId", "languageStyle", "bibleSourceRef",
    "bibleStoryKey", "audioFilePath",
    "scriptureTextFilePath", "reflectionAudioPath", "narratorVoiceKey",
    "reflectionQuestion", "timeOfDay", "seasonTag", "primaryCharacterId",
    "primaryCharacterDisplayName", "timelineEra",
)
_OPTIONAL_INT = ("length", "bibleOrderIndex", "characterPathOrder")
_OPTIONAL_BOOL = ("kidFriendly", "shortScripture")
_OPTIONAL_STR_LIST = (
    "emotionalTags", "scriptureSources", "characterIds",
    "characterDisplayNames", "themeTags",
)


def _is_int(value) -> bool:
    """True only for a Dart-safe integer: a real int (bool is an int
    subclass in Python, but JSON true/false decodes as bool in Dart and
    `as int?` throws there) within the signed 64-bit range — a JSON
    integer outside it decodes as a double in the Dart VM, so the runtime
    `as int` cast would throw."""
    return (isinstance(value, int) and not isinstance(value, bool)
            and INT64_MIN <= value <= INT64_MAX)


def is_valid_version(value) -> bool:
    """Catalog generation: 1 <= version <= INT64_MAX."""
    return _is_int(value) and value > 0


def validate_parable_entry(entry, index: int) -> list[str]:
    """Errors that would make CatalogService reject the entry or make
    Parable.fromJson throw. Empty list = entry is runtime-acceptable."""
    where = f"parables[{index}]"
    if not isinstance(entry, dict):
        return [f"{where}: entry is not a JSON object"]

    errors = []

    # Translation allowlist first, like CatalogService: only STRING values
    # are screened (a wrong-typed value is caught by the type rules).
    # EXACT canonical match — nothing is upper-cased, nothing is trimmed.
    # A value such as "kjv" is NOT normalized to "KJV"; it is rejected,
    # because Parable.fromJson would silently serve it as WEB.
    val = entry.get("translationId")
    if isinstance(val, str) and val not in ALLOWED_TRANSLATIONS:
        errors.append(
            f"{where}.translationId: banned/unknown/non-canonical "
            f"translation {val!r} (exact match required, one of "
            f"{sorted(ALLOWED_TRANSLATIONS)})")
    val = entry.get("languageStyle")
    if isinstance(val, str) and val not in ACTIVE_LANGUAGE_STYLES:
        errors.append(
            f"{where}.languageStyle: banned/unknown/non-canonical "
            f"translation {val!r} (exact match required, one of "
            f"{sorted(ACTIVE_LANGUAGE_STYLES)}; values are never "
            f"case-normalized)")

    for key in _REQUIRED_STR:
        val = entry.get(key)
        if not isinstance(val, str):
            errors.append(
                f"{where}.{key}: required string missing or wrong type "
                f"(got {type(val).__name__})")

    # Identity and serving anchors must carry real content — a present but
    # blank storyId/title/mood is unusable at runtime.
    for key in _REQUIRED_NONBLANK:
        val = entry.get(key)
        if isinstance(val, str) and is_blank_identity(val):
            errors.append(f"{where}.{key}: must not be blank")

    val = entry.get("storytellingMode")
    if isinstance(val, str) and val not in ACTIVE_STORYTELLING_MODES:
        errors.append(
            f"{where}.storytellingMode: {val!r} is not an active catalog "
            f"mode (allowed: {sorted(ACTIVE_STORYTELLING_MODES)})")

    val = entry.get("storyLength")
    if isinstance(val, str) and val not in ACTIVE_STORY_LENGTHS:
        errors.append(
            f"{where}.storyLength: {val!r} is not a supported bucket "
            f"(allowed: {sorted(ACTIVE_STORY_LENGTHS)})")

    for key in _REQUIRED_PATHS:
        val = entry.get(key)
        if not isinstance(val, str):
            errors.append(
                f"{where}.{key}: required serving anchor missing or wrong "
                f"type (got {type(val).__name__})")
        elif not is_safe_relative_asset_path(val):
            errors.append(
                f"{where}.{key}: must be a non-empty safe relative asset "
                f"path that cannot escape the asset root; got {val!r}")

    for key in _OPTIONAL_PATHS:
        val = entry.get(key)
        # An empty string is a deliberate "not rendered yet" marker for
        # lane entries and stays allowed; any other value must be safe.
        if isinstance(val, str) and val != "" and \
                not is_safe_relative_asset_path(val):
            errors.append(
                f"{where}.{key}: must be a safe relative asset path that "
                f"cannot escape the asset root; got {val!r}")

    for key in _OPTIONAL_STR:
        val = entry.get(key)
        if val is not None and not isinstance(val, str):
            errors.append(
                f"{where}.{key}: must be a string when present "
                f"(got {type(val).__name__})")

    for key in _OPTIONAL_INT:
        val = entry.get(key)
        if val is not None and not _is_int(val):
            errors.append(
                f"{where}.{key}: must be an integer when present "
                f"(got {type(val).__name__})")

    for key in _OPTIONAL_BOOL:
        val = entry.get(key)
        if val is not None and not isinstance(val, bool):
            errors.append(
                f"{where}.{key}: must be a boolean when present "
                f"(got {type(val).__name__})")

    for key in _OPTIONAL_STR_LIST:
        val = entry.get(key)
        if val is None:
            continue
        if not isinstance(val, list):
            errors.append(
                f"{where}.{key}: must be a list when present "
                f"(got {type(val).__name__})")
        elif not all(isinstance(e, str) for e in val):
            errors.append(f"{where}.{key}: every element must be a string")

    val = entry.get("scriptureKeyVerse")
    if val is not None and not isinstance(val, dict):
        errors.append(
            f"{where}.scriptureKeyVerse: must be an object when present "
            f"(got {type(val).__name__})")

    val = entry.get("generatedAt")
    if val is not None:
        if not isinstance(val, str):
            errors.append(
                f"{where}.generatedAt: must be an ISO-8601 string when "
                f"present (got {type(val).__name__})")
        elif not _is_publisher_safe_timestamp(val):
            errors.append(
                f"{where}.generatedAt: not a canonical ISO instant "
                f"(yyyy-mm-ddTHH:MM:SS[.ffffff][Z|±HH:MM]): {val!r}")

    return errors


def _is_publisher_safe_timestamp(value: str) -> bool:
    """Narrow, publisher-safe grammar (see _GENERATED_AT_RE) plus a real
    calendar/clock range check — Dart's DateTime.parse silently wraps
    out-of-range components, so rejecting them here is strictly narrower,
    never weaker."""
    match = _GENERATED_AT_RE.fullmatch(value)
    if not match:
        return False
    year, month, day, hour, minute, second = (int(g) for g in match.groups())
    try:
        datetime(year, month, day)
    except ValueError:
        return False
    return hour <= 23 and minute <= 59 and second <= 59


def validate_catalog(manifest, body_bytes: int,
                     max_bytes: int = DEFAULT_MAX_BYTES,
                     max_entries: int = DEFAULT_MAX_ENTRIES) -> list[str]:
    """Full catalog validation. Empty list = catalog is runtime-acceptable.
    `manifest` is the parsed JSON value; `body_bytes` is the serialized
    size (the same cap CatalogService applies to a remote body)."""
    if not isinstance(manifest, dict):
        return ["root: manifest root must be a JSON object"]

    errors = []

    if body_bytes > max_bytes:
        errors.append(f"size: {body_bytes} bytes > {max_bytes} bytes cap")

    if not is_valid_version(manifest.get("version")):
        v = manifest.get("version")
        errors.append(
            "version: must be a positive integer (not missing, boolean, "
            f"non-integer, or <= 0); got {v!r} ({type(v).__name__})")

    parables = manifest.get("parables")
    if not isinstance(parables, list):
        errors.append('parables: top-level "parables" missing or not a list')
        return errors
    if len(parables) == 0:
        errors.append("parables: list is EMPTY — never a valid catalog")
        return errors
    if len(parables) > max_entries:
        errors.append(f"entry_count: {len(parables)} > {max_entries}")

    # Story identity must be unique: duplicate ids make selection,
    # favorites, history and resume ambiguous, and let one entry shadow
    # another silently.
    seen_ids = set()
    for i, entry in enumerate(parables):
        entry_errors = validate_parable_entry(entry, i)
        errors.extend(entry_errors)
        if isinstance(entry, dict):
            story_id = entry.get("storyId")
            if isinstance(story_id, str):
                if story_id in seen_ids:
                    errors.append(
                        f"parables[{i}].storyId: duplicate story id "
                        f"{story_id!r} — story ids must be unique")
                seen_ids.add(story_id)
        if len(errors) >= 20:
            errors.append("… further errors suppressed")
            break

    return errors


def semantic_sha256(manifest) -> str:
    """Canonical-JSON hash: sorted object keys, compact separators, array
    order preserved — formatting-independent, content-sensitive."""
    canonical = json.dumps(
        manifest, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Validate a catalog manifest against the app's "
                    "effective runtime acceptance contract.")
    parser.add_argument("file", help="Path to the catalog JSON file")
    parser.add_argument("--max-bytes", type=int, default=DEFAULT_MAX_BYTES)
    parser.add_argument("--max-entries", type=int,
                        default=DEFAULT_MAX_ENTRIES)
    parser.add_argument("--report", action="store_true",
                        help="Print human-readable gate lines before the "
                             "summary line")
    args = parser.parse_args(argv)

    try:
        with open(args.file, "rb") as f:
            raw = f.read()
    except OSError as e:
        print(f"FAIL read: {e}", file=sys.stderr)
        return 1

    if starts_with_utf8_bom(raw):
        print("FAIL bom: catalog JSON must not begin with a UTF-8 BOM "
              "(Dart's utf8.decode silently discards it, so a BOM would be "
              "accepted by the app and rejected here — the wire format is "
              "canonical, BOM-free UTF-8)", file=sys.stderr)
        return 1

    try:
        manifest = loads_strict(raw.decode("utf-8"))
    except Exception as e:  # noqa: BLE001 — any parse failure is fatal
        print(f"FAIL json: parse failed -- {e}", file=sys.stderr)
        return 1

    errors = validate_catalog(manifest, len(raw),
                              max_bytes=args.max_bytes,
                              max_entries=args.max_entries)
    if errors:
        print("Catalog validation FAILED:", file=sys.stderr)
        for e in errors:
            print(f"  FAIL {e}", file=sys.stderr)
        return 1

    version = manifest["version"]
    count = len(manifest["parables"])
    sha = semantic_sha256(manifest)

    if args.report:
        print("  OK json: parseable object root")
        print(f"  OK version: positive integer ({version})")
        print(f"  OK parables: non-empty ({count} entries "
              f"<= {args.max_entries})")
        print(f"  OK size: {len(raw)} bytes <= {args.max_bytes} bytes")
        print(f"  OK entries: all {count} entries satisfy the "
              "Parable.fromJson contract")
        print(f"  OK identity: non-blank storyId/title/mood/mode, "
              f"{count} unique story ids")
        print(f"  OK modes: all in {sorted(ACTIVE_STORYTELLING_MODES)}")
        print(f"  OK translations: translationId in "
              f"{sorted(ALLOWED_TRANSLATIONS)}, languageStyle in "
              f"{sorted(ACTIVE_LANGUAGE_STYLES)} (exact match, never "
              "normalized)")
        print("  OK paths: all asset paths are safe, normalized and "
              "relative to the asset root")
    print(version, count, sha)
    return 0


if __name__ == "__main__":
    sys.exit(main())
