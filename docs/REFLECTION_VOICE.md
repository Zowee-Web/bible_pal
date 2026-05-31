# Bible PAL Reflection Voice

## Purpose

This document locks the editorial voice for every reflection in the Bible PAL corpus. Reflections close each story and pull the listener into the anchor's emotional space. Once 20+ reflections exist under one rule, changing the rule becomes expensive — so the rule is fixed here before the 120-story retrofit begins.

The rule applies to all Traditional stories that are not V3_PILOT or `shortScripture: true` (those are audio-only schema variants exempt from the reflection requirement).

## Reflection Voice Rules

1. Reflections begin from a concrete image, action, tension, or moment in the story.
2. Reflections must remain specific to the story's actual events and imagery.
3. Generic devotional and life-coaching language is prohibited.
4. No mandatory application section.
5. No mandatory closing invitation.
6. Reflections may end in one of two valid forms:
   - **Earned Question** (default) — a story-shaped question arising naturally from the narrative
   - **Earned Observation** (rare, ~1/10) — a story-shaped observation arising naturally from the narrative
7. Variance is encouraged; formula is discouraged.
8. The reflection should stop once the question or observation lands. No follow-on instruction.
9. Listener interpretation is preferred over narrator instruction.

## The Headline Test

> *Could this reflection be pasted onto a different story without feeling wrong?*

If yes, it's generic — rewrite.

This single test does more work than any prohibition list. The prohibition lists below catch specific surface patterns; the paste-test catches the underlying failure mode (lack of story-specificity) regardless of which surface phrases are used.

## Allowed Endings

### Earned Question (default form)

Pattern:
1. Optional 1-sentence setup naming the anchor's specific image
2. A question that uses the story's own concepts and imagery
3. Direct second-person ("you")
4. Length: 1-2 sentences, typically 25-45 words

Openings that work: *"What does it feel like to…"* / *"What would it be like to…"* / *"What remains when…"* / *"Have you ever…"* / *"What is the…"*

### Earned Observation (rare form, ~1/10)

Reserved for anchors where the emotional landing is so quiet and complete that a question would intrude. Extended form, typically ~150 words. Ends on a specific image or observation — not a question, not an instruction.

## Prohibited Patterns

### Generic life-coaching

Without a story anchor: *"Where in your life is there a place that…"*

### Imperative or instruction language

Any of: *"take a moment"*, *"remember"*, *"consider"*, *"pray about"*, *"place this before Him"*, *"sit with this"*, *"reflect on…"*. These pull the listener out of the story and into devotional-app posture.

### Mandatory closing invitation

A "closing invitation" sounds good in one reflection. Repeated across 120 reflections, it becomes a pattern the listener hears coming before the story finishes. Forbidden as a required element.

### Generic moral lessons

*"Sometimes God provides…"* / *"God always…"* — preachy, not story-shaped.

### Disconnected hypotheticals

*"If you could ask God for one thing…"* without naming the story's specific moment.

### Observer-distance statements

Statements that keep the listener watching the story rather than entering it — the failure mode that produced the rejected B20-B22 batches. Save observation/afterglow for the prose; reflection asks (or names with such specificity that the listener inhabits the observation).

## Audio Craft Rules

Reflections render to TTS audio per the `audio_<id>_reflection.mp3` pattern.

- Final word should end on a soft consonant — **n / m / ng / l / voiced-z / voiced-v** — when practical.
- Avoid hard-plosive endings: **p / t / k**.
- *"When practical"* is a real qualifier — sometimes content drives the final word and engineering an /n/ ending would force formula. Use judgment; soft endings are the default but not absolute.

Per [feedback_audio_end_clip](../../.claude/projects/-Users-adamlipps-bible-pal/memory/feedback_audio_end_clip.md): hard-plosive endings get clipped by the v3 TTS, and v2 has the same risk in less aggressive form.

## KJV Companion Texture

When writing KJV reflection companions:

- "you" → "thou / thee / thy / thine"
- "yours" → "thine"
- "have you" → "hast thou"
- "feel" stays modern; *"doth it feel"* is acceptable archaic register
- "would it be" stays modern; over-archaizing breaks naturalness

Same scripture-faithfulness discipline as story prose per [BIBLE_TRANSLATION_COMPLIANCE.md](BIBLE_TRANSLATION_COMPLIANCE.md) and the KJV register memory: no Yahweh, no contractions, no `you/your` outside scripture quotes.

## Six-Point Audit Checklist

Before approving any reflection, verify all six:

1. **Specific anchor image present** (a concrete element from THIS story: Red Sea, vessel marred, lamp gone low, etc.)
2. **No generic encouragement language**
3. **No imperative language** ("take a moment", "remember", "consider", "pray about", etc.)
4. **Ends on an earned question OR earned observation** (no closing instruction)
5. **Soft-consonant audio ending** (n/m/ng/l/voiced-z/voiced-v) when practical
6. **Paste-test passes:** could not be pasted onto another story without feeling wrong

All six → benchmark candidate. Five or fewer → rewrite.

## Benchmark Reflections

### Question-form benchmarks

- **1050 Jeremiah 18:1-6** (calm):
  > *The vessel was marred and the potter made it again. What does it feel like to be reshaped by hands you cannot see but have chosen to trust?*
- **1055 Job 1:1-22** (weary):
  > *Everything was taken in a single afternoon — the animals, the servants, the children. What remains when everything you built is gone and the only thing left is the ground beneath you?*
- **1067 Isaiah 6:1-8** (encouraging):
  > *What would it be like to be fully seen — every hidden and imperfect part of you laid bare — and to find that the response waiting for you is not rejection, but an invitation?*
- **1069 Psalm 139:1-18** (hurting):
  > *What does it feel like to be fully known — every hidden wound, every unspoken thought — and to wonder whether being that deeply seen is something you long for or something you fear?*

### Observation-form benchmark

- **1096 John 5:1-15** (weary, Bethesda pool):
  > *Thirty-eight years is a long time to wait for something that never comes… Sometimes the thing we most need is not a better system. It is someone who speaks to us as though change is still possible — even when we have stopped believing it ourselves.*

### Calibration candidate

- **1117 Exodus 14:10-31** Crossing of the Red Sea — to be added after first-write approval (2026-05-31).

## Kid-Friendly Convention

For `kidFriendly: true` stories (the 1041/1042/1043 era), reflections may use a different convention: a paragraph of explanation in the KJV text field followed by a simple direct question. Simpler vocabulary and more everyday-life questions (*"Can you think of a time when…"*) while staying anchored to the story.

Adult reflections (`kidFriendly: false`) follow the benchmarks above without exception.

## Lane Coverage

Per the dual-lane corpus pattern, reflections may have both WEB and KJV variants:

- `reflection_<id>_traditional_web.txt`
- `reflection_<id>_traditional_kjv.txt`

The `meta.reflectionText` field must match one of the files (the `reflection_consistency_test` is lane-aware). Per `feedback_reflection_canonical_lane`, meta should match the file whose lane equals `meta.languageStyle`.

For the 2026-05-31 retrofit, WEB-only first pass is acceptable; KJV companions can be a second sweep.

## History

- **2026-05-22** — Locked. Earlier "5 modes" rule (quiet observation / image callback / soft invitation / emotional afterglow / gentle question with at-least-3-of-5 non-question) rejected after B20-B22 review for keeping the listener at observer distance.
- **2026-05-31** — Refined and elevated to docs. Headline paste-test, explicit no-imperative prohibition with examples, audio craft rules, observation-form acknowledgment (1096), six-point audit checklist added before 120-story reflection retrofit began.
