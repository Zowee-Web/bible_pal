# Bible PAL Journey Transition Voice

> A trusted friend walking beside you — remembering where you have been, and gently pointing toward where the story goes next.

---

## Purpose

This document locks the editorial voice for **journey transition beats** — the short spoken moment where PAL recalls the story you just heard and gently opens the door to the next one in a journey. In the shipped code these are the per-source-story continuation offers (`<journeyId>_offer_<sourceStoryIndex>`); at the Journey Doctrine's Scale Horizon they become the per-story continuation beat (`<sourceStoryId>_pal_continuation`).

The register was first locked at the 2026-06-29 voice audit as three ellipsis-joined clauses. This document keeps that skeleton and adds what it was missing: a rule for making the *forward* glimpse as alive as the callback without breaking the relational, reverent voice PAL is built on — plus a repeatable process for discovering the best examples rather than freezing today's favorites into doctrine.

Once a handful of these beats exist, writers calibrate every future beat against them. So the rule and the method are fixed here **before** the corpus scales to hundreds of transitions.

**North-star image:** a trusted friend walking beside you — remembering where you have been, and gently pointing toward where the story goes next. *Never* a narrator selling the next episode. This is deliberately **not** a movie trailer: trailers exist to maximize anticipation; PAL does not. The event is part of the magic — it just must never outrank the person God is working through.

## Relationship to the other docs

This is a **child of [PAL_VOICE.md](PAL_VOICE.md)**. Every transition beat inherits PAL's Five Pillars and must pass PAL's eight-question Voice Audit. Nothing here overrides PAL_VOICE; it specializes it for one surface.

- **[PAL_VOICE.md](PAL_VOICE.md)** governs how PAL speaks everywhere.
- **[JOURNEY_DOCTRINE.md](JOURNEY_DOCTRINE.md)** governs *when and whether* PAL speaks a transition at all — the continuation cascade, the silence floor, the entry-point split, the cooldown. This doc governs only the *wording* once the doctrine has decided PAL may speak.
- This doc is **not** about the generic mood-flow transition pool (`assets/pal/pal_transition_lines.json`, loaded by `lib/core/pal_transition_lines.dart`). That is a different surface — deliberately generic lines used only in mood flow. Journey transition beats are handcrafted, per-transition, and memory-grounded.

---

## The Transition Beat

A transition beat is one continuous spoken thought in three clauses:

1. **The look-back** — *"Last time, we [active companion verb] [vivid, specific scene]…"*
   PAL was *there with them*: *we walked with*, *we stood in the fire with*, *we watched*. The scene is a particular moment, not a label — *"sat with young Daniel as he chose what was true,"* not *"heard Daniel 1."*

2. **The look-forward** — the glimpse of what comes next.
   This is the clause the 2026-06-29 register left generic (*"There's more to his story if you'd like to hear it"*). It may be as vivid as the look-back — as long as it obeys the two rules below.

3. **The open door** — *"…or, tell me what's on your heart today"* (adult) / *"…or, what's on your mind?"* (kid).
   **Required.** It signals the third response path (redirect) to a first-time user who would otherwise hear only yes/no. Without it the beat fails Voice Audit Q7. It also keeps the offer an invitation, never an obligation.

The shipped floor benchmark shows the skeleton with a *generic* forward glimpse:

> *"Last time, we walked with Daniel into the lions' den… There's more to his story if you'd like to hear it… or, tell me what's on your heart today."*

Everything below is about earning a forward glimpse worthy of the look-back.

---

## The Two Load-Bearing Rules

### 1. The relational-center rule

**Every transition answers one question: *"Who are we walking with next?"*** The person stays at the center of the sentence; the event creates anticipation *around* them. This is the wording-level form of the Journey Doctrine's word-for-word lock:

> *"PAL does not primarily remember stories. PAL remembers the people and places in Scripture that you have spent time with."*

Do not replace the person with a detached plot teaser — and do not shrink the event to a footnote either. The event is part of the magic; it simply must not outrank the person.

There are **two failure modes**, not one:

- **Plot teaser** — the event becomes the subject and the person disappears.
  ✗ *"…would you like to hear what happened when a king demanded everyone bow to a golden statue?"* (Daniel is gone; this is plot navigation, the curriculum voice the doctrine forbids.)
