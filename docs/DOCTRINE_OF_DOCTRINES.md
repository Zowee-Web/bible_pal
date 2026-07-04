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
| PAL_VOICE | `checklist_in_doc` (human 8-Q audit; a thin 6-phrase lint on 2 datasets) | none | #4 | Voice Audit + Pillars enforced by human only; no in-doc History *(the "four pillars" CLAUDE.md drift was fixed 2026-07-04)* |
| REFLECTION_VOICE | `checklist_in_doc` (six-point audit) | history (exemplary demotions) | #6 | zero machine enforcement of the voice; the nearest test would *pass* reflections the doc rejects |
| JOURNEY_TRANSITION_VOICE | `checklist_in_doc` | demotion (built-in) | #9 | no automated enforcement of the wording rules *(benchmark set promoted 2026-07-04: 12 exemplars + canonical ladder + near-misses; two new rules discovered and locked at that pass)* |
| JOURNEY_DOCTRINE | `executable_test` (strong behavioral) | history | #8 | *resolved 2026-07-04*: missing telemetry-type test written; `primaryJourney` requirement honestly downgraded to Slice-3 deferral |
| PAL_MEMORY_DOCTRINE | `executable_test` (gates its real rules) | none | #5 | 6-line invariant landed in INVARIANTS 2026-07-04; remaining: no in-doc History; Level 4 needs a test before it ships |
| AUDIO_LOUDNESS | `script_gate` (producer-only) | history | #10 | no post-hoc verifier — a hand-edited or un-swept compressed file passes every gate and ships silently |
| STORY_NARRATION_STYLE_GUIDE | `checklist_in_doc` (unconfirmed) | none | #7 | governs story prose with no build-failing gate; sole editorial enforcer has zero test coverage |

## Open gaps — the backlog this doc exists to close

**P1 — docs that lie about enforcement. ✅ DONE 2026-07-04.**
- ~~**INVARIANTS "Delilah Opening Layer"**~~ — rewritten to the shipped reality (12 lines × `OpeningTimeBucket`, real test citations); the void tone rules formally retired.
- ~~**JOURNEY_DOCTRINE Implementation Enforcement**~~ — the "no journey-type in telemetry" test now exists (`journey_offer_runtime_test.dart`); the `primaryJourney` requirement is honestly downgraded to an explicit Slice-3 deferral.

**P2 — complete the hierarchy (rule 3). ✅ DONE 2026-07-04** (ordering ratified by Adam). The four absent standards are ranked, the parent-below-child inversion is fixed, and PAL_MEMORY's 6-line invariant landed in INVARIANTS as that doctrine promised.

**P3 — close the widest gateable gaps (rule 1).**
- **AUDIO_LOUDNESS:** add a post-hoc LUFS verifier over the *published* mirror. It is the one gate that would catch silent drift, and it's cheaply scriptable.
- **Voice docs:** these are checklist-tier by nature (reverence isn't executable) — but the *partial* lints that are gateable should exist: extend the banned-phrase lint beyond its two datasets to the corpus; add the soft-consonant-ending check REFLECTION_VOICE already specifies.

**P4 — revision hygiene (rule 2).** Add a dated History + demotion note to the docs missing one (PAL_VOICE, PAL_MEMORY_DOCTRINE). ~~Fix the "four pillars" → "Five Pillars" drift in CLAUDE.md~~ *(done 2026-07-04, rode with P2)*. ~~Populate JOURNEY_TRANSITION_VOICE's pending benchmarks~~ *(done 2026-07-04 — first promotion pass: 12 promoted, Ruth ladder canonical, two new rules discovered)*.

## How a new standard enters

Before a doc is called *locked*, it must satisfy all three requirements — or state plainly, in the doc, which one it cannot meet yet and why (the way JOURNEY_TRANSITION_VOICE marks its benchmarks `PENDING` instead of pretending they exist). Honesty about a missing gate is a valid state. A silent missing gate is the failure this document exists to prevent.

## Authority of this document

This is a **meta-standard**: it governs *how* standards are formed, gated, revised, and ranked. It does not outrank the content invariants on their own subject matter — INVARIANTS still wins on translation licensing, kid safety, and privacy. Its authority is over process, and it sits in the governance tier alongside CLAUDE.md.

## History

- **2026-07-04** — Created. Codifies the three-requirement rule after a verified audit of the ten locked standards (matrix above). Written the same session as JOURNEY_TRANSITION_VOICE, whose "living standard" section seeded requirement 2.
- **2026-07-04** (same session) — P1 closed: both false enforcement claims corrected (Delilah invariant rewritten to shipped reality; journey telemetry-type test written; `primaryJourney` downgraded to explicit Slice-3 deferral). P2 closed: full hierarchy ratified by Adam and landed in CLAUDE.md; PAL Memory 6-line invariant promoted into INVARIANTS. Matrix updated to post-remediation state.
