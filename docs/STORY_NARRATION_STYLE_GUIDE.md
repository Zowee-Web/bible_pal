# Story Narration Style Guide

> This document is currently authoritative for human-guided story generation and regeneration. Future Stage 2 work may wire prompt-generation systems directly to this guide.

Bible PAL stories are written for **audio**, not reading. Prose rhythm — not the voice model — determines whether narration sounds oral or robotic. The same voice will sound human or mechanical depending entirely on the cadence on the page. This guide is the operational floor.

When this guide conflicts with `_TRADITIONAL_HARD_RULES`, `_NARRATION_STYLE_GUARDRAILS`, `_NARRATION_TRADITIONAL_EXTRA`, `_ANTI_REPETITION_RULES`, `_KJV_AUDIO_RULES`, or `_KID_SAFETY_RULES` in [scripts/story_factory/claude_prompts.py](../scripts/story_factory/claude_prompts.py), **this guide is authoritative** for human-written prose. The inline prompts will be wired to this doc in Stage 2.

---

## 0. Two Governing Laws

These sit above every mechanical rule below. When a craft rule and a law conflict, the law wins. They map to how authoring actually goes: first find the register the passage is already in (Law 1), then hold faithfulness in both directions as you write it (Law 2 — the guardrail that keeps Law 1 from drifting into invention).

### Law 1 — Find the human register already inside the text

Before writing, ask: **what kind of human speech is this Scripture?** — testimony, prayer, lament, praise, warning, wonder, confession, exhortation, remembrance. Write in *that* register.

