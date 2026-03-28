# Bible PAL — Story Factory Specification (Locked)

**Status:** LOCKED

This document defines the canonical rules, invariants, and contracts for generating
Bible PAL stories using the Story Factory pipeline.

Any change to this document requires an explicit spec update and approval
before implementation.

---

## 0. Engine Architecture (Locked — Revised 2026-03-28)

### Active Engine: Claude Opus 4.6

All new story generation uses **Claude Opus 4.6** via the Anthropic API as the
sole active engine for both Traditional and Creative modes.

| Mode        | Engine                  | Generator Script               | ID Range    |
|-------------|------------------------|---------------------------------|-------------|
| Traditional | Claude Opus 4.6 (Cloud) | `generate_story_claude.py`     | 1000–1999   |
| Creative    | Claude Opus 4.6 (Cloud) | `generate_story_claude.py`     | 2000–2999   |

**Active Engine Rules:**
- Both modes MUST use `claude-opus-4-6` via the Anthropic Python SDK.
- Metadata records `"createdByModel": "claude-opus-4-6"`.
- Registries are separate: `used_scripture_anchors.json` (Traditional) vs `used_creative_themes.json` (Creative).
- Output directories are separate: `assets/stories/traditional/` vs `assets/stories/creative/`.
- No cross-engine content. No cross-registry reads. No blurring.

### Retired Engines (Legacy)

The following engines are retired. Their scripts remain in the repo but are no
longer used for new content. Legacy stories (IDs 501–519, 801–834) remain in
the app for testing and are never deleted.

| Mode        | Engine (Retired)                | Generator Script (Retired)                                        | ID Range   |
|-------------|--------------------------------|-------------------------------------------------------------------|------------|
| Traditional | OpenAI gpt-4.1 (Cloud)         | `generate_traditional_story.py`                                   | 801–834    |
| Creative    | mistral-nemo via Ollama (Local) | `generate_v2_batch.sh`, `generate_creative_story.py`              | 501–519    |

**Why Single Engine:**
- Consistent prose quality across both modes from a single best-in-class model
- Eliminates continuation-stitching issues from local models
- Simplifies tooling (one script, one API, one validation pipeline)
- Preserves doctrinal trust (Opus 4.6 proven for faithful scripture retelling)

---

## 1. Canonical Story Author

- Canonical author model: **Claude Opus 4.6** (`claude-opus-4-6`)
- All new story and reflection prose MUST be generated via the Anthropic API
  using Claude Opus 4.6.
- Legacy Traditional stories (801–834) were authored by gpt-4.1; legacy Creative
  stories (501–519) were authored by Ollama models. These remain but are not
  extended.
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
- Reflection is generated via the active engine (Claude Opus 4.6 for new stories).
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

---

## PART B: Creative Story Generation

The following sections define the Creative story generation pipeline.
Creative stories are original faith-themed narratives — NOT Bible retellings.

---

## 12. Creative Canonical Story Author

- Canonical author model: **Claude Opus 4.6** (`claude-opus-4-6`)
- All new creative story and reflection prose MUST be generated via the Anthropic
  API using Claude Opus 4.6.
- Legacy Creative stories (501–519) were authored by Ollama models (mistral-nemo,
  gemma:7b). These remain but are not extended.
- Generation scripts MUST NOT contain hard-coded prose, fallback prose,
  or template expansions.
- The `createdByModel` metadata field records `"claude-opus-4-6"` for new stories.

**Invariant:**
The generator may orchestrate, validate, and persist content —
but must never author content itself.

---

## 13. Creative Story Themes

### 13.1 Theme-Based (Not Scripture-Anchored)

- Creative stories are anchored to a **theme**, not a Scripture passage.
- Each story has exactly ONE theme (a short descriptive phrase).
- A theme+mood combination may NEVER be reused.
- NO `scriptureAnchor` or `bibleSourceRef` field in Creative metadata.
- NO `bibleStoryKey` field in Creative metadata.

### 13.2 Theme Format Rules

Themes are free-form descriptive phrases, e.g.:
- `"finding unexpected joy in small acts of kindness"`
- `"a tired traveler who finds rest in an unlikely place"`
- `"a potter who learns to trust the process of shaping clay"`

### 13.3 Curated Theme Pools

Themes are curated per mood in `batch_generate_creative.py`.
Each mood has 8+ theme suggestions for scalability.

---

## 14. Creative Content Guardrails (Non-Negotiable)

All Creative stories MUST obey:

