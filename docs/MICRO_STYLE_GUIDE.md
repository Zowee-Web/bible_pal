# Bible PAL — MICRO Style Guide

**Status:** v1, derived from Phase 1 discovery pass (2026-05-05/06)
**Scope:** authoring rules for MICRO scripture extracts (50–250-word audio
companions to existing Traditional stories under the B1 variant architecture)

This guide is the operational artifact of Phase 1. It captures what was
learned authoring 3 flagship MICROs across 3 voices and 3 mood registers,
with takes preserved at `assets/stories/audio_archive/2026-05-05_micro_phase_1/`
for future reference.

---

## What MICRO is, in one sentence

A MICRO is a **60-second audio companion** that delivers the emotional
center of a Bible passage — felt, not summarized — under the same parent
storyId as the longer narrative version, served via the 70/30 weighted bias
when a user lands on Short with a high-intensity mood.

A good MICRO feels like *"someone beside you is reminding you of a moment in
Scripture."* A bad MICRO feels like *"here is a short Bible summary."*

---

## Phase 1 anchors (the three MICROs that locked these rules)

| Anchor | Parent | Voice | Text approach | Word count |
|---|---|---|---|---|
| Elijah whisper at Horeb (1 Kings 19:11–13) | story_825 | VOICE_NOAH_PATIENT | Verbatim WEB, em-dash pause before whisper | 113 |
| Jesus calms the storm (Matthew 8:23–27) | story_1090 | VOICE_REVEREND_MICHAEL_C_VINCENT | Pure Matthew 8 verbatim, no Mark cross-pollination | 97 |
| Road to Emmaus (Luke 24:13–35) | story_1115 | VOICE_NATASHA_AFRICAN_AMERICAN | Verbatim WEB, compressed to recognition center | 140 |

All three locked on first or second take. Pattern: **verbatim WEB beat
engineered prose**, even for "warmth without event" stories like Emmaus.

---

## Locked technical defaults

These settings won across all three anchors and are the MICRO standard
unless a specific story argues otherwise:

```json
{
  "model_id": "eleven_v3",
  "voice_settings": {
    "stability": 0.50,
    "similarity_boost": 0.85,
    "style": 0.10,
    "use_speaker_boost": true
  }
}
```

**Notes on each setting:**
- `eleven_v3` — *not* `eleven_turbo_v2_5`. MICRO sits closer to PAL audio
  in emotional terrain than to a regular Short. Story full/short audio still
  uses turbo (separate concern).
- `stability: 0.50` — the load-bearing setting. Lower (0.35) destabilized
  Natasha in Emmaus Take 3; the steadier 0.50 carried the warmth without
  performance. Higher (0.65) flattened Noah's whisper register on Elijah
  Take 1. **0.50 is the MICRO sweet spot across voices.**
- `style: 0.10` — gentle stylization. 0.0 felt sterile; 0.20 (Emmaus Take 3)
  felt performative. 0.10 lands as "speaking with feeling" rather than
  "performing emotion."
- `similarity_boost: 0.85` — preserves voice identity through soft passages
  where lower values let the voice drift.

---

## Authoring rules (what to write)

### Length

- **Target:** 120–150 words
- **Hard ceiling:** 180 words
- **Floor:** there is no floor — Storm calmed landed at 97 words because the
  Matthew 8:23–27 passage IS that length verbatim. **Discipline beats
  hitting a target.** Padding to 120 corrupts the format.

### One emotional beat. One emotional pivot maximum.

A MICRO has *one* moment. Pick it. Compress around it.

| Anchor | The one beat |
|---|---|
| Elijah whisper | Whisper after spectacle |
| Storm calmed | Panic compressed into "great calm" |
| Emmaus | Recognition at the breaking of bread |

If the story you're MICRO-izing has multiple beats (Joseph's saga, Moses
wilderness arc, prophetic sequences), pick one or pass on the anchor.

### Verbatim WEB > engineered prose

**The single biggest Phase 1 finding.** Take 2 of Emmaus engineered the
"hearts burning within them" foreshadowing earlier; Take 3 broke long
sentences into short conversational beats; both lost to the verbatim Take 1.

**The discipline:** trust the WEB rhythm. Compress by *omitting*, not by
rephrasing. The format works because Scripture's own cadence — when
honored — carries weight that prose engineering cannot.

Allowed:
- Omitting verses or clauses outside the chosen beat
- Light pacing edits (paragraph breaks, line breaks)
- Em-dashes for breath beats (see below)

Not allowed:
- Paraphrase to "modernize" or "humanize" the language
- Added commentary or interpretive bridges
- Foreshadowing the emotional pivot
- Theological summaries
- Lesson voice ("And so we learn that…")

### Present tense emotionally

Past-tense narration historically; *immediate* emotionally. Listeners should
feel the moment is being lived, not recapped. Achieved by:
- Direct opening that drops listener into the scene with no setup
- Trust that the parent story carries broader context
- No exposition in the MICRO itself
- No "and so" or "therefore" hinges that re-frame the moment as didactic

