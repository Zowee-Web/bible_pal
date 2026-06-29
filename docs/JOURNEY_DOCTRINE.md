# Journey Doctrine

> Locked: 2026-06-28
> Owner: Adam Lipps
> Version: v0 — recognition shipped, single-journey continuation next

## The Doctrine

Bible PAL is not a Bible app with an assistant. Bible PAL is a companion who knows Scripture and knows you.

The Memory Doctrine taught PAL to remember where you have been. The Journey Doctrine teaches PAL to offer to continue — and to let the journey rest the moment a person needs something different.

**Journeys are never the goal.** PAL's goal is never to finish a journey. PAL's goal is to help the person. If today's need is different from yesterday's journey, PAL lets the journey rest without making the person feel guilty for leaving it. The journey is always there. The person always comes first.

This sentence is the test for every product decision the doctrine ever has to make:

> **Stories become PAL's response instead of PAL simply wrapping a story.**
>
> **Every conversation should feel like it could only happen because PAL remembers the person.**

If a feature, principle, or implementation choice contradicts those two sentences, the doctrine forbids it. The journey exists because it makes the conversation possible — not because continuing stories is the objective. When the doctrine and the journey disagree, the doctrine wins.

And one more principle that governs every offer, every gate, every cascade decision the doctrine spawns:

> **A continuation is always an invitation, never an obligation.**

Even when every cascade gate passes, PAL is never required to speak. The doctrine reserves PAL's right to stay silent because silence was the more loving response, even when continuation was technically available. The continuation cascade is the ceiling on what PAL may say — never the floor on what PAL must say.

## The Foundational Move

The conversation is the feature. The journey is the scaffolding that makes the conversation honest across days.

A person opening Bible PAL after listening to Daniel yesterday should not think *"I'm in Journey #14."* They should think *"PAL remembered me."* Then *"PAL remembered Daniel."* Then *"PAL remembered I wanted to keep going."*

The journey engine exists to make PAL feel human. Not the other way around. Every section that follows is in service of that sentence.

## What a Journey Is (and Is Not)

A **journey** is a hand-curated, editorially-shaped sequence of stories that PAL can offer to continue. Each journey carries a type (Narrative, Character, Theme, Teaching, Practice), an ordered list of stories, a per-voice offer line, and editorial intent.

A journey is **NOT**:

- a reading plan
- a streak
- a completion goal
- an algorithmic playlist
- a content classification surfaced to the user
- a measure of spiritual progress
- a thing the user fails at by leaving

Journeys exist inside PAL's memory of the user, not inside the user's accounting of themselves. The user never sees "you are 5 of 14" inside a journey because journeys are not accomplishments.

## Journey vs. Path vs. Mood-Flow

Three coexisting systems with different jobs. The doctrine names them so they never get conflated.

| System | Question it answers | Initiative | Memory of state |
|---|---|---|---|
| **Mood-Flow** | "I need something for today." | User-initiated | Stateless per session |
| **Path** (Feature 50) | "Let me explore Scripture this way." | User-initiated | Read-only taxonomy + completion |
| **Journey** (this doctrine) | "Would you like to continue what we were doing?" | PAL-initiated, user-accepted | Durable per-user state |

**Paths** are taxonomies — passive surfaces for exploration. The user enters a path deliberately and traverses its sequence. The "Next in Your Journey" UI block today is a path affordance, not a journey continuation.

**Journeys** extend paths with two things paths don't have: PAL-initiated conversational offers, and durable per-user "where we left off" state. A journey can wrap an existing path's sequence (e.g., the curated Life-of-Jesus path becomes a Narrative journey when PAL begins offering its continuation by voice). Not every path becomes a journey, and not every journey wraps a path.

**Mood-Flow** is the always-available decline branch from any journey offer. The user telling PAL what's on their heart today is never wrong; it is one of two valid responses to every journey offer.

## The Slice Plan

The doctrine deliberately designs only Slices 1 and 2 in detail. Slices 3–5 are named so the architecture knows where it can grow, but they are not designed until Slice 2 has shipped and produced real user experience.

**Slice 1 — Recognition** *(SHIPPED — PAL Memory Slice 2d + PALs Paths Feature 50)*

PAL can name where the user has been. *"Yesterday we spent time with Daniel."* Silence floor enforced — missing clip means silence, never fallback. Pal's Paths provides the navigation taxonomy and completion tracking that future slices will build on.