- NO Bible story retellings (no specific Bible characters by name)
- NO scripture quoting or verse references
- NO teaching doctrine as fact
- NO God speaking directly as a dialogue character
- NO spiritual authority claims
- NO fear-based framing (guilt, shame, punishment)
- NO commands or prescriptions to the listener
- NO dependency language

Allowed:
- Fictional characters
- Modern or timeless settings
- Parables and metaphor narratives
- Symbolic elements
- Biblical themes (grace, kindness, perseverance, forgiveness, hope)
- Faith shown through characters' actions and observations

---

## 15. Creative Story Length System (Locked)

Creative stories use **shorter ranges** than Traditional to match the parable format
and Gemma 7B's natural output characteristics.

| Bucket | Word Count |
|--------|------------|
| Short  | 200–400    |
| Full   | 401–700    |
| Long   | 701–1100   |

Kid ranges:

| Bucket | Kid Word Count |
|--------|---------------|
| Short  | 200–500       |
| Full   | 501–900       |
| Long   | 901–1400      |

**Rationale:** Creative stories are original parables and metaphor narratives —
naturally more concise than detailed Bible retellings. Shorter ranges also reduce
the need for continuation stitching with the local model, preserving prose quality.

---

## 16. Creative Reflection System

Same rules as Traditional (Section 6):

- Each story has exactly ONE canonical reflection.
- Reflection applies to all three lengths.
- Reflection is generated via the active engine (Claude Opus 4.6 for new stories).
- Reflection word count target: **120–220 words** (adult), **60–120 words** (kid).
- Same guardrails: no advice, no prescriptions, no theological interpretation.
- Same optional reflection question rules (Section 6.1).

---

## 17. Creative Audio Generation

Same as Traditional (Section 7):

- All audio is generated via ElevenLabs.
- Exactly 4 audio files per story.
- Each audio file must be >= 1000 bytes.
- `--skip-audio` flag available for text-only generation.

---

## 18. Creative File & Directory Contract

Directory:
`assets/stories/creative/<story_id>/`

Required files:
- `story_<id>_creative_<lane>_short.txt`
- `story_<id>_creative_<lane>_full.txt`
- `story_<id>_creative_<lane>_long.txt`
- `reflection_<id>_creative_<lane>.txt`
- `audio_<id>_story_short.mp3`
- `audio_<id>_story_full.mp3`
- `audio_<id>_story_long.mp3`
- `audio_<id>_reflection.mp3`
- `meta_<id>.json`

### 18.1 Creative Metadata Schema

Same `schemaVersion: 2` as Traditional, with these differences:

- `"mode": "creative"` (not `"traditional"`)
- `"theme": "..."` (theme string, replaces `scriptureAnchor`)
- `"createdByModel": "<model_used>"` (e.g., `"mistral-nemo"`, `"gemma:7b"` — captured dynamically)
- NO `scriptureAnchor` field (Creative mode forbids it)

---

## 19. Creative Theme Registry

- Used themes are tracked in `used_creative_themes.json`.
- Registry key format: `"mood:theme"` (e.g., `"joyful:finding unexpected joy..."`)
- Keys must be unique.
- Registry updates only after successful generation.
- Registry is sorted and formatted with indent=2.

---

## 20. Creative Validation Gates

All Creative stories pass through these gates (in order):

1. **Meta-text check** — Same blocklist as Traditional
2. **Word count validation** — Same locked ranges
3. **Creative compliance check** — Catches scripture retelling, authority claims,
   direct God dialogue, spiritual commands, fear framing
4. **Kid forbidden words** (kid mode only) — Same blocklist as Traditional
5. **Anti-repetition** — Same rules embedded in prompts

On violation: sanitize rewrite attempted, then fresh regeneration.
Max attempts: 5 (adult), 5 (kid).

---

## 21. Story ID Space

### Active Ranges (Claude Opus 4.6)
- Traditional story IDs: **1000–1999**
- Creative story IDs: **2000–2999**

### Legacy Ranges (Retired Engines)
- Creative (Ollama): **501–519**
- Traditional (gpt-4.1): **801–834**

All ranges MUST NOT overlap.

---

## 22. Design Intent (Non-Normative)

The dual-engine Story Factory exists to ensure:
- Zero drift at scale across both modes
- Deterministic, auditable content creation
- Clear separation between engines, modes, and registries
- Cost control (local model for creative, cloud for traditional)
- Vendor independence (creative runs entirely offline)

This document is the single source of truth for all story generation.
