# PAL Memory Doctrine

> PAL should never tell the user who they are. PAL should remember where they've been.

**Status:** Captured 2026-06-18. Slice 1 (session log) and Slice 2a (rules engine) shipped — pure infrastructure, no surface integration. Slice 2b (audio + delivery) pending after R2 Phase 2 and Play release.

---

## The Doctrine

PAL remembers what the user did, observes what keeps recurring, presents authored meaning at milestones, and stays silent when the signal is weak.

PAL should never tell the user who they are. PAL should remember where they've been.

Every return should feel like a continuation, not a restart.

---

## The Four Levels

**Level 1 — Silence.** When confidence is low, PAL says nothing memory-related and falls back to the locked neutral cold-open. Silence is an explicit product choice, not the absence of memory. The willingness to not speak is part of why users will trust the speaking.

**Level 2 — Facts.** Verifiable from the session log. "Yesterday you sat with Daniel. Want to hear what came after?" "Last week you heard three stories from the Psalms." Facts never hallucinate.

**Level 3 — Patterns.** Observable patterns in the log, surfaced only after deterministic thresholds (e.g., 3+ completed sessions in 14 days with consistent theme tags). Spoken in collaborative-witness register: "We keep returning to stories about waiting" — not "You've been struggling with waiting." The user can agree or disagree freely. Templates should have 3–4 wording variants so the form doesn't calcify into a tic.

**Level 4 — Meaning.** Hand-authored milestone reflections triggered by overwhelming deterministic evidence (e.g., 20+ stories, 60+ days, dominant tag concentration). Written by Adam under the same editorial regime as [REFLECTION_VOICE.md](REFLECTION_VOICE.md), including the paste-test and audio-first gate. Runtime-generated meaning is forbidden.

---

## Allowed / Forbidden

**Allowed**

- Facts verifiable from the session log
- Observations of recurring patterns above threshold
- Hand-authored milestone reflections at deterministic triggers
- Silence

**Forbidden**

- Runtime-generated meaning
- Claims about the user's interior state
- Psychological interpretation
- "I know how you feel" language
- Low-confidence memory assertions

---

## Observation vs Inference

The enforceable boundary between Level 3 and forbidden territory.

**Observation** describes what the user has done — testable against the log. *"We keep returning to waiting stories."* Allowed.

**Inference** describes what the user is feeling — a claim PAL can't verify from the log. *"You've been carrying uncertainty."* Forbidden at runtime; only ever expressible through authored Level 4 meaning at milestone triggers.

---

## Graceful Recovery

PAL will sometimes be wrong, even at high thresholds. Every Level 3 utterance must be paired with an easy redirect path. When the user pushes back ("that's not where I am"), PAL listens, adjusts, and the correction itself becomes evidence that PAL listens. Without recovery, the first wrong observation is unrecoverable. With recovery, the misread strengthens trust.

---

## Implementation Enforcement

Doctrines that live only in their own document get quietly weakened. To survive, this one needs the same scaffolding that protects Bible translation compliance:

- The 6-line invariant moves into [INVARIANTS.md](INVARIANTS.md) with the same legal weight as translation compliance.
- Thresholds live as named constants in code, with tests that fail if any constant drops below its floor.
- Templates live in a versioned registry file (same shape as [lib/core/pal_voice_registry.dart](../lib/core/pal_voice_registry.dart)), audited like the voice registry.
- Hand-authored milestone reflections live alongside [REFLECTION_VOICE.md](REFLECTION_VOICE.md) and pass the same paste-test and audio-first gates as the story corpus.
- No runtime LLM. Deterministic detection, hand-authored meaning, locked editorial voice on every template. Offline-capable by default.

---

## Launch Shape

Memory's value compounds per-user. The longer a user has been with PAL, the deeper their log, the more attuned PAL feels. Early users become the most-remembered, most-bonded users on the platform.

Mass marketing dilutes the moat — a million users with three-session logs feel less remembered than a thousand users with sixty-session logs. A small, intimate beta where logs accumulate and templates refine against real return patterns is a competitive advantage, not a constraint.

---

## First Ship

When the implementation slot opens (after R2 Phase 2 and Play release), ship Level 2 (Facts) only. One template, or close to it:

> "Yesterday you sat with Daniel. Want to hear what came after?"

Nothing else. No pattern recognition, no milestones, no meaning. Measure return behavior. If users light up, the upper levels are earned. If they don't, the elegance of the doctrine doesn't save you, and you've spent one slice instead of a quarter.

---

## Slice 2b Audio Architecture

When Slice 2b lands, this is how the engine's output gets spoken.

**The magic isn't the generation; it's the remembering.** Memory audio is pre-rendered and audited, never runtime TTS. The same voice, the same prosody, every time — that consistency is the trust the user comes back for. Runtime TTS would erode it without anyone realizing why, and would break Bible PAL's offline guarantee. The discipline matches the rest of the voiced surface: story audio, PAL greetings, and name audio are all pre-rendered and editorially reviewed.

**Delivery is stitched, not generated.** A spoken line concatenates three pre-rendered components: a carrier fragment ("Yesterday you sat with"), a `palMemoryDisplayName` clip for the source story ("Daniel"), and an optional follow-up question ("Want to hear what came after?"). `palMemoryDisplayName` is an editorial field on each anchor — the speakable form chosen deliberately ("Daniel" / "the parable of the lost son" / "Psalm 139"), not the title or `bibleStoryKey`. Carrier fragments are rendered with leading-into-a-name prosody so the stitch reads as a sentence, not a collage; programmatic silences (~250ms intra-line, ~700ms before the follow-up) preserve natural cadence.

**Missing clip means silence, not fallback generation.** If any component required by the engine's chosen line is missing from the bundle or R2, the line does not get spoken. PAL stays silent. The editorial discipline only holds if every line that ships was rendered and listened to — there is no runtime widening of the spoken surface for missing combinations.

**Build-time integrity check ships before Slice 2b ships.** Because [PalMemoryEngine](../lib/features/pal_memory/pal_memory_engine.dart) deterministically picks a variant per source session, every combination of (band × variant × `palMemoryDisplayName` × PAL voice) that can ever fire is enumerable at build time. A test asserts that each combination has a bundled clip or a registered R2 asset. No surprise gaps in production, no silent regressions when a new template or anchor lands without its audio.

---

## The 6-Line Invariant

To move into [INVARIANTS.md](INVARIANTS.md) when implementation begins:

1. PAL may remember facts.
2. PAL may observe patterns only after deterministic thresholds are met.
3. PAL may never infer personal meaning from user behavior at runtime.
4. PAL may present hand-authored reflections when deterministic milestone conditions are met.
5. When confidence is low, PAL remains silent.
6. Trust is more important than visibility.

---

## Origin

This doctrine emerged in a three-way synthesis on 2026-06-18:

- Adam's project instinct: locked editorial voice, deterministic systems, codebase-enforced invariants — the philosophy that has shaped every surviving system in Bible PAL.
- A parallel ChatGPT thread contributed the three-level hierarchy, the "we keep returning" collaborative-witness register, continuation-not-restart as the user-facing test, and the closing one-line distillation.
- Claude (this assistant) contributed silence as Level 1, observation vs inference as the enforceable boundary, graceful recovery, and the requirement to codify the rules in INVARIANTS.md so the doctrine survives feature pressure.

Worth naming honestly. A doctrine about humility and listening should not have a single-author origin story.
