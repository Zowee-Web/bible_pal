# Bible PAL - Technical Specification

**Version:** 3.0
**Last Updated:** 2026-03-28

This document is the single source of truth for Bible PAL's features and behavior. All code must follow this specification. Changes to app behavior require explicit updates to this document.

---

## Table of Contents

1. [PAL's Parables System](#pals-parables-system)
2. [Kid Safe Harness](#kid-safe-harness)
3. [Onboarding](#onboarding)
4. [Daily Bread](#daily-bread)
5. [Post-Story Everyday Life Reflection](#post-story-everyday-life-reflection)
6. [Bedtime Mode](#bedtime-mode)
7. [Listening Streaks](#listening-streaks)
8. [Reflection Journal](#reflection-journal)
9. [Seasonal & Calendar Awareness](#seasonal--calendar-awareness)
10. [Share Clips](#share-clips)
11. [Living Sky Theme](#living-sky-theme)
12. [Sanctuary & Study Layout](#sanctuary--study-layout)
13. [Settings](#settings)
15. [Security & Technical Architecture](#security--technical-architecture)

---

## PAL's Parables System

### Core User Flow

**1. PAL's Parables Button**
- Main button on the home screen to start the parable experience

**2. PAL Check-In Prompt System (Feature 2.1)**
- After tapping PAL's Parables, PAL asks a time-aware, category-weighted check-in question
- The prompt adjusts based on current time of day and a weighted random category
- 96 total prompts: 16 buckets (4 time windows × 4 categories) × 6 lines each
- No repeat within a bucket until all 6 lines are used (session-only freshness)
- This prompt leads directly into mood input

**Time Windows:**
- 🌅 **Morning:** 05:00–11:59
- 🌤️ **Afternoon:** 12:00–16:59
- 🌇 **Evening:** 17:00–21:59
- 🌙 **Late Night:** 22:00–04:59

**Prompt Categories:**
- `day` — general day check-in
- `heart` — emotional/spiritual state
- `burden` — what's weighing on the user
- `gratitude` — thankfulness and bright spots

**Weighted Category Distribution:**

| Time Window | day | heart | burden | gratitude |
|-------------|-----|-------|--------|-----------|
| Morning     | 35% | 25%   | 15%    | 25%       |
| Afternoon   | 30% | 30%   | 25%    | 15%       |
| Evening     | 20% | 35%   | 30%    | 15%       |
| LateNight   | 15% | 40%   | 35%    | 10%       |

**Mood Input Methods:**
Users respond to the check-in prompt using one of three input paths:
- **Quick mood buttons:** Tap one of 8 mood buttons (Joyful, Grateful, Weary, Anxious, Hurting, Brave, Peaceful, Encouraged) — bypasses keyword detection, directly sets mood. Buttons reorder based on time of day (morning surfaces encouraging/joyful first; evening surfaces calm/grateful first).
- **Text input:** Type feelings into TextField → `MoodService.detectMood()` analyzes text
- **Voice input:** Speak feelings via STT → transcript placed in TextField → same detection pipeline as text

When a mood button is tapped, a brief thinking delay (800–1500ms randomized) is shown before continuing the flow, to make PAL feel conversational rather than mechanical.

**Implementation Notes:**
- `PalPromptService` owns prompt selection and non-repeat logic
- `PalAudioService` only plays by `lineId` and returns display text
- Prompt bucket key format: `${timeWindow}_${category}` (e.g. `morning_day`, `lateNight_burden`)
- All prompt content defined in `assets/pal/pal_lines.json` under `"prompts"` key
- Choice of prompt does not affect mood classification, only UX

**2.2 PAL Voice Mood Input (Feature 2.2)**
- User can optionally speak their mood response instead of typing (Milestone 1 = single-turn voice input only)
- A mic button appears on the PAL's Parables mood check-in screen near the mood TextField
- Voice input is never automatic; it only starts after an explicit mic tap
- If the PAL prompt audio is still playing and the user taps the mic, the app auto-stops the prompt and immediately proceeds to permission/listening
- SoLoud playback must be fully stopped before STT activation to avoid audio session conflicts
- Voice transcription is placed into the same TextField used for typed input
- User can edit the transcript before continuing
- Voice transcripts go through the identical pipeline as typed text: _handleMoodSubmission() → MoodService.detectMood()
- Fallback is always available: user can cancel voice and type at any time
- Micro-response is audio + text in PAL V2 (played via pre-generated PAL voice audio)

**Voice Conversation States (Milestone 1):**
- `idle` — TextField visible, mic available
- `awaiting_permission` — system permission request in progress
- `listening` — mic active, partial transcript shown (preview only)
- `confirming` — final transcript inserted into TextField, user can edit/re-record
- `proceeding` — same as existing flow after Continue (mood result → micro-response → verse → auto-story start)

**Listening Behavior:**
- `listenFor`: 10 seconds max
- `pauseFor`: 3 seconds of silence triggers finalize
- If STT returns 0 words, show a short snackbar ("I didn't catch that") and return to idle
- Partial transcript may be shown during listening, but only the final transcript is inserted into the TextField

**Permissions:**
- Microphone (and speech recognition where required) permission is requested only on the first mic tap (never on screen load)
- If permission is denied, the app returns to idle and the user can type instead
- If permission is permanently denied, show a short message with an option to open system Settings

**Kid Mode:**
- No special voice-only rules in Milestone 1 beyond existing kid safety rules
- Voice transcript is treated exactly like typed text and must still respect kid-safe filtering and kid-friendly story pool constraints

**Privacy and Storage:**
- Voice transcripts must never be logged, persisted, or included in diagnostics/support bundles
- The transcript exists only in memory for the current screen session

**Platform Support:**
- **iOS / Android**: Full support; microphone and speech permissions already configured
- **macOS**: Requires adding `com.apple.security.device.audio-input` to sandbox entitlements and `NSMicrophoneUsageDescription` to Info.plist; if STT initialization fails, mic button is disabled with tooltip "Voice input not available on this platform"

**Telemetry / Observability (privacy-safe):**
- `voice_input_started` — user tapped mic (no text payload)
- `voice_permission_result` — {granted: bool, permanently_denied: bool}
- `voice_input_completed` — {input_method: "voice", word_count: N, detected_mood: "<mood_key>"}
- `voice_input_cancelled` — {reason: "user_cancel" | "timeout" | "permission_denied" | "stt_unavailable"}

**3. Mood Detection Flow**
- User can type or speak (Feature 2.2) their answer to the greeting question
- Text is analyzed to detect mood (positive / neutral / negative plus finer emotional tags)
- Voice input places transcribed text into the TextField, then follows the identical detection pipeline

**4. Micro-Response System**
- After mood input, PAL plays a short, mood-specific micro-response (audio + text)
- 40 total micro-responses: 8 mood buckets (joyful, grateful, weary, anxious, hurting, brave_courage, calm_peaceful, encouraging) × 5 lines each
- All micro-responses must be ≤ 12 words
- No repeat within a mood bucket until all 6 lines are used (session-only freshness)
- Micro-response selection logic lives in the service layer, not the audio layer
- After micro-response + verse display, a ~2 second cancellable delay triggers automatic story selection and navigation
- If `palGreetingsEnabled == false`, micro-response text still displays and auto-start flow still works; only audio playback is skipped
- All micro-response content defined in `assets/pal/pal_lines.json` under `"microResponses"` key

**5. Parable Generation / Selection Engine**
- Chooses or generates a parable based on:
  - User's detected mood
  - Storytelling mode (creative vs traditional)
  - Selected length
- If pre-generated stories exist that match criteria, selects one
- Otherwise generates a new one on demand

### Story Length & Generation

**6. Story Length Buckets**

Three user-facing length options with clear bucket labels:
- **Short Story**: 250–600 words (LOCKED SPEC)
- **Full Story**: 601–1200 words (LOCKED SPEC)
- **Long Story**: 1201–2000 words (LOCKED SPEC)

Each option has a subtitle hint:
- Short Story — "A quick moment to pause"
- Full Story — "A complete story experience"
- Long Story — "When you have time to settle in"

**Length Selection Flow (PAL Conversational Picker):**
- First time: After mood selection, PAL shows a bottom sheet ("I have a story for you.") with three tappable length options showing label and subtitle
- User's choice is persisted in `UserPreferences.preferredLengthBucket`
- Subsequent visits: saved preference is used automatically (no picker shown)
- Manual override still available via the horizontal selector on the main menu

Implementation notes:
- Selection filters by `StoryLengthBucket` enum (short/full/long)
- Word ranges are for generation validation; selection uses bucket mapping
- Preferred length persisted in UserPreferences (survives app restarts)
- `sessionLengthBucketProvider` stays in sync for backwards compatibility

**Compatibility with existing assets:**
- New stories use `storyLength` field directly ("short", "full", "long")
- Legacy stories may have `length` in minutes (5, 10, 15, 20)
- Legacy mapping: 5-min/10-min → short, 15-min → full, 20-min → long
- `Parable.lengthBucket` getter prioritizes `storyLength`, falls back to legacy `length`

**7. Nightly Batch Generation**
- Automated script runs at 2:00 AM daily
- Generates 20 new parables per night
- Moods and lengths are mixed across generation
- Stories stored as text files plus metadata

### Metadata & Organization

**8. Parable Metadata System**

Each parable includes:
- `storyId` (unique identifier)
- `title` (AI-generated, user-editable)
- `mood` / emotional tags
- `storyLength` ("short", "full", or "long" - primary field, LOCKED SPEC)
- `length` (minutes: 5, 10, 15, or 20 - legacy field for backwards compatibility)
- `lengthBucket` (computed getter: prioritizes storyLength, falls back to length)
- `storytellingMode` (creative or traditional)
- `scriptureSources` (array of verse references)

**PALs Paths metadata (optional, Traditional stories only — Feature 50):**

These fields are all optional. Stories without them remain fully servable via mood flow, favorites, history, and keyword search. See Feature 50.9 for the partial-coverage rules.

- `primaryCharacterId` (string, OPTIONAL) — canonical `snake_case` character ID from `assets/stories/character_registry.json`
- `primaryCharacterDisplayName` (string, OPTIONAL) — display name matching the registry entry for `primaryCharacterId`
- `characterIds` (array<string>, OPTIONAL) — additional character IDs appearing in the story (secondary path membership)
- `characterDisplayNames` (array<string>, OPTIONAL) — display names parallel to `characterIds`
- `bibleOrderIndex` (int, OPTIONAL) — canonical-order rank for the Bible Order path (unique per story)
- `timelineEra` (string, OPTIONAL) — one of the nine canonical eras in Feature 50.2
- `themeTags` (array<string>, OPTIONAL) — theme path memberships
- `characterPathOrder` (int, OPTIONAL) — per-character sort order within a character path (unique per `primaryCharacterId`)

Creative stories MUST NOT carry any of these fields. Presence of any of them on a Creative story fails Story Mode contract validation.

**9. AI-Generated Story Titles (Editable)**
- Each parable has an AI-generated title by default
- User can rename any title
- Edited title replaces AI title for that user
- Original AI title preserved for other users

### User Library Management

**10. Favorites System**
- Unlimited favorites capacity
- Saved locally on device (SQLite)
- Metadata stored per favorite:
  - `storyId`
  - `title` (edited or AI-generated)
  - `mood`
  - `length`
  - `scriptureSources`
  - `dateSaved`

**11. History System**
- Automatically records listened parables
- Stores last **20 entries only**
- When 21st entry added, oldest entry is removed (FIFO)
- Metadata stored per entry:
  - `storyId`
  - `title`
  - `mood`
  - `length`
  - `scriptureSources`
  - `timestamp`

**12. Scripture Sources Panel**
- Collapsible panel below story title on player screen
- Collapsed by default; expands on tap to show:
  - Scripture reference(s) (e.g., "Mark 4:35-41")
  - Bible translation label (e.g., "World English Bible (WEB)")
- "Read Scripture" button appears after playback completes
  - Opens bottom sheet with reference, translation, and verse text (when available)
- Hidden for Creative stories (no scripture reference)
- Scripture reference display is driven by story metadata for the current `storyId`
- Reused in Favorites and History views (future)

### Storytelling Modes

**13. Creative / Traditional Mode Toggle**

Two distinct storytelling approaches:
- **Creative Mode:** Modern, imaginative style with contemporary applications
- **Traditional Mode:** Biblical narrative tone, closer to scripture style

Affects:
- Story generation prompts
- Pre-generated story selection pool

---

### Story Mode Contracts v2 (LOCKED)

Story Mode Contracts v2 defines two orthogonal axes that govern story content and presentation. These contracts are **LOCKED** and must never be violated or blurred.

#### Axis 1 — Story Mode (Authority)

`storytellingMode`: `traditional` | `creative`

This axis determines the **authority and source** of the story content.

#### Axis 2 — Language Style (Presentation)

`languageStyle`: `WEB` | `KJV`

This axis determines the **diction and presentation style** only. It NEVER changes authority.

**IMPORTANT:** `languageStyle` is separate from `translationId` (used for Bible translation compliance in Daily Bread and scripture references). Stories use `languageStyle` for presentation; scripture features use `translationId` for compliance.

---

#### Traditional Mode Contract (DEFAULT)

Traditional mode is the **default** for all users. Stories in Traditional mode are **faithful retellings of actual Bible stories**.

**Core Definition (LOCKED):**
Traditional stories MUST be **real Bible stories retold faithfully**. They are not devotional content, not original stories with biblical themes, not paraphrased scripture. They are specific, identifiable Bible narratives rendered in narrative form.

**Requirements:**
- Must map directly to specific Bible passages
- Preserve characters, event order, outcomes, and meaning from scripture
- Third-person narrative by default; biblical narrative posture
- `bibleSourceRef` field is **REQUIRED** (e.g., "Luke 15:3-7", "Genesis 22:1-19")
- `bibleStoryKey` field is **REQUIRED** — a stable canonical identifier for the Bible story (e.g., "lost_sheep", "jesus_calms_storm", "david_and_goliath")
- **Scripture Anchor Registry**: Traditional stories are backed by a canonical registry (`assets/stories/scripture_anchor_registry.json`). Each anchor identifies one canonical narrative unit via `scriptureAnchorId` — the primary no-repeat key. An anchor may serve multiple moods via `moodTags`. No anchor is ever reused. See ADR-022.

**Allowed ("Pizzazz"):**
Scripture-faithful narrative enrichment is allowed:
- Pacing adjustments and transitions
- Scene detail, sensory description, emotional texture implied by the text
- languageStyle may be WEB (modern) or KJV (classical)

**Pizzazz Constraints:**
"Pizzazz" means narrative style, NOT narrative license:
- NO new events that aren't in scripture
- NO altered outcomes or reordered events
- NO invented theology or doctrine
- NO modern framing (e.g., "like when you feel stressed at work")
- NO inner monologue not implied by scripture

**Forbidden:**
- Invented motives or inner monologue not implied by scripture
- Changed outcomes or reordered events
- MoDC companionship voice (e.g., "I sit with you", "I am here")
- First/second-person spiritual guide posture
- Commentary or devotional asides within the narrative
- Blurring into Creative mode territory
- **Reflective narrator endings** — no interpretive, poetic, or emotionally summarizing closure language in story body text. Traditional stories must end at the scripture boundary with observable action only. Forbidden patterns include:
  - Listener-directed comfort language ("rest now", "enough for today", "one long breath")
  - Implied moral summary not present in scripture ("it was enough", "at last, peace")
  - Internal/interpretive phrasing ("he felt", "she seemed", "rest at last") unless directly warranted by observable scripture text
  - Narrator commentary that shifts from retelling to reflection

**Separation of Story Body and Reflection Content:**
- **Story body** contains only the faithful scripture retelling — no reflective language
- **Reflection content** (Feature 34) is a separate asset, displayed after the story via the Reflection UX
- Poetic or emotionally resonant closing language belongs ONLY in reflection content or Creative mode, never in Traditional story body text
- Reflection content must never be merged into or appended to the Traditional story body

**Validation:**
- Traditional stories without `bibleSourceRef` are **EXCLUDED** from the serving pool
- Traditional stories without `bibleStoryKey` are **EXCLUDED** from the serving pool
- Stories with MoDC narrator patterns fail validation
- Stories with invented inner-monologue markers fail validation
- Stories that read as devotional commentary rather than narrative fail validation
- Stories with reflective narrator ending patterns fail validation (see forbidden patterns above)


---

#### Creative Mode Contract (USER TOGGLE)

Creative mode produces original stories with biblical meaning and values. These are NOT derived from specific Bible passages.

**Requirements:**
- Original stories only; not retellings of specific Bible stories
- MoDC (Model of Digital Companionship) rules apply fully:
  - Non-directive: no commands or prescriptions
  - Optional: user can skip/dismiss at any time
  - Interruptible: no forced completion
- `bibleSourceRef` field must be **ABSENT or empty**

**Allowed:**
- Biblical themes, values, and wisdom woven into original narratives
- Contemporary or timeless settings
- languageStyle may be WEB (modern) or KJV (poetic)

**Forbidden:**
- Retelling specific Bible stories (even loosely)
- Implying scriptural authority ("as the Bible says", "scripture tells us")
- Teaching doctrine as fact
- Commands or prescriptions ("you should", "you must")
- Dependency language ("you need this", "come back tomorrow")
- `bibleSourceRef` field present

**Creative + KJV Extra Restrictions:**
When `languageStyle=KJV` in Creative mode, treat as **poetic diction only**. Additional forbidden patterns:
- "Thus saith" or similar archaic authority markers
- Verse numbering or chapter references
- "This is the Word" or "hear the Word"
- Any markers that imply scripture quotation

**Validation:**
- Creative stories with `bibleSourceRef` present fail validation
- Stories with strong signals of Bible story retelling fail validation
- Stories with scripture-authority claims fail validation
- Stories with advice/prescription/dependency language fail validation
- Creative+KJV stories with scripture-claim markers fail validation

**Creative Story DNA (Pipeline Diversity — ADR-020):**

Creative stories use a deterministic "Story DNA" planner to inject structural variety before generation. Each story is assigned attributes from rotating pools:
- **Opening type** (8): dialogue, action, question, emotional_reflection, memory, object_focus, conflict, setting
- **Structure type** (8): conversation, journey, witness, flashback, unexpected_encounter, problem_solution, parallel_lives, object_lesson
- **Setting emphasis** (3, weighted low): low (no place description), medium, high
- **Character archetype** (10): traveling merchant, shepherd, fisherman, widow, child, craftsman, teacher, farmer, healer, stranger
- **Tone** (8): hopeful, reflective, warm, bittersweet, wonder, gentle, solemn, tender

A repetition guard prevents 3+ consecutive stories from sharing the same opening_type or structure_type. A place-name avoidance list prevents reuse of overused fictional location names. Story DNA is stored in `meta_*.json` under the `storyDna` key (pipeline metadata only — the Flutter app does not read it).

---

#### Global Invariants (Story Mode)

1. **Non-Blur Enforcement**: Traditional and Creative modes must NEVER blur. Mode determines authority and validation rules.

2. **No Silent Fallback**: If no stories match the user's selected mode, return empty pool. Never silently serve cross-mode content.

3. **bibleSourceRef Integrity**:
   - Traditional: REQUIRED. Stories without it are excluded (not guessed).
   - Creative: FORBIDDEN. Stories with it fail validation.

4. **languageStyle Independence**: Changing languageStyle (WEB↔KJV) never changes authority rules or mode validation.

5. **Default is Traditional**: New users and unset preferences default to Traditional mode.

---

#### Parable Metadata (Updated for Contracts v2)

Each parable now includes:
- `storyId` (unique identifier)
- `title` (AI-generated, user-editable)
- `mood` / emotional tags
- `storyLength` ("short", "full", or "long" - LOCKED SPEC)
- `length` (legacy minutes field for backwards compatibility)
- `storytellingMode` ("traditional" or "creative") - **REQUIRED**
- `languageStyle` ("WEB" or "KJV") - **REQUIRED** for new stories
- `translationId` (Bible translation for compliance - separate from languageStyle)
- `bibleSourceRef` (scripture reference - **REQUIRED for Traditional, ABSENT for Creative**)
- `bibleStoryKey` (canonical Bible story identifier - **REQUIRED for Traditional, ABSENT for Creative**)
- `kidFriendly` (boolean)
- `scriptureSources` (array of verse references used in story)
- `narratorVoiceKey` (symbolic voice key - **REQUIRED** for all stories)
- `reflectionAudioPath` (path to pre-generated reflection audio - **REQUIRED** for all stories)
- `reflectionTextPath` (path to reflection text file - optional)

---

### Golden Prompt Mode: Adult Traditional SHORT Bucket Generation

Golden Prompt mode is a specialized generation strategy for adult traditional SHORT bucket parables (250-600 words, LOCKED SPEC) that uses structure-based length control instead of continuation prompts.

**Goals:**
- Reliable single-shot generation that meets word count requirements
- Exploit Gemma-7B's strength with constrained, structured prompts
- Eliminate story repetition/duplication bugs caused by continuation logic

**Non-Goals:**
- Creative mode support (standard mode only)
- Kid-friendly generation (separate harness)
- Full/Long bucket stories (SHORT bucket only)

**Inputs:**
- Mood: one of `joyful`, `weary`, `anxious`, `hurting`, `neutral`, `encouraging`, `calm_peaceful`, `brave_courage`
- Model: `gemma:7b` via Ollama

**Prompt Constraints (Structure-Based Length Control):**
- Attempt 1: exactly 10 paragraphs, exactly 5 sentences per paragraph
- Attempt 2 fallback: exactly 12 paragraphs, exactly 5 sentences per paragraph
- No headings, no numbering, no bullet points
- No modern slang, no fantasy, no humor, no dialogue-heavy scenes
- Scripture may be referenced gently (no long quotes)

**Retry Policy:**
- Maximum attempts: 2
- If attempt 1 word count < 250: regenerate fresh with stricter structure (12 paragraphs)
- NO continuation prompts — always single-shot generation
- Each retry uses the same mood but escalated structure

**Output:**
- Filename pattern: `parable_3XX_<mood>_short_golden_trad.txt`
- Story ID range: 301-308 (one per mood)
- YAML frontmatter with `mode: golden_traditional`, `storyLength: short`

**Quarantine Behavior:**
- If attempt 2 still fails min_words (< 250): story is quarantined
- Quarantine location: `assets/stories_failed/`
- Metadata includes: `failure_reason: word_count_too_low`, `actual_words`, `attempts`

**Acceptance Examples:**

1. **Escalation case**: If attempt 1 produces 200 words, attempt 2 MUST regenerate with 12 paragraphs (not continue the story).

2. **Quarantine case**: If attempt 2 still produces only 180 words, the story MUST be quarantined to `assets/stories_failed/` with `kidSafe: false` equivalent marking.

3. **Success case**: If attempt 1 produces 450 words (within 250-600 range), no retry is needed — story is saved immediately.

**Script:**
- `server/generate_adult_traditional_stories.sh --golden-prompt`
- Prompt template: `server/prompts/golden_trad_adult_short.prompt.txt`
- Contract: `server/contracts/golden_contract_trad_adult_short.yaml` (if exists)

### Sharing & Replay Logic

**14. Share With a PAL**
- Available after parable completion
- Shares specific parable by `storyId`
- Recipient can open shared story in their own app

**15. Non-Repeat Story Serving Rule**
- User should not receive same parable twice until all eligible parables exhausted
- Eligibility based on current filters:
  - Storytelling mode
  - Length preference
  - Other active criteria
- After pool exhausted, stories repeat using "least recently played" ordering

**15b. Mood Expansion Serving Rule**

Bible PAL preserves the user's selected mood as the primary intent, while expanding the eligible story pool in a controlled way to reduce fast repetition.

**Scope:** Mood Expansion governs mood-launched serving only. Stories launched via PALs Paths (Feature 50), search results, favorites, history, or any explicit-by-`storyId` entry point are served deterministically by the caller and DO NOT pass through the Mood Expansion engine. For those launches, `selectedMood` is `null` on the served-story record and `servedMood` is the story's own mood tag.

**Serving Priority Order**

When a user selects a mood, the serving engine builds the eligible pool in this order:
1. Exact selected mood + unseen stories
2. Similar moods + unseen stories
3. Exact selected mood + seen stories, sorted least-recently-played first
4. Similar moods + seen stories, sorted least-recently-played first

**Required Filters**

At every stage above, the pool must also be filtered by:
- Story must have the requested `StoryLengthBucket` available (no fallback to other lengths)
- Active mode/settings must match
- All existing serving invariants still apply

**Exact Mood Protection**
- The system must never silently switch to unrelated moods
- The selected mood remains primary
- Similar moods are only a fallback expansion layer, not a replacement of user intent

**Expansion Trigger**
- Always try exact mood first
- If the exact unseen pool is empty, expand to similar moods
- Optional future tuning: expand earlier if the exact unseen pool is below a threshold (e.g., 5 stories), but do not implement unless explicitly requested

**Similar Mood Map**
- `anxious` → `calm_peaceful`, `encouraging`, `weary`
- `calm_peaceful` → `anxious`, `grateful`, `encouraging`
- `brave_courage` → `encouraging`, `hurting`, `anxious`
- `encouraging` → `brave_courage`, `calm_peaceful`, `grateful`
- `grateful` → `joyful`, `calm_peaceful`, `encouraging`
- `hurting` → `weary`, `encouraging`, `calm_peaceful`
- `joyful` → `grateful`, `encouraging`, `calm_peaceful`
- `weary` → `hurting`, `calm_peaceful`, `encouraging`

**Tracking Requirements**

For each served story, persist enough data to support repeat protection and analysis:
- `storyId`
- `selectedMood` — the mood the user chose
- `servedMood` — the actual mood of the story returned (may differ from `selectedMood` when expansion is used)
- `playedAt`
- `length`
- `mode`

**Telemetry**
- The system may log pool size before and after expansion for telemetry, enabling future threshold tuning without requiring a spec change

**Behavioral Goal**

This rule exists so Bible PAL can make a small story library feel much larger without violating user trust. The engine should: honor the chosen mood first, expand only to emotionally adjacent moods, avoid repeats until the pool is exhausted, then use least-recently-played ordering.

### Storage & Playback

**16. Offline Local + External Storage**
- Parables stored locally on device
- Support for external drive storage (e.g., T9) for bulk libraries
- App fully functional without internet connection

**17. ElevenLabs v3 Audio Playback**
- Parables converted to audio using ElevenLabs v3
- Single narrator voice per story (multi-voice deferred)
- SSML tags for enhanced narration
- Pre-generated audio files (not live streaming TTS)
- High-quality playback from stored audio files

**17b. PAL Voices**

Four selectable PAL conversation voices for check-in prompts, micro-responses, and previews:

| Voice Key | Display Name | Emoji | Description | ElevenLabs Voice |
|-----------|-------------|-------|-------------|-----------------|
| `VOICE_GRACE` | Grace | 🌿 | Gentle & comforting | Juniper |
| `VOICE_SHEPHERD` | Shepherd | 📖 | Wise storyteller | Mark |
| `VOICE_HOPE` | Hope | ☀️ | Bright encouragement | Hope |
| `VOICE_STILLWATER` | Stillwater | 🌙 | Calm companion | James |

- Default voice: `VOICE_GRACE`
- Audio asset path: `assets/pal/audio/{VOICE_KEY}/{line_id}.mp3`
- Fallback chain: selected voice → default voice (Grace) → text-only display
- PAL voices are separate from the narrator voice pool used for story narration

**Voice Quality Guardrails:**

PAL voices should sound:
- conversational, warm, calm, grounded, storyteller-like, emotionally supportive

PAL voices should NOT sound:
- announcer-like, corporate, metallic, dominating, trailer-style, overly theatrical

Spoken cadence guidance:
- Preserve punctuation and ellipses (these aid natural pauses)
- Prefer short and medium-length sentences
- Allow commas for breathing room
- Avoid flattening punctuation or overlong run-on sentences

Category tone personalization (content/voice-direction, not inference):
- `day` = neutral / steady
- `heart` = warmer / more intimate
- `burden` = gentler / softer
- `gratitude` = brighter / lighter

---

## Kid Safe Harness

The Kid Safe Harness ensures that all kid-mode story generations are safe for children ages 5-9. Parents can confidently have stories play for their child at any time.

### Contract Injection

**28. Kid Story Contract**
- All kid-mode generations MUST include the Kid Story Contract in the prompt
- Contract location: `docs/prompts/kid_bedtime_contract.txt`
- Contract specifies:
  - Audience: ages 5-9 audio listening
  - Calm/comforting tone requirement
  - No peril/violence/terror imagery
  - No crowns/thrones/power reward arcs
  - Biblical accuracy (no invented promotions)
  - Fixed 5-part structure with gentle, positive ending
  - "Parent Test" self-check instruction

### Forbidden Vocabulary Gate

**29. Forbidden Vocabulary Enforcement**
- Single source-of-truth: `server/kid_bedtime_forbidden.txt`
- Post-generation scanner flags ANY forbidden word (case-insensitive)
- Categories include:
  - Violence/peril (roar, jaws, devour, attack, battle, sword, etc.)
  - Death/dying (death, dead, perish, etc.)
  - Fear/terror (terror, nightmare, frightened, etc.)
  - Punishment/retribution (punish, vengeance, doom, etc.)
  - Power rewards (crown, throne, king, ruler, reign, etc.)
  - Predator imagery (beast, monster, hunt, chase, flee, etc.)
  - Biblical inaccuracies ("became king", "was crowned", etc.)
- If ANY forbidden word detected, story is rejected

### Structure Validation

**30. Required Story Structure**
- Stories must have at least 3 distinct sections (paragraphs)
- Minimum word count: 200 words
- Average sentence length: 15 words or fewer
- Ending should be gentle and positive (warm, hopeful tone)

### Post-Generation Validator

**31. Validation Pipeline**
- Validator: `server/kid_bedtime_validator.sh` (bash) or `lib/safety/kid_bedtime_validator.dart` (Dart)
- Runs after each generation attempt
- Checks:
  1. No forbidden words present
  2. Required structure exists
  3. Sentence length within limits
- Returns detailed violation list for repair instructions

### Bounded Regeneration

**32. Automatic Regeneration on Failure**
- If validation fails, automatically regenerate with repair instruction
- Repair instruction tells Gemma exactly what failed (lists violations)
- Maximum attempts: **3** (configurable constant `kMaxRegenAttempts`)
- If still failing after max attempts:
  - Return best attempt but mark as `kidSafe: false`
  - Story MUST NOT be saved to kid library
  - Deterministic logging of all failures

### Harness Wrapper

**33. Kid Safe Harness**
- Harness script: `server/kid_bedtime_harness.sh`
- Wraps generation with validation loop
- Process:
  1. Inject Kid Story Contract into prompt
  2. Call Ollama/Gemma to generate story
  3. Validate output against contract
  4. If failed, append repair instruction and retry
  5. Repeat until valid or max attempts reached
- Creates metadata file with `kidSafe` boolean and `validationFailures` array

---

## Onboarding

**18. Christian General Only (LOCKED)**

Bible PAL serves all Christians with a unified, non-denominational experience:
- No faith tradition or denomination selection
- All stories use Christian General perspective
- No denomination-specific content branching
- This is a permanent design decision (not a v1 deferral)

See [INVARIANTS.md](INVARIANTS.md) for the enforcement details.

**19. Bible Translation Selector**
- Presented on first launch
- User selects preferred Bible translation(s)
- Affects:
  - Scripture references throughout app
  - Scripture Sources panel
  - Daily Bread verse
- User can change later in Settings

---

## Daily Bread

**20. Daily Bread Verse Display**
- Static verse displayed at top of main menu
- Uses user's selected Bible translation
- Fixed position and style (no floating animation)

**21. Thematic Alignment**
- When possible, Daily Bread verse should match or complement the theme of the day's parable

---

## Post-Story Everyday Life Reflection

**34. Post-Story Reflection Feature**

After a PAL's Story finishes playing, an optional reflection connects the story's themes to everyday life.

**Behavior:**
- **Default**: Enabled on first app launch
- **User-toggleable**: Via Settings ("Relate stories to everyday life" toggle)
- **Persisted**: Setting survives app restarts
- **Optional**: User may skip/dismiss at any time with no consequence
- **Opt-in audio**: Reflection audio is NEVER auto-played. User must tap "Hear Reflection" button.

**Reflection System (LOCKED):**
- **Every story has a reflection**: Both Traditional AND Creative stories have a story-specific reflection created alongside the story.
- **Reflection audio uses same narrator voice**: The `narratorVoiceKey` for reflection audio MUST match the story's `narratorVoiceKey`. No separate "PAL voice" for reflections.
- **Pre-generated audio**: Reflection audio is pre-generated alongside story audio, not runtime TTS.

**Scripture Reference Display (Traditional Mode):**
- Scripture reference (`bibleSourceRef`) is displayed AFTER story playback completes, NOT during narration.
- Display format: Book Chapter:Verse-Verse (e.g., "Mark 4:35-41")
- Scripture reference is NOT spoken in the narration.

**UI Flow:**
1. Story playback completes
2. For Traditional stories: Display scripture reference (e.g., "Mark 4:35-41")
3. Show standalone reflection controls (no card/container):
   - "Hear Reflection" button (if reflection audio exists)
   - "Jot a thought..." journal input (adult mode only)
4. User may dismiss at any time

**When Disabled:**
- No reflection UI, audio, or questions appear
- Scripture reference for Traditional stories is still shown

**35. Reflection Language Constraints**

Reflections MUST:
- Use descriptive, non-prescriptive language
- Describe patterns, not instructions
- Use phrases like "often looks like", "can reflect", "stories like this show..."
- Be grounded in a specific moment, image, or action from the story

Reflections MUST NOT:
- Give advice ("you should", "try to")
- Make diagnostic claims ("you are feeling...")
- Promise outcomes ("this will help you...")
- Use therapeutic language

**35a. Reflection vs. Story Body Boundary (LOCKED)**

Reflection content is the ONLY lane where gentle, emotionally resonant closing language is permitted. This includes phrases like "enough for today", "one small step", or poetic restatements of story themes.

This language MUST NOT appear in Traditional story body text (see Traditional Mode Contract — Forbidden: Reflective narrator endings). The boundary is enforced by:
- Generation prompt templates (Traditional prompt forbids reflective closings)
- Automated test scans of Traditional story text files
- The reflection prompt template, which produces reflection content as a separate asset

**36. Kid Mode Reflection Constraints**

When `kidFriendlyOnly` is enabled:
- Reflection language is short and literal
- No abstract concepts or emotional probing
- Age-appropriate vocabulary (5-9 year olds)
- Example tone: "This story shows that being kind matters, even when things feel unfair."

---

## Bedtime Mode

**38. Bedtime Mode (Feature 38)**

A toggle that transforms the listening experience for nighttime use.

**Behavior:**
- **Toggle**: Settings → "Bedtime Mode" (default: OFF)
- **Sleep Timer**: Configurable delay after story ends (0 / 5 / 10 / 15 / 30 minutes, default: 5 min)
- **Audio Fade-Out**: When sleep timer expires, audio volume fades to zero over 5 seconds, then playback stops
- **Dim Overlay**: Player screen shows a semi-transparent dark overlay (30% opacity) when bedtime mode is active
- **Reflection audio also stopped**: Sleep timer stops both story and reflection audio

**Implementation:**
- `UserPreferences.bedtimeModeEnabled` (bool, persisted)
- `UserPreferences.sleepTimerMinutes` (int, persisted)
- `AudioService.fadeOutAndStop()` — 20-step linear volume interpolation over configurable duration
- Sleep timer starts in `ParablePlayerScreen` after `playbackCompletedStream` fires

**Constraints:**
- Bedtime mode does not auto-activate based on time of day — it is always user-controlled
- The dim overlay does not block touch interaction (uses `IgnorePointer`)
- Volume is reset to 1.0 after fade-out completes so next playback starts at full volume

---

## Listening Streaks

**39. Listening Streaks (Feature 39)**

Tracks consecutive days of story listening to encourage gentle daily habit formation.

**Behavior:**
- **Computed**: Streak is updated each time `addToHistory()` is called
- **Display**: Shows "X day streak" on main menu when streak ≥ 2 days
- **No guilt**: If user misses a day, streak resets to 1 silently — no "you lost your streak" messaging
- **Warm tone**: Display uses warm gold color, small body text — visible but not attention-grabbing

**Implementation:**
- `UserPreferences.currentStreak` (int, default: 0)
- `UserPreferences.lastListenDate` (String?, ISO date yyyy-MM-dd)
- Logic: if `lastListenDate` is yesterday → increment. If today → no change. If older → reset to 1.
- Updated inside `AppStateNotifier.addToHistory()` alongside history persistence

**Constraints:**
- Streaks are based on calendar days, not 24-hour windows
- Only one streak increment per day (multiple listens same day don't over-count)
- Streak display is hidden when streak < 2

---

## Reflection Journal

**40. Reflection Journal (Feature 40)**

After the post-story reflection, users can jot a one-line thought tied to the story.

**Behavior:**
- **Input**: Single-line text field ("Jot a thought...") appears in the reflection card after story playback
- **Max length**: 200 characters
- **Save**: Tap checkmark to save. Shows "Saved to your journal." confirmation
- **Not shown in kid mode**: Journal input is hidden when `kidFriendlyOnly` is true
- **Storage**: Last 100 entries persisted in SharedPreferences

**Data Model:**
- `JournalEntry`: id, storyId, storyTitle, mood, note, createdAt
- Stored in `StorageService` under `journal_entries` key

**Constraints:**
- Journal entries are local-only (never synced, never logged)
- No editing after save (write-once)
- FIFO: oldest entries are trimmed when exceeding 100

---

## Seasonal & Calendar Awareness

**41. Seasonal Story Surfacing (Feature 41)**

Stories tagged with a liturgical/cultural season are soft-preferred during that season.

**Supported Seasons:**
- `advent` — Dec 1–24
- `christmas` — Dec 25 – Jan 6
- `lent` — Ash Wednesday to Holy Saturday (computed from Easter)
- `easter` — Palm Sunday through Easter +7 days
- `thanksgiving` — Nov 20–30

**Behavior:**
- `SeasonalCalendar.getCurrentSeason()` returns current season or null
- Story selection sorts season-tagged stories before untagged ones (soft preference, not hard filter)
- `SeasonalCalendar.getSeasonalGreeting()` provides optional PAL greeting text for special seasons
- `Parable.seasonTag` field (nullable String) for story tagging

**Implementation:**
- Easter date computed via Anonymous Gregorian algorithm
- Seasonal boost applied in `ParableService.selectParable()` sorting, after filtering
- If no season-tagged stories exist for the current season, selection falls through to normal pool

**Constraints:**
- Season detection is date-based only (no user location or timezone heuristics)
- Seasons are non-overlapping by design
- Seasonal greeting is optional — PAL may or may not use it

---

## Morning vs. Evening Awareness

**42. Time-of-Day Story Intelligence (Feature 42)**

The app adjusts mood surfacing and story selection based on time of day.

**Mood Button Reordering:**
- Morning (05:00–11:59): encouraging, joyful, grateful first
- Afternoon (12:00–16:59): default order (no reordering)
- Evening (17:00–21:59): calm_peaceful, grateful, weary first
- Late Night (22:00–04:59): calm_peaceful, weary, hurting first

**Story Selection Boost:**
- `Parable.timeOfDay` field (nullable: 'morning', 'evening', or null for any time)
- Stories tagged for the current time window are soft-preferred in selection sorting
- Morning = 05:00–11:59, Evening = 17:00–04:59, Afternoon = no preference

**Constraints:**
- Mood buttons always show all 8 moods — reordering only, never hiding
- Time-of-day is a soft preference, not a hard filter
- Uses `PalPromptService.getTimeWindow()` for consistent time classification

---

## Share Clips

**44. Share Clips (Feature 44)**

Shareable story excerpts for social sharing and word-of-mouth growth.

**Behavior:**
- **Button**: "Share a clip" appears alongside existing "Share with a PAL" in the player
- **Content**: Extracts 2-3 compelling sentences from the story's middle third
- **Format**: Quoted excerpt, em-dash with story title, scripture ref (if Traditional), "Listen on Bible PAL"
- **Platform**: Uses `share_plus` package to invoke native share sheet

**Excerpt Algorithm:**
- Split story into sentences (by `.!?` boundaries)
- Skip first third (setup) and last third (resolution)
- Take 2-3 sentences from the middle
- Cap at 200 characters

**Constraints:**
- Excerpt is text-only (no audio clips in v1)
- If story is very short (≤3 sentences), use the full text
- Share action is fire-and-forget (no tracking of share success beyond platform callback)

---

## Favorites "Listen Again"

**45. Favorites Listen Again (Feature 45)**

Encourages users to revisit saved favorite stories.

**Behavior:**
- **Display**: "Listen to an old favorite" text link appears above mood buttons on main menu
- **Visibility**: Only shows when user has ≥1 saved favorite
- **Selection**: Picks a random favorite and loads it into the player
- **Flow**: Favorite → addToHistory → loadParable → navigate to player

**Constraints:**
- Random selection uses current timestamp modulo for simplicity
- Favorites list is read from app state (already loaded)
- "Listen Again" does not bypass the mood detection flow — it's an alternative entry point

---

## Family / Kids Mode

**46. Family / Kids Mode (Feature 46)**

A first-class visual experience when kid-friendly mode is active.

**Behavior:**
- **Theme Switch**: When `kidFriendlyOnly` is true, the main menu uses a warmer color theme
- **Colors**: Warm peach primary, sunshine gold accent, cream background, soft lavender containers
- **Typography**: Slightly larger app bar title (22px vs 20px)
- **Content**: All existing kid-safe content filtering still applies (kid-friendly stories only, age-appropriate reflections)

**Implementation:**
- `AppTheme.kidsTheme` — a `ThemeData` variant with warmer colors
- Applied via `Theme()` widget wrapper on main menu when kid mode is active
- Theme switch is immediate (no animation/transition)

**Constraints:**
- Kids theme only affects visual appearance, not behavior
- All mood buttons, length selection, and PAL flows work identically in kid mode
- Journal input is hidden in kid mode (Feature 40)

---

## Living Sky Theme

**47. Living Sky Theme (Feature 47)**

The app's visual identity shifts with the time of day through four phases, creating a living atmosphere.

**Sky Phases:**

| Phase | Time Window | Sky Gradient | Particles | PAL Orb Color | Text Color | Feeling |
|-------|------------|-------------|-----------|---------------|------------|---------|
| **Dawn** | 05:00–07:59 | Warm peach/rose | Soft golden light drifting upward | Warm amber | Deep warm brown (#3A2A1A) | Fresh start, new mercies |
| **Day** | 08:00–16:59 | Bright warm cream/sky blue | Floating golden dust motes in sunlight | Warm gold | Deep charcoal (#2A2A2A) | Vibrant, alive |
| **Golden Hour** | 17:00–19:59 | Rich amber/deep orange tones | Warm golden particles drifting slowly | Burnished amber | Warm ivory (#EEE8D5) | Reflection, gratitude |
| **Night** | 20:00–04:59 | Deep navy (current Sacred Night theme) | Twinkling starfield | Celestial blue | Warm ivory (#EEE8D5) | Reverent, peaceful |

**Behavior:**
- Sky phase is determined by device local time, checked on each app resume and widget build
- The Living Sky background replaces the static `StarfieldBackground` on the main menu
- The starfield variant is retained and used during the Night phase
- Other screens (settings, player, etc.) continue using the existing Sacred Night theme

**Kid Mode Override:**
- When `kidFriendlyOnly` is true, the kids theme palette (Feature 46) overrides Living Sky regardless of time of day

**Constraints:**
- Phase transitions are instant (no animated blending between phases)
- Time classification uses device local time only (no timezone heuristics)
- Living Sky applies to the main menu only — all other screens are unchanged

---

## Main Horizontal Navigation

**48. Main Horizontal Navigation (Feature 48) — LOCKED**

The main menu is a horizontal three-page `PageView`. Pages are ordered left-to-right by index. Default landing page is always the PAL Sanctuary at index 0. Each page preserves state across swipes (no rebuild on page change). Living Sky background is shared and continuous across all three pages — no visible seam.

**Page 0 — "PAL Sanctuary" (Default Landing, LOCKED):**
- Living Sky background (Feature 47) fills the entire screen
- PAL orb is the sole hero element — 280×280px, centered, with a slow breathing glow animation whose color changes with the sky phase
- Daily Bread verse floats as faint atmospheric text in the lower portion (no card, no border — just text on the sky)
- Streak counter appears as subtle warm gold text near the PAL orb when streak ≥ 2
- A single soft animated chevron (›) at the right edge gently pulses to hint the page is swipeable
- Settings gear icon remains top-right, faintly visible

**Page 1 — "Mood" (One Page Forward from PAL Sanctuary):**
- Same Living Sky background, continuous from page 0
- 8 mood buttons with emoji+color pills, time-of-day reordered (Feature 42)
- Text PAL / Read Story glass buttons
- Now Playing / Finished panel (when active)
- Favorites / History / My PALs glass navigation buttons
- "Listen to an old favorite" link when favorites exist (Feature 45)
- Soft chevrons (‹ ›) at both edges hint at adjacent pages

**Page 2 — "PALs Paths" (Two Pages Forward from PAL Sanctuary):**
- Same Living Sky background, continuous from pages 0 and 1
- Path-type selector at top:
  - **Featured tile: The Life of Jesus** (`jesus_life`) — visually distinct, positioned above or prominently separated from the four standard tiles. Not buried under Characters.
  - Four standard tiles: Bible Order, Timeline, Themes, Characters
- Main content area (path list / search results / path detail) between the selector and the search input
- **Bottom-anchored search input** matching the Mood page input style (glass surface, keyboard-safe, does not scroll with the content area) — placeholder: "Search scripture, character, or story"
- Soft chevron (‹) at the left edge hints back to Mood
- Full behavior is defined in Feature 50

**Navigation:**
- Smooth horizontal `PageView` with snap physics
- Page indicator dots at bottom (three dots, subtle warm gold) — at rest on PAL Sanctuary the dots read ● ○ ○
- Swipe gesture or tap chevron to navigate between pages
- Nested horizontal scroll widgets inside any page (e.g. horizontal mood pill rows, path lists) MUST NOT consume the outer `PageView` horizontal drag; inner horizontal scrollers must yield to the outer page drag on overscroll

**Constraints:**
- Default landing page is always PAL Sanctuary (page 0) — LOCKED
- PageView preserves state across swipes (no rebuild on page change)
- Living Sky background is shared and continuous — no visible seam
- All existing main menu functionality is preserved on the Mood page; nothing is removed from the pre-Feature-50 experience
- Kid mode still uses the kids theme palette (Feature 46) on all three pages
- On entry, the PageView always resets to page 0; deep links do not override the default landing page

---

## Ambient Background Sound

**49. Ambient Background Sound (Feature 49)**

Optional background audio that plays alongside story narration to create a calm, immersive atmosphere.

**Behavior:**
- **Toggle**: Settings → "Background Sound" (default: OFF)
- **Sound Type Selector**: Visible when toggle is ON. Options: Rain (default), Soft Wind, Night Ambience, Soft Pads
- **Playback**: Ambient audio starts when story narration starts (if enabled), loops continuously
- **Volume**: Fixed at 0.15 — always below narration volume (1.0). No dynamic ducking in v1
- **Fade-In**: 300ms linear fade-in on start
- **Fade-Out**: 300ms linear fade-out on stop
- **Stop Conditions**: Ambient stops on playback complete, pause, stop, clear, or screen exit
- **Resume**: When narration resumes after pause, ambient restarts if still enabled
- **Post-Story**: Ambient does NOT continue into reflection playback

**Implementation:**
- `AmbientAudioService` — dedicated `just_audio` player for ambient loops
- `AmbientSoundType` enum: rain, wind, night, pads
- Settings persisted in SharedPreferences (`settings.backgroundSoundOn`, `settings.ambientSoundType`)
- Assets: `assets/audio/ambient/{type}.mp3`

**Constraints:**
- Ambient does not auto-play outside of story playback
- Ambient does not play during reflection, PAL audio, or any non-narration audio
- No new dependencies (uses existing `just_audio`)
- Exactly 4 sound types in v1 — no dynamic additions
- Duplicate-start guard prevents concurrent playback of the same or overlapping sounds

---

## PALs Paths

**50. PALs Paths (Feature 50)**

PALs Paths is a top-level Scripture exploration and progression system that complements the mood-driven serving engine. It lives on page 2 of the main horizontal nav (Feature 48). It operates **only on Traditional stories** — Creative stories are invisible to every path type and every search result.

### Purpose

- Give users a structured way to explore Scripture through five path types: the featured **Life of Jesus** curated journey, plus Bible Order, Timeline, Themes, and Characters — in addition to the mood check-in
- Track long-horizon progression across a path ("David's Journey" completion, "The Life of Jesus" completion) without disturbing the 20-entry history cap
- Surface "what's next" in a deterministic, ordered way for path-launched sessions, without replacing mood expansion for mood-launched sessions
- Preserve path order as sacred: stories are traversed in canonical sequence and are never auto-skipped based on completion state (Feature 50.6)

### Access

- Enter via page 2 of the main horizontal nav (Feature 48)
- No other entry points in v1 (no deep links, no push notifications, no onboarding branch into a path)

### 50.1 Path Types (LOCKED)

Five path types. The enum is LOCKED for v1.

1. **`jesus_life`** — SPECIAL. The Life of Jesus (see 50.1b). Featured in the PALs Paths UI; visually distinguished from the other four path types and positioned at the top of the path-type selector (not buried in the Characters list).
2. **`bible_order`** — canonical Bible order, grouped by book. Ordering by `bibleOrderIndex` on each Traditional story; ties broken by `characterPathOrder`, then `storyId`.
3. **`timeline`** — grouped by one of 9 canonical eras (see 50.2).
4. **`themes`** — grouped by `themeTags[]` entries.
5. **`characters`** — grouped by `primaryCharacterId` (primary path membership) with `characterIds[]` as secondary membership. Ordered within a character path by `characterPathOrder`. **Jesus is NEVER a character path entry** — stories with Jesus as the primary figure are surfaced exclusively through `jesus_life` and `timeline` (`jesus_ministry` era).

### 50.1b The Life of Jesus (Special Path — LOCKED)

`jesus_life` is a **curated, chronologically ordered** journey through the life and ministry of Jesus. It is NOT auto-derived from metadata like the other path types.

**Curation rules:**

- The sequence is defined by a curated index asset: `assets/stories/jesus_life_index.json`, a single ordered list of `storyId` values. Editing the list is an owner-approved change (same posture as the timeline era list).
- Only stories where `primaryCharacterId == "jesus"` are eligible. Stories where Jesus is a secondary figure (`characterIds` contains `"jesus"` but `primaryCharacterId` is someone else) are NOT included.
- Order is manual — authored by the owner, not derived from `bibleOrderIndex`, `characterPathOrder`, or any other metadata field.
- The index is versioned; adding a story later appends it at the editor's chosen position, not automatically at the end.

**Canonical v1 sequence (reference — actual story IDs filled in during annotation):**

1. Birth of Jesus
2. Early life
3. Baptism
4. Wilderness temptation
5. Calling the disciples
6. Miracles
7. Teachings & parables
8. Key encounters (Zacchaeus, Samaritan woman, etc.)
9. Transfiguration
10. Triumphal entry
11. Last Supper
12. Crucifixion
13. Resurrection
14. Ascension

The v1 sequence is expected to grow as annotation batches land. The per-stage entries are ordering anchors, not hard stage labels shown to the user — the UI shows each story individually in sequence, not grouped by stage.

**Completion and progression:**

- Uses the exact same completion rule as every other path (Feature 50.4): story body completed at ≥ 90% playback. Reflection playback does not affect completion.
- Inside the canonical player during a `jesus_life` session, "Next in Your Journey" advances to the next entry in the curated index **by position** (Feature 50.6 — sequence rule). Completed entries are NOT skipped.
- On the `jesus_life` detail screen, "Continue Your Journey" uses the resume heuristic (Feature 50.6b): it jumps to the first entry in the curated index not yet in `CompletedStoriesStore`, or to the first entry if every story has been completed.
- `PathService.getCompletionPercentage('jesus_life', 'default')` is computed over the curated index, after kid-mode eligibility filtering.
- A Phase 4 completion badge (`badge_id: "life_of_jesus_complete"`, `badge_category: "path"`) is awarded when every eligible story in the curated index is completed. The badge is reserved in the allowlist for v1 but not awarded until Phase 4.

**UI prominence:**

- In the PALs Paths page (Feature 48 page 2), the path-type selector renders `jesus_life` as a visually distinct featured tile at the top of the selector, separated from the four standard path types. Exact visual treatment is owner-designed; the SPEC fixes only the position (top / featured) and the semantic distinction (not under Characters).
- When the user selects `jesus_life`, the main content area shows the curated sequence as a vertical list in order, with a "Continue Your Journey" affordance at the top when progress > 0.

**Kid mode:**

- If the curated sequence contains zero kid-eligible stories, the `jesus_life` featured tile is hidden entirely in kid mode (same rule as other empty paths).
- If the sequence contains a mix of kid-eligible and adult-only stories, `PathService` filters adult-only stories out before returning — kid-mode users see a shorter sequence, and the completion percentage denominator shrinks accordingly.

**Traditional only:**

- `jesus_life` follows the same Story Mode Non-Blur rule as all other path types: only Traditional stories. Creative stories with Jesus themes are never surfaced in `jesus_life`.

### 50.2 Canonical Timeline Eras (LOCKED)

The timeline path uses these nine era IDs. The list is LOCKED for v1 and requires owner approval to change.

- `creation`
- `patriarchs`
- `exodus`
- `judges`
- `kingdom`
- `exile`
- `return`
- `jesus_ministry`
- `early_church`

### 50.3 Character Path Disambiguation (LOCKED)

Characters with the same given name MUST use distinct `snake_case` IDs. A canonical registry at `assets/stories/character_registry.json` holds the disambiguated IDs plus `displayName` and a short descriptor. Seed IDs for v1 are listed in Feature 50.8.

Required rules:

- Each `primaryCharacterId` must exist in the registry
- Each entry in `characterIds[]` must exist in the registry
- A story's `primaryCharacterDisplayName` must match the registry's `displayName` for that ID
- Renaming a character ID after it ships requires a documented migration path (character IDs are an API contract once shipped)

### 50.4 Completion Rule (LOCKED)

A story is marked **completed** when **story body** playback position reaches **≥ 90%** of the **story body** duration, measured from the existing `just_audio` position stream in [ParablePlayerNotifier](../lib/providers/parable_player_notifier.dart).

- Completion is write-once idempotent: calling `CompletedStoriesStore.markCompleted(storyId)` twice for the same `storyId` is a no-op
- Completion persists across app restarts (separate from History)
- Completion is recorded regardless of launch source (mood, path, favorite, history, search) — any story-body playback reaching ≥ 90% counts
- Completion drives path progress; History (20-entry FIFO) is unchanged

**Story body only — LOCKED:**

- **Completion is measured on the story body only.** Reflection audio (Feature 34) is opt-in and plays after the story body finishes. Reflection playback position is NEVER used to compute completion.
- A user who skips reflection entirely gets the exact same completion signal as a user who plays it. Tying completion to reflection would penalize users who opt out of Feature 34, which is not acceptable.
- The "Read Scripture" bottom sheet (Feature 12) is similarly orthogonal — it does not affect completion.

**Non-goals for v1:**
- No scrub-gaming prevention. If users scrub past 90% of the story body immediately, the story is marked completed. This is an accepted v1 simplification.

**Deferred to v2 (flagged, not implemented):** a more robust completion definition combining ≥ 90% position with a minimum "actively playing" duration threshold, to prevent scrub-to-end abuse. Tracked as an open follow-up in the SPEC.

### 50.5 Path Completion Percentage

`PathService.getCompletionPercentage(pathType, pathId)` returns a value in `[0.0, 1.0]` computed as:

```
completed_eligible / total_eligible
```

where `eligible` means the story passes all currently active filters (kid_mode, translation compliance, content filter) — the same filter layer [ParableService](../lib/services/parable_service.dart) uses today. Ineligible stories never count toward the denominator, so a kid-mode user does not see "50% complete" on a path whose remaining stories are adult-only.

### 50.6 Next-in-Journey Rule (LOCKED — path order is sacred)

When a story is launched from a path, the launch call carries a `PathLaunchContext { pathType, pathId, positionInPath }`. The canonical player reads this context and renders a "Next in Your Journey" block at the bottom of the player screen **only when `launchContext != null`**.

**Rendering conditions:**

- Renders only when `launchContext != null`
- Standalone search launches that do not carry a path context do not render it
- Mood, favorite, and history launches do not render it UNLESS the launch explicitly carries a `PathLaunchContext` (a later phase may allow explicit hand-offs into a path from a non-path entry point — the rule is "context-driven, not source-driven")

**Content (LOCKED — path order is sacred):**

- Shows the title and scripture reference of the **next story in exact canonical path order** — i.e. the story at `positionInPath + 1` within `pathType + pathId`
- **Does NOT skip stories that have been previously listened to or completed.** Completed stories remain in sequence and are visually marked as completed in the path list, but path traversal from the player NEVER auto-skips them. This is the central rule of PALs Paths: a guided Scripture journey, not a "what haven't you heard yet" checklist.
- Shows exactly one "next" story — never a recommendation list
- Hides entirely only when the current story is the final entry in the path (`positionInPath + 1 >= pathLength`)
- A completed next story is shown with a subtle completion marker (soft gold check or similar — visual treatment deferred) but remains the active "next" affordance; tapping it replays the story and advances path position normally

**Distinction from Continue Your Journey (Feature 50.6b):**

"Next in Your Journey" inside the Story Player is a **sequence rule**: it advances along the canonical path order regardless of completion state. "Continue Your Journey" on the path detail screen is a **resume rule**: it jumps to a sensible resume point based on completion. The two are intentionally different and must not be conflated.

### 50.6b Continue Your Journey Rule

When a user lands on a path detail screen (not the player), a "Continue Your Journey" affordance appears at the top of the content area. Unlike "Next in Your Journey", this affordance uses a **resume** heuristic:

- Jumps to the first story in the path (in canonical order) whose `storyId` is NOT in `CompletedStoriesStore`
- If every story in the path is already completed, jumps to the first story in the path — the user is free to replay the journey from the beginning
- Is hidden only if the user has zero progress on this path yet (no interactions at all) AND the path has at least one story — in that case the user should simply tap the first story in the visible list

**Two "next" behaviors — do not merge:**

| Affordance | Location | Rule | Filters by completion? |
|---|---|---|---|
| Continue Your Journey | Path detail screen (path page 2) | Resume heuristic | YES — jumps to first incomplete |
| Next in Your Journey | Inside the Story Player | Sequence rule | NO — advances by canonical position |

`PathService` exposes these as two distinct methods:

- `getNextInPath(pathType, pathId, positionInPath)` — for the player. Advances by position. Kid-mode filtered. NEVER filtered by completion.
- `getResumePoint(pathType, pathId)` — for the path detail screen. Returns the first incomplete story after kid-mode filtering, or the first story if all complete.

### 50.7 Search

- **Scope:** Traditional stories only. Creative stories are invisible to search.
- **Query types:** verse ("John 3:16"), chapter ("Psalm 23"), book ("Genesis"), character ("David"), event ("burning bush"), keyword ("faith")
- **Priority order (LOCKED):**
  1. Scripture anchor match (`bibleSourceRef` / `bibleStoryKey`)
  2. Chapter or book match parsed from the query
  3. Metadata match (title, `themeTags[]`, `characterIds[]`, `characterDisplayNames[]`)
- **Kid mode:** search respects `kidFriendlyOnly` at the same filter layer as ParableService. Adult-only stories never surface in kid-mode search.
- **Empty paths / empty results:** hidden entirely rather than shown empty (avoids confusing child users with "no results")
- **Privacy:** the raw query string is NEVER persisted, logged, or sent in telemetry. Only the fact that a search was performed may be logged, via an opaque event count — see 50.10.

### 50.8 Character Registry Seed (v1)

The v1 seed registry is intentionally conservative and high-confidence. It ships at `assets/stories/character_registry.json`. Additions require owner approval. All IDs are `snake_case`.

**Old Testament:**
- `adam`
- `eve`
- `noah`
- `abraham`
- `sarah`
- `isaac`
- `rebekah`
- `jacob`
- `joseph_son_of_jacob`
- `moses`
- `aaron`
- `joshua`
- `deborah`
- `gideon`
- `samson`
- `ruth`
- `samuel`
- `saul_king`
- `david`
- `solomon`
- `elijah`
- `elisha`
- `daniel`
- `jonah`
- `esther`

**New Testament (with disambiguation where names collide):**
- `john_baptist`
- `john_disciple`
- `mary_mother_jesus`
- `mary_magdalene`
- `mary_sister_of_martha`
- `james_son_zebedee`
- `james_son_alphaeus`
- `james_brother_of_jesus`
- `simon_peter`
- `simon_zealot`
- `judas_iscariot`
- `judas_thaddaeus`
- `paul_apostle` (a.k.a. Saul of Tarsus — stored under `paul_apostle` post-conversion; pre-conversion appearances map to the same ID for path purposes)
- `stephen_martyr`
- `barnabas`
- `lydia`
- `priscilla`
- `aquila`
- `timothy`

**Jesus (special case — LOCKED):**
- `jesus` is a **reserved character ID**. Stories with Jesus as the primary figure use `primaryCharacterId: "jesus"`. Jesus is never a "secondary" in `characterIds[]` when he is also the primary.
- `jesus` **NEVER appears as a Character Path** in the Characters path list. The Characters path enumerates every `primaryCharacterId` present in the manifest **except** `"jesus"`.
- Stories with `primaryCharacterId: "jesus"` are surfaced exclusively through:
  1. `jesus_life` (Feature 50.1b), the curated Life of Jesus path
  2. `timeline` — specifically the `jesus_ministry` era
  3. Keyword/scripture/book search results (Feature 50.7)
  4. Mood flow, favorites, history, and `bible_order` path (unchanged)
- A story where Jesus is a secondary figure (`characterIds` contains `"jesus"` but `primaryCharacterId` is someone else, e.g. a Peter-centric narrative where Jesus appears) is handled normally under that other character's path — the `jesus` ID in `characterIds` does NOT promote the story into `jesus_life`.

### 50.9 Partial Metadata Coverage (LOCKED)

The 8 new metadata fields added to Feature 8 are all **optional**. The following rules govern partial coverage:

- A story missing `primaryCharacterId` does not appear in any Characters path
- A story missing `bibleOrderIndex` does not appear in the Bible Order path
- A story missing `timelineEra` does not appear in the Timeline path
- A story missing `themeTags[]` (or with an empty list) does not appear in any Themes path
- A story with none of these fields still serves normally via mood flow, favorites, and history. It remains searchable only through baseline searchable fields such as `title`, `bibleSourceRef`, and `bibleStoryKey` where present — it will NOT surface via character, theme, or timeline filters until those fields are populated. This keeps the promise precise: the minimum search surface is the baseline fields, and structured path membership is opt-in via annotation.
- `PathService` MUST NOT crash or warn on missing optional fields
- `PathService` MUST NOT surface an empty path in the UI — paths with zero eligible stories are hidden from the path list

This lets PALs Paths ship the moment the navigation and service layer land, and lets content coverage grow over time without blocking releases.

### 50.10 Telemetry (allowlisted)

Six new events. All payloads are fire-and-forget via `AppLogger.logEvent()` and pass through the existing allowlist. New allowlisted payload keys are added to the canonical allowlist in `lib/core/analytics_events.dart`:

| Event | Allowed payload fields |
|---|---|
| `path_opened` | `path_type`, `path_id` |
| `character_path_selected` | `path_type` (always `"characters"`), `path_id` (character_id), `language_style` |
| `continue_journey_clicked` | `path_type`, `path_id` |
| `story_completed` | `story_id`, `mood`, `mode`, `length_bucket`, `kid_friendly`, `translation_id`, `language_style`, `voice_key`, `source` |
| `path_completed` | `path_type`, `path_id`, `completion_pct` |
| `badge_awarded` | `badge_id`, `badge_category` |

**Path type enum** (valid values for `path_type`): `jesus_life`, `bible_order`, `timeline`, `themes`, `characters`.

**Path ID conventions:**
- For `jesus_life`: `path_id` is always `"default"` (single curated sequence)
- For `bible_order`: `path_id` is a book slug (e.g. `"genesis"`)
- For `timeline`: `path_id` is one of the 9 era IDs (e.g. `"kingdom"`)
- For `themes`: `path_id` is a theme tag (e.g. `"faith"`)
- For `characters`: `path_id` is a `primaryCharacterId` from the registry (NEVER `"jesus"` — see 50.8)

New allowlist keys (added to `analyticsAllowedKeys`):
- `path_type`
- `path_id`
- `completion_pct`
- `badge_id`
- `badge_category`
- `source` (one of: `mood`, `path`, `favorite`, `history`, `search`)

Forbidden in all path-related payloads (consistent with existing invariants):
- Raw search query strings
- User text of any kind
- Minute-based length fields
- Tradition / denomination fields
- PII

### 50.11 Data Capacity

Two new persisted collections. Both are capped and healed by `StorageService.validateAndHealInvariants()` on startup.

| Collection | Max Entries | Enforcement | Ordering |
|---|---|---|---|
| `completedStories` | 1000 | Storage + Migration | Insertion order (set semantics) |
| `awardedBadges` | 200 | Storage + Migration | Insertion order (set semantics) |

`completedStories` is a set of `storyId` values — no duplicates possible. `awardedBadges` is a set of `badge_id` values — no duplicates possible. Both caps are high enough that hitting them is unlikely; if hit, oldest entries are evicted FIFO.

### 50.12 Canonical Player Contract (LOCKED)

All story launches — from PAL Sanctuary, Mood, PALs Paths, search, character paths, Continue Journey, Favorites, History — MUST route to the single canonical [ParablePlayerScreen](../lib/features/pals_parables/parable_player_screen.dart). No duplicate player implementations are permitted. This contract is enforced by repo-wide test: any new `...PlayerScreen` widget outside the canonical path fails the test suite.

### 50.13 Badges (Phase 4 — NOT v1)

The badge subsystem (BadgeService, BadgeRegistry, overlay widget, award-once semantics, Character → Path → Progress → Engagement priority) is defined here for completeness but is **deferred to Phase 4**. v1 ships the telemetry event `badge_awarded` and the capacity cap, so the event stream and storage shape are stable before the subsystem lands. No badge is awarded in v1.

Badge categories (for the Phase 4 implementation):
1. **Character completion** — all stories in a character path completed
2. **Path completion** — all stories in a non-character path completed
3. **Progress milestones** — 1, 10, 25, 50, 100 stories completed
4. **Engagement** — first favorite, first reflection, first share, streak thresholds

Award priority (when multiple would trigger simultaneously): Character → Path → Progress → Engagement. Badges are shown in the canonical player as a soft gold glow overlay with minimal animation. No gamification language, no points, no leaderboards.

### 50.14 Open Questions (v1 draft)

- Does the Themes path use a LOCKED theme vocabulary (e.g. `faith`, `fear`, `grief`, `provision`, `mercy`, `courage`) or a free-form tag set? v1 leans toward LOCKED — requires owner approval of the vocabulary before first annotation batch lands.
- Should search query strings be hashed + counted for aggregate "what are users searching for" insight, or not persisted at all? v1 defaults to not persisted at all.
- Scrub-to-end abuse — follow-up for v2 per §50.4.
- Visual treatment of the `jesus_life` featured tile in the path-type selector (color, size, position relative to other tiles). SPEC fixes only the position (top/featured) and the semantic distinction. Exact visual design deferred to owner.

---

## Settings

**22. Creative/Traditional Mode Toggle**
- Global setting for storytelling mode
- **Default**: Traditional mode
- **Persistence**: Mode persists across app restarts until explicitly changed
- Affects parable selection and generation
- Only two modes: Traditional and Creative (no other modes exist)

**23. Change Bible Translation**
- Allows user to update preferred Bible translation(s) after onboarding

**24. Content Filtering / Moderation Controls**
- Filter inappropriate or offensive content in generated parables
- Applied before content reaches user

**25. Everyday Life Reflection Toggle**
- Label: "Relate stories to everyday life"
- Default: ON (enabled on first launch)
- Controls whether post-story reflections are displayed
- Persisted in UserPreferences

**25a. Bedtime Mode Toggle**
- Label: "Bedtime Mode"
- Subtitle: "Dims the screen, fades audio after stories end"
- Default: OFF
- When enabled, shows sleep timer dropdown (0 / 5 / 10 / 15 / 30 min)
- Persisted in UserPreferences (`bedtimeModeEnabled`, `sleepTimerMinutes`)

**25b. Background Sound Settings**
- Label: "Background Sound"
- Subtitle: "Play ambient audio during stories"
- Default: OFF
- When enabled, shows sound type selector: Rain / Soft Wind / Night Ambience / Soft Pads
- Persisted in SharedPreferences (`settings.backgroundSoundOn`, `settings.ambientSoundType`)

---

## Security & Technical Architecture

**26. User Data Encryption**
- Secure storage for:
  - Mood input text
  - User preferences
  - Favorites metadata
  - History metadata

**27. Local Parable Library + Optional Cloud Sync**
- Parable metadata can sync from Mac (generation source) to user devices
- Personal user data remains local only (not synced to cloud)
- Only story libraries and story-related metadata sync
- User preferences, favorites, and history stay on-device

**Platform-specific audio delivery (Cloud Foundation v1):**
- iOS uses fully bundled audio assets for playback
- Android uses bundled seed assets plus Cloudflare R2 HTTP audio delivery with persistent local caching
- Android includes a bundled seed set of 32 short stories covering all mood × mode × audience combinations
- Android works offline with bundled and previously cached audio
- No Firebase, no auth, no Firestore, no messaging — R2 is a dumb file host accessed via HTTP only

**Smart Offline Library v1** (extends Cloud Foundation v1, Android only)
- Cached story audio is automatically managed within a soft 600 MB target.
  The 600 MB target is a goal, not a hard cap — the system may temporarily
  exceed it (for example, when favorited audio alone is larger than the target).
- When a user favorites a story, its audio is silently downloaded if not
  already cached, and is protected from auto-eviction. There is no new
  user-facing affordance for this behavior — no "Download" button, no
  "Available offline" label, and no new explanatory UI about offline
  storage. Existing playback download progress UI from Cloud Foundation v1
  may still appear when audio must be fetched on demand.
- Listened-but-not-favorited audio is treated as disposable cache. It may
  be auto-evicted by the cache management routine to keep total cache size
  near the soft target.
- Cache management is recency-based for v1. The eviction routine prefers
  to keep audio that was most recently read or written, using filesystem
  modified-time (mtime) updated by normal cache reads and writes. v1 does
  NOT distinguish "recently replayed" from "recently completed" as
  separate ranked concepts — both are captured by the same recency signal.
- Richer ranking — predictive prefetch driven by behavior signals (length
  preference, mood patterns, time-of-day usage, replay frequency,
  predicted-interest scoring) — is RESERVED for v2.
- Removing a favorite does NOT immediately delete that story's local
  audio. It only removes the eviction-protection flag. The audio remains
  cached and continues to play offline until a future cache-management
  pass evicts it as part of normal recency-based cleanup.
- The Smart Offline Library is intentionally invisible to the user:
  - No "Downloaded", "Offline", or "Saved locally" labels
  - No tooltips or copy explaining offline behavior
  - No settings toggles for offline storage or cache size
  - No storage usage indicators
  - No "Download" buttons
  The product principle is "the app just works, even offline" — not
  "the app is managing storage."
- All cached audio resides inside the app sandbox
  (`getApplicationDocumentsDirectory()/audio_cache/`) and is removed
  automatically by the OS on app uninstall. Shared/external storage is
  not used.

---

## Observability & Logging (v1)

Bible PAL implements minimal, privacy-safe structured logging for diagnostics and crash breadcrumbs. This is NOT enterprise observability — it's lightweight instrumentation to make real-user bugs diagnosable.

### Design Principles

**38. Privacy-Safe Logging**
- NEVER log raw user-entered text (mood input, prompts, transcripts)
- NEVER log PII (names, emails, phones, addresses)
- Use story IDs, mode flags, and numeric scores — not content
- If correlation needed, use local random UUIDs (not user identifiers)

**39. Structured JSON Format**
- All logs are single-line JSON for machine parsing
- Required fields: `event`, `level`, `ts` (ISO8601 UTC)
- Optional fields: `app_version`, `app_build`, `story_id`, etc.
- Example: `{"event":"story_selected","level":"info","ts":"2026-01-05T10:12:33Z","story_id":"parable_113","mode":"kid_traditional"}`

**40. Breadcrumb Ring Buffer**
- In-memory buffer of last 50 events
- Attached to error logs for crash diagnostics
- Accessible via `getRecentBreadcrumbs()` for debug screens
- **Optional persistence** when `DIAGNOSTICS_ENABLED=true`:
  - Breadcrumbs persist to disk (survive app restart)
  - Throttled writes (5 second debounce) to minimize I/O
  - Load on startup and merge with in-memory buffer

**41. Safe-Fail Behavior**
- Logging NEVER crashes the app
- If logging fails, it silently no-ops
- Malformed data is blocked, not thrown

### Event Categories

**Story Serving Events:**
- `story_pool_loaded` — Manifest loaded with counts
- `story_selected` — Final parable chosen (story_id, mode, length, score)
- `story_excluded` — Parable filtered out (reason_code)
- `pool_exhausted` — All eligible stories played (strategy=LRP)
- `filters_applied` — Active filters for selection

**Safety/Invariant Events:**
- `kid_mode_guard_pass` — Kid mode filter succeeded
- `kid_mode_guard_fail` — Kid mode violation detected
- `translation_policy_block` — Banned translation blocked
- `invariant_violation` — General invariant failure

**Audio Lifecycle Events:**
- `audio_asset_missing` — Expected audio file not found
- `audio_play_start` — Playback began
- `audio_play_pause` — Playback paused (with position_ms)
- `audio_play_complete` — Playback finished
- `audio_error` — Playback error occurred
- `ambient_started` — Ambient audio started (`sound_type`)
- `ambient_stopped` — Ambient audio stopped (`sound_type`)
- `ambient_type_changed` — Sound type changed in settings (`from`, `to`)

**App Lifecycle Events:**
- `app_started` — App launched (version, build)
- `screen_view` — Screen navigation
- `length_selected` — User chose story length
- `mode_changed` — Storytelling mode toggled
- `translation_changed` — Bible translation updated

**Error Events:**
- `error_caught` — Exception caught (error_type, location, breadcrumbs_attached)

### Implementation

**Core Module:** `lib/core/app_logger.dart`

```dart
// Log a structured event
logEvent('story_selected', {
  'story_id': 'parable_113',
  'mode': 'kid_traditional',
  'length_min': 5,
  'score': 0.82,
});

// Log an error with breadcrumbs
logError('audio_load_failed', 'ParablePlayerNotifier.loadParable',
  storyId: parable.storyId,
  errorMessage: e.toString(),
);

// Get breadcrumbs for crash report
final breadcrumbs = getRecentBreadcrumbs();
```

**42. Diagnostics Mode (Optional)**

Enable via: `flutter run --dart-define=DIAGNOSTICS_ENABLED=true`

When enabled:
- Breadcrumbs persist to disk (SharedPreferences)
- Hidden Diagnostics screen accessible
- Export support bundle to clipboard for bug reports
- Crash reporter hooks ready for future SDK integration
- Lifecycle observer flushes breadcrumbs on app backgrounding

When disabled (default):
- Breadcrumbs are in-memory only (no disk I/O)
- Diagnostics screen shows "not available" message
- Crash reporter uses NoopCrashReporter (logs to console only)
- No lifecycle observers registered (zero overhead)

**Session ID:**
- Random 16-character hex string generated once per app run
- Used to correlate events without PII
- Included in support bundle export
- NOT persisted across app restarts

**Support Bundle Export:**
The diagnostics screen exports a full support bundle containing:
- `session_id` - Random hex ID for this app run
- `exported_at` - UTC ISO8601 timestamp
- `diagnostics_enabled` - Boolean flag
- `app_version` / `app_build` - App version info
- `platform` / `platform_version` - OS info (safe, non-PII)
- `last_filters` - Last known filter state (safe fields only)
- `breadcrumb_count` / `breadcrumbs` - Last 50 events (already sanitized)

**Diagnostics Screen Features:**
- View last 50 breadcrumbs with event, level, timestamp
- Expandable tiles showing full JSON data
- Copy support bundle to clipboard (formatted JSON)
- Clear breadcrumbs button with confirmation
- Refresh button to reload from memory + disk

**Lifecycle Flush:**
- `DiagnosticsLifecycleObserver` registered on app start (when enabled)
- Flushes pending breadcrumbs to disk on `paused` or `inactive` state
- Ensures breadcrumbs survive app termination

**Crash Reporter Interface:**
- `CrashReporter` abstract interface for future Crashlytics/Sentry integration
- `NoopCrashReporter` default implementation (console logging only)
- Automatic breadcrumb forwarding to crash reporter
- Error reporting hook in `logError()`

**43. Error Type Taxonomy**

All `errorType` values passed to `logError()` must follow the naming convention:
- Format: `snake_case`
- Pattern: `{category}_{specific_error}`
- Example: `audio_load_failed`, `network_timeout`

See [ERROR_TAXONOMY.md](ERROR_TAXONOMY.md) for the canonical list of error types and categories.

### Non-Goals

- No external logging vendors or dashboards (deferred via CrashReporter interface)
- No storing or transmitting user input text
- No user tracking or identification

### Anonymous Usage Telemetry — Favorites

**44. Story Favorited Event**

When a user adds a story to favorites, a single `story_favorited` event is emitted via `AppLogger.logEvent()`. This enables aggregate insight into which content resonates without tracking individual users.

**Event Name:** `story_favorited`

**Allowlisted Payload Fields (EXHAUSTIVE):**

| Field | Source | Example |
|-------|--------|---------|
| `story_id` | `Parable.storyId` | `"807"` |
| `mood` | `Parable.mood` | `"weary"` |
| `mode` | `Parable.storytellingMode` | `"traditional"` |
| `length_bucket` | `Parable.lengthBucket.name` | `"short"` |
| `kid_friendly` | `Parable.kidFriendly` | `true` |
| `translation_id` | `Parable.translationId` | `"WEB"` |
| `language_style` | `Parable.languageStyle` | `"KJV"` |
| `voice_key` | `Parable.narratorVoiceKey` | `"VOICE_JAMES_HUSKY"` |

**45. PALs Paths Events (Feature 50.10)**

Six additional allowlisted events introduced by Feature 50. All share the same privacy guarantees as `story_favorited`: fire-and-forget, safe-fail, allowlist-validated, never blocks user action.

| Event | Field | Example |
|---|---|---|
| `path_opened` | `path_type` | `"characters"` |
| `path_opened` | `path_id` | `"david"` |
| `character_path_selected` | `path_type` | `"characters"` |
| `character_path_selected` | `path_id` | `"david"` |
| `character_path_selected` | `language_style` | `"WEB"` |
| `continue_journey_clicked` | `path_type` | `"timeline"` |
| `continue_journey_clicked` | `path_id` | `"kingdom"` |
| `story_completed` | `story_id`, `mood`, `mode`, `length_bucket`, `kid_friendly`, `translation_id`, `language_style`, `voice_key`, `source` | (same shape as `story_favorited` plus `source`) |
| `path_completed` | `path_type`, `path_id`, `completion_pct` | `"themes"`, `"faith"`, `1.0` |
| `badge_awarded` | `badge_id`, `badge_category` | `"davids_journey_complete"`, `"character"` |

**New allowlist keys added to `analyticsAllowedKeys`:** `path_type`, `path_id`, `completion_pct`, `badge_id`, `badge_category`, `source`.

All existing forbidden keys (user text, PII, minute-based length, tradition) remain forbidden. The raw search query string is NEVER logged.

**Privacy Constraints:**
- NO user text, titles, scripture content, or PII
- NO minute-based length fields (telemetry invariant)
- NO tradition/denomination fields (Christian General Only invariant)
- Payload fields are validated against an allowlist at compile time via tests

**Emission Rules:**
- Fire-and-forget: result is ignored by caller
- Single emission: exactly one event per `addFavorite()` call
- After storage: event fires only after successful `StorageService.addFavorite()`
- Safe-fail: emission failure never blocks the favorite operation

**Implementation:**
- Event builder: `lib/core/analytics_events.dart` → `AnalyticsEvents.logStoryFavorited(Parable)`
- Call site: `lib/providers/app_state_notifier.dart` → `addFavorite()`
- Backend: existing `AppLogger.logEvent()` (no Firebase, no external vendor)

---

## Development Principles

1. **SPEC.md is the source of truth** - All code must align with this document
2. **No feature creep** - Do not add features unless explicitly requested
3. **Update SPEC.md first** - Any intentional behavior changes must update this document before code changes
4. **Maintain simplicity** - Follow the specified features without over-engineering