**Slice 2 — Single-Journey Continuation** *(FIRST UNSHIPPED SLICE)*

After recognition, when the cascade gates open and the moment is right, PAL **may** offer a single continuation. *"Yesterday we spent time with Daniel. We could continue Daniel's story… or simply tell me what's on your heart today."* Voice-rendered offer line per voice. The user's response either accepts (next-in-journey story plays), declines (mood-flow takes over), or is silence (gentle fallback to mood-flow). Cooldown advances only on accepted continuation. The cascade is the **ceiling** on what PAL may say — never the floor on what PAL must say (see *A continuation is always an invitation, never an obligation* above).

**Slice 3 — Multi-Journey Arbitration** *(FUTURE — NOT DESIGNED)*

When a completed story belongs to multiple journeys, decide whether and how to surface alternates. v1 default for Slice 2: each story carries an editorial `primaryJourney` field and PAL offers continuation only in the primary journey. Cross-journey discovery deferred.

**Slice 4 — Dormancy & Re-Engagement** *(FUTURE — NOT DESIGNED)*

The six-months-later vignette. *"It's been a little while since we spent time with Daniel."* Requires per-journey persistent state (`lastEngagedAt`), additional recency-band carrier audio, and a doctrine on what counts as dormancy.

**Slice 5 — Graduation, Recommendation, & The Guidance Graph** *(FUTURE — NOT DESIGNED)*

What happens when a journey completes. Hand-authored close-of-journey moments. "Next journey" suggestions only when editorial intent is strong. The doctrine will explicitly forbid any badge / streak / completion-ceremony framing that would turn journeys into accomplishments. This slice will also absorb the long-term **scale horizon** (see *The Scale Horizon* below) — the shift from curated arcs to per-source-story continuation beats. Designed in a dedicated review once Slice 2 has produced real user experience.

**Slice 0.5 — Authoring Flow Inversion** *(PREREQUISITE FOR ALL SLICES)*

A workflow change, not a code change. See *Authoring Discipline* below.

## Allowed / Forbidden

**PAL may:**

- Name a story the user has heard, sourced from the verified session log
- Offer to continue a journey when the user's last completed story belongs to a registered journey AND the next-in-journey story has rendered audio
- Let a journey rest when the user signals a different need
- Stay silent when a continuation cannot be offered honestly
- Speak in the first-person plural ("we spent time with Daniel") when the editorial register calls for it — recognition warmth, not narration

**PAL must never:**

- Make the user feel guilty for leaving a journey
- Use streak / completion / "you're 5 of 30" / reading-plan framing
- Offer continuation without rendered audio for both the offer and the next-in-journey story (silence floor)
- Name a journey **type** to the user ("you're in a Theme journey", "your Narrative path")
- Infer the user's emotional state from journey participation ("you've been on a journey through grief")
- Suggest journeys the user hasn't started yet from current memory data — proactive journey suggestion is a separate future product decision, not part of the recognition-and-continuation cascade
- Interrogate a decline ("Why don't you want to continue Daniel?")
- Re-offer the same journey twice in the same 3-day cooldown window

## Continuation, Decline, and Silence (Slice 2 in detail)

### The shape of the offer

The offer is two beats: recognition + invitation.

> *"Yesterday we spent time with Daniel.*
> *We could continue Daniel's story… or simply tell me what's on your heart today."*

Recognition uses the same Slice 2d display-name registry that already ships. Invitation is hand-authored per journey type and per voice. The line is intentionally not yes/no — it tells the user they have two paths and that either is valid, and it lets them respond conversationally instead of compliantly.

### Response handling

PAL classifies the user's response into one of four buckets. v1 implementation is a rule-based heuristic. ML classification is reserved for future slices only if the heuristic proves limiting.

| User response | Bucket | PAL behavior |
|---|---|---|
| "yes" / "continue" / "let's hear it" / "what happened next" | **Accept** | Play next-in-journey story. Advance journey cooldown. Telemetry: `pal_journey_continuation_accepted`. |
| "no" / "today instead" / "something else" / "different" | **Decline** | Fall through to mood-flow. Do NOT advance cooldown. Telemetry: `pal_journey_continuation_declined`. |
| Any mood-word phrase: "I'm anxious" / "I couldn't sleep" / "I'm overwhelmed" / "I need help" | **Implicit decline (mood)** | Route to mood-flow with the named mood. Do NOT advance cooldown. The user expressing mood IS the decline signal — never ask them to also decline explicitly. Telemetry: `pal_journey_continuation_mood_redirect`. |
| Silence / "I don't know" / "hmm" / ambiguous | **Gentle default** | PAL says *"That's okay. Let's find something for today."* — one line, no second offer. Fall through to mood-flow. Do NOT advance cooldown. Telemetry: `pal_journey_continuation_ambiguous_default`. |

