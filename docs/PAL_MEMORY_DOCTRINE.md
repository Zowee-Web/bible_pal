# PAL Memory Doctrine

> PAL should never tell the user who they are. PAL should remember where they've been.

**Status:** Captured 2026-06-18. No implementation yet. Return after R2 Phase 2 and Play release.

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