- **Abstraction drift** — the glimpse dissolves into a general spiritual truth that could belong to anyone.
  ✗ *"…faithfulness can lead us into hard places."* (True of Daniel, Joseph, Esther, and half the corpus. It has stopped being *this* person's next chapter.)

A worthy glimpse is **relational AND specific** — unmistakably the next chapter of *this* person's walk.

### 2. The anticipation-not-cliffhanger rule

Anticipation comes from the person's own path, never from PAL editorializing about how remarkable it is. PAL inherits Pillars 2–4: disappear behind Scripture, never impress, silence is a gift.

Banned outright: *"you won't believe,"* *"wait till you hear,"* *"the most incredible part,"* and any stakes-inflating adjective (*shocking, unbelievable, astonishing*). A trusted friend creates quiet anticipation by telling you the truth about where the story goes — not by promising you'll be amazed.

---

## The Paste-Test

Three questions. Any *yes* to the wrong answer means rewrite. (Mirrors the [Reflection Voice](REFLECTION_VOICE.md) Headline Test.)

1. **Could this look-back be pasted onto a different story without feeling wrong?** → generic callback, rewrite.
2. **Who are we walking with next — is the person the center of gravity, or has the event taken over? And could this glimpse paste onto another person's story?** → event-centered or too abstract, rewrite.
3. **Would this beat feel reverent and complete even if the user never taps yes?** → the offer must stand on its own. Silence and decline are the default (declines don't even advance the cooldown), so the beat has to be a gift in itself, not a setup that only pays off on acceptance.

---

## The Forward-Glimpse Craft

How to make the second clause alive without breaking either rule.

- **Highest register — anticipation through the person's path, not the named event.** Hint the next chapter through what it will *ask of the person*, not by naming the outcome.
  - *"Daniel is about to discover that faithfulness can carry a person into places no one would choose to go…"* — the furnace is *felt*, never named.
  - *"Joseph's path is about to lead somewhere none of his brothers could imagine…"* — Egypt is hinted, not headlined; *"his brothers"* keeps it unmistakably Joseph's.

- **The grammatical-subject tell (the checkable form of rule 1).** Is the person the subject the sentence is built around, or has the event become the subject? This is stronger than "does it contain a name" — a line can name Daniel and still be a plot hook. Ask where the sentence's center of gravity sits.

- **Name the cost or the question, never the resolution.** A glimpse points at what the person walks *into*, never at how it turns out. *"…the night his own law was turned against him"* ✓; *"…how he walked out of the lions' den unharmed"* ✗ (spoiler, and it kills the reason to listen).

- **One image, or one thematic hint — not stacked.** Inherits [feedback_midscene_grounding]. Two vivid images in one clause is one too many for a single spoken breath.

---

## Prohibited Patterns

- **Free-floating plot cliffhanger** — a next-event teaser with no person or place at its center (the golden-statue failure).
- **Engagement hooks** — *"you won't believe,"* *"wait till you hear,"* *"the most incredible part."*
- **Stakes-inflation** — *shocking, unbelievable, astonishing,* or any adjective straining to make the moment bigger than it is.
- **Spoiling the payoff** — naming the rescue, the deliverance, the reconciliation. The glimpse names the situation, not the ending.
- **Curriculum / system voice** — *"continue the journey,"* *"story 2 of 4,"* *"next up,"* *"you've completed."* PAL speaks of people, never of journey objects or positions.
- **Generic look-back** — *"Last time, we spent time with David."* No scene, no image; interchangeable with any story. Rewrite until the callback could only be this one.

---

## Audio Craft

Transition beats render to TTS as short, expressive clips. They inherit the [Reflection Voice](REFLECTION_VOICE.md) audio rules plus a few specific to this surface.

- **Model: `eleven_v3`** (not turbo). These are short, prosodically delicate utterances; turbo over-clips consonants on short input. Locked, matches the offer/decline cascade for tonal consistency.
- **Soft-consonant ending** where practical — *n / m / ng / l / voiced-z / voiced-v*. Avoid hard plosives (*p / t / k*), which the v3 model clips. See [feedback_audio_end_clip].
- **Ellipsis prosody** — the *"…"* between clauses is a real instruction to the model: a soft, trailing pause, not a full stop. Keep the beat one continuous thought.
- **"Last time," not "yesterday."** "Last time" spans the engine's 1–7-day recency band, so one clip covers the whole window without per-band re-renders.
- **Length** — one continuous spoken thought, roughly 150–220 characters. If it needs a second breath to say aloud, it is too long.

---

## The Transition Audit Checklist

Before any beat ships, verify all eight — layered on top of the PAL_VOICE eight-question Voice Audit, which must also pass.

1. **Look-back is scene-specific** — a particular moment from *this* story; the paste-test passes.
2. **Forward glimpse is relationally centered** on the person AND specific enough it could not paste onto another person.
3. **Glimpse names the cost or the question, not the resolution** — no spoiler.
4. **No hook, no stakes-inflation** — anticipation comes from the path, not from PAL.
5. **No curriculum / system voice** — no journey objects, positions, or completion language.
6. **Open-door tail present** — the third-path redirect closes the beat.
7. **Soft ending, one spoken thought** — audio-clean, one continuous breath.
8. **Complete and gracious even if the user never says yes** — a gift on its own.

All eight → the beat may **ship**. Shipping is the floor, not the ceiling. Whether a beat becomes a **benchmark** is a further question — see below.

---

## Benchmarks — the section that teaches taste

*The benchmark section is not here to prove the rules — it is here to teach taste. Rules tell a writer what is allowed; benchmarks show what great feels like.*

Two consequences, stated up front:

- **(a) Benchmarks are chosen for instructional value, not for being the prettiest lines.** The set is a *map of distinct editorial problems solved* — not a greatest-hits gallery. **A benchmark is not the same as a favorite.**
- **(b) The set is illustrative, not exhaustive.** Future writers learn its *principles*. They must never imitate its cadence.

### Three questions, three different jobs

A line climbs through three gates, and each gate asks something different:

1. **Audit — may it *ship*?** (the checklist above). Necessary, never sufficient. A checklist can be gamed; passing it *begins* the question "is this worthy?", it does not answer it.
2. **Durability — is it a *worthy line*?** *"Would I still want to hear this six months from now — does it make me smile a little every time?"* Users hear these beats hundreds of times. A benchmark must **reward** repetition, not merely survive it. (This is a higher bar than PAL_VOICE Voice-Audit Q5's "still sound natural on the 100th hearing.")
3. **Instructional value — should it be a *benchmark*?** Does it teach a distinct editorial problem the set does not yet cover? A line can be worthy — durable, loved — and still not earn a benchmark slot if its lesson is already taught. It ships and is loved; the section stays a coverage map, not a favorites list.

### The floor

The shipped `daniel_arc_offer_2` clip, also the ✅-Excellent example in [PAL_VOICE.md](PAL_VOICE.md):

> *"Last time, we walked with Daniel into the lions' den… There's more to his story if you'd like to hear it… or, tell me what's on your heart today."*

Vivid look-back; **generic** forward glimpse. This is the floor the enriched register is meant to rise above — included so the climb is visible.

### The Technically Correct → Good → Better → Promoted ladder

For one or two stories (at least one of them a *quiet* story), the benchmark section shows the same transition at four levels, with a one-line note on why the promoted version won:

- **Technically Correct** — passes every audit point and still has no soul. This is what audit-passing-but-unworthy looks like: the gap between *acceptable* and *worthy of becoming doctrine*, made concrete. It is the single most instructive rung, because learning to feel that gap is exactly what a great editor learns.
- **Good** — alive, but a rule is soft (the glimpse drifts toward abstraction, or the image is a half-step generic).
- **Better** — the rules hold; the beat lands.
- **Promoted** — durable and instructive; it teaches.

### The voice-fingerprint test

**Strip every proper noun from the promoted set. It should still sound unmistakably like PAL.** If the beats go generic or become interchangeable once the names are gone, the voice is living in the stories, not in PAL — regenerate. This is "uniformity of humility" made checkable, and it stands beside the **paste-test** and the **quiet-transition test** as this document's three signature tests.

### The promoted set

> **STATUS: PENDING EDITORIAL PROMOTION.**
> The 8–12 canonical benchmarks are promoted by the curator from a pool of exploration drafts, following the process below. Until that review completes, this section holds only the floor benchmark above. The promoted set is filled in afterward, each entry labeled with the **editorial problem it teaches** (the coverage map) and a one-line note on why it earned its slot.

Requirements on the promoted *set* (not just each line):

- **Range of feeling, not range of form.** The set spans emotional textures — gentle, mysterious, hopeful, solemn, joyful, quiet, aching — while every beat still sounds like the same humble PAL. *Range of feeling; uniformity of humility.* The fixed three-clause skeleton makes rhythmic sameness the default failure; the set exists to prove the voice has range within it, without ever reaching for showiness.
- **At least one quiet-transition benchmark** — a beat where almost nothing happens (see the quiet-transition test).
- **One editorial problem per benchmark.** Each promoted beat is labeled with the distinct problem it teaches. A blank cell on the coverage map is a prompt to *generate more*, not a line to prettify.
- **Fame-blind.** Judged on the line, not the story's prestige. When a quiet, unfamous beat outperforms an expected Daniel or Joseph favorite, *record it* — that record is itself teaching. Surprise is a symptom of honest judging, never a quota to fill.

### Annotated near-misses

The section keeps three to five *rejected* drafts, each with a one-line "why it failed": *drifted abstract / spoiled the payoff / went cliffhanger / event ate the person / correct-but-forgettable.* Near-misses teach the rule as sharply as the winners. (Mirrors [feedback_negative_style_library].)

---

## Generation and Curation Process

Benchmarks are *discovered*, not decreed. The method is part of the doctrine so it can be repeated every time the set grows.

1. **Generate exploration drafts.** Roughly 20–30 beats, written to be discarded — not "seeds" expected to grow. They live in a working artifact, never in this doc.
2. **Span the coverage matrix** (below). The pool must reach the *edges*, not twenty-five easy narrative-hero beats. A biased pool curates to a biased set.
3. **Curate fame-blind against the three questions.** Promote the strongest 8–12.
4. **Write only the promoted set into this doc**, plus the near-misses, with a dated entry in History.

### The coverage matrix

- **Genre:** narrative, psalm / poetry, prophecy / oracle, wisdom, gospel / parable, epistle.
- **Feeling:** gentle, mysterious, hopeful, solemn, joyful, quiet, aching.
- **The quiet-transition test (the acceptance test for the whole voice):** *Can the voice survive a transition where almost nothing happens?* — Ruth gleaning, Elijah waiting, Jesus praying, Paul in prison before anything changes. If the beats only sing when lions, furnaces, giants, and pits appear, this is not a transition voice — it is a highlight reel. The quiet stories are where we learn whether the voice is genuinely editorial.
- **Other rule-stress cases:**
  - a "next" with no single human figure (Creation, a Psalm) — does the relational-center rule survive, or does it need a God/Israel-as-"who" escape hatch?
  - a next chapter that is *darker* — a loss — where anticipation cannot honestly promise something wonderful.
  - a woman-centered arc.
  - a next story that is rest or resolution, with nothing to "tease."

### Generation hygiene (protects the voice over time)

**Every new generation round is seeded from the rules and the coverage map — never from re-reading the promoted lines.** Otherwise the benchmarks breed cadence-clones and the voice narrows with every cycle. Benchmarks are for *comparison at promotion*, never *inspiration at generation*.

---

## Keeping the Standard Living

So it never calcifies into today's favorites:

- **Benchmarks can be demoted, not only promoted.** When a better exemplar of the same editorial problem appears — or a promoted beat comes to feel dated — it moves to a dated "former benchmarks" note with the reason, and the set is periodically re-audited fame-blind. A benchmark section that only grows becomes a museum; one that also prunes stays a standard.
- **Real usage can promote a beat retroactively.** The best exemplar of a problem may be a *shipped* line that everyone realizes, months later, best defines the voice — the way the Reflection Voice promoted the pre-existing 1121 Hannah reflection. Leave that door open. The standard stays tied to reality, not only to authoring sessions.

---

## Scope and Non-Goals

This document governs **wording** only.

- It does **not** decide *when* PAL offers a continuation — that is [JOURNEY_DOCTRINE.md](JOURNEY_DOCTRINE.md) (cascade gates, silence floor, entry-point split, cooldown).
- It explicitly **excludes "alternative futures"** — a single story leading to more than one next story. That is Slice 3 multi-journey arbitration, deliberately deferred. Current doctrine is one continuation per beat (`primaryJourney` only). This spec assumes a single, linear next.

---

## History

- **2026-07-04** — Locked. Formalizes the 2026-06-29 three-clause register and adds: the two load-bearing rules (relational-center; anticipation-not-cliffhanger), the three-part paste-test, the forward-glimpse craft, the three-question benchmark model (ship / worthy / teach), the Technically-Correct → Promoted ladder, the voice-fingerprint test, the quiet-transition test, the generate→curate→promote process with its coverage matrix and generation hygiene, and the living-standard demotion path. Benchmark promoted set is pending the first editorial curation pass.
