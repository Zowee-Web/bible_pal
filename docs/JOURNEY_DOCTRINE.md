# Journey Doctrine

> Locked: 2026-06-28
> Amended: 2026-07-03 — v1.0 (identity + relational memory + three layers)
> Owner: Adam Lipps
> Version: v1.0 — recognition shipped; single-journey continuation in flight; long-horizon layers named

## Identity

> **Journeys are not the mechanism by which users get to the next story. They are the mechanism by which PAL's memory of shared reading becomes narrative continuity.**

Every product decision this doctrine ever makes flows from that sentence. Contradict it and the doctrine forbids the decision.

## The Relational Memory Principle

> **PAL does not primarily remember stories. PAL remembers the people and places in Scripture that you have spent time with.**

This is the memory-model principle, not a voice preference. Its consequences ripple through the rest of the doctrine:

- **Continuation is relational, not indexical.** *"Let's return to David."* Not *"Continue Journey #14."*
- **Discovered Journeys (Layer 2) surface through co-visitation of people, not story IDs.**
- **Personal Journeys (Layer 3) are seasons with figures, not sequences of stories.**
- **PAL's memory is of the person you were walking with last time**, not of a row in the manifest.

The librarian metaphor in [PAL_VOICE.md](PAL_VOICE.md) already asks *"is this the right story for who this person seems to be right now?"* This principle sharpens it: PAL remembers who you walked with, and that is what continuation reaches back for.

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

## The Editorial Purpose of a Journey

> **A Journey exists whenever remembering changes the experience of the next story.**

That is the litmus test. When considering whether a set of stories should be a Journey, ask *"does remembering matter here?"* If yes, it's a Journey — regardless of length or ordering. If no, it's simply more stories. The point is not curation; the point is whether PAL's memory of what came before changes how the next story lands.

## The Three Layers of Journey

A Journey can exist at three layers. **Only Layer 1 is a v1.0 commitment.** Layers 2 and 3 are named to prevent architectural paint-into-corner, not promised as launch features. All three share one substrate: PAL's memory of who the user has walked with.

- **Layer 1 — Editorial Journeys** *(what ships)*. Curator-created sequences: Joseph, David, Life of Jesus, Kid David Arc. Hypotheses that remembering will change how each subsequent story lands.
- **Layer 2 — Discovered Journeys** *(architectural direction, not built)*. Someday PAL may notice patterns in aggregate user movement — Gideon → Deborah, Elijah → Elisha. Slice 5 territory.
- **Layer 3 — Personal Journeys** *(the horizon, not built)*. The shape of one specific user's walk — Daniel, then Job, then Elijah — remembered as a season, never interpreted. Slice 5 territory.

**Doctrinal implication.** Every Layer 1 decision must preserve the possibility of Layers 2 and 3. Rigid Editorial Journeys (forced order, curriculum voice, story-ID-indexed continuation) close off the later layers. Relational-memory framing keeps the door open.

## What a Journey Is (and Is Not)

A **journey** is the memory of walking through Scripture together — held on the curator's side as a hand-shaped sequence with a type and editorial intent, felt on the user's side as remembered warmth.

A journey is **NOT** a reading plan, a streak, a completion goal, an algorithmic playlist, a content classification surfaced to the user, a measure of spiritual progress, or a thing the user fails at by leaving.

Journeys exist inside PAL's memory of the user, not inside the user's accounting of themselves. The user never sees *"you are 5 of 14"* because journeys are not accomplishments. What the user experiences is *"Last time we spent time with Daniel…"* — memory, not curriculum.

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

## Entry-Point Split

Locked 2026-06-30 after the first on-device smoke test of Slice 2.

> **PAL button = conversation. Mood buttons = shortcuts.**

The journey cascade — memory beat, offer audio, STT capture, dispatch — fires **only from the PAL button**. Mood-button taps go straight to the mood-flow story with no journey audio, no STT, no branching.

The doctrine test that produced this: *if a user taps "Anxious," they have already communicated today's intent. Interrupting with "Remember Daniel…?" doesn't help them accomplish what they just asked for.* Two entry points, two roles:

- **PAL button** — *"Talk with PAL."* The place where PAL remembers, offers continuation, listens, and guides.
- **Mood buttons** — *"Take me straight to Scripture."* Instant. No memory beat. No STT. The existing transition + framing intro stays — those are storytelling rhythm, not conversation.

