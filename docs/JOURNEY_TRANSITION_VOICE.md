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
   This is the clause the 2026-06-29 register left generic (*"There's more to his story if you'd like to hear it"*). It may be as vivid as the look-back — as long as it obeys the rules below.

3. **The open door** — *"…or, tell me what's on your heart today"* (adult) / *"…or, what's on your mind?"* (kid).
   **Required.** It signals the third response path (redirect) to a first-time user who would otherwise hear only yes/no. Without it the beat fails Voice Audit Q7. It also keeps the offer an invitation, never an obligation.

The shipped floor benchmark shows the skeleton with a *generic* forward glimpse:

> *"Last time, we walked with Daniel into the lions' den… There's more to his story if you'd like to hear it… or, tell me what's on your heart today."*

Everything below is about earning a forward glimpse worthy of the look-back.

---

## The Load-Bearing Rules

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

**Who may be the "who" (ratified 2026-07-04, first promotion pass):**

> *The relational center is the primary relational subject of the passage. Most often this is a person. When Scripture itself centers God, Christ, or the Shepherd, they are the legitimate relational center.*

This is one consistent rule, not an exception. Scripture itself often centers God rather than a human — *"The LORD is my shepherd"* walks with the Shepherd, not David; Creation centers the Maker. Forcing a human center into those passages would make them feel *less* biblical. The Psalm 23 benchmark below is the exemplar.

### 2. The anticipation-not-cliffhanger rule

Anticipation comes from the person's own path, never from PAL editorializing about how remarkable it is. PAL inherits Pillars 2–4: disappear behind Scripture, never impress, silence is a gift.

Banned outright: *"you won't believe,"* *"wait till you hear,"* *"the most incredible part,"* and any stakes-inflating adjective (*shocking, unbelievable, astonishing*). A trusted friend creates quiet anticipation by telling you the truth about where the story goes — not by promising you'll be amazed.

## Two Rules Discovered at the First Promotion Pass (2026-07-04)

The first exploration pool broke in two ways the original rules did not name. Both failures were caught editorially, and both are now doctrine, **carrying the same weight as rules 1 and 2**. (This is the benchmark process working as designed: benchmarks exist to *discover* rules, not just illustrate them.)

### 3. The next-chapter rule

> *The glimpse always points to the actual next story in the active journey manifest. Never the character's broader biography.*

The failure it prevents: a writer asks *"what's the next famous thing that happens to Daniel?"* instead of *"what is the next story in this journey?"* The exploration pool made this error **three times** in Daniel beats alone — glimpsing the lions' den from a look-back whose actual next story was the friends' furnace, and glimpsing a story the user had *just finished*. If the doctrine's own author trips on it three times, every writer will.

**Procedural form:** draft every beat with the journey manifest open, and name the `sourceStoryIndex → next` mapping in the draft. A beat written from memory of the figure's arc is presumed wrong until checked.

