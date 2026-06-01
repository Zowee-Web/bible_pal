# Bible PAL Reflection Voice

## Purpose

This document locks the editorial voice for every reflection in the Bible PAL corpus. Reflections close each story and pull the listener into the anchor's emotional space. Once 20+ reflections exist under one rule, changing the rule becomes expensive — so the rule is fixed here before the 120-story retrofit begins.

The rule applies to **every active Traditional story**. The earlier V3_PILOT and `shortScripture: true` exemptions were retired 2026-05-31 after the dual-lane KJV backfill brought the corpus to 100% coverage; `reflection_consistency_test.dart` now enforces the contract without exception.

## Reflection Voice Rules

1. Reflections begin from a concrete image, action, tension, or moment in the story.
2. Reflections must remain specific to the story's actual events and imagery.
3. Generic devotional and life-coaching language is prohibited.
4. No mandatory application section.
5. No mandatory closing invitation.
6. Reflections may take one of three valid forms:
   - **Earned Question** (default) — a story-shaped question arising naturally from the narrative
   - **Earned Observation** (rare, ~1/10) — a story-shaped observation arising naturally from the narrative
   - **Image Cascade** (also rare) — a series of 3-5 concrete narrative beats from the story, structured as short paragraphs that walk the listener through the key images in sequence; no question, no observation-statement — the cascade IS the reflection
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

Openings that work (strongest first):

- *"What is it to…"* / *"What is it like to…"*
- *"What does it feel like to…"*
- *"What would it be like to…"*
- *"What remains when…"*
- *"Have you ever…"*
- *"How do you…"* / *"How does X arrive when…"*

**Weaker patterns to avoid:** *"What is the [encouragement / hurt / weariness / anxiety / etc.] of…"* — naming a mood-noun in the stem presumes the listener should feel that mood AND often misses the actual emotional center of the passage. Listener-experience framing ("What is it to…") lets the listener find the actual register the story is asking them into. (Locked 2026-05-31 after Adam diagnosed 1192 Hagar: the story's center is the surprise-of-being-heard, not the hurt that preceded it.)

**KJV-specific:** modern abstract nouns ("encouragement", "anxiety") feel out of register with thou/thee/thy. Prefer KJV-natural nouns when mood-naming is unavoidable: comfort, mercy, grace, strength, thanksgiving, courage, grief, joy, sorrow. Or default to *"What is it to…"* which is register-neutral.

### Earned Observation (rare form, ~1/10)

Reserved for anchors where the emotional landing is so quiet and complete that a question would intrude. Compressed form, **target ~70–90 words / ~30 seconds of audio**. Ends on a specific image or observation — not a question, not an instruction.

**Length cap tightened 2026-05-31** after the first batch of audio renders proved that ~150-word reflections produced 60–75-second audio that felt too long in the player UX. The locked benchmarks below (1096, 1121) were retroactively compressed to ~80 words while preserving their anchor image and quiet landing; the original 150-word form is no longer the target.

### Image Cascade (also rare)

A series of 3-5 concrete narrative beats from the story, structured as short paragraphs that walk the listener through the key images in sequence. No question, no observation-statement, no narrator interpretation — the cascade IS the reflection. Lands on a final image that completes the arc.

Reserved for anchors where the story's images are so iconic that re-presenting them in compressed form IS the reflection. Typically ~80-120 words. Identified as a valid form during the 2026-05-31 mechanical-sync triage when 1111-1115 were found to use this form and pass all six audit points.

Examples:
- **1112 David & Goliath**:
  > *For forty days the Philistine drew near morning and evening. For forty days no one in Israel answered. David chose five smooth stones from the brook. His sling was in his hand. He walked toward the giant with no sword, no armor, no shield. The stone struck Goliath in the forehead. He fell on his face to the earth. The valley lay quiet between the ridges.*
- **1114 Daniel in the Lion's Den**:
  > *Daniel's windows were open toward Jerusalem. He kneeled three times a day, and prayed, and gave thanks before his God, as he did before. The decree was signed. The windows stayed open. The prayer did not change. The king passed the night fasting, with no music and no sleep. In the morning he went in haste to the den and cried out with a troubled voice. Daniel's voice answered from the darkness below.*

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
- **1117 Exodus 14:10-31** (anxious, Crossing of the Red Sea):
  > *The pillar that had led them through the wilderness moved that night and stood behind them, between Israel and the army of Pharaoh. What is it like to be guarded by the very thing that has been leading you on?*

### Observation-form benchmarks

- **1096 John 5:1-15** (weary, Bethesda pool):
  > *Thirty-eight years is a long time to wait for something that never comes… Sometimes the thing we most need is not a better system. It is someone who speaks to us as though change is still possible — even when we have stopped believing it ourselves.*
- **1121 1 Samuel 1:9-20** (hurting, Hannah's silent prayer):
  > *She did not raise her voice. She did not need to. The room was empty enough that her silence was already a kind of speech, and her tears were already a kind of prayer… Not every prayer is answered the way Hannah's was. But every prayer is heard the way Hannah's was — by a God who reads lips that no one else can see move.*

  *Why this is benchmark-grade:* built around a single anchor image (silent lips), stays tightly attached to the narrative throughout, never drifts into generic encouragement, ends on an observation unique to Hannah ("a God who reads lips that no one else can see move").

### Promotion history

- **1117 Red Sea** (question form) promoted 2026-05-31 — first reflection written under the refined spec; first written test of the paste-test discipline.
- **1121 Hannah** (observation form) promoted 2026-05-31 — pre-existing reflection identified during calibration-block triage; chosen over 1122 Thomas because 1121 stays more tightly attached to a single anchor image (silent lips) while 1122 edges toward broader theological observation.

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
- **2026-05-31** (later same day) — Image-cascade acknowledged as a third valid form during mechanical-sync triage of stories 1111-1115. The corpus was found to already contain well-crafted reflections in this form that pass all six audit points but did not fit the original binary. Spec updated to acknowledge the form rather than rewrite the existing good content.
- **2026-05-31** (audio batch 1 calibration) — Observation-form length cap tightened from ~150 words to ~70–90 words / ~30s audio after Adam reported that 60–75s reflection audio felt too long in the player UX. 1036 (was bloated + generic), 1096 (Bethesda), and 1121 (Hannah) refactored to the new cap. Image-cascade and question-form unchanged.
