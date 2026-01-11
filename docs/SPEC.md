# Bible PAL - Technical Specification

**Version:** 1.2
**Last Updated:** 2026-01-03

This document is the single source of truth for Bible PAL's features and behavior. All code must follow this specification. Changes to app behavior require explicit updates to this document.

---

## Table of Contents

1. [PAL's Parables System](#pals-parables-system)
2. [Kid Bedtime Safe Harness](#kid-bedtime-safe-harness)
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

**2. Context-Aware Emotional Check-In Greeting (Feature 2.1)**
- After tapping PAL's Parables, PAL greets the user with a time-appropriate emotional check-in question
- The greeting adjusts based on current time of day
- Randomly selects from 3-5 phrasing variations for naturalness
- Avoids sounding robotic or repetitive
- This greeting leads directly into mood detection

**Time Windows and Greeting Options:**

🌅 **Morning (5 AM – 11:59 AM)**
- "Good morning! How's your day starting out?"
- "Morning! How are you feeling so far today?"
- "Hi there — how's your morning going?"
- "Good morning! What's on your heart today?"

🌤️ **Afternoon (12 PM – 4:59 PM)**
- "How's your afternoon going?"
- "I'm glad you're here — how are you doing today?"
- "How's your day been so far?"
- "Checking in — how are you feeling this afternoon?"

🌇 **Evening (5 PM – 8:59 PM)**
- "How's your evening going?"
- "Good to see you — how are you feeling tonight?"
- "How has your day been winding down?"
- "How are you doing this evening?"

🌙 **Late Night (9 PM – 4:59 AM)**
- "How's your night going?"
- "It's a quiet hour — how are you feeling?"
- "How are you doing tonight?"
- "Is everything going okay this late? How are you feeling?"

**Implementation Notes:**
- App randomly selects one greeting from the appropriate time window
- Displayed on PAL's Parables mood check-in screen
- Choice of greeting does not affect mood classification, only UX
- This is the first step before mood detection

**3. Mood Detection Flow**
- User can type or speak their answer to the greeting question
- Text is analyzed to detect mood (positive / neutral / negative plus finer emotional tags)

**4. Compassionate Reply System**
- After mood detection, app shows a short, caring text reply that matches the mood
- This reply appears before the parable starts

**5. Parable Generation / Selection Engine**
- Chooses or generates a parable based on:
  - User's detected mood
  - Faith tradition
  - Storytelling mode (creative vs traditional)
  - Selected length
- If pre-generated stories exist that match criteria, selects one
- Otherwise generates a new one on demand

### Story Length & Generation

**6. Story Length Buckets**

Three user-facing length options (no minute estimates shown to users):
- **Short Story**: 300–700 words
- **Full Story**: 900–1400 words
- **Long Story**: 1700–2600 words

Implementation notes:
- UI presents descriptive labels only (Short/Full/Long), not minutes
- Selection filters by `StoryLengthBucket` enum (short/full/long)
- Word ranges are for generation validation; selection uses bucket mapping
- Length selection is stateless (chosen fresh each session after mood detection)

**Compatibility with existing assets:**
- Existing stories store `length` in minutes (5, 10, 15, 20)
- Mapping: 5-min → short, 10-min → short, 15-min → full, 20-min → long
- Manifest schema unchanged; `Parable.lengthBucket` getter handles mapping

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
- `length` (minutes: 5, 10, 15, or 20 - legacy field for asset compatibility)
- `lengthBucket` (computed: short, full, or long - used for selection)
- `faithTradition`
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
  - `faithTradition`
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
  - `faithTradition`
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

### Golden Prompt Mode: Adult Traditional 5-Min Generation

Golden Prompt mode is a specialized generation strategy for adult traditional 5-minute parables that uses structure-based length control instead of continuation prompts.

**Goals:**
- Reliable single-shot generation that meets word count requirements
- Exploit Gemma-7B's strength with constrained, structured prompts
- Eliminate story repetition/duplication bugs caused by continuation logic

**Non-Goals:**
- Creative mode support (standard mode only)
- Kid-friendly generation (separate harness)
- Variable-length stories (5-min only)

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
- If attempt 1 word count < 450: regenerate fresh with stricter structure (12 paragraphs)
- NO continuation prompts — always single-shot generation
- Each retry uses the same mood but escalated structure

**Output:**
- Filename pattern: `parable_3XX_<mood>_5min_golden_trad.txt`
- Story ID range: 301-308 (one per mood)
- YAML frontmatter with `mode: golden_traditional`

**Quarantine Behavior:**
- If attempt 2 still fails min_words (< 450): story is quarantined
- Quarantine location: `assets/stories_failed/`
- Metadata includes: `failure_reason: word_count_too_low`, `actual_words`, `attempts`

**Acceptance Examples:**

1. **Escalation case**: If attempt 1 produces 433 words, attempt 2 MUST regenerate with 12 paragraphs (not continue the story).

2. **Quarantine case**: If attempt 2 still produces only 420 words, the story MUST be quarantined to `assets/stories_failed/` with `kidSafe: false` equivalent marking.

3. **Success case**: If attempt 1 produces 512 words, no retry is needed — story is saved immediately.

**Script:**
- `server/generate_adult_traditional_stories.sh --golden-prompt`
- Prompt template: `server/prompts/golden_trad_adult_5min.prompt.txt`
- Contract: `server/contracts/golden_contract_trad_adult_5min.yaml`

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
  - Faith tradition
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

---

## Kid Bedtime Safe Harness

The Kid Bedtime Safe Harness ensures that all kid-mode story generations are safe for children ages 5-9 listening at bedtime. Parents can confidently let their child fall asleep while PAL's Stories plays.

### Contract Injection

**28. Kid Bedtime Contract**
- All kid-mode generations MUST include the Kid Bedtime Contract in the prompt
- Contract location: `docs/prompts/kid_bedtime_contract.txt`
- Contract specifies:
  - Audience: ages 5-9 bedtime audio
  - Calm/comforting tone requirement
  - No peril/violence/terror imagery
  - No crowns/thrones/power reward arcs
  - Biblical accuracy (no invented promotions)
  - Fixed 5-part structure
  - Soothing bedtime closing requirement
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
- Ending MUST include bedtime/sleep signals:
  - Examples: sleep, rest, dream, peaceful, calm, quiet, stars, moon, blanket, cozy

### Post-Generation Validator

**31. Validation Pipeline**
- Validator: `server/kid_bedtime_validator.sh` (bash) or `lib/safety/kid_bedtime_validator.dart` (Dart)
- Runs after each generation attempt
- Checks:
  1. No forbidden words present
  2. Required structure exists
  3. Bedtime closing signal present
  4. Sentence length within limits
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

**33. Kid Bedtime Harness**
- Harness script: `server/kid_bedtime_harness.sh`
- Wraps Gemma generation with validation loop
- Process:
  1. Inject Kid Bedtime Contract into prompt
  2. Call Ollama/Gemma to generate story
  3. Validate output against contract
  4. If failed, append repair instruction and retry
  5. Repeat until valid or max attempts reached
- Creates metadata file with `kidSafe` boolean and `validationFailures` array

---

## Onboarding

**18. Faith Tradition Selector**
- Presented on first launch
- Options include:
  - Catholic
  - Protestant
  - Orthodox
  - Messianic
  - Non-Denominational
  - Other
- Influences story details and scripture interpretation
- User can change later in Settings

> **V1 Scope:** Denomination selector is disabled in v1. All users default to 'christian' tradition.
> Controlled by `lib/core/feature_flags.dart` via `ENABLE_DENOMINATION_SELECTOR` dart-define (default: false).
> Enable in v2+ with: `flutter run --dart-define=ENABLE_DENOMINATION_SELECTOR=true`

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

**When Enabled:**
- Display a 2-4 sentence reflection after story completion
- Optionally show one gentle reflection question
- Reflection derives from story metadata (mood, emotional tags) without additional AI calls

**When Disabled:**
- No reflection UI, audio, or questions appear

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
- Global setting for default storytelling mode
- Affects parable selection and generation

**23. Change Faith Tradition**
- Allows user to update faith tradition after onboarding

**24. Change Bible Translation**
- Allows user to update preferred Bible translation(s) after onboarding

**25. Content Filtering / Moderation Controls**
- Filter inappropriate or offensive content in generated parables
- Applied before content reaches user

**26. Everyday Life Reflection Toggle**
- Label: "Relate stories to everyday life"
- Default: ON (enabled on first launch)
- Controls whether post-story reflections are displayed
- Persisted in UserPreferences

---

## Security & Technical Architecture

**27. User Data Encryption**
- Secure storage for:
  - Mood input text
  - User preferences
  - Favorites metadata
  - History metadata

**28. Local Parable Library + Optional Cloud Sync**
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
- `tradition_changed` — Faith tradition updated
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
- No analytics or user tracking

---

## Development Principles

1. **SPEC.md is the source of truth** - All code must align with this document
2. **No feature creep** - Do not add features unless explicitly requested
3. **Update SPEC.md first** - Any intentional behavior changes must update this document before code changes
4. **Maintain simplicity** - Follow the specified features without over-engineering