This mirrors the librarian in [PAL_VOICE.md](PAL_VOICE.md): PAL is the librarian when you ask for help; the mood buttons are the shelves you've chosen to walk to yourself. The split is a UX guarantee, not a rule about what's possible — technically the cascade could fire on any entry, but doctrine forbids it because it dilutes what "tapping PAL" means.

Kept the door open for future revision: if beta testers report they want journey recognition on mood buttons after all, the runtime is still capable — the mood-button path just calls into it with the appropriate params. Short-variant offer clips remain bundled per the never-delete-audio rule. The lock is in the code path (`_handleMoodButtonTap` goes straight to `selectStoryAndOpenPlayer`), not the primitives.

## Journey Types (architecture + behavioral principle)

Six kinds. Type is a **behavioral lens**, not a locked table.

- **Narrative** — sequential arcs where order carries meaning. *Joseph*, *Life of Jesus*.
- **Character** — episodes with one figure, each largely self-contained. *Daniel*, *David*, *Peter*.
- **Theme** — varied stories bound by shared feeling. *Waiting on God*, *Comfort*.
- **Teaching** — parables, sayings, discourses. *Parables of the Kingdom*.
- **Practice** *(kid-lane)* — patterns the child can enact. *Being Brave*, *Being Kind*.
- **Collection** *(new)* — curated groupings that share a lens. *Women of the Bible*, *Miracles of Jesus*, *Psalms of Comfort*. Deliberate sets, neither narrative nor character.

> **Journey type influences how PAL introduces, continues, and revisits stories. The exact behaviors of each type emerge through editorial testing rather than being frozen prematurely.**

Curator override: individual Journeys may depart from their type's typical behavior when editorial judgment calls for it. Type is a lens, not a straitjacket.

## Where a Journey Begins — Three Paths

Journeys begin the way stories begin: the user encounters one. Three paths, chosen by the user's state.

**(a) First use — onboarding.** A new user has no memory yet. The obvious temptation is to override the first tap and route into an onboarding Journey's story 1. **Doctrine rejects this.** The first tap — PAL button or mood button — is sacred. A first-time user who says *"I'm anxious"* deserves an anxious-story answer, not *"here's Story 1 of our onboarding Journey."* Empty-memory is a real problem; the solution is to **add** something (a self-introduction beat, a post-first-story invitation, or a mood-aware silent preference for onboarding-Journey stories that genuinely fit the tap), never to hijack the first request. Doctrine locks the constraint. The specific onboarding solution is editorial experiment.

**(b) Mood-flow selection (steady state).** Entry-Point Split remains locked: mood buttons never fire the cascade. Beyond that, **mood-flow selection MAY take Journey structure into account when doing so improves the editorial experience, while always respecting the user's expressed intent.** Whether to silently prefer a Journey's next-unheard story is a hypothesis to test, not a lock.

**(c) User-initiated selection (Paths, search, favorites).** PAL respects the pick — completely. If the user chose Daniel 6 from Paths, they get Daniel 6, not Daniel 1. PAL's memory tracks where they left off from THAT choice. Future territory (Slice 3) may allow a gentle *"this story begins earlier — would you like to start there?"* invitation on curator-flagged stories. Silence or "no" plays the selected story.

All three preserve user agency. Even on first use — especially on first use — the user's expressed intent leads.

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

### Journey Continuation Voice — after "yes"

The mood-flow transition-line library was authored for **discovery**; playing a discovery transition after Journey accept is a category error. The Relational Memory Principle governs what the accept-path voice sounds like: continuation is about returning to a person, not resuming a Journey object.

**Direction (Round 6):** ship a small library of accept-context transition lines in relational voice. Story-specific framing alone is too bare after "yes"; a short transition line before framing gives the accept path warmth without pretending to have matched a mood.

Initial commissioned line set (curator may add/edit):

- *"Let's return to David."* *(person-specific, character/narrative)*
- *"Here's what happened next."* *(sequence-agnostic, narrative)*
- *"Picking it back up with him."* *(pronoun form for repeat mentions of the same figure)*
- *"Back to the story."* *(minimalist fallback)*
- *"Let's spend more time with Joseph."* *(person-specific alternate form)*

Person-specific lines are keyed on the Journey's central figure via the Memory display-name registry. Theme and Collection Journeys, which have no single figure, carry the sequence-agnostic lines. Framing-only remains the safety fallback if a line fails to load. **System voice is forbidden** — never *"Let's continue the Journey,"* never *"Story N of M."* Speak of people and places.

