"""
story_voice_registry.py — Dedicated story narrator voice registry for Bible PAL.

ARCHITECTURE RULE (PERMANENT):
- PAL voices and story narrator voices are TWO SEPARATE SYSTEMS.
- PAL voices: used for PAL prompts, mood responses, UI interactions.
- Story narrator voices: used for story audio + reflection audio ONLY.
- These systems must NEVER overlap.

This module enforces the approved narrator pool and banned voice list.
No silent fallbacks. No defaults. Every story must explicitly declare a voice.
"""

from __future__ import annotations


# ── PERMANENTLY BANNED VOICES (NON-NEGOTIABLE) ───────────────────────────
# These must NEVER be used in story narration or reflection audio.
# Violation = immediate failure. No fallback. No silent correction.

BANNED_VOICES = frozenset({
    "VOICE_GRACE",
    "VOICE_ABILENE",
    "VOICE_GRANT",
    # PAL conversation voices — separate system, never for narration
    "VOICE_SHEPHERD",
    "VOICE_HOPE",
    "VOICE_STILLWATER",
    # Explicitly banned from all story narration by owner directive
    "VOICE_SARAH_DEFAULT_VOICES",
    "VOICE_LYDIA_GRACIOUS",
    # Banned per owner directive (PR γ alignment with
    # feedback_voice_rules.md). Legacy manifest entries using these have
    # been remapped to allowed voices in the same PR.
    "VOICE_JOHN_DOE",
    "VOICE_CHRIS_DEFAULT",
})

# ── APPROVED STORY NARRATOR POOL ─────────────────────────────────────────
# ONLY these voices may be used for story and reflection audio.
# No other voices are permitted. No exceptions.

APPROVED_NARRATOR_VOICES = frozenset({
    "VOICE_ARABELLA",
    "VOICE_LILY_WOLFF",
    "VOICE_CHARLOTTE_V3",
    "VOICE_NATASHA_AFRICAN_AMERICAN",
    "VOICE_JAMES_BRITISH_PROFESSIONAL",
    "VOICE_REVEREND_MICHAEL_C_VINCENT",
    "VOICE_ARCHER",
    "VOICE_BRADFORD",
    "VOICE_JAMES_HUSKY",
    # V3 PILOT pool — used by 1280+ batches; IDs sourced from server/voices.json
    "VOICE_NOAH_PATIENT",
    "VOICE_MIRIAM_JOYFUL",
    "VOICE_BARNABAS_ENCOURAGER",
    "VOICE_ELIJAH_SAGE",
    "VOICE_DAVID_SHEPHERD",
    "VOICE_PETER_BOLD",
})


class VoiceValidationError(Exception):
    """Raised when a voice key fails validation."""
    pass


def validate_story_voice(voice_key: str) -> None:
    """Validate a story narrator voice key.

    Raises VoiceValidationError if:
    - voice_key is None or empty
    - voice_key is in the banned list
    - voice_key is not in the approved pool

    No silent fallback. No defaults. Fail loud.
    """
    if not voice_key or not voice_key.strip():
        raise VoiceValidationError(
            "MISSING VOICE: Every story must explicitly define a narrator voice. "
            "No defaults. No fallbacks."
        )

    voice_key = voice_key.strip()

    if voice_key in BANNED_VOICES:
        raise VoiceValidationError(
            f"BANNED VOICE: '{voice_key}' is permanently banned from story narration. "
            f"Banned voices: {', '.join(sorted(BANNED_VOICES))}. "
            f"This is non-negotiable."
        )

    if voice_key not in APPROVED_NARRATOR_VOICES:
        raise VoiceValidationError(
            f"UNKNOWN VOICE: '{voice_key}' is not in the approved narrator pool. "
            f"Approved voices: {', '.join(sorted(APPROVED_NARRATOR_VOICES))}."
        )


def validate_reflection_voice(voice_key: str) -> None:
    """Validate a reflection narrator voice key. Same rules as story voice."""
    validate_story_voice(voice_key)


def is_banned(voice_key: str) -> bool:
    """Check if a voice key is banned."""
    return voice_key in BANNED_VOICES


def is_approved(voice_key: str) -> bool:
    """Check if a voice key is in the approved narrator pool."""
    return voice_key in APPROVED_NARRATOR_VOICES


def get_approved_voices() -> list[str]:
    """Return sorted list of approved narrator voices."""
    return sorted(APPROVED_NARRATOR_VOICES)


def get_banned_voices() -> list[str]:
    """Return sorted list of banned voices."""
    return sorted(BANNED_VOICES)
