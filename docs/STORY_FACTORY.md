# Bible PAL — Story Factory Specification (Locked)

**Status:** LOCKED

This document defines the canonical rules, invariants, and contracts for generating
Traditional Bible PAL stories using the Story Factory pipeline.

Any change to this document requires an explicit spec update and approval
before implementation.

---

## 1. Canonical Story Author

- Canonical author model: **gpt-4.1**
- All story and reflection prose MUST be generated via the OpenAI Responses API
  using gpt-4.1.
- No other model (OpenAI, local, or third-party) may author Traditional Bible PAL prose
  unless this spec is explicitly revised.
- Generation scripts MUST NOT contain hard-coded prose, fallback prose,
  or template expansions.

**Invariant:**
The generator may orchestrate, validate, and persist content —
but must never author content itself.

---

## 2. Story Modes & Anchors

### 2.1 Traditional Mode

- Stories must retell real, identifiable Bible passages.
- Each story is anchored to exactly ONE Scripture anchor
  (e.g., "Psalm 46", "Matthew 11:28–30").
- A Scripture anchor may NEVER be reused.

### 2.2 Anchor Format Rules

Anchor strings must use the form `"Book Chapter"` or `"Book Chapter:Verse–Verse"`
(en-dash, not hyphen). Book names must use their full unabbreviated Protestant English
form (e.g., "Psalm" not "Ps", "Matthew" not "Matt"). No translation suffixes.

Examples:
- `"Psalm 23"`
- `"Matthew 11:28–30"`
- `"Romans 8:28"`

---

## 3. Language Lanes

| Lane    | Code | Description                        |
|---------|------|------------------------------------|
| Modern  | web  | Modern English, WEB-style          |
| Classic | kjv  | Elevated, reverent KJV-like cadence |

Rules:
- Lane values are lowercase in filenames.
- Lane selection affects system prompts only, not structure or validation.

---

## 4. Content Guardrails (Non-Negotiable)

All Traditional stories MUST obey:

- No interpretation
- No symbolism
- No inner monologue
- No invented theology
- No added events beyond the anchor passage
- No advice or moral instruction

Allowed:
- Observable actions
- Spoken words
- Scene pacing and sensory detail
- Poetic elevation without semantic drift

### 4.1 Poetic Style Tiers

Stories use a tiered poetic style system to control prose ornamentation:

| Tier | Label           | Description                                        |
|------|-----------------|----------------------------------------------------|
| 1    | Plain/Clear     | Minimal ornament, plain narrative                  |
| 2    | Vivid+          | Moderate sensory detail, warm imagery, clarity first|
| 3    | Elevated        | Rich poetic language, complex rhythm               |

**Traditional WEB** defaults to **Tier 2 (Vivid+)**.

Tier 2 guidance for prompts:
- Favor clarity and warmth over ornamentation.
- Sensory detail is welcome; purple prose is not.
- Concrete images preferred over abstract flourishes.
- If a phrase feels literary rather than natural, pull back.

---

## 5. Story Length System (Locked)

Story lengths are bucket-based only.

| Bucket | Word Count |
|--------|------------|
| Short  | 300–500    |
| Full   | 501–900    |
| Long   | 901–1500   |

Invariants:
- Word counts must fall strictly within ranges.
- No padding, trimming, or post-processing allowed.
- Violations trigger fail-clean abort.

---

## 6. Reflection System (Option B2)

- Each story has exactly ONE canonical reflection.
- Reflection applies to all three lengths.
- Reflection is generated via gpt-4.1.
- Reflection word count target: **120–220 words**.

Reflection Guardrails:
- No advice
- No prescriptions
- No theological interpretation

Allowed:
- Gentle observations
- Pattern-based language
- Invitations to notice, not commands

### 6.1 Reflection Question (Optional)

Per SPEC.md Feature 37, each reflection may include a single optional question.

Rules:
- 0 or 1 question per reflection (empty string `""` is valid).
- Gentle, invitational, everyday-life phrasing (e.g., "Have you ever…", "Is there…", "Where in your life…").
- NOT directive, NOT guilt-inducing, NOT therapeutic language.
- The question is display-only; user response is NOT captured or stored.
- Stored inline in `meta_<id>.json` as `reflectionQuestion` (string).

---

## 7. Audio Generation

- All audio is generated via ElevenLabs.
- Exactly 4 audio files per story:
  - Short story
  - Full story
  - Long story
  - Reflection

Validation:
- Each audio file must be >= 1000 bytes.
- Smaller files are treated as failures.

---

## 8. File & Directory Contract

Directory:
`assets/stories/traditional/<story_id>/`

Required files:
- `story_<id>_traditional_<lane>_short.txt`
- `story_<id>_traditional_<lane>_full.txt`
- `story_<id>_traditional_<lane>_long.txt`
- `reflection_<id>_traditional_<lane>.txt`
- `audio_<id>_story_short.mp3`
- `audio_<id>_story_full.mp3`
- `audio_<id>_story_long.mp3`
- `audio_<id>_reflection.mp3`
- `meta_<id>.json`

Filenames are authoritative and must not change.

### 8.1 Metadata Schema

`meta_<id>.json` MUST include a top-level `"schemaVersion"` field.

**Current version: 2** (added `reflectionQuestion` field).

Any structural change to the metadata format requires incrementing this version
and updating this spec.

Schema changelog:
- **v1**: Initial schema (story files, reflection files, audio files).
- **v2**: Added `reflectionQuestion` (string, may be `""`).

---

## 9. Anchor Registry

- Used anchors are tracked in `used_scripture_anchors.json`.
- Anchors must be unique.
- Registry updates only after successful generation.
- Registry is sorted and formatted with indent=2.

---

## 10. Failure Semantics

- Any failure after output directory creation triggers:
  - Immediate abort
  - Full cleanup (rm -rf story directory)
- Exit codes:
  - 0 = success
  - 1 = failure only
- Wrapper scripts must always print elapsed time.

### 10.1 Retry Policy

Transient HTTP failures (429, 502, 503, timeout) MAY be retried up to 3 times
with exponential backoff before triggering abort.

Non-transient failures (400, 401, 422) MUST abort immediately with no retry.

Retries MUST NOT be applied to validation failures
(word count, file size, anchor duplication).

---

## 11. Design Intent (Non-Normative)

The Story Factory exists to ensure:
- Zero drift at scale
- Deterministic, auditable content creation
- Clear separation between:
  - Story authoring (AI)
  - System orchestration (scripts)
  - App consumption (Bible PAL)

This document is the single source of truth
for Traditional story generation.