Audio implementation (generation, wiring into the accept path) is a separate change, gated on a separate approval. Doctrine names the direction; doctrine does not ship the clips.

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

### The Final Story

When the last story in a Journey ends, **PAL stays quiet.** No immediate offer of another Journey. No wrap-up beat. No reflection. Let the last story land ([PAL_VOICE.md](PAL_VOICE.md) Pillar 4).

The next PAL-button session begins without ceremony. **PAL does not cross-reference** — no *"you finished Daniel; want to try Joseph?"* That is curriculum voice; doctrine forbids it.

Slice 5 may design an optional graduation surface — hand-authored close-of-journey moments where a specific ending merits a specific line. Exception, not rule.

## Journeys and Memory

Journeys are Memory in narrative form — and per the Relational Memory Principle, that memory is of **people, not story IDs**. Each mechanic maps to a [PAL_MEMORY_DOCTRINE.md](PAL_MEMORY_DOCTRINE.md) tier:

- **Silence** (Level 0) — no offer.
- **Facts** (Level 1) — *"Hey Adam!"* on the story after accept. Suppressed on the accept path itself; the offer beat already named the character.
- **Patterns** (Level 2, future) — *"It's been a while since we spent time with Daniel."* Framing is *time with Daniel*, not *story 1114*. Discovered Journeys (Layer 2) also live here.
- **Meaning** (Level 3) — **never PAL's job.** PAL notes where the user has been; PAL never tells the user what those stories mean for them. Personal Journeys (Layer 3) surface here — as memory of shared walking, never as interpretation.

Concretely: every completed Journey story is a `PalSession` record. The Memory display-name registry makes Journey beats speakable in relational terms (*"David,"* *"Joseph,"* *"the widow at Zarephath"*). Journey type influences expression; the Relational Memory Principle governs voice.

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

**Required tests (each cites its enforcer; verified 2026-07-04):**

- Every story listed in a journey has a registered anchor — fail otherwise (`journey_registry_validator_test.dart`)
- No kid journey contains more than 5 stories — fail otherwise (`journey_registry_validator_test.dart`)
- No kid journey has type `theme` or `teaching` — fail otherwise (`journey_registry_validator_test.dart`)
- Voice clips for every offer line and every continuation next-story are bundled per active voice — fail otherwise (`journey_audio_inventory_validator_test.dart`, mirroring the Slice 2c.3 `memory_audio_inventory_validator_test.dart`)
- Journey-continuation cooldown advances only on accepted continuation — fail otherwise (`journey_offer_runtime_test.dart`, cooldown-not-advanced assertions on every decline branch, mirroring `pal_memory_runtime_test.dart`)
- No telemetry event payload contains the literal journey type — fail otherwise (`journey_offer_runtime_test.dart` → "no telemetry event name or prop leaks the journey type"; the silence-on-naming-journey-type invariant)

**Deferred to Slice 3 (NOT yet enforced — do not claim a test):**

- Every story in a journey carries a `primaryJourney` field referencing a registered journey. The field is reserved for Slice 3 multi-journey arbitration and is not yet populated on stories, so enforcing it now would fail on a field that does not exist. Tracked here so the requirement is not lost, but explicitly ungated until Slice 3 lands. *(Corrected 2026-07-04, Doctrine of Doctrines audit: this was previously listed as a required test that never existed.)*

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

### v1.0 Amendment (2026-07-03)

After PR #69 shipped a framing-only continuation intro, Adam and ChatGPT (Star) paused implementation to re-frame Journeys as a product design problem, not a code problem. Six rounds of pushback deepened the framing until it stabilized around three additions the doctrine did not have at v0:

- The **Identity** section, giving the doctrine a single sentence to face outward with.
- The **Relational Memory Principle**, making explicit that PAL remembers people and places, not story IDs. This reshapes continuation voice, and it opens the architectural door to Layers 2 and 3.
- The **Three Layers** framing (Editorial / Discovered / Personal), where only Layer 1 is a v1.0 commitment; Layers 2 and 3 are named to prevent paint-into-corner decisions.

Two decisions locked at the same time: the **first-tap override** on onboarding is rejected (the user's first tap answers the user's first tap; empty-memory is solved by adding, never by hijacking), and a small **relational-voice continuation transition audio** library is authorized for commission (implementation in a separate change).
