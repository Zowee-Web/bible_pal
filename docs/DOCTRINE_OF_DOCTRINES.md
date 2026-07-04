# Bible PAL — Doctrine of Doctrines

> The operating rule for standards. Not a philosophy piece — a checklist for the checklists.

Bible PAL now governs story voice, reflection voice, PAL memory, journey transitions, journeys, audio loudness, translation fidelity, and product invariants. That is a real governance layer. This document is the rule that keeps it a *system* instead of a pile of good documents.

## The rule

**Every locked standard must have three things. A standard missing any of them is a draft, not a standard.**

1. **An enforcement gate** — something that makes a violation fail automatically, or an explicit checklist a human is required to run.
2. **A revision / demotion path** — a named way to change *or retire* the rule.
3. **A place in the hierarchy** — a ranked position, so two standards in tension have a resolution.

## Two things to keep taped above the work

- **A standard is the ratchet, not the engine.** Standards raise the floor and stop regression; they do not create quality. The story, the take, the ear still do that. A corpus can be perfectly consistent and perfectly lifeless. Guard the parts of each standard that teach *taste*, not only the parts that check *compliance*.
- **Reverence is not a checklist property.** The most important thing these standards protect cannot be asserted in a test. So some of what matters most will always live in a human-run audit — and that is correct, not a failure. The discipline is: **gate what is gateable, and name honestly what is not.** A doc that pretends prose is enforced is worse than one that admits it isn't.

## What each requirement means

**1 — Enforcement gate.** Gates come in tiers. Prefer the highest tier the rule admits; a rule with no gate is a hope, not a standard.

| Tier | What it is | Example in this repo |
|------|-----------|----------------------|
| `executable_test` | a build-failing test / CI check | `bible_translation_compliance_test.dart` |
| `script_gate` | a producer or pre-commit script that applies/checks the rule | `loudnorm_audio.sh`, `validate_kids.py` |
| `checklist_in_doc` | an explicit human-run audit / paste-test the doc mandates | REFLECTION_VOICE six-point audit |
| `prose_only` | stated but ungated | *not a gate — fix or admit it* |

A checklist-tier gate is legitimate (see: reverence). What is *not* legitimate is a doc that **labels a rule "enforced by test" when no test enforces it** — that is drift wearing a gate's clothes, and the audit below found it in two places.