### The cooldown contract

The journey-continuation cooldown is the same 3-day window as the Memory recognition cooldown (`PalMemoryEngine.kCooldown`). It advances ONLY when the user **accepts** continuation and the next-in-journey story plays successfully. Any decline branch — explicit, mood-redirect, or gentle-default — leaves the cooldown un-advanced. The doctrine is silence-floor honest: PAL only "burns" cooldown when PAL actually helped.

### Silence at every gate

The continuation gate inherits the Memory silence floor. PAL stays silent (and falls through to mood-flow without ever surfacing the offer) when:

- The user has no registered-journey story in their session log
- The next-in-journey story has no rendered audio for the active voice
- The offer line itself has no rendered audio for the active voice
- The user has explicitly disabled PAL voice (`palVoiceEnabled == false` or `palGreetingsEnabled == false`)
- Any audio resolver returns null at any step

Silence is the default. Continuation is the affirmative-only branch.

## Kid-Lane Appendix

Kid journeys are a distinct shape, not a downscaled adult journey. The doctrine treats them as a separate design surface with their own invariants. The kid lane participates in journeys, but on the kid lane's terms.

### Journey types allowed for kids

**Narrative** (David shepherd → Goliath → King), **Character** (all David stories), **Practice** (heroes doing what the child can do).

**NOT allowed for kids:** Theme, Teaching. Kids parse characters and concrete actions, not abstractions. A theme journey is school; a character journey is bedtime.

### Length cap

3–5 stories per kid journey. Target sweet spot: 3. Never scale adult journey lengths down. A child finishing a 3-story arc and being offered a fresh next-journey beats a child being told they are 5 of 30.

### Cooldown override

**No 3-day cooldown.** **No same-day exclusion.** *(Overrides Continuation Invariant rule 3 for the kid lane only.)* A child listening to the same story twice in one day is not a signal failure; it is bonding. Memory is bonding, and kids bond through repetition. The voice line on same-day re-encounter is *"Have you heard this one?"* — never *"Want to hear what came after?"*

### Offer line

Character-named and concrete. *"Want to hear another David story?"* — never *"Want to explore courage?"* Hand-authored carrier + character clip + follow-up, stitched the same way as Memory audio. Missing clip = silence (same invariant).

### Decline handling

One gentle voice response: *"Okay, let's find something else."* No follow-up question. No *"Why didn't you want to hear David?"* Immediate reset to the feeling-cards picker. The child controls the next direction. Journey progress saves; re-offer can happen tomorrow.

### UI affordances

Kid journeys never surface progress bars, position-in-path, or completion percentages. Those are adult affordances and break the bedtime-companion feeling. A kid journey is invisible scaffolding from the child's perspective — they hear one story, then later PAL gently offers another about the same person.

### Curation

Kid journeys are hand-authored by Adam in `assets/stories/kid_journey_manifest.json`, shaped:

```json
{
  "journeyId": "kid_david_arc",
  "journeyType": "narrative",
  "stories": ["1801_shepherd", "1802_goliath", "1803_king"],
  "offerLines": {
    "VOICE_STILLWATER": {
      "offerCarrierClipId": "kid_offer_carrier_another_story_about",
      "offerCharacterClipId": "kid_offer_name_david",
      "declineClipId": "kid_offer_decline_okay_lets_find"
    }
  }
}
```

No algorithmic derivation from `kid_anchor_registry` tags. Same editorial discipline as `KID_STORY_PROMPT`. The `kid_anchor_registry` provides the natural taxonomy (Moses & Exodus, David, Jonah, etc.); Adam curates which categories become journeys and in what order. Not every category needs to become a journey.

## Authoring Discipline (Slice 0.5 — prerequisite)

This is a workflow change, not a code change. It is a prerequisite for every other slice.

### The old workflow (which failed for Life of Jesus)

```
generate story → register anchor → try to fit into a journey → discover the journey is shallow
```

