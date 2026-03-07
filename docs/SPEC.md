# Bible PAL - Technical Specification

**Version:** 2.0
**Last Updated:** 2026-02-27

This document is the single source of truth for Bible PAL's features and behavior. All code must follow this specification. Changes to app behavior require explicit updates to this document.

---

## Table of Contents

1. [PAL's Parables System](#pals-parables-system)
2. [Kid Safe Harness](#kid-safe-harness)
3. [Onboarding](#onboarding)
4. [Daily Bread](#daily-bread)
5. [Post-Story Everyday Life Reflection](#post-story-everyday-life-reflection)
6. [Settings](#settings)
7. [Security & Technical Architecture](#security--technical-architecture)

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
- **Quick mood buttons:** Tap one of 5 mood buttons (Joyful, Neutral, Weary, Anxious, Hurting) — bypasses keyword detection, directly sets mood
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
- 30 total micro-responses: 5 mood buckets (joyful, weary, anxious, hurting, neutral) × 6 lines each
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

Three user-facing length options (no minute estimates shown to users):
- **Short Story**: 250–600 words (LOCKED SPEC)
- **Full Story**: 601–1200 words (LOCKED SPEC)
- **Long Story**: 1201–2000 words (LOCKED SPEC)

Implementation notes:
- UI presents descriptive labels only (Short/Full/Long), not minutes
- Selection filters by `StoryLengthBucket` enum (short/full/long)
- Word ranges are for generation validation; selection uses bucket mapping
- Length selector is on the main menu screen (below PAL's Parables button)
- Session-scoped: user picks length before entering PAL flow; selection persists for the session but resets on app restart
- Not persisted to SharedPreferences

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
- Displays during parable playback
- Lists all Bible verses used in the story
- Uses user's selected Bible translation
- Source list saved per `storyId`
- Reused in Favorites and History views

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
- **One Bible story per mood**: Each mood has exactly ONE canonical Bible story. This ensures users always hear the same Bible story for their emotional state.

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

**Validation:**
- Traditional stories without `bibleSourceRef` are **EXCLUDED** from the serving pool
- Traditional stories without `bibleStoryKey` are **EXCLUDED** from the serving pool
- Stories with MoDC narrator patterns fail validation
- Stories with invented inner-monologue markers fail validation
- Stories that read as devotional commentary rather than narrative fail validation
- Multiple Traditional stories sharing a mood but different `bibleStoryKey` fail validation

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
3. Show "Hear Reflection" button (if reflection audio exists)
4. User taps button → play reflection audio
5. User may dismiss at any time

**When Disabled:**
- No reflection UI, audio, or questions appear
- Scripture reference for Traditional stories is still shown

**35. Reflection Language Constraints**

Reflections MUST:
- Use descriptive, non-prescriptive language
- Describe patterns, not instructions
- Use phrases like "often looks like", "can reflect", "stories like this show..."

Reflections MUST NOT:
- Give advice ("you should", "try to")
- Make diagnostic claims ("you are feeling...")
- Promise outcomes ("this will help you...")
- Use therapeutic language

**36. Kid Mode Reflection Constraints**

When `kidFriendlyOnly` is enabled:
- Reflection language is short and literal
- No abstract concepts or emotional probing
- Age-appropriate vocabulary (5-9 year olds)
- Example tone: "This story shows that being kind matters, even when things feel unfair."

**37. Reflection Question (Optional)**

- A single, gentle reflection question may follow the reflection text
- Questions are open-ended, not leading
- User may dismiss/skip without answering
- No user response is stored or tracked

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
