# Bible PAL — Story Factory Specification (Locked)

**Status:** LOCKED

This document defines the canonical rules, invariants, and contracts for generating
Bible PAL stories using the Story Factory pipeline.

Any change to this document requires an explicit spec update and approval
before implementation.

---

## 0. Engine Architecture (Locked — Revised 2026-05-13)

### Active Engine: Claude (Opus 4.6 → 4.7 → 4.8 → Fable 5 → Opus 5)

All new story generation uses **Claude** via the Anthropic API. The active
model has advanced over time and each story's metadata records the model that
authored it: `claude-opus-4-6` (initial Opus batches), `claude-opus-4-7` (added
2026-05, 1M context), `claude-opus-4-8` (added 2026-06; e.g. 1543, 1552-1570),
`claude-fable-5` (added 2026-07; TEXT-FIRST STORY FACTORY 2.0 pilot, stories
1571-1610), and **`claude-opus-5`** (added 2026-08-01 by Adam's explicit
approval, current active model; 1M context, text-first batch from story 1611).
Traditional is the only active mode (Creative was
retired 2026-05-13; see
[archive/CREATIVE_RETIREMENT_2026_05_13.md](archive/CREATIVE_RETIREMENT_2026_05_13.md)).

| Mode        | Engine                  | Generator Script               | ID Range    |
|-------------|------------------------|---------------------------------|-------------|
| Traditional | Claude Opus (Cloud)     | `generate_story_claude.py`     | 1000–1999+  |

**Active Engine Rules:**
- MUST use the current sanctioned Claude model (now `claude-opus-5`) via the Anthropic Python SDK.
- Metadata records `"createdByModel"` = the model that authored the story (4-6 / 4-7 / 4-8 / fable-5 / opus-5).
- Registry: `used_scripture_anchors.json`.
- Output directory: `assets/stories/traditional/`.

### Retired Engines (Legacy)

The following engines are retired. Their scripts remain in the repo only where
needed for legacy support. Legacy Traditional stories (IDs 801–834) remain in
the app for testing and are never deleted.

| Mode        | Engine (Retired)                | Generator Script (Retired)         | ID Range   |
|-------------|--------------------------------|-------------------------------------|------------|
| Traditional | OpenAI gpt-4.1 (Cloud)         | `generate_traditional_story.py`    | 801–834    |

Creative engines (mistral-nemo via Ollama for IDs 501–519; Claude Opus 4.6 for
IDs 2000–2079) are archived to T9 and removed from the working tree as of
Creative retirement (2026-05-13).

**Why Single Engine:**
- Consistent prose quality from a single best-in-class model
- Eliminates continuation-stitching issues from local models
- Simplifies tooling (one script, one API, one validation pipeline)
- Preserves doctrinal trust (Opus 4.6 proven for faithful scripture retelling)

---

## 1. Canonical Story Author

- Canonical author model: **Claude Opus 4.6** (`claude-opus-4-6`)
- All new story and reflection prose MUST be generated via the Anthropic API
  using Claude Opus 4.6.
- Legacy Traditional stories (801–834) were authored by gpt-4.1. They remain
  in the app but are not extended. Legacy Creative stories (501–519, 2000–2079)
  were retired on 2026-05-13 and archived.
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

### 4.2 Required Retelling Craft (ADR-031)

The guardrails above forbid **departing** from scripture. This section forbids the opposite
failure: **reproducing** it.

A Traditional story is a faithful, listening-oriented **retelling** of its anchor. It is not a
scripture audiobook, a chapter with new punctuation, a verse-by-verse transcription, or a lightly
modified paraphrase that keeps the source's structure without listening craft.

Review is **two-level**, applied at text review before rendering. **Both levels must pass.**

**Level 1 — Reconstruction Test (hard failure for direct reproduction):**

> Could the story be reconstructed from the scripture source by changing only punctuation,
> capitalization, whitespace, paragraphing, and quotation marks?

If yes, it fails. This is a qualitative pass/fail judgement, **not** an overlap percentage.

**Level 2 — Retelling Craft Review (required qualitative evidence):**

**Passing the Reconstruction Test does not by itself establish that a story is an adequate
retelling.** The test detects direct reproduction; a lightly modified or mostly copied passage
may technically pass while still lacking meaningful listening-oriented transformation. It must
also pass the qualitative Retelling Craft review — the evidence list below.

Merely adding one or two connective sentences, swapping synonyms, or breaking verses into
paragraphs **does not** convert a transcription into a retelling.

**Required evidence of transformation** — as applicable to the anchor; no story must contain
every technique:

- establish clearly who is present, where the action occurs, and what is happening
- turn verse structure into natural narrative movement
- divide long biblical sentences into spoken beats
- use neutral connective narration where the passage jumps
- re-anchor speakers, characters, titles, and pronouns when audio listeners could lose the referent
- allow important actions, contrasts, and explicitly stated emotional turns to land
- narrate surrounding action rather than copying it merely because the wording is available
- remain strictly inside the approved anchor — no invented events, settings, motives, thoughts,
  doctrine, or sermon commentary

**Essential dialogue exception.** Biblical dialogue may remain exact or near-exact when the words
themselves are the central action, when altering them would weaken meaning or recognition, and
when the quotation is clear and natural spoken aloud. Preserving important dialogue **does not**
permit copying all surrounding narration.