This is why the corpus has 591 generated stories but only 535 registered anchors, and why the flagship Life-of-Jesus path is only 29% complete despite 71 Jesus stories existing.

### The new workflow

```
define journey → identify anchor gaps → author stories to fill gaps → register anchors → ship journey
```

Stories authored under the old workflow are not retired. They serve mood-flow and existing paths exactly as before. But **new adult story authoring after this doctrine ratifies is journey-driven**. Mood-coverage authoring rests.

### Exceptions

The pause applies to **both adult and kid lanes** equally. New stories in either lane are written only under one of the following exceptions:

- **Journey-driven gaps** — a registered journey requires a story the corpus does not yet contain. The journey defines the gap; authoring fills the gap; the new story carries its journey membership on day one.
- **Quality fixes** — replacing a weak story with a better version of the same anchor, in either lane. Quality fixes are not new coverage; they are corpus health.
- **Editorial promotion** of existing un-promoted stories (the gap between generation and registration) is journey-eligible work that can happen without new authoring.

The kid lane's previously-planned trajectory toward 150 and 200–250 stories under its feeling-anchor doctrine **rests** here. The kid lane currently sits at ~119 stories / 113 anchors; further kid authoring waits on a kid journey identifying a specific gap. Kid quality fixes continue without restriction.

### What this costs

Adam's instinct to "stop expanding the corpus" is right in intent and wrong in literal text. The correct framing: **stop coverage-driven authoring in both lanes; start journey-driven authoring.** New stories will still get written. They will just be written to fill specific journey gaps, not to expand mood or feeling coverage. The shift from corpus-as-trajectory to corpus-as-companion-substrate applies uniformly to adult and kid lanes.

## Implementation Enforcement

The doctrine is enforced by tests that fail at CI time. The doctrine is not enforced by a hope that authors remember it.

**Required tests:**

- Every story listed in a journey has a registered anchor — fail otherwise
- No kid journey contains more than 5 stories — fail otherwise
- No kid journey has type `theme` or `teaching` — fail otherwise
- Every story in a journey carries a `primaryJourney` field referencing a registered journey — fail otherwise
- Voice clips for every offer line and every continuation next-story are bundled per active voice — fail otherwise (mirror the Slice 2c.3 `memory_audio_inventory_validator_test.dart`)
- Journey-continuation cooldown advances only on accepted continuation — fail otherwise (cooldown-not-advanced assertions on every decline branch, mirroring `pal_memory_runtime_test.dart`)
- No telemetry event payload contains the literal journey type as user-visible text — fail otherwise (silence-on-naming-journey-type invariant)

**Required runtime invariants:**