(The Daniel arc also exposed a related coverage case: sometimes the *next* story belongs to **different figures** than the one just heard — Daniel 1 leads to the friends' furnace, where Daniel himself is absent. The relational-center rule still governs: the glimpse centers on whoever the next story walks with.)

### 4. The compressed-theology rule

> *A transition beat must never carry theological weight that only the full story can safely hold.*

The failure it prevents: *"…and still not curse the God who let it go…"* is scripturally defensible — it is Job's own theology — but Job says it *inside* forty chapters that hold the weight. A three-second beat asserting divine permission of loss, in PAL's own voice, with no story around it yet, is theodicy as a hook. The story may carry hard theology because the story has room; the beat does not. When a passage's weight needs the whole story, the glimpse names the *situation* and lets Scripture do the theology.

---

## The Paste-Test

Three questions. Any *yes* to the wrong answer means rewrite. (Mirrors the [Reflection Voice](REFLECTION_VOICE.md) Headline Test.)

1. **Could this look-back be pasted onto a different story without feeling wrong?** → generic callback, rewrite.
2. **Who are we walking with next — is the person the center of gravity, or has the event taken over? And could this glimpse paste onto another person's story?** → event-centered or too abstract, rewrite.
3. **Would this beat feel reverent and complete even if the user never taps yes?** → the offer must stand on its own. Silence and decline are the default (declines don't even advance the cooldown), so the beat has to be a gift in itself, not a setup that only pays off on acceptance.

---

## The Forward-Glimpse Craft

How to make the second clause alive without breaking any of the four rules above.

- **Highest register — anticipation through the person's path, not the named event.** Hint the next chapter through what it will *ask of the person*, not by naming the outcome.
  - *"Daniel is about to discover that faithfulness can carry a person into places no one would choose to go…"* — the furnace is *felt*, never named.
  - *"Joseph's path is about to lead somewhere none of his brothers could imagine…"* — Egypt is hinted, not headlined; *"his brothers"* keeps it unmistakably Joseph's.

- **The grammatical-subject tell (the checkable form of rule 1).** Is the person the subject the sentence is built around, or has the event become the subject? This is stronger than "does it contain a name" — a line can name Daniel and still be a plot hook. Ask where the sentence's center of gravity sits.

- **Name the cost or the question, never the resolution.** A glimpse points at what the person walks *into*, never at how it turns out. *"…the night his own law was turned against him"* ✓; *"…how he walked out of the lions' den unharmed"* ✗ (spoiler, and it kills the reason to listen).
  **The fulfillment clause (ratified at the first promotion pass):** when the next chapter *is* rest or fulfillment — the coverage matrix's "nothing to tease" case — the glimpse may name the rest, because arrival is the whole point and there is no suspense to spoil. Anticipation without a cliffhanger; Simeon is the exemplar. This is a narrow clause for rest/resolution beats only, never a license to name rescues.

- **One image, or one thematic hint — not stacked.** Inherits [feedback_midscene_grounding]. Two vivid images in one clause is one too many for a single spoken breath.

---

## The Production Invitation Families (ratified 2026-07-04)

Production beats use the **enriched register** — the floor register ("There's more to his story…") was the v0 mechanics-proving form and is superseded for all journeys (Adam's product-first ruling at the first slate: with a small beta, qualitative delight outweighs a controlled baseline; floor clips remain archived per never-delete). The enrichment lives in the middle clause, drawn from a small family of approved invitation patterns — **different wording, same voice** — rotated so no journey repeats a pattern back-to-back:

1. **Curious (default):** *"Would you like to hear what happened when Joseph was called before Pharaoh?"* / *"…what happened next…"* / *"…where this story leads…"*
2. **Simple:** *"Would you like to hear what happened next?"* (+ doorway sentence)
3. **Walking (the most Bible PAL):** *"Shall we keep walking with Joseph?"* / *"Shall we stay with Ruth a little longer?"* — this is the relational-voice family the Journey Doctrine's v1.0 amendment already commissioned ("Let's return to David"); two independent design paths converged here. **Question form only (2026-07-05):** the declarative *"Let's stay with Ruth a little longer."* was retired here — spoken aloud it reads as a statement, not an invitation (see the one-clear-question rule). Keep the *"Shall we…"* framing.
4. **Gentle curiosity:** *"Would you like to see where God leads Elijah next?"*
5. **Warm companion (RETIRED 2026-07-05):** *"Whenever you're ready, there's another part of the story waiting."* Retired: it is purely declarative — no question to answer — and it draws attention to PAL rather than the story (Pillar 2). Where its gentleness is wanted, carry it *inside* a question: *"Shall we follow Elijah to the quiet of the mountain?"*
6. **Compound (invite + doorway):** an invitation followed by ONE declarative picture — *"Shall we keep walking with Joseph? He's about to be called before Pharaoh."* Not the ending. Just the doorway.

**The one-question rule (locked, Adam's wording):** every invitation answers only *"Why should I listen to the next story?"* — never *"Why is the next story amazing?"*
- ✗ *"Would you like to hear how Joseph became the second most powerful man in Egypt?"* — destination given away.
- ✓ *"Would you like to hear what happened when Pharaoh's dreams left everyone searching for answers?"* — a doorway.

All four load-bearing rules apply unchanged — the invitation carries the glimpse, so the next-chapter rule, no-resolution rule (with its fulfillment clause), compressed-theology rule, and anti-sensational bans govern the invitation exactly as they governed the declarative glimpse. The open-door tail remains **required**.

**The one-clear-question rule (locked 2026-07-05, on-device finding).** The invitation clause must pose a single clear yes/no question — *"Shall we keep walking with Joseph?"*, *"Would you like to hear what happened when…?"* On-device beta testing exposed the failure the earlier "both forms are valid" allowance missed: a purely **declarative** invitation (*"Let's stay with Ruth a little longer."*, *"Whenever you're ready, there's another part of the story waiting."*) gives the listener nothing to say *yes* to — they hear a statement, then the mic opens for a response they never knew was wanted. The story-announcement that follows a *yes* is spoken by PAL; the invitation that precedes it must therefore **ask**, aloud, in question form. **Place the question last — immediately before the open-door tail** (*"…not knowing whose it is — shall we stay with her a little longer? Or, tell me…"*). A declarative "doorway" sentence sitting *between* the question and the tail buries the ask: on-device (2026-07-05), Ruth's *"Shall we stay with her a little longer? She's gleaning in a stranger's field… Or, tell me…"* did not register as a question at all — the beat trailed off into a statement. If you want a doorway picture, put it *before* the question (Family 6 compound becomes picture-then-invite), never after.

---

## Prohibited Patterns

- **Free-floating plot cliffhanger** — a next-event teaser with no person or place at its center (the golden-statue failure).
- **Engagement hooks** — *"you won't believe,"* *"wait till you hear,"* *"the most incredible part."*
- **Stakes-inflation** — *shocking, unbelievable, astonishing,* or any adjective straining to make the moment bigger than it is.
- **Spoiling the payoff** — naming the rescue, the deliverance, the reconciliation. The glimpse names the situation, not the ending. (Sole sanctioned exception: the fulfillment clause for rest/resolution beats — see the Forward-Glimpse Craft.)
- **Curriculum / system voice** — *"continue the journey,"* *"story 2 of 4,"* *"next up,"* *"you've completed."* PAL speaks of people, never of journey objects or positions.
- **Generic look-back** — *"Last time, we spent time with David."* No scene, no image; interchangeable with any story. Rewrite until the callback could only be this one.

---

## Audio Craft

Transition beats render to TTS as short, expressive clips. They inherit the [Reflection Voice](REFLECTION_VOICE.md) audio rules plus a few specific to this surface.

- **Model: `eleven_v3`** (not turbo). These are short, prosodically delicate utterances; turbo over-clips consonants on short input. Locked, matches the offer/decline cascade for tonal consistency.
- **Soft-consonant ending** where practical — *n / m / ng / l / voiced-z / voiced-v*. Avoid hard plosives (*p / t / k*), which the v3 model clips. See [feedback_audio_end_clip].
- **Ellipsis prosody** — the *"…"* between clauses is a real instruction to the model: a soft, trailing pause, not a full stop. Keep the beat one continuous thought.
- **"Last time," not "yesterday."** "Last time" spans the engine's 1–7-day recency band, so one clip covers the whole window without per-band re-renders.
- **Length** — one continuous spoken thought. **The gate is the breath, not the count:** if it needs a second breath to say aloud, it is too long. Calibration tightened **2026-07-05** after on-device listening: the first shipped slate ran 205–258 characters and felt long spoken, so every beat was trimmed to **~150–210 characters** (one comfortable breath). Treat ~210 as the ceiling, not the target.

---

## The Transition Audit Checklist

Before any beat ships, verify all ten — layered on top of the PAL_VOICE eight-question Voice Audit, which must also pass.

1. **Look-back is scene-specific** — a particular moment from *this* story; the paste-test passes.
2. **Forward glimpse is relationally centered** on the person AND specific enough it could not paste onto another person.
3. **Glimpse names the cost or the question, not the resolution** — no spoiler (rest/resolution beats: the fulfillment clause applies).
4. **No hook, no stakes-inflation** — anticipation comes from the path, not from PAL.
5. **No curriculum / system voice** — no journey objects, positions, or completion language.
6. **Open-door tail present** — the third-path redirect closes the beat.
7. **Soft ending, one spoken thought** — audio-clean, one continuous breath.
8. **Complete and gracious even if the user never says yes** — a gift on its own.
9. **Glimpse verified against the journey manifest's actual next story** — the `sourceStoryIndex → next` mapping named in the draft (the next-chapter rule).
10. **No theological weight the full story alone can hold** (the compressed-theology rule).

And because beats paraphrase Scripture by design: check every glimpse against [BIBLE_TRANSLATION_COMPLIANCE.md](BIBLE_TRANSLATION_COMPLIANCE.md) — a banned translation's signature rendering must never appear in a beat. (This audit caught one at the first promotion pass; the automated fingerprint scan covers verse text, not PAL prose, so this check is on the writer.)

All ten → the beat may **ship**. Shipping is the floor, not the ceiling. Whether a beat becomes a **benchmark** is a further question — see below.

---

## Benchmarks — the section that teaches taste

*The benchmark section is not here to prove the rules — it is here to teach taste. Rules tell a writer what is allowed; benchmarks show what great feels like.*

Two consequences, stated up front:

- **(a) Benchmarks are chosen for instructional value, not for being the prettiest lines.** The set is a *map of distinct editorial problems solved* — not a greatest-hits gallery. **A benchmark is not the same as a favorite.** *The promoted set is not a "best of" collection. It is a teaching corpus selected to span the widest editorial situations with the fewest examples.* (So the answer to "why isn't Moses in here?" is: that is not what this list is for.)
- **(b) The set is illustrative, not exhaustive.** Future writers learn its *principles*. They must never imitate its cadence.
- **(c) Benchmarks are text exemplars.** Audio is rendered only when a real journey uses a beat. Stories render because they ship; reflections render because they ship; benchmarks exist to teach writers. Different artifacts.

### Three questions, three different jobs

A line climbs through three gates, and each gate asks something different:

1. **Audit — may it *ship*?** (the checklist above). Necessary, never sufficient. A checklist can be gamed; passing it *begins* the question "is this worthy?", it does not answer it.
2. **Durability — is it a *worthy line*?** *"Would I still want to hear this six months from now — does it make me smile a little every time?"* Users hear these beats hundreds of times. A benchmark must **reward** repetition, not merely survive it. (This is a higher bar than PAL_VOICE Voice-Audit Q5's "still sound natural on the 100th hearing.") **Guard:** durability must be earned by the *person's story* rewarding repetition — never by PAL's own phrasing being the memorable thing. Pillar 2 outranks the smile test.
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

#### The canonical ladder: Ruth gleaning (promoted 2026-07-04)

A *quiet* story on purpose — the ladder proves the voice on the quiet-transition test, where nothing "big" happens:

- **Technically Correct:**
  > *Last time, we watched Ruth gather grain in the field all day… There's more to Ruth's story if you'd like to hear it… or, tell me what's on your heart today.*
  Person-centered, no spoiler, open door — and utterly flat. This is the acceptable-vs-worthy gap.
- **Good** *(glimpse drifts abstract)*:
  > *Last time, we followed Ruth through the barley field, gathering what the harvesters let fall… Ruth's faithfulness is about to be repaid in a way she never asked for… or, tell me what's on your heart today.*
  *"Faithfulness repaid"* could paste onto half the corpus.
- **Better:**
  > *Last time, we followed Ruth into the barley field, gathering the grain that fell behind the harvesters… Ruth is about to be noticed by the owner of the field, in a kindness she never went looking for… or, tell me what's on your heart today.*
- **Promoted:**
  > *Last time, we followed Ruth into the barley field, stooping for the grain the harvesters left behind… Ruth is about to look up and find the owner of the field already watching — with a gentleness she never asked for… or, tell me what's on your heart today.*
  Why it won: the physical stoop grounds the quiet; *"look up and find… already watching"* is unmistakably this moment, relational, and names the situation — not the marriage it becomes.

*(A Daniel ladder from the same pool was held back at promotion: its rungs violated the next-chapter rule — glimpsing the lions' den, and even the just-finished story, instead of the journey's actual next. It returns only after being rewritten against the manifest.)*

### The voice-fingerprint test

**Strip every proper noun from the promoted set. It should still sound unmistakably like PAL.** If the beats go generic or become interchangeable once the names are gone, the voice is living in the stories, not in PAL — regenerate. This is "uniformity of humility" made checkable, and it stands beside the **paste-test** and the **quiet-transition test** as this document's three signature tests.

### The promoted set (first promotion pass, 2026-07-04 — curated by Adam from a 28-draft pool)

Each beat is labeled with the **editorial problem it teaches**. Adult beats end *"…or, tell me what's on your heart today"*; kid beats end *"…or, what's on your mind?"*

**Exemplar status (read before reusing a beat):** these benchmarks teach the *register* against transitions whose `A → B` labels record an assumed story split — most are hypothetical, since only three journey manifests exist today. Rule 9 of the audit (manifest verification) applies when a beat enters **production**: any benchmark reused in a real journey must be re-verified against that journey's actual manifest, and several here would need re-splitting or redrafting to survive it (the corpus ships some of these pericopes as single stories). A benchmark is a tuning fork, not a rendered clip.

1. **Joseph — the pit → Egypt** · *narrative baseline; hint, never headline*
   > *Last time, we watched Joseph disappear into the dry pit while his brothers sat down to their bread… Joseph's road is about to carry him somewhere none of them could have imagined… or, tell me what's on your heart today.*
   Egypt is never named; *"his brothers"* keeps the glimpse unmistakably Joseph's. The look-back's bread detail (Gen 37:25) is the indelible image.

2. **Ruth — the road from Moab → gleaning** · *woman-centered arc; loyalty*
   > *Last time, we walked the road out of Moab with Ruth, who would not let Naomi go home alone… Ruth is about to stoop in a stranger's field, not knowing whose it is or who is watching… or, tell me what's on your heart today.*
   The glimpse names the situation's unknowns — whose field, who is watching — without ever spoiling Boaz.

3. **Esther — the decree → the throne room** · *solemn; darker next chapter* *(trimmed at promotion)*
   > *Last time, we stood with Esther as she learned what had been decreed against her people… Esther is about to decide whether to speak, though speaking could cost her everything… or, tell me what's on your heart today.*
   Anticipation that cannot honestly promise safety — and doesn't try to.

4. **Elijah — wind and fire → the low voice** · *quiet; anticipation of something QUIETER*
   > *Last time, we stood on the mountain with Elijah while the wind tore past and the fire went by… Elijah is about to hear the thing he came for arrive so quietly he could almost miss it… or, tell me what's on your heart today.*
   The anti-escalation exemplar: the next thing is smaller, not bigger, and the glimpse makes *that* the draw.

5. **Paul — the cell → the joy letter** · *epistle; near-nothing-happens*
   > *Last time, we sat with Paul in the cell where the chain never came off… Paul is about to fill a whole letter with joy, from the one place no one would think to look for it… or, tell me what's on your heart today.*
   Non-narrative genre, no external event at all — the voice survives on the situation's own paradox.

6. **Psalm 23 — green places → the valley** · *no single human figure; God as the relational center* *(valley phrasing corrected at verification; staff imagery restored at curator review)*
   > *Last time, we walked the green places beside the Shepherd, near the water that does not rush… the Shepherd is about to lead us through the valley of the shadow of death — and not once let go of the staff… or, tell me what's on your heart today.*
   The exemplar of the ratified who-may-be-the-"who" rule: the Shepherd is the passage's own center, and *"us"* puts the listener inside the psalm. The staff clause is a craft lesson in itself: the glimpse stays inside the passage's **own symbols** (the staff, Ps 23:4) rather than abstracting to generic closeness — "stay just as close" could fit many passages; the staff could only be this one. (Verification note: an earlier trim read *"the darkest valley"* — the signature NIV/NRSV rendering, a banned-translation fingerprint. Corrected to the public-domain phrase. Kept in this annotation as a live warning: paraphrase drifts toward the translations you've heard most.)

7. **Zacchaeus — the tree → "today"** · *joyful; gospel*
   > *Last time, we watched a small man climb a tree, just to see Jesus pass in the crowd… Zacchaeus is about to hear his own name from below, and a sentence he never expected: today, Jesus is coming to his house… or, tell me what's on your heart today.*
   Names the invitation, not the transformation — joy without spoiling what the visit changes.

8. **Ezekiel — the valley of bones → the breath** · *prophecy/oracle; Scripture's own question as the glimpse*
   > *Last time, we stood with Ezekiel in a valley full of bones, dry as the dust between them… Ezekiel is about to be asked a question with no reasonable answer: can these bones live?… or, tell me what's on your heart today.*
   When the passage itself asks the question, the glimpse may simply hand it on.

9. **Peter — the courtyard fire → the beach** · *aching → grace; restoration*
   > *Last time, we stood by the fire in the courtyard while Peter said, three times, that he never knew the man… Peter is about to meet those same eyes on a beach — and be asked not about the failure, but about love… or, tell me what's on your heart today.*
   The two fires echo without being named; the glimpse names what the meeting *asks*, not how it ends.

10. **Bartimaeus — the roadside → the question** · *the fame-blind exemplar; hopeful*
    > *Last time, we sat with Bartimaeus at the roadside, calling out over the crowd that told him to be quiet… Bartimaeus is about to be asked what he wants, as if it weren't already written all over him… or, tell me what's on your heart today.*
    An unfamous figure outperforming famous ones at promotion — kept partly as the *record* of that.

11. **Simeon — the long wait → the child** · *rest/resolution; nothing to tease*
    > *Last time, we waited in the temple with Simeon, who had been promised he would not die before he saw it… Simeon is about to hold the whole promise in his two arms, and be ready to go in peace… or, tell me what's on your heart today.*
    The exemplar of the **fulfillment clause** (see Forward-Glimpse Craft): when the next chapter IS the rest, the glimpse may name the rest — arrival is the whole point, so there is no suspense to spoil.

12. **Kid Noah — the boat → the first raindrop** · *kid-lane register*
    > *Last time, we helped Noah build a giant boat while everybody else laughed… Noah's about to feel the very first raindrop, and find out he was right to listen… or, what's on your mind?*
    Same voice, same three clauses, simpler words. The kid register is a dialect, not a different language. (*"Right to listen"* names the vindication of listening — the feeling-first payload for a child who just felt Noah being laughed at — while the flood's real payoff, the family's survival, stays unnamed.)
    **Kid-lane shape note:** the *shipped* v0 kid offer follows the Journey Doctrine Kid-Lane Appendix (concrete yes/no line, no verbal third path). This three-clause register with the open-door tail describes the Scale-Horizon per-story beat, and the kid open door must be reconciled with the kid response affordance (feeling cards vs. STT) before any kid beat renders. The parent doctrine governs until then.

**Promotion record (per the fame-blind rule — the record is itself teaching):** at the first pass, the famous figures lost. All three David beats (two adult, one kid) and all three Daniel beats went unpromoted (the Daniel beats for next-chapter-rule violations); Bartimaeus, Simeon, and two Ruths outperformed them. The curator's own first-pass top eight over-weighted quiet beats ("I overweighted quiet stories because I personally loved them") and was rebalanced against the coverage map — recorded because *that correction is the "benchmark ≠ favorite" discipline working*.

Requirements on the promoted *set* (not just each line):

- **Range of feeling, not range of form.** The set spans emotional textures — gentle, mysterious, hopeful, solemn, joyful, quiet, aching — while every beat still sounds like the same humble PAL. *Range of feeling; uniformity of humility.* The fixed three-clause skeleton makes rhythmic sameness the default failure; the set exists to prove the voice has range within it, without ever reaching for showiness.
- **At least one quiet-transition benchmark** — a beat where almost nothing happens (see the quiet-transition test).
- **One editorial problem per benchmark.** Each promoted beat is labeled with the distinct problem it teaches. A blank cell on the coverage map is a prompt to *generate more*, not a line to prettify.
- **Fame-blind.** Judged on the line, not the story's prestige. When a quiet, unfamous beat outperforms an expected Daniel or Joseph favorite, *record it* — that record is itself teaching. Surprise is a symptom of honest judging, never a quota to fill.

### Annotated near-misses (first promotion pass)

Rejected drafts, kept because near-misses teach the rule as sharply as the winners. (Mirrors [feedback_negative_style_library].) *Correct-but-forgettable* lives above, as the ladder's first rung.

- **Wrong next chapter** *(new category, discovered at this pass)*:
  > *Last time, we sat with young Daniel as he turned down the king's table… Daniel is about to learn what it costs to keep praying with the windows open, once the law itself has turned against him…*
  The glimpse describes Daniel 6; the journey's actual next story is Daniel 3 — the friends' furnace, where Daniel himself is absent. Written against the biography, not the manifest.
- **Compressed theology** *(new category, discovered at this pass)*:
  > *…Job is about to lose it in a single afternoon, and still not curse the God who let it go…*
  Job can say it inside forty chapters; a three-second beat in PAL's own voice cannot.
- **Plot teaser** — *"…would you like to hear what happened when a king demanded everyone bow to a golden statue?"* — the event became the subject; Daniel vanished.
- **Abstraction drift** — *"…sometimes the deepest prayers are the ones we can't say out loud…"* — dissolves into a general truth; pastes onto anyone.
- **Spoiled payoff** — *"…Joseph is about to rise to second in all Egypt and save his whole family from the famine…"* — names the resolution; nothing left to listen for.
- **Engagement hook** — *"…you won't believe what she risks next…"* — banned phrase; PAL selling.

---

## Generation and Curation Process

Benchmarks are *discovered*, not decreed. The method is part of the doctrine so it can be repeated every time the set grows.

1. **Generate exploration drafts.** Roughly 20–30 beats, written to be discarded — not "seeds" expected to grow. They live in a working artifact, never in this doc. After a pass completes, the pool is archived under `docs/editorial/history/` as provenance — non-authoritative, and per the hygiene rule below, never used to seed a future round.
2. **Span the coverage matrix** (below). The pool must reach the *edges*, not twenty-five easy narrative-hero beats. A biased pool curates to a biased set.
3. **Curate fame-blind against the three questions.** Promote the strongest 8–12.
4. **Write only the promoted set into this doc**, plus the near-misses, with a dated entry in History.

### The coverage matrix

- **Genre:** narrative, psalm / poetry, prophecy / oracle, wisdom, gospel / parable, epistle.
- **Feeling:** gentle, mysterious, hopeful, solemn, joyful, quiet, aching.
- **The quiet-transition test (the acceptance test for the whole voice):** *Can the voice survive a transition where almost nothing happens?* — Ruth gleaning, Elijah waiting, Jesus praying, Paul in prison before anything changes. If the beats only sing when lions, furnaces, giants, and pits appear, this is not a transition voice — it is a highlight reel. The quiet stories are where we learn whether the voice is genuinely editorial.
- **Other rule-stress cases:**
  - a "next" with no single human figure (Creation, a Psalm) — *resolved 2026-07-04*: no escape hatch needed; God/Christ/the Shepherd is the legitimate relational center when Scripture itself centers him (see rule 1). Psalm 23 is the promoted exemplar.
  - a next chapter that is *darker* — a loss — where anticipation cannot honestly promise something wonderful.
  - a woman-centered arc.
  - a next story that is rest or resolution, with nothing to "tease."
  - *(discovered at the first pass)* a next story that belongs to **different figures** than the one just heard (Daniel 1 → the friends' furnace). The relational-center rule governs — center on whoever the next story walks with — but no promoted exemplar exists yet. **Open cell.**
  - *(still open)* **wisdom literature** — Proverbs/Ecclesiastes have no narrative arc to glimpse; no draft has cracked it. **Open cell.**

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
- **2026-07-04** (first promotion pass, same session) — Adam curated a 28-draft exploration pool: **12 benchmarks promoted** (set rebalanced against the coverage map from his first-pass eight), the Ruth-gleaning ladder locked as canonical, six near-misses annotated. Two new rules discovered through the pass and locked, with the next-chapter rule's procedural form (manifest open, mapping named): the **next-chapter rule** (glimpse targets the journey manifest's actual next story, never the biography — the pool violated it three times in Daniel beats) and the **compressed-theology rule** (a beat never carries weight only the full story can hold — the Job draft). The who-may-be-the-"who" question ruled: God/Christ/the Shepherd is a legitimate relational center when Scripture itself centers him — one rule, no exception list (also recorded in JOURNEY_DOCTRINE's amendment history). Also locked: benchmarks are text exemplars; audio renders only when a real journey uses a beat. Fame-blind record: the famous figures (Daniel, David) lost; Bartimaeus and Simeon won. Trim wordings for Esther and Psalm 23 were applied editorially at write-in. Open cells: figure-shift transitions, wisdom literature.
- **2026-07-04** (curator wording review, same session) — Adam's final pass on the two trim texts: Esther *"when speaking"* → *"though speaking"* (rhythm); Psalm 23 keeps the public-domain valley phrase but **restores the staff imagery** (*"not once let go of the staff"*) over the trimmed *"stay just as close"* — the glimpse should stay inside the passage's own symbols rather than abstracting them. That principle is now recorded in the beat's annotation as a craft lesson.
- **2026-07-04** (production register, same session) — Adam ratified the **enriched register for ALL journeys** (including Daniel — the floor-vs-enriched controlled experiment deliberately traded away: at beta scale, qualitative feedback is the real instrument and the product matters more; floor clips archived, funnel telemetry still measures absolute behavior). Added the **Production Invitation Families** (six rotating patterns; "Shall we keep walking with…" the signature; Family 5 sparing per Pillar 2) and the **one-question rule** ("Why should I listen to the next story?" — never "Why is the next story amazing?"). Both question-form and declarative glimpses valid; open-door tail unchanged.
- **2026-07-04** (verification pass, same session) — A three-lens adversarial verification of the promotion amendment caught and fixed, before commit: a **banned-translation fingerprint** in the Psalm 23 beat (*"the darkest valley"*, the NIV/NRSV signature — corrected to the public-domain phrase; the automated fingerprint scan covers verse text, not PAL prose, so this check now lives in the audit); the **fulfillment clause** ratified into the craft rule, prohibited patterns, and checklist (previously an ad-hoc note on the Simeon beat); the **audit checklist extended 8 → 10** (manifest-mapping check; compressed-theology check) plus the writer-side translation-compliance check; the **length guidance corrected to breath-first** (~145–260 observed across the promoted set); an **exemplar-status preamble** (benchmarks are tuning forks against assumed splits; audit rule 9 governs production reuse); the **kid-lane shape note** (the Kid-Lane Appendix governs the shipped v0 offer; this register describes the Scale-Horizon beat); and a **durability guard** (Pillar 2 outranks the smile test).
- **2026-07-05** (first on-device listening pass, Adam) — The 20 shipped offer clips were heard on-device for the first time. Two corrections, both now locked above: (1) the **one-clear-question rule** — a purely declarative invitation (*"Let's stay with Ruth a little longer."*, Family 5's *"Whenever you're ready…"*) leaves the listener with nothing to say *yes* to; every invitation must now pose a clear yes/no question. This supersedes the 2026-07-04 "both question-form and declarative valid" allowance; Family 3's declarative variant and Family 5 were retired. (2) **Length tightened to ~150–210 characters** — the shipped slate (205–258) felt long spoken. All 20 offers were rewritten to satisfy both and re-rendered (STILLWATER/eleven_v3). Companion fix in the same pass: **12 journey-target framing "announce" lines** (the accept-path line PAL speaks before the story player) were authored + rendered — they had been empty registry stubs, so accepting Joseph/Ruth/Kid-Joseph continuations jumped straight into the story with no announcement.