### Warmth without event is a first-class principle

Emmaus proved this works. The MICRO format is **not** dependent on dramatic
peaks. Quiet companionship moments — Emmaus, Mary at Bethany, Hagar seeing
the well — can carry MICRO if the listener is allowed to feel without being
told what to feel.

This is MICRO's hidden differentiator vs every other Bible-app product.
Scripture's quiet moments are emotionally underserved. MICRO can hold them.

### Strong opening, no setup

- Drop the listener into the moment.
- The parent story carries backstory; the MICRO does not.
- No "Once upon a time…" framing. No "It came to pass that…"  recaps.

Examples that worked:
- *"The Lord said, 'Go out, and stand on the mountain before me.'"*
- *"When he got into a boat, his disciples followed him."*
- *"Behold, two of them were going that very day to a village named Emmaus."*

### Closing — let the question hang

All three Phase 1 anchors happened to have natural closing questions:
- *"What are you doing here, Elijah?"*
- *"What kind of man is this, that even the wind and the sea obey him?"*
- *"Weren't our hearts burning within us, while he spoke to us along the way?"*

The pattern: **end on the question; do not answer it; do not commentary.**
The question is the landing. The listener's own answer is the resolution.

When the chosen anchor has no closing question (most won't), the equivalent
discipline is: **end on the iconic line, not on commentary.**
- Trust the line. Don't gild it.
- No "And so" / "And the Lord saw" interpretive caps.
- The audio ends. The silence after the audio IS part of the MICRO.

### What MICRO must never sound like

- A Bible summary
- A children's storybook condensation
- A devotional reading with applied lesson
- A preacher's sermon excerpt
- A narrator reading at performance pitch

What it should sound like: a friend, who has read the passage many times,
quietly bringing it to you because they thought you might need it right now.

---

## Pacing & punctuation findings

### Em-dash for breath beats (works)

V3 honors em-dashes as breath/anticipation pauses with surprising
sensitivity. Used effectively in:
- *"And after the fire — a still, small voice."*
- *"…he took the bread, and gave thanks, and broke it — and there was a great calm."*

The em-dash creates space without naming silence.

### Standalone "silence." as a word (doesn't work)

Tried in Elijah Take 1 (turbo) — *"And after the fire — / silence. / Then,
a still, small voice."* — landed awkward. Naming silence makes it
self-conscious. The em-dash on its own carries the silence implicitly.
**Rule: don't write the word "silence" as a standalone beat.** Let the
punctuation do the work.

### Periods between actions (helps in some cases, neutral in others)

Tested in Emmaus Take 3 — *"He took the bread. He gave thanks. He broke it."*
Felt mannered, not human. Lost to verbatim Take 1's *"…he took the bread
and gave thanks. Breaking it, he gave to them."*

Conclusion: **don't break compound WEB sentences into short ones for
"breath."** WEB punctuation is already engineered for spoken cadence.

### Paragraph breaks honored as stanza pauses

V3 treats paragraph breaks as longer pauses than commas, shorter than full
sentence ends. Used effectively to separate the wind/earthquake/fire triple
in Elijah and the bread/recognition pivot in Emmaus.

---

## Voice findings

### Tested and confirmed for MICRO

| Voice | Mood register | What it carries |
|---|---|---|
| **VOICE_NOAH_PATIENT** | calm / silence / restraint | Whisper passages, contemplative arcs, "patience under" tone |
| **VOICE_REVEREND_MICHAEL_C_VINCENT** | gravitas / pivot weight | Panic-to-peace transitions, sermonic moments without sounding sermon-y |
| **VOICE_NATASHA_AFRICAN_AMERICAN** | warmth / female intimacy | Companionship moments, recognition warmth, "warmth without event" |

These three are the proven MICRO-safe pool. Each handles its mood register
distinctively; they do not interchange freely.

### Not yet tested in MICRO format

Every other narrator in `server/voices.json`. The Phase 1 plan listed
backup candidates (VOICE_ELIJAH_SAGE, VOICE_JAMES_HUSKY, VOICE_LILY_WOLFF)
that were not exercised because primaries landed on first or second take.

When Phase 2 expands the MICRO corpus, plan to test:
- **VOICE_LILY_WOLFF** (alternate female intimacy register vs Natasha)
- **VOICE_ELIJAH_SAGE** (alternate male contemplative vs Noah)
- **VOICE_JAMES_HUSKY** (warm pastoral male — different from Reverend's gravitas)
- **VOICE_BRADFORD** (steady male — alternate for pivot moments)
- **VOICE_NOAH_PATIENT** stress-tested on louder material (does patience
  carry brave_courage? joy?)

### Narrator-fit-by-mood (preliminary, Phase 1 evidence only)

| Mood | Recommended primary | Notes |
|---|---|---|
| anxious | NOAH_PATIENT, REVEREND_MICHAEL_C_VINCENT | Both proven; Noah for restraint, Reverend for pivot weight |
| calm_peaceful | NATASHA_AFRICAN_AMERICAN | Proven on Emmaus; alternates untested |
| weary | (untested in MICRO) | Recommend NOAH_PATIENT or VOICE_RUTH_COMFORT* |
| hurting | (untested in MICRO) | Recommend Natasha or LILY_WOLFF for female intimacy |
| joyful | (untested) | Recommend VOICE_MIRIAM_JOYFUL or LILY_WOLFF |
| brave_courage | (untested) | Recommend VOICE_BRADFORD or VOICE_PETER_BOLD |
| grateful | (untested) | Recommend Natasha or VOICE_HANNAH_HOPE |
| encouraging | (untested) | Recommend VOICE_BARNABAS_ENCOURAGER |

\* VOICE_RUTH_COMFORT is currently a PAL-system voice; using it for story
narration would cross system boundaries — flagged for owner decision before
testing.

### Failure modes to watch for during Phase 2

- **Patient register flattening at lower stability** — Natasha at 0.35 lost
  groundedness in Emmaus Take 3. **If a voice sounds "performing emotion"
  at 0.50, the fix is voice swap, not setting drop.**
- **Pastoral register becoming sermon-y** — Reverend at MICRO length stays
  short of sermon delivery only because the closing question lets the
  silence land. On stories without a question close, watch for sermon drift.
- **Warm female voices over-honeying** — none of the Phase 1 takes hit this,
  but with `style` raised above 0.10 it became a risk in Emmaus Take 3.

---

## Architecture (B1 variant model — short version)

A MICRO attaches as a length variant on the parent story:

1. Author `story_<id>_traditional_web_micro.txt` in the parent's directory.
2. Generate audio to `audio_<id>_story_micro.mp3` (or `_take1.mp3` first;
   promote to canonical when approved).
3. Update `meta_<id>.json`:
   - Add `"micro"` to the `lengths` array.
   - Add a `files.micro` block: `{ "storyText": "...", "storyAudio": "..." }`.
4. Update the manifest's `<id>_<mood>_short_traditional` row:
   - `"hasMicroVariant": true`
   - `"microAudioPath": "traditional/<id>/audio_<id>_story_micro.mp3"`
   - `"microTextPath": "traditional/<id>/story_<id>_traditional_web_micro.txt"`
5. The variant resolver in `lib/services/parable_service.dart` picks up the
   MICRO automatically when the bias engages (intense mood + Short bucket +
   70% dice).

The merge IS the feature flag. Don't merge MICRO content until the
listening pass approves it.

---

## Take preservation rule

Every audio generation is preserved. None are deleted. Workflow:

```
audio_<id>_story_micro_take1.mp3   ← first generation
audio_<id>_story_micro_take2.mp3   ← if revision needed
audio_<id>_story_micro_take3.mp3   ← further revision
audio_<id>_story_micro.mp3         ← canonical (= the approved take, copied)
```

Losing takes go to `assets/stories/audio_archive/<date>_<batch>/`. The
archive folder is part of the discovery record — future MICRO authors
should be able to listen to what didn't work and learn why.

---

## Cost expectations

V3 is more expensive per character than turbo. Phase 1 averages:
- Per MICRO generation: ~$1–2 in credits (~110-140 words at V3 pricing)
- Iteration budget: expect 1–3 takes per MICRO during discovery; ~$3–6 per
  finalized MICRO
- Phase 2 (12 stories): rough estimate $40–80 in credits before approval

---

## Open questions for Phase 2

- Does verbatim WEB hold for moods Phase 1 didn't test? (joyful, grateful,
  brave_courage, encouraging)
- Does the closing-question pattern hold when the chosen anchor lacks a
  natural question? What's the equivalent discipline for those?
- At what corpus density does the 70/30 bias deliver enough MICRO frequency
  to feel like a real product feature vs an occasional easter egg?
- How does MICRO behave when the anchor is a single verse (Psalm 23:1, John
  11:35)? Phase 1 anchors all spanned multiple verses.

These are next-batch discovery questions, not blockers.

---

## Phase 1 verdict

The MICRO format works. The format's strength is restraint. The discovery
pass converged faster than expected because the discipline is simpler than
it sounds: **trust WEB, hold the silence, end on the line.**

What scales from here:
- The locked settings (V3 / 0.50 / 0.85 / 0.10)
- The verbatim-WEB authoring discipline
- The take-preservation workflow
- The "merge is the feature flag" release discipline

What still needs Phase 2 to reveal:
- Voice-mood fit for the 5 untested moods
- Whether single-verse passages can carry MICRO
- Whether `tagKeywords` should add the new emotional registers from PR β
  to make the matcher infer them from user input (currently they're
  validation-only)

The 12-MICRO Phase 2 batch can begin against this guide whenever the
listening pass on the 3 Phase 1 MICROs is fully approved and the branch is
ready to merge.
