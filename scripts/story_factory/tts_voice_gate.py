#!/usr/bin/env python3
"""
tts_voice_gate.py — fail-closed narrator resolution for NEW-story TTS.

THE PROBLEM THIS CLOSES
  New-authoring doctrine makes `storyVoiceKey` the canonical narrator field,
  but the legacy shell renderer resolves `.voiceKey // .storyVoiceKey`, so a
  stray legacy `voiceKey` (schema-unconstrained, possibly banned) can silently
  override the approved narrator. Historical stories where the fields differ
  are deliberately NOT migrated or reinterpreted here — this gate governs new
  autonomous stories only, on the one designated safe TTS route.

THE RULE
  For a new story, `storyVoiceKey` is the SOLE narrator authority. Before any
  ElevenLabs request the gate must prove, offline and deterministically:

    1.  storyVoiceKey exists and is a non-empty string;
    2.  validate_story_voice() passes (not banned, canonically known);
    3.  the key is in the meta.schema.json storyVoiceKey enum;
    4.  the key is NOT a legacy-audio-only narrator (voices.json
        _legacyAudioOnlyVoices — historical playback only, never new TTS);
    5.  exactly ONE active mapping exists in server/voices.json .voices[]
        (palVoices is a separate conversation pool and is never consulted);
    6.  the resolved ElevenLabs ID is non-empty and unambiguous (no other
        active narrator maps to the same ID);
    7.  an _LOAD_FROM_ENV_ placeholder resolves from the environment to a
        plausibly-shaped ID — checked without ever printing the value;
    8.  metadata carries no CONFLICTING legacy field: `voiceKey` absent is
        ideal, equal-to-storyVoiceKey is tolerated for compatibility (flagged),
        different is a hard failure; `voiceKeys{}` and `reflectionVoiceKey`
        are always hard failures on new stories;
    9.  a kid-friendly story's narrator must carry the "kid" audience tag;
   10.  the controller's expected narrator (if supplied) equals
        metadata.storyVoiceKey — Claude cannot silently swap the assignment.

  Any failure raises TtsVoiceGateError. NO TTS REQUEST may follow a failure.
  This module performs no network I/O and never prints secret material.

Approval doctrine itself lives in story_voice_registry.validate_story_voice();
this gate consumes it rather than re-implementing it.

CLI (consumed by scripts/generate_opus_audio.sh --new-authoring):
    python3 scripts/story_factory/tts_voice_gate.py --meta <meta.json> \
        [--expected VOICE_KEY]
  On success: prints {"storyVoiceKey": ..., "elevenLabsId": ...} and exits 0.
  On failure: prints a one-line reason to stderr and exits 1. The caller must
  treat a non-zero exit as NO-TTS for that story.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass

_HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(_HERE))
sys.path.insert(0, os.path.dirname(_HERE))

from story_factory.story_voice_registry import (  # noqa: E402
    VoiceValidationError, validate_story_voice,
)

DEFAULT_VOICES_PATH = os.path.join(REPO_ROOT, "server", "voices.json")
DEFAULT_SCHEMA_PATH = os.path.join(REPO_ROOT, "assets", "stories", "meta.schema.json")

# ElevenLabs voice IDs are 20-char base62 tokens. Used to sanity-check env
# material WITHOUT ever echoing it.
_ELEVENLABS_ID_SHAPE = re.compile(r"^[A-Za-z0-9]{20}$")
_ENV_PLACEHOLDER_PREFIX = "_LOAD_FROM_ENV_"


class TtsVoiceGateError(Exception):
    """Narrator resolution failed — the caller MUST NOT issue a TTS request."""


@dataclass(frozen=True)
class ResolvedTtsVoice:
    """Proof object: the only narrator a new-story TTS call may use."""
    story_voice_key: str
    eleven_labs_id: str
    mapping_source: str          # "voices.json" | "voices.json+env:<VAR>"
    legacy_field_equal: bool     # meta carried voiceKey == storyVoiceKey


def _load_json(path: str, what: str) -> dict:
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        raise TtsVoiceGateError(f"cannot read {what} at {path}: {exc}") from exc


def _schema_enum(schema_path: str) -> frozenset[str]:
    schema = _load_json(schema_path, "meta schema")
    enum = (schema.get("properties", {}).get("storyVoiceKey", {}) or {}).get("enum")
    if not isinstance(enum, list) or not enum:
        raise TtsVoiceGateError(
            f"meta schema at {schema_path} has no storyVoiceKey enum")
    return frozenset(enum)


def resolve_new_story_tts_voice(
    metadata: dict,
    *,
    expected_story_voice_key: str | None = None,
    voices_path: str = DEFAULT_VOICES_PATH,
    schema_path: str = DEFAULT_SCHEMA_PATH,
    env: dict | None = None,
) -> ResolvedTtsVoice:
    """Authorize and resolve the narrator for ONE new story, or raise.

    Deterministic, offline, secret-safe. `env` defaults to os.environ and is
    injectable for tests.
    """
    if not isinstance(metadata, dict):
        raise TtsVoiceGateError("metadata is not an object")
    env = os.environ if env is None else env

    # -- 1/2: canonical field exists and passes approval doctrine ------------
    svk = metadata.get("storyVoiceKey")
    if svk is None:
        raise TtsVoiceGateError("storyVoiceKey is missing from metadata")
    if not isinstance(svk, str) or not svk.strip():
        raise TtsVoiceGateError("storyVoiceKey is empty or not a string")
    svk = svk.strip()
    try:
        validate_story_voice(svk)
    except VoiceValidationError as exc:
        raise TtsVoiceGateError(f"storyVoiceKey rejected by registry: {exc}") from exc

    # -- 10: controller assignment must agree BEFORE anything else resolves --
    if expected_story_voice_key is not None and expected_story_voice_key != svk:
        raise TtsVoiceGateError(
            f"expected narrator {expected_story_voice_key!r} does not match "
            f"metadata storyVoiceKey {svk!r}; the assigned narrator may not "
            "be changed by the authoring side")

    # -- 8: conflicting legacy fields ----------------------------------------
    legacy = metadata.get("voiceKey")
    legacy_equal = False
    if legacy is not None:
        if not isinstance(legacy, str) or legacy.strip() != svk:
            raise TtsVoiceGateError(
                f"legacy voiceKey {legacy!r} conflicts with storyVoiceKey "
                f"{svk!r}; a legacy field may never select the narrator for a "
                "new story")
        legacy_equal = True  # tolerated for compatibility, but flagged
    if metadata.get("voiceKeys"):
        raise TtsVoiceGateError(
            "legacy voiceKeys{} per-length map present; forbidden on new stories")
    if "reflectionVoiceKey" in metadata:
        raise TtsVoiceGateError(
            "reflectionVoiceKey present; reflections share the story narrator "
            "and this field is forbidden")

    # -- 3: schema enum membership -------------------------------------------
    enum = _schema_enum(schema_path)
    if svk not in enum:
        raise TtsVoiceGateError(
            f"storyVoiceKey {svk!r} is not in the meta.schema.json enum")

    # -- 4/5/6: voices.json mapping ------------------------------------------
    voices_doc = _load_json(voices_path, "voices.json")
    legacy_only = set(
        (voices_doc.get("_legacyAudioOnlyVoices") or {}).get("voices") or [])
    if svk in legacy_only:
        raise TtsVoiceGateError(
            f"{svk} is a legacy-audio-only narrator; historical playback only, "
            "never eligible for new TTS")

    pool = voices_doc.get("voices")
    if not isinstance(pool, list) or not pool:
        raise TtsVoiceGateError("voices.json has no active narrator pool")
    hits = [v for v in pool if v.get("voiceKey") == svk]
    if len(hits) == 0:
        raise TtsVoiceGateError(f"no active voices.json mapping for {svk}")
    if len(hits) > 1:
        raise TtsVoiceGateError(
            f"{len(hits)} active voices.json mappings for {svk}; ambiguous")
    entry = hits[0]

    raw_id = entry.get("elevenLabsId")
    if not isinstance(raw_id, str) or not raw_id.strip():
        raise TtsVoiceGateError(f"mapping for {svk} has an empty ElevenLabs ID")
    raw_id = raw_id.strip()

    # -- 7: env placeholder, secret-safe -------------------------------------
    if raw_id.startswith(_ENV_PLACEHOLDER_PREFIX):
        var = raw_id[len(_ENV_PLACEHOLDER_PREFIX):]
        material = (env.get(var) or "").strip()
        if not material:
            raise TtsVoiceGateError(
                f"mapping for {svk} requires environment variable {var}, which "
                "is missing or empty")
        if not _ELEVENLABS_ID_SHAPE.match(material):
            raise TtsVoiceGateError(
                f"environment variable {var} for {svk} does not look like an "
                "ElevenLabs voice ID")  # value deliberately not shown
        resolved_id, source = material, f"voices.json+env:{var}"
    else:
        resolved_id, source = raw_id, "voices.json"

    # -- 6b: the resolved ID must be unambiguous across the active pool ------
    same_id = [
        v.get("voiceKey") for v in pool
        if v.get("voiceKey") != svk and (v.get("elevenLabsId") or "").strip() == raw_id
    ]
    if same_id:
        raise TtsVoiceGateError(
            f"ElevenLabs ID for {svk} is also mapped to {same_id}; ambiguous")

    # -- 9: audience compatibility -------------------------------------------
    if metadata.get("kidFriendly") is True:
        audience = entry.get("audience") or []
        if "kid" not in audience:
            raise TtsVoiceGateError(
                f"{svk} is not kid-audience eligible but the story is "
                "kidFriendly")

    return ResolvedTtsVoice(
        story_voice_key=svk,
        eleven_labs_id=resolved_id,
        mapping_source=source,
        legacy_field_equal=legacy_equal,
    )


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        description="Fail-closed narrator resolution for new-story TTS")
    ap.add_argument("--meta", required=True, help="path to meta_<id>.json")
    ap.add_argument("--expected", default=None,
                    help="narrator assigned by the production controller; "
                         "must equal metadata storyVoiceKey")
    ap.add_argument("--voices", default=DEFAULT_VOICES_PATH)
    ap.add_argument("--schema", default=DEFAULT_SCHEMA_PATH)
    args = ap.parse_args(argv)

    try:
        meta = _load_json(args.meta, "story metadata")
        result = resolve_new_story_tts_voice(
            meta,
            expected_story_voice_key=args.expected,
            voices_path=args.voices,
            schema_path=args.schema,
        )
    except TtsVoiceGateError as exc:
        print(f"TTS-VOICE-GATE REFUSED: {exc}", file=sys.stderr)
        return 1
    json.dump({
        "storyVoiceKey": result.story_voice_key,
        "elevenLabsId": result.eleven_labs_id,
        "mappingSource": result.mapping_source,
        "legacyFieldEqual": result.legacy_field_equal,
    }, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