**2 — Revision / demotion path.** A standard you cannot revise calcifies; one you cannot *demote* outlives its own truth. The leverage that makes a good standard compound makes a stale one compound too. Minimum: a dated History. Better: an explicit demotion mechanism (see JOURNEY_TRANSITION_VOICE's "Keeping the standard living").

**3 — Conflict hierarchy.** Every standard gets a rank in the CLAUDE.md Document Hierarchy. Rule: *official docs win over CLAUDE.md; higher rank wins over lower.* A parent doctrine must rank above the voice docs it governs. A standard absent from the hierarchy has undefined authority — a latent conflict with no resolution.

## Current state — audited 2026-07-04

Ten locked standards, each verified against the real test suite (not assumed). Gate tier is what an enforcer *actually* checks, not what the doc claims.

| Standard | Gate (verified) | Revision | Hierarchy | Biggest gap |
|----------|-----------------|----------|-----------|-------------|
| INVARIANTS | `executable_test` (~29/30 CI-gated) | demotion procedures | #1 | "Delilah Opening Layer" invariant claims test-enforcement for a 60-entry model that doesn't exist (code ships 12); no test catches the drift |
| SPEC | `executable_test` (broad, not total) | history (no ledger) | #2 | ~a dozen prose-only clauses; revision trail scattered, no maintained changelog |
| BIBLE_TRANSLATION_COMPLIANCE | `executable_test` (strongest — repo-wide, CI hard-gated) | none | #3 | no demotion path (low risk — legal, only tightens); runs in CI, not local pre-commit |
| PAL_VOICE | `checklist_in_doc` (human 8-Q audit; a thin 6-phrase lint on 2 datasets) | none | #4 | Voice Audit + Pillars enforced by human only; CLAUDE.md says "four pillars", doc says "Five" — untracked drift |
| REFLECTION_VOICE | `checklist_in_doc` (six-point audit) | history (exemplary demotions) | #5 | zero machine enforcement of the voice; the nearest test would *pass* reflections the doc rejects |
| JOURNEY_TRANSITION_VOICE | `checklist_in_doc` | demotion (built-in) | #6 | no automated enforcement; benchmark section still `PENDING` (no promoted exemplars yet) |
| JOURNEY_DOCTRINE | `executable_test` (strong behavioral) | history | **ABSENT** | 2 of its 7 self-declared required tests don't exist; ranks *below its own child* (JTV #6) |
| PAL_MEMORY_DOCTRINE | `executable_test` (gates its real rules) | none | **ABSENT** | absent from hierarchy; its 6-line invariant never landed in INVARIANTS despite governing shipped code |
| AUDIO_LOUDNESS | `script_gate` (producer-only) | history | **ABSENT** | no post-hoc verifier — a hand-edited or un-swept compressed file passes every gate and ships silently |
| STORY_NARRATION_STYLE_GUIDE | `checklist_in_doc` (unconfirmed) | none | **ABSENT** | governs story prose with no build-failing gate; sole editorial enforcer has zero test coverage |

## Open gaps — the backlog this doc exists to close

**P1 — docs that lie about enforcement (fix first; these are the ones that erode trust in the whole layer).**
- **INVARIANTS "Delilah Opening Layer":** rewrite it to the shipped reality (12 lines × `OpeningTimeBucket`), or build the 60-entry model it describes. Today it says "enforced by test" and nothing enforces it.
- **JOURNEY_DOCTRINE Implementation Enforcement:** it lists 7 required tests; the `primaryJourney`-required test and the "no journey-type in telemetry" test do not exist. Write them, or downgrade the claim to pending.

**P2 — complete the hierarchy (rule 3).** Add the four ABSENT standards to CLAUDE.md and fix the parent-below-child inversion. Recommended ordering: INVARIANTS · SPEC · BIBLE_TRANSLATION_COMPLIANCE · PAL_VOICE · PAL_MEMORY_DOCTRINE · REFLECTION_VOICE · STORY_NARRATION_STYLE_GUIDE · JOURNEY_DOCTRINE · JOURNEY_TRANSITION_VOICE · AUDIO_LOUDNESS · ARCHITECTURE · DOCTRINE_OF_DOCTRINES · CLAUDE.md. Also land PAL_MEMORY's 6-line invariant in INVARIANTS, as that doc already promises.

**P3 — close the widest gateable gaps (rule 1).**
- **AUDIO_LOUDNESS:** add a post-hoc LUFS verifier over the *published* mirror. It is the one gate that would catch silent drift, and it's cheaply scriptable.
- **Voice docs:** these are checklist-tier by nature (reverence isn't executable) — but the *partial* lints that are gateable should exist: extend the banned-phrase lint beyond its two datasets to the corpus; add the soft-consonant-ending check REFLECTION_VOICE already specifies.

**P4 — revision hygiene (rule 2).** Add a dated History + demotion note to the docs missing one (PAL_VOICE, PAL_MEMORY_DOCTRINE). Fix the "four pillars" → "Five Pillars" drift in CLAUDE.md. Populate JOURNEY_TRANSITION_VOICE's pending benchmarks.

## How a new standard enters

Before a doc is called *locked*, it must satisfy all three requirements — or state plainly, in the doc, which one it cannot meet yet and why (the way JOURNEY_TRANSITION_VOICE marks its benchmarks `PENDING` instead of pretending they exist). Honesty about a missing gate is a valid state. A silent missing gate is the failure this document exists to prevent.

## Authority of this document

This is a **meta-standard**: it governs *how* standards are formed, gated, revised, and ranked. It does not outrank the content invariants on their own subject matter — INVARIANTS still wins on translation licensing, kid safety, and privacy. Its authority is over process, and it sits in the governance tier alongside CLAUDE.md.

## History

- **2026-07-04** — Created. Codifies the three-requirement rule after a verified audit of the ten locked standards (matrix above). Written the same session as JOURNEY_TRANSITION_VOICE, whose "living standard" section seeded requirement 2.