- Do **not** flatten it into a summary; do **not** invent a scene to dramatize it.
- The register comes from **selection, emphasis, spacing, and the text's own voice** (John 1's "we saw his glory" — first-person, past, astonished), never an added frame. **Register, not invention.**
- Wrong question: "How do I turn this into a story?" Right question: "What experience is this Scripture already producing, and how do I let the listener have it?"
- Hardest for idea-heavy passages (John's prologue, the epistles, contemplative psalms, the "I AM" sayings), where the writing must carry far more emotional weight than an action narrative.

### Law 2 — Dual Faithfulness

A Bible PAL story must be faithful **both** to what the Scripture says **and** to the human experience through which the Scripture reaches the listener. Neither may be bought by sacrificing the other. This is the guardrail on Law 1: the register must be the passage's *own*, surfaced — never one imported to make it land.

- Faithful-to-text but not faithful-to-experience → **complete but emotionally distant**: an accurate summary the listener learns from but wouldn't choose to finish.
- Faithful-to-experience but not faithful-to-text → **invention**: a scene, emotion, or framing the passage does not contain, added to make it land.

*Cross-cutting:* Dual Faithfulness also governs [REFLECTION_VOICE.md](REFLECTION_VOICE.md), the journey voices, and the kid lane (each cross-references it here). If it comes to be cited across many systems, promote it to its own rank in the CLAUDE.md Document Hierarchy; until then this guide is its home.

### Worked example — John 1:1-18 (story 1562)

The prologue is already *testimony shaped by wonder*: an eyewitness looking back. Written primarily as a doctrinal summary, it came out complete but emotionally distant. Written in the testimony already present in the passage — the incarnation set as a standalone hinge, the cosmic opening establishing the height it falls from, the residue aimed at the realization *"the God who made everything came here"* — it became an eyewitness sharing what he had seen, and a story someone keeps listening to. Nothing was invented; the change was entirely register. The issue was never that the passage makes doctrinal claims (it does) — it was that John 1 is *already* testimony, and the adaptation worked when it reflected the passage's own voice.

### Acceptance audit (the human-run gate)

Neither law is machine-checkable. Run this before approving a story:

1. **Register named** — one word for the passage's human speech-act. If you can't, you're about to write a summary.
2. **No invention** — every image, emotion, and frame traces to the passage.
3. **Residue test** — an hour later, what does a first-time listener remember? A realization ("God came and lived with us") beats a line beats "there was something about the Word."
4. **Keep-listening test** — would someone who once found the Bible inaccessible want to press play on the next story?

### Enforcement · Revision · Rank

- **Gate:** `checklist_in_doc` — the four-point audit above (not test-enforceable; per [DOCTRINE_OF_DOCTRINES.md](DOCTRINE_OF_DOCTRINES.md), reverence is not a checklist property).
- **Rank:** foundational within this guide (#7); Law 2 is cross-referenced from the reflection and journey-transition voice docs.
- **Revision:** see History below.

### History

- **2026-07-18** — Both laws discovered and locked while rewriting story 1562 (John 1 prologue) from a doctrinal summary into the passage's own testimony register — the passage that forced the text-versus-experience distinction into the open.

---

## 1. Sentence Rhythm

Vary sentence length deliberately. Three same-length sentences in a row reads as anthological flatness — the TTS will deliver three identically-shaped beats.

- Bad: `Noah was a good man. He walked with God. He had three sons.` (three sentences, similar length, all subject-first)
- Good: `Noah walked with God. He had three sons — Shem, Ham, and Japheth.`

Mix at least one long-with-a-clause sentence into every paragraph of short ones, and vice versa.

## 2. Breath & Pause Rules

Each sentence boundary is a deliberate breath placement. Each comma triggers a hidden micro-breath the listener feels. Reduce comma stacking.

- Bad: `He picked up his tools, sharpened them, walked to the workshop, and began.` (four comma-breaths in one sentence)
- Good: `He picked up his tools. He walked to the workshop.`

**Watch for appositive comma stacks** — `X, a Y of Z under W, who…` creates a mid-sentence breath reset. Split at the appositive: `X, a Y of Z under W. He…`.

## 3. Mid-Scene Grounding

One to two physical details per moment. If a sentence adds a second image, cut one. Avoid environment-stacking (light + silence + atmosphere in sequence).

- Bad: `They sat at the table. The bread lay broken. The chair across was empty. The room was quiet.`
- Good: `They sat at the table. The bread lay broken before them.`

If it feels like a camera lingering after the action stopped — cut.

## 4. Emotional Compression

One emotional beat per paragraph. Do not stack emotional summaries. Show emotion through action, not labels.

- Bad: `He was afraid. His hands trembled. His voice shook. He could not go on.`
- Good: `He was afraid. He spoke anyway.`

## 5. Paragraph Shape

No three consecutive paragraphs with the same structural pattern (e.g., setup-detail-conclusion repeated). Vary openers — not every paragraph should start with the subject. Vary paragraph length: a short paragraph (1–2 sentences) between two longer ones gives the listener a breath.

## 6. Dialogue Restraint

Direct quotes only when the speech *is* the action. Long quoted speech is broken into beats interleaved with physical reactions, movement, or environment.

- Bad: six lines of continuous quoted speech
- Good: `He spoke. The hall grew still. He spoke again, louder now.`

For sustained-speaker oracles or sermons (Joel, Isaiah, Peter, Stephen, etc.), introduce the speaker **once**, then let subsequent quoted paragraphs stand without `he said` tags. Re-tag only at major shifts.

## 7. Ending Cadence

End on a single physical, visual, or audible moment. No abstract restatement, no thematic summary, no second thought.

- Bad: `He trusted God, and he obeyed.`
- Good: `The bread lay broken upon the table. He was not there.`

Prefer nouns and actions over adjectives in the final line — adjectives are where cinematic tone sneaks back in.

If a closing sentence ends in `realized`, `understood`, `trusted`, `obeyed`, or `knew` — rewrite.

## 8. Anti-Exposition Rules

Never explain cultural context, define terms, or comment on Scripture meta-narratively.

- Forbidden: `A covenant was a strong, unbreakable agreement.` (definition)
- Forbidden: `Pitch was a dark, sticky material…` (concept explanation)
- Forbidden: `The Bible says…` / `Scripture tells us…` / `The story shows…` (meta-commentary)
- Forbidden: `Jews did not pass through Samaria…` (cultural context interjection)

If a concept appears (covenant, yoke, pitch, robe), show understanding through physical reactions, behavior, posture, environment — never definition.

## 9. Transition Control

Between beats, use action or movement, not summary connectives. `After that,` / `Soon,` / `Eventually,` as defaults are flat. Let the action carry the time-jump.

- Bad: `Soon, the people gathered.`
- Good: `By morning the courtyard was full.`

## 10. Length Discipline

The **Traditional (adult)** row below is a **non-authoritative summary**. Adult Traditional
bands are specified in
[STORY_FACTORY.md §5](STORY_FACTORY.md#5-story-length-system-revised-2026-07-19--adr-030),
which is authoritative — if this row ever disagrees with it, STORY_FACTORY.md wins. Short is
the default expected version; Full and Long are created only when the approved anchor
honestly supports them (ADR-030).

The **Traditional (kid)** row is unchanged and is not affected by ADR-030.

| Mode | Short | Full | Long |
|---|---|---|---|
| Traditional (adult) | 300–500 | 501–900 | 901–1500 |
| Traditional (kid) | 250–600 | 601–1200 | 1201–1800 |
| Creative (adult) | 200–400 | 401–700 | 701–1500 |

Reflection: 120–220 (adult) / 60–120 (kid).

- Psalms may go below 300w if the full passage is included. Do not extend with framing.
- Mixed-tone passages (oracle + narrative, poem + discourse) split into separate stories — do not merge to pad word count.
- Single literary units (psalm, oracle, patterned list) must include the full arc; never truncate at the turning point.
- Do not expand to "improve." Word count grows only when actual observable scene detail is added.

## 11. Robot Warning Signs

Self-audit checklist before saving prose:

- [ ] Three or more consecutive sentences of the same length
- [ ] Three or more consecutive sentences starting with the same word/structure
- [ ] Any `Pitch was…` / `A covenant was…` / `The Bible says…` style meta or term-definition
- [ ] Any sentence closing the story on `realized` / `understood` / `trusted` / `obeyed` / `knew`
- [ ] Any paragraph that adds a second physical image after the first one already lands
- [ ] Any imagery (sky, light, sun, clouds, stars) appearing more than twice in the story
- [ ] Same sentiment word (`gentle`, `peaceful`, `safe`) restated across paragraphs
- [ ] Two emotional beats stacked in one paragraph
- [ ] Modern-language renderings where traditional biblical phrasing exists (e.g., `utility belt` instead of `belt of truth`, `ship` where the figure is `ark`)
- [ ] Long quoted speech with no intervening narration / action

## 12. Human Narration Test

Listen, do not read.

- Play the existing audio (or read aloud at narration pace — *not* silent-reading pace).
- A paragraph that requires re-reading to parse on first pass is wrong. The listener cannot re-read.
- If you hear the model insert a mid-sentence breath in an awkward place — that is a comma-stack signal. Rewrite the source prose.
- Each paragraph should feel like *someone telling the story out loud*, not *someone reading a page*. If it sounds anthological, it is wrong.

---

## Kid-Story Addendum

When `kidFriendly: true`:

- Sentence average ≤ 12 words (still varied within that ceiling).
- 5-part structure: peaceful opening → gentle situation → faith in action → quiet resolution → gentle positive ending.
- Banned vocabulary per `_KID_SAFETY_RULES`: `creature(s)`, `chase(d)`, `flee`, `kingdom`, `throne`, `crown`, `monster`, `beast`, `enemy`, `death/dead`, `battle`, `sword`, `terror`, `prowl`, etc. Use gentle alternatives (`animals`, `followed`, `village`, `living things`).
- Tone: never startling or suspenseful. Comforting throughout.
- All other rules in this guide still apply.

---

## Source Provenance

This guide consolidates rules previously scattered across:

- `_TRADITIONAL_HARD_RULES`, `_NARRATION_STYLE_GUARDRAILS`, `_NARRATION_TRADITIONAL_EXTRA`, `_ANTI_REPETITION_RULES`, `_KJV_AUDIO_RULES` in [scripts/story_factory/claude_prompts.py:15-193](../scripts/story_factory/claude_prompts.py#L15-L193)
- Duplicate ruleset in [scripts/story_factory/generate_traditional_story.py:82-122](../scripts/story_factory/generate_traditional_story.py#L82-L122) (Stage 2 dedup target)
- Memory feedback entries: `audio_segmentation`, `midscene_grounding`, `story_endings`, `traditional_story_style`, `no_modern_language`, `complete_arcs`, `split_mixed_tone_passages`, `psalm_word_floor`

**Stage 2 follow-up:** wire `claude_prompts.py` to source from this guide so prompts and human writing share one source of truth.