**Lane distinction.** WEB = faithful retelling in clear modern spoken English. KJV = faithful
retelling in classical / KJV-compatible diction. **The KJV lane is not permission to reproduce
the KJV passage word-for-word**; classical register may preserve recognizable phrases, dialogue,
titles, and cadence while still restructuring narration for listening.

**Diagnostic warnings.** Tooling may flag a fully reconstructible file, unusually long
uninterrupted source runs, or very high overlap with little original connective narration. These
are **review triggers, not quality scores**, and no acceptable-overlap percentage is defined.
Essential dialogue, poetry, epistles, wisdom, and liturgical anchors may naturally produce high
overlap and require qualitative review.

**Non-narrative anchors** (poetry, epistles, doctrinal discourse, blessings) raise a separate
eligibility question that ADR-031 does not settle; they need their own editorial review.

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

## 5. Story Length System (Revised 2026-07-19 — ADR-030)

**This section is the authoritative source for adult Traditional authoring lengths.**
Other documents may summarize this policy for their own operational context, but this
section remains authoritative; every summary must cross-reference it and must not
establish competing boundaries.

Scope: **adult Traditional** content. Traditional Kid bands are separate and unchanged.

> Not to be confused with runtime bucket classification (Short 250–600, Full 601–1200,
> Long 1201–2000) implemented in `lib/core/story_length_bucket.dart`. That system labels
> and serves whatever exists; it is not an authoring standard. See the Two Length Systems
> Invariant in [INVARIANTS.md](INVARIANTS.md).

### 5.1 Production-validation bands (hard bounds)

Enforced by `test/core/story_word_count_compliance_test.dart`:

| Bucket | Validation band (hard) |
|--------|------------------------|
| Short  | 300–500                |
| Full   | 501–900                |
| Long   | 901–1500               |

### 5.2 Preferred drafting targets (guidance, not boundaries)

Aim here when the anchor allows. These are **drafting guidance only** — a story is
compliant anywhere inside its §5.1 band, and falling outside a target is not a violation:

| Bucket | Drafting target | Aim For |
|--------|-----------------|---------|
| Short  | 350–450         | 400     |
| Full   | 700–850         | 780     |
| Long   | ~1200–1400      | 1300    |

### 5.3 Supported-length policy (ADR-030)

- Every new adult Traditional anchor is **evaluated for Short, Full, and Long**.
- **Short is the default expected production version.**
- **Full and Long are conditional** on what the approved anchor honestly supports.
  **Neither is universally required.**
- Never pad, repeat propositions, invent physical detail, add unstated thoughts or
  motives, or insert theological explanation merely to reach a bucket floor.
- When a length is unsupported, **omit it and document the reason** in the story's
  `editorialNotes`.
- **Anchor widening** requires a coherent continuous passage and **owner approval before
  drafting**.

Raw scripture word count may be used as an editorial warning signal, never as an
automatic eligibility formula. Feasibility is an editorial judgement about how much
explicit narrative, dialogue, imagery, and action the anchor actually contains.

Each story declares its available lengths via `lengths` in meta and `availableLengths`
in manifest entries.

### 5.4 `shortScripture` exception

`shortScripture: true` is an **explicit, owner-approved authoring exception**. It may
allow an adult Traditional Short below 300 words when the complete approved passage has
been rendered faithfully and additional words would require padding, invention, or
commentary. It is **not** legacy-only, and it is **not** self-service — each use requires
owner approval and a documented reason.

Runtime still classifies such a story as Short (any value ≤600 is Short).

### 5.5 Invariants

- Word counts must fall strictly within the §5.1 bands, except under §5.4.
- No padding or repetition to reach minimum word counts.
- Violations trigger correction (regeneration, not patching).

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

## PART B: Creative Mode Retirement (2026-05-13)

Creative mode and its dual-engine pipeline have been retired. The PART B
sections that previously defined Creative story authoring, themes,
guardrails, length system, reflection rules, audio generation, file
contract, theme registry, and validation gates are no longer active.

- Archive: [archive/CREATIVE_RETIREMENT_2026_05_13.md](archive/CREATIVE_RETIREMENT_2026_05_13.md)
- Superseded ADRs: ADR-014 (dual-engine pipeline), ADR-020 (Story DNA)
- Git tag for restoration: `pre-creative-retirement-2026-05-13`
- T9 cold archive: `/Volumes/T9-Archive/bible_pal_archives/creative_retirement_2026_05_13/`

Reactivation requires a new SPEC update and explicit owner approval.

---

## 12. Story ID Space

### Active Range (Claude Opus 4.6, Traditional only)
- Traditional story IDs: **1000–1999** (with overflow into 1100+/1200+/1300+ as the corpus grows)

### Legacy Range (Retired Engine)
- Traditional (gpt-4.1): **801–834**

The Creative ranges (501–519 legacy, 2000–2999 modern) are reserved on the
T9 archive and are not assignable to new content.

---

## 13. Design Intent (Non-Normative)

The Story Factory exists to ensure:
- Zero drift at scale for Traditional Bible stories
- Deterministic, auditable content creation
- Clear separation between engines, modes, and registries
- Vendor independence where practical (Traditional is locked to gpt-4.1 per ADR-014/016)

This document is the single source of truth for Traditional story generation.
