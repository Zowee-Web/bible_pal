#!/usr/bin/env python3
"""Single source of truth for the Bible PAL reflection length contract.

Adopted after the corpus-wide impact audit (682 numeric Traditional story
concepts across every live worktree):

  * WEB median 56 words, p95 77, and 94.6% of reflections inside 25-80.
  * The previous 120-220 authoring range fit 16/682 stories (2.3%) and would
    have rejected both owner exemplars (1242 at 57/62, 1537 at 28/40) and all
    six REFLECTION_VOICE named benchmarks (57-83).

Option B therefore fixes the standard band at 25-80 with a 35-60 writing
target, and permits a wider 25-120 band ONLY for the two long-established
non-standard forms -- `observation` and `image_cascade` -- and only when the
planner explicitly assigns that form.  A writer can never elevate its own
form: the assignment is immutable planning data and metadata must match it.

Every numeric range in the factory must come from this module.  Prompt text
and controller validation both consume these constants so the two can never
drift apart again, which is precisely how the 120-220 conflict arose.

Existing rendered stories are grandfathered; this contract governs new and
in-flight controller-authorized work only.
"""

from __future__ import annotations


STANDARD_FORM = "standard"

EXCEPTION_FORMS = frozenset({
    "observation",
    "image_cascade",
})

REFLECTION_FORMS = frozenset({STANDARD_FORM}) | EXCEPTION_FORMS

STANDARD_VALID_RANGE = (25, 80)
STANDARD_TARGET_RANGE = (35, 60)

EXCEPTION_VALID_RANGE = (25, 120)
EXCEPTION_TARGET_RANGE = (60, 100)


class ReflectionContractError(ValueError):
    """Raised when a reflection form or word count violates the contract."""


def normalize_reflection_form(form: object) -> str:
    """Return the canonical form name.

    `None` and absent values normalize to `standard`, which is what makes the
    contract backward compatible with every packet and metadata file authored
    before adoption.  Anything else must be an exact, known form: unknown
    strings, booleans and non-strings all fail closed rather than silently
    degrading to `standard`, because a typo must never quietly buy the wider
    ceiling.
    """
    if form is None:
        return STANDARD_FORM
    if not isinstance(form, str):
        raise ReflectionContractError(
            f"reflection form must be a string or absent, not {type(form).__name__}"
        )
    candidate = form.strip()
    if not candidate:
        return STANDARD_FORM
    if candidate not in REFLECTION_FORMS:
        raise ReflectionContractError(f"unknown reflection form {form!r}")
    return candidate


def is_exception_form(form: object) -> bool:
    """True when the (normalized) form is entitled to the extended ceiling."""
    return normalize_reflection_form(form) in EXCEPTION_FORMS


def valid_reflection_range(form: object = None) -> tuple[int, int]:
    """Inclusive (floor, ceiling) word range permitted for `form`."""
    return EXCEPTION_VALID_RANGE if is_exception_form(form) else STANDARD_VALID_RANGE


def target_reflection_range(form: object = None) -> tuple[int, int]:
    """Inclusive (floor, ceiling) writing target for `form`.

    The target is advisory guidance for the writer prompt; `valid_reflection_range`
    is what validation enforces.
    """
    return EXCEPTION_TARGET_RANGE if is_exception_form(form) else STANDARD_TARGET_RANGE


def assert_assignment_matches_metadata(assigned: object, declared: object) -> str:
    """Return the agreed form, or fail closed.

    `assigned` is the controller's immutable planning value; `declared` is what
    the writer put in metadata.  Metadata may omit the field (normalizing to
    `standard`), but it may never disagree with the assignment -- that is the
    self-elevation path this contract exists to close.
    """
    assigned_form = normalize_reflection_form(assigned)
    declared_form = normalize_reflection_form(declared)
    if assigned_form != declared_form:
        raise ReflectionContractError(
            f"metadata reflection form {declared_form!r} does not match the "
            f"assigned form {assigned_form!r}"
        )
    return assigned_form


def validate_reflection_word_count(words: object, form: object = None) -> tuple[int, int]:
    """Validate `words` against the band for `form`; return the applied range.

    Raises ReflectionContractError on a non-integer count, a negative count, or
    a count outside the applicable band.  Booleans are rejected explicitly:
    `True` is an `int` in Python and must not be read as a word count.
    """
    if type(words) is not int:
        raise ReflectionContractError(
            f"reflection word count must be an integer, not {type(words).__name__}"
        )
    if words < 0:
        raise ReflectionContractError("reflection word count cannot be negative")
    floor, ceiling = valid_reflection_range(form)
    if not floor <= words <= ceiling:
        raise ReflectionContractError(
            f"{words} words outside {floor}-{ceiling} for reflection form "
            f"{normalize_reflection_form(form)!r}"
        )
    return floor, ceiling


def describe_contract(form: object = None) -> dict:
    """Machine-readable contract slice for assignments and validation evidence."""
    canonical = normalize_reflection_form(form)
    valid = valid_reflection_range(canonical)
    target = target_reflection_range(canonical)
    return {
        "reflectionForm": canonical,
        "validWordRange": list(valid),
        "targetWordRange": list(target),
        "explicitlyAssignedException": canonical in EXCEPTION_FORMS,
    }


__all__ = [
    "EXCEPTION_FORMS", "EXCEPTION_TARGET_RANGE", "EXCEPTION_VALID_RANGE",
    "REFLECTION_FORMS", "ReflectionContractError", "STANDARD_FORM",
    "STANDARD_TARGET_RANGE", "STANDARD_VALID_RANGE",
    "assert_assignment_matches_metadata", "describe_contract",
    "is_exception_form", "normalize_reflection_form",
    "target_reflection_range", "valid_reflection_range",
    "validate_reflection_word_count",
]