- The continuation cascade is wrapped in the same `_playbackLock` discipline as `PalAudioService.playMemoryPlan` (the iOS -11849 wedge prevention that the Memory wiring's adversarial review caught)
- The continuation engine is a pure function over (session log, journey registry, current voice, current time, `lastJourneySpokenAt`). No IO, no inference, no LLM
- A failed continuation playback never advances the cooldown — silence-floor honesty

## Launch Shape

The first ship of Slice 2 deliberately uses **three corpus-ready journeys** so the doctrine is validated against real material before the flagship Life-of-Jesus pass begins.

### Three journeys at first ship

1. **Daniel Arc** *(Narrative, adult)* — 15 registered anchors already exist covering exile, faithfulness tests, lions' den, visions, and final years. Zero new authoring required. Validates the conversational continuation mechanic against a journey Scripture itself binds tightly.
2. **Learning to Wait** *(Theme, adult — exception)* — ~21 anchors across David's caves (6), Job's trial (6), Hannah (4), Simeon/Anna, Isaiah 40, Exodus manna. Validates theme-driven journeys when the theme aligns with Scripture's narrative rhythms.
3. **Kid David Arc** *(Narrative, kid)* — Shepherd → Goliath → King, already present in `kid_anchor_registry`. Validates the kid-lane appendix end-to-end (length cap, character-named offer, no-cooldown, gentle decline).

### After validation — the flagship pass

Once the three first-ship journeys have produced real user experience, the **Life of Jesus** authoring pass begins:

- ~10 new adult stories
- 9 anchor registrations
- Strict curation against the 14-point arc: Birth → Early Life → Baptism → Temptation → Disciples Called → Miracles → Teachings → Encounters → Transfiguration → Triumphal Entry → Last Supper → Crucifixion → Resurrection → Ascension

This is the eventual flagship. Naming it openly here keeps authoring direction oriented toward it even while the smaller journeys ship first.

## The Continuation Invariant

Seven rules that govern every continuation offer PAL ever makes. **The adult lane follows all seven verbatim. The kid lane overrides rule 3 only** (no 3-day cooldown for kids) per the Kid-Lane Appendix; every other rule applies to both lanes.

1. **A continuation is always an invitation, never an obligation.** Even when every other rule below is satisfied, PAL retains the right to stay silent if silence is the more loving response. The rules below are the gates the offer must clear before it CAN be made — never gates that force the offer to BE made.
2. **PAL may offer continuation only when ALL THREE conditions hold:** a registered journey exists, the user's last completed story is in that journey, and the next-in-journey story has rendered audio for the active voice.
3. **PAL never offers continuation for the same journey twice in 3 days** (the same cooldown as Memory recognition).
4. **PAL never offers continuation for a story that has not been registered in a journey,** even if the next story technically exists in the corpus.
5. **PAL accepts any non-affirmative response as gentle decline.** No interrogation. Mood phrases are decline by default.
6. **PAL never names the journey type to the user.** "Daniel's story" is fine. "The Narrative path you're on" is forbidden.
7. **When confidence is low, PAL says nothing about journeys and serves today's mood.** Silence is the default. Continuation is the affirmative-only branch.

## The Scale Horizon

The doctrine ships at v0 with **two journeys** (Daniel Arc, Kid David Arc — 7 rendered clips total). This is intentionally small so the cascade can be validated against real user experience before scaling.

The long-term vision is fundamentally larger.

**Every story in the Bible PAL library eventually gets its own PAL continuation beat.** At current corpus size (~535 registered anchors and growing) this scales to **~800–900+ unique PAL journey clips per voice**, with growth as the library grows.

This is a different product shape than "a small set of curated arcs that PAL occasionally offers to continue." Slice 2's cascade engine, audio resolver, response classifier, and dispatch logic are general-shape and survive the transition. Several today-decisions become tomorrow-constraints if the scale shift is forgotten:

- **Clip ID convention shifts.** `<journeyId>_offer_<sourceStoryIndex>` is correct for arc-positioned offers. At scale the natural key is `<sourceStoryId>_pal_continuation` — keyed off the source story, not its arc position. The "what comes next" becomes editorial metadata on each story, not a position lookup. Today's convention is a v0 simplification.
- **"Always candidate, mostly silence" replaces "rarely candidate, usually fire."** When every recent completion has a registered continuation beat, the cascade fires on every session unless the cooldown gate holds. **Cooldown becomes load-bearing**, not optional. The continuation invariant's silence floor is the only thing keeping PAL from offering something every single time the app opens.
- **R2, not bundle.** ~800 clips × 3 voices × ~100KB ≈ 240MB. Above the bundle ceiling. Journey clips at scale follow the PAL Memory R2 pattern, not the bundled-asset pattern Slice 2 first ship uses.
- **Authoring discipline transfers.** At ~10 clips, hand-authoring is fine. At 800, the editorial workflow needs the same shape `REFLECTION_VOICE.md` already established — template + per-story scene-imagery + `PAL_VOICE.md` Voice Audit gate — so that voice consistency holds across thousands of utterances written across years.

The current `Journey` data model is a stepping stone, not the destination. Slice 5 (above) absorbs the shape transition. The doctrine forbids baking the v0 implementation deeper into runtime code than necessary. When a refactor touches the journey system, the test is:

> *Does this change keep the conversation possible across both shapes — 10 curated arcs and 800 per-story beats — or does it freeze the system into one of them?*

If the answer is *freezes*, the doctrine forbids the refactor.

## Origin

Story Journeys grew from PAL Memory Slice 2d's recognition mechanism and Adam's instinct that recognition without continuation was incomplete — *"PAL feels alive only when she remembers and offers a way forward."*

The 2026-06-28 design conversation that this document records named the underlying philosophical move:

> **"Stories become PAL's response instead of PAL simply wrapping a story."**

The doctrine deliberately ships at v0 in narrower scope than the PAL Memory Doctrine. The reason is Adam's instruction: *"Don't design Version 3 before we've designed Version 1."* Slices 3–5 are named as future but not designed. They grow when Slice 2 ships and produces user experience the doctrine can learn from.
