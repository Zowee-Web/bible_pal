# Bible PAL - Architecture Decision Records

This document logs key design decisions and trade-offs made during development.

---

## ADR-001: History Limit Reduced to 20 Entries

**Date:** 2026-01-03
**Status:** Accepted
**Context:** SPEC.md originally specified 100 history entries, but INVARIANTS.md enforced 20 entries. Code implementation followed INVARIANTS (20 entries).

**Decision:** Align SPEC.md with INVARIANTS.md by changing History limit from 100 to 20.

**Rationale:**
- 20 entries provides sufficient history for user needs
- Reduces storage footprint on mobile devices
- Aligns with existing code implementation
- INVARIANTS document takes precedence for safety-critical limits

**Consequences:**
- SPEC.md §11 updated: "Stores last **20 entries only**"
- No code changes required (already implemented correctly)

---

## ADR-002: Multi-Voice Playback Deferred + Forbidden Voices

**Date:** 2026-01-03
**Updated:** 2026-01-11
**Status:** Deferred (multi-voice); Accepted (forbidden voices)
**Context:** SPEC.md §17 originally specified "Multiple voices per story" as a feature. Testing revealed quality issues with certain voices and multi-voice coordination complexity.

**Decision:**
1. Defer multi-voice playback. Use single narrator voice per story.
2. **FORBIDDEN VOICES:** The following ElevenLabs voices are permanently banned from Bible PAL:
   - **Grace** — Removed from voice pool
   - **Abilene** — Child voice, quality issues
   - **Grant** — Child voice, quality issues

**Rationale:**
- Child voices (Grant, Abilene) did not sound natural in stories
- Grace voice removed per project policy
- Multi-voice coordination adds production complexity
- Single narrator provides consistent, high-quality experience
- Feature can be revisited when voice quality improves

**Forbidden Voice Enforcement:**
- These voices must NOT appear in: voice pools, .env files, generation scripts, test fixtures, or fallback logic
- `server/voices.json` includes `_forbiddenVoices` section documenting the ban
- Treat these voices as non-existent for this project

**Consequences:**
- SPEC.md §17 updated: "Single narrator voice per story (multi-voice deferred)"
- Multi-voice generation scripts disabled (.DISABLED suffix)
- Existing multi-voice test story removed from manifest
- Grace, Grant, and Abilene voices removed from .env
- Default voice changed from Grace to James Husky in gen_one_audio.sh

**PAL V2 Clarification (2026-02-27):** The PAL V2 update introduces a voice display name "Grace" (`VOICE_GRACE`) which maps to ElevenLabs voice **Juniper** — NOT the forbidden ElevenLabs voice named "Grace." The forbidden "Grace" voice remains banned. The display name was chosen for the user-facing persona; the underlying ElevenLabs voice is different.

---

## ADR-003: Kid Bedtime Safe Harness (Prompt Constraints + Validator)

**Date:** 2026-01-03
**Status:** Accepted
**Context:** Kid-mode story generation using Gemma 7B (Ollama) occasionally produced content inappropriate for bedtime listening by children ages 5-9. Issues included:
- Predator imagery (roaring lions, snapping jaws)
- Death/violence language
- Biblical hallucinations (e.g., "Jonah was crowned king")
- Startling or scary descriptions
- Stories lacking calm bedtime closings

The question was: How do we ensure kid-mode stories are truly safe for unattended bedtime listening?

**Decision:** Implement a multi-layer "Kid Bedtime Safe Harness" using:
1. **Prompt-level contract injection** - Strict rules injected into every Gemma prompt
2. **Post-generation validation** - Scanner checks for forbidden words and structure
3. **Bounded regeneration** - Automatic retry with repair instructions (max 3 attempts)
4. **Unsafe story blocking** - Stories that fail validation marked unsafe, not saved to kid library

**Rationale:**
- **Prompt constraints over model training**: We can't retrain Gemma, but we can constrain its output through detailed prompts. The Kid Bedtime Contract tells Gemma exactly what is/isn't allowed.
- **Validator over trust**: We don't trust the LLM to follow instructions perfectly. Post-generation validation catches violations the prompt didn't prevent.
- **Forbidden vocabulary list**: A deterministic, auditable blocklist is more reliable than heuristic "scary" detection. Parents can review the exact list.
- **Regeneration over rejection**: Rather than failing immediately, we give Gemma specific repair instructions. This improves success rates without human intervention.
- **Bounded attempts**: Prevents infinite loops. After 3 attempts, we accept failure and mark the story unsafe rather than serving questionable content.
- **Fail-safe design**: If all else fails, the story is marked `kidSafe: false` and blocked from the kid library. Children never see unsafe content.

**Alternatives Considered:**
1. **Fine-tune Gemma for kid content** - Rejected. Requires ML expertise, training data, compute resources. Not practical for this project.
2. **Use a different kid-safe model** - Rejected. No open-source models specifically trained for kid bedtime content exist.
3. **Manual review of all stories** - Rejected. Doesn't scale. Adds latency. Human error still possible.
4. **Simple keyword filter only** - Rejected. Too brittle. Doesn't catch subtle issues like biblical hallucinations or scary tone without explicit keywords.
5. **Trust Gemma with good prompts** - Rejected. LLMs don't reliably follow instructions. Validation layer is essential.

**Consequences:**
- New files created:
  - `docs/prompts/kid_bedtime_contract.txt` - The contract
  - `server/kid_bedtime_forbidden.txt` - Forbidden vocabulary (160+ patterns)
  - `server/kid_bedtime_validator.sh` - Bash validator
  - `server/kid_bedtime_harness.sh` - Harness wrapper
  - `lib/safety/kid_bedtime_validator.dart` - Dart validator
  - `test/kid_bedtime_safe/` - Test suite (3 test files)
- SPEC.md updated with new section (§28-33)
- INVARIANTS.md updated with new Kid Bedtime Safe invariant
- Existing kid story generation scripts should integrate the harness
- Generation takes slightly longer (validation + potential regeneration)
- Some valid stories may be rejected (false positives from strict rules)
- Parents can confidently use kid mode for unattended bedtime listening

---

## ADR-004: Minimal Privacy-Safe Structured Logging

**Date:** 2026-01-05
**Status:** Accepted
**Context:** Bible PAL needed lightweight logging for post-launch diagnostics without enterprise observability overhead. Key requirements:
- Diagnosable bugs from crash reports
- Privacy protection (users share vulnerable emotional states)
- No external vendors or persistent log files
- Testable constraints

**Decision:** Implement a single-file logging module (`lib/core/app_logger.dart`) with:

1. **JSON-structured output** — Single-line JSON for machine parsing, not free-form text
2. **Privacy blocklist** — Hardcoded blocked keys (`userText`, `prompt`, `email`, etc.) and PII pattern detection (email/phone regex)
3. **Breadcrumb ring buffer** — In-memory circular buffer of last 50 events for crash context
4. **Safe-fail wrapper** — All logging wrapped in try/catch; failures silently no-op
5. **Build-failing tests** — Tests verify blocked keys are rejected, PII is detected, logging never throws

**Rationale:**
- **JSON over key=value**: JSON is universally parseable by log aggregators, crash reporters, and debugging tools. Single-line format is grep-friendly.
- **Blocklist over allowlist**: Allowlists are error-prone (easy to forget new safe fields). Blocklists catch the dangerous fields we know about.
- **Regex PII detection**: Catches accidental PII leakage even in "safe" fields. Simple patterns (email, phone) cover 90% of cases.
- **Ring buffer over persistence**: No file I/O complexity, no storage concerns, no GDPR data retention issues. 50 events is enough context for most crashes.
- **Safe-fail over strict**: Logging should never break the app. Silent failure is better than crash.
- **Tests over trust**: Privacy invariants are enforced by failing tests, not documentation.

**Alternatives Considered:**
1. **Use Firebase Crashlytics / Sentry** — Rejected. External vendor adds dependency, privacy policy complexity, and potential data leakage.
2. **Log to local files** — Rejected. File I/O is complex, storage management needed, user data retention concerns.
3. **Free-form debugPrint** — Rejected. Not machine-parseable, no structure for filtering/aggregation.
4. **No logging** — Rejected. Post-launch bugs would be undiagnosable.

**Consequences:**
- New file: `lib/core/app_logger.dart` (~350 lines)
- New tests: `test/core/app_logger_test.dart` (~400 lines)
- SPEC.md updated with Observability section (§38-41)
- INVARIANTS.md updated with Logging Privacy Invariant
- Logging integrated at key decision points:
  - Story selection (ParableService)
  - Audio lifecycle (AudioService, ParablePlayerNotifier)
  - UI events (Settings, PalsParablesScreen)
  - App startup (main.dart)
- Minimal runtime overhead (JSON encoding, regex checks)
- No external dependencies added

---

## ADR-005: Diagnostics Mode with Deferred Crash Reporter SDK

**Date:** 2026-01-05
**Status:** Accepted
**Context:** After implementing basic AppLogger (ADR-004), we needed:
1. Breadcrumb persistence to survive app restarts (for bug reports)
2. Export capability for users to share diagnostics
3. A path to integrate crash reporting SDKs (Crashlytics/Sentry) without lock-in

The question was: How do we add these features without bloating the app or committing to a specific crash reporting vendor?

**Decision:** Implement a "Diagnostics Mode" with compile-time toggle and abstract crash reporter interface:

1. **Compile-time toggle**: `DIAGNOSTICS_ENABLED` via `--dart-define`
   - Default: false (no disk I/O, no diagnostics screen)
   - Enable for debug builds or beta testing

2. **Breadcrumb persistence**: `BreadcrumbStore` writes to SharedPreferences
   - Throttled writes (5s debounce) to minimize I/O
   - Only active when DIAGNOSTICS_ENABLED=true
   - Reuses existing sanitization (no PII leakage)

3. **Diagnostics screen**: Hidden screen to view/export breadcrumbs
   - Copy to clipboard for bug reports
   - Only accessible when DIAGNOSTICS_ENABLED=true

4. **Abstract CrashReporter interface**: Future-ready hook
   - `recordBreadcrumb()`, `reportError()`, `reportFatalCrash()`
   - `NoopCrashReporter` default (logs to console)
   - Swap for real SDK when ready without changing call sites

**Rationale:**
- **Compile-time toggle over runtime**: No overhead in production builds. Dead code elimination removes unused paths.
- **SharedPreferences over file I/O**: Simpler API, atomic writes, already a dependency. 50 breadcrumbs × ~200 bytes ≈ 10KB is trivial.
- **Throttled writes**: Prevents disk thrashing on rapid events. 5s is long enough to batch, short enough to capture recent context.
- **Abstract interface over direct SDK**: No vendor lock-in. Can integrate Crashlytics, Sentry, or custom solution later. All logging already flows through hooks.
- **NoopCrashReporter default**: App works without any SDK. Crash reporter is optional enhancement, not requirement.

**Alternatives Considered:**
1. **Always persist breadcrumbs** — Rejected. Adds disk I/O overhead for all users when most don't need it.
2. **Use SQLite for persistence** — Rejected. Overkill for 50 small JSON objects. SharedPreferences is simpler.
3. **Integrate Crashlytics now** — Rejected. Adds external dependency, privacy policy complexity, and vendor lock-in. Can add later via CrashReporter interface.
4. **No persistence, just export in-memory** — Rejected. Loses context on crash/restart when it's most needed.

**Consequences:**
- New files created:
  - `lib/core/diagnostics_config.dart` — Compile-time toggle
  - `lib/core/breadcrumb_store.dart` — Disk persistence
  - `lib/core/crash_reporter.dart` — Abstract interface + NoopCrashReporter
  - `lib/features/diagnostics/diagnostics_screen.dart` — Export UI
  - `test/core/diagnostics_config_test.dart`
  - `test/core/breadcrumb_store_test.dart`
  - `test/core/crash_reporter_test.dart`
  - `test/features/diagnostics_screen_test.dart`
- `lib/core/app_logger.dart` modified to wire up persistence and crash reporter
- SPEC.md updated with §42 (Diagnostics Mode)
- No new external dependencies
- Debug builds can enable diagnostics for testing
- Production builds have zero overhead (DIAGNOSTICS_ENABLED=false)

---

## ADR-006: Production Diagnostics Hardening (Support Bundle + Lifecycle Flush)

**Date:** 2026-01-05
**Status:** Accepted
**Context:** The initial diagnostics layer (ADR-005) provided basic breadcrumb persistence and export. For production readiness, we needed:
1. Richer export format for support teams
2. Reliable breadcrumb persistence on app backgrounding
3. Event correlation without PII
4. Consistent error naming

**Decision:** Harden diagnostics with production-ready features:

1. **Session ID**: Random 16-char hex string per app run
   - Generated via `Random.secure()` at startup
   - Included in all support bundles
   - NOT persisted (new ID each launch)
   - Enables event correlation without user identification

2. **Support Bundle Export**: Rich JSON export containing:
   - session_id, exported_at, diagnostics_enabled
   - app_version, app_build
   - platform, platform_version (safe OS info)
   - last_filters (sanitized filter snapshot)
   - breadcrumbs (already sanitized)

3. **Last Filters Tracking**: Automatic snapshot of `filters_applied` events
   - Stored in memory only
   - Captured when `filters_applied` event logged
   - Included in support bundle for debugging

4. **Lifecycle Flush**: `DiagnosticsLifecycleObserver`
   - Registered only when DIAGNOSTICS_ENABLED=true
   - Flushes breadcrumbs on `paused`/`inactive` states
   - Ensures breadcrumbs survive app termination

5. **Error Taxonomy**: Canonical error type naming
   - Format: `{category}_{specific_error}` (snake_case)
   - Categories: audio, network, storage, story, verse, tts, etc.
   - Documented in ERROR_TAXONOMY.md
   - Test validation for convention compliance

**Rationale:**
- **Session ID over user ID**: Correlates events without PII. New ID each launch means no tracking.
- **Support bundle over raw breadcrumbs**: Developers need context (version, platform, filters) not just events.
- **Lifecycle flush**: Mobile apps can be killed anytime. Flushing on background ensures breadcrumbs persist.
- **Error taxonomy**: Prevents log chaos. Queryable, consistent error names.
- **Zero overhead when disabled**: All features gated by compile-time constant.

**Crash Reporter SDK Integration - Deferred:**
We intentionally defer Firebase Crashlytics/Sentry integration because:
1. External SDKs add dependencies and app size
2. Privacy policy updates required
3. Configuration complexity (API keys, consent flows)
4. Current NoopCrashReporter + support bundle export is sufficient for beta
5. CrashReporter abstraction allows easy swap later

When crash reporting is needed:
1. Implement `CrashReporter` interface with SDK calls
2. Call `setCrashReporter()` in main.dart
3. All breadcrumbs/errors automatically flow to SDK

**Consequences:**
- New files:
  - `lib/core/diagnostics_lifecycle_observer.dart`
  - `docs/ERROR_TAXONOMY.md`
  - `test/core/diagnostics_lifecycle_observer_test.dart`
  - `test/core/support_bundle_test.dart`
  - `test/core/error_taxonomy_test.dart`
- Modified:
  - `lib/core/app_logger.dart` (session_id, last_filters, getters)
  - `lib/features/diagnostics/diagnostics_screen.dart` (support bundle)
  - `lib/main.dart` (lifecycle observer init)
  - `docs/SPEC.md` (§42-43 updates)
- Support teams get richer diagnostic data
- Breadcrumbs reliably persist on background
- Error logs are consistent and queryable

---

## ADR-007: First-Launch Onboarding Gate (Silent, Race-Free)

**Date:** 2026-01-08
**Status:** Accepted (Frozen)
**Context:** Bible PAL needed a first-launch onboarding flow that:
1. Shows PAL introducing itself with a typing animation
2. Collects user's name
3. Routes directly to PAL's Stories
4. Plays NO audio during onboarding
5. Shows NO voice consent dialog during onboarding
6. Has NO race conditions that could flash wrong screens

**Decision:** Implement a `FutureBuilder`-gated routing system:

1. **Single source of truth**: `kFirstLaunchCompleteKey` in SharedPreferences
2. **FutureBuilder gate**: Bootstrap widget awaits SharedPreferences before routing
3. **Loading state**: Shows spinner while preferences load (not a functional screen)
4. **Error fallback**: On SharedPreferences error, default to FirstLaunchScreen (privacy-safe)
5. **No initialRoute override**: Only `home:` property used in MaterialApp

**Routing Logic:**
```
Bootstrap._isFirstLaunch() → FutureBuilder
  ├─ hasError → AppRouter(showFirstLaunch: true)  // Safe default
  ├─ !hasData → CircularProgressIndicator         // Loading
  ├─ data=true → AppRouter(showFirstLaunch: true) // First launch
  └─ data=false → AppRouter(showFirstLaunch: false) // Returning user
```

**Hard Invariants (Frozen):**
- FirstLaunchScreen is ALWAYS the first functional screen on true first launch
- No VoiceConsentGate, TraditionSetupScreen, or MainMenuScreen can appear before it
- No audio plays during FirstLaunchScreen (silent by design)
- Completion flag is set BEFORE navigation away from FirstLaunchScreen
- On error, default to first-launch flow (never to main app)

**Rationale:**
- **FutureBuilder over async main()**: Keeps main() synchronous, standard Flutter pattern
- **Error → FirstLaunchScreen**: If we can't read prefs, safer to show onboarding than assume user is returning
- **Flag before navigate**: Prevents re-triggering onboarding if app is killed during transition
- **No initialRoute**: Prevents accidental override of the home screen logic

**Consequences:**
- New files:
  - `lib/features/onboarding/first_launch_screen.dart`
  - `test/features/onboarding/first_launch_screen_test.dart`
- Modified:
  - `lib/main.dart` (Bootstrap with FutureBuilder)
  - `lib/app_router.dart` (showFirstLaunch parameter)
  - `lib/models/user_preferences.dart` (userName field)
- This behavior is FROZEN — do not modify routing logic without explicit approval

---

## ADR-008: Golden Prompt Story Generator Behavior (SHORT Bucket)

**Date:** 2026-01-11
**Status:** Accepted
**Context:** Bible PAL uses a "golden prompt" generation mode for producing high-quality, prose-only story seed files using Gemma via Ollama. These stories are used as foundational content and must meet strict formatting and length guarantees while remaining model-agnostic.

Early testing showed that Gemma-7B does not reliably hit the target length range in a single generation pass.

**Decision:** Golden prompt mode is defined with the following **intentional behavior**:

1. **SHORT bucket only**
   - Acceptance range: **300–700 words**
   - Prompt target: **380–620 words**
   - This mode does **not** claim 5-minute / 600-word calibration

2. **Prose-only output**
   - Generated `.txt` files contain ONLY story prose
   - No YAML headers, metadata, IDs, titles, or commentary
   - Metadata is handled externally (manifest, filename, etc.)

3. **Controlled continuation is allowed**
   - If initial output is below 300 words:
     - Up to **2 continuation attempts** are allowed
     - Continuation uses last 1–2 sentences for context
   - If still under range, a single full regeneration is allowed
   - This is **intentional** and **not** a single-shot generator

4. **Over-length handling**
   - If output exceeds 700 words:
     - One regeneration is allowed using a tighter target range (350–600)

5. **Contract files are documentation only**
   - YAML contract files describe intent and constraints
   - They are **not parsed or enforced at runtime**
   - Contract paths are no longer printed during generation

**Rationale:**
- **Continuation over single-shot**: Allowing limited continuation dramatically improves length reliability for smaller local models without sacrificing story quality.
- **Prose-only over metadata-embedded**: Simplifies downstream consumption and avoids duplication of metadata concerns.
- **Hardcoded gates over contract parsing**: Keeps behavior explicit in the script. Avoids false assumptions about runtime contract enforcement.

**Alternatives Considered:**
1. **True single-shot golden** — Rejected. Gemma-7B frequently produces under-length output. Would require many retries.
2. **Parse contract YAML at runtime** — Rejected. Adds complexity without benefit. Script is the source of truth.
3. **Include metadata in story files** — Rejected. Creates duplication with manifest. Makes story files harder to consume.

**Consequences:**
- Golden mode is optimized for **reliability and quality**, not purity
- Future "single-shot" experimentation must be explicitly introduced (e.g., via a new flag), not by modifying golden mode
- Any changes to golden generator behavior must update this ADR
- Script changes:
  - `server/generate_adult_traditional_stories.sh` — bash shebang, strict mode, gate branching
  - `server/prompts/golden_trad_adult_5min.prompt.txt` — OUTPUT RULES section
  - `server/contracts/golden_contract_trad_adult_5min.yaml` — marked as documentation only

---

## ADR-009: Story Length UI Migration (Minutes → Buckets)

**Date:** 2026-01-11
**Status:** Accepted
**Context:** The original story length UI presented 4 buttons (5/10/15/20 minutes) which:
1. Exposed implementation details (minute-based audio lengths) to users
2. Created confusion about what "5 minutes" vs "10 minutes" meant semantically
3. Required 4 buttons when 3 meaningful categories would suffice
4. Made it harder to adjust generation word counts without changing the UI

The question was: How do we present story lengths in a user-friendly way while maintaining backwards compatibility with existing minute-based story assets?

**Decision:** Replace the 4-button minute UI with 3 descriptive bucket labels:

| UI Label | Enum Value | Maps From (Legacy Minutes) | Word Count Range (LOCKED SPEC) |
|----------|------------|---------------------------|--------------------------------|
| Short Story | `short` | 5 min, 10 min | 250–600 words |
| Full Story | `full` | 15 min | 601–1200 words |
| Long Story | `long` | 20 min | 1201–2000 words |

**Note:** Word count ranges updated to LOCKED SPEC values (2026-01-11). Previous ranges (300-700, 900-1400, 1700-2600) are superseded.

Implementation:
1. **New enum**: `StoryLengthBucket` in `lib/core/story_length_bucket.dart`
2. **Primary field**: `storyLength` in manifest ("short", "full", "long")
3. **Compatibility mapper**: `lengthMinutesToBucket(int)` function for legacy assets
4. **Computed property**: `Parable.lengthBucket` getter prioritizes `storyLength`, falls back to mapper
5. **Selection filtering**: `ParableService` filters by `parable.lengthBucket == lengthBucket`
6. **Stateless selection**: Length bucket is chosen fresh each session (not persisted)
7. **Additive telemetry**: Keep `length_min` for backwards compatibility, add `length_bucket`

**Rationale:**
- **Buckets over minutes**: Users think in "short story" vs "long story", not "5 minutes vs 10 minutes"
- **3 buttons over 4**: Short/Full/Long covers the semantic space; 5 vs 10 minutes was arbitrary
- **Primary `storyLength` field**: New stories use `storyLength` directly; manifest updated with backfill
- **Keep legacy `length` field**: Older assets still work via `lengthMinutesToBucket()` fallback
- **Stateless selection**: Length was never persisted; users choose length fresh each session
- **Additive telemetry**: Don't break existing analytics pipelines; add new dimension

**Alternatives Considered:**
1. **Add `lengthBucket` to manifest.json** — Initially rejected, then implemented as `storyLength` field via backfill script.
2. **Use word count instead of buckets** — Rejected. Would require reading story files to compute counts. Bucket mapping is simpler.
3. **Keep 4 buttons with new labels** — Rejected. 5 min and 10 min both map to "short"; having 4 UI options for 3 buckets is confusing.
4. **Persist length preference** — Rejected. Current stateless behavior (choose each session) matches product design.

**Consequences:**
- New file: `lib/core/story_length_bucket.dart` (~50 lines)
- Modified:
  - `lib/models/parable.dart` (added `lengthBucket` getter)
  - `lib/services/parable_service.dart` (bucket-based filtering)
  - `lib/providers/app_state_notifier.dart` (updated signature)
  - `lib/features/pals_parables/pals_parables_screen.dart` (3 buttons)
  - All test files using `lengthMinutes` parameter
  - `docs/SPEC.md` (updated Feature #6)
  - `.clinerules` (updated line 66)
- UI shows "Short Story", "Full Story", "Long Story" instead of "5 min", "10 min", etc.
- All existing story assets remain compatible (no manifest changes)
- Telemetry now includes both `length_min` and `length_bucket`

---

## ADR-010: Traditional Mode = Real Bible Story System

**Date:** 2026-01-16
**Status:** Accepted (Locked)
**Context:** Traditional storytelling mode was ambiguously defined. Some stories labeled "traditional" were devotional content or generic faith-based stories, not actual Bible narratives. Users selecting Traditional mode expected actual Bible stories like "Jesus Calms the Storm" or "The Good Samaritan", not original compositions with biblical themes.

The question was: What EXACTLY is Traditional mode, and how do we enforce it?

**Decision:** Lock the following system for Traditional mode:

1. **Traditional = Real Bible Story Retelling**
   - Traditional stories MUST be faithful retellings of specific, identifiable Bible narratives
   - NOT devotional content, NOT original stories with biblical themes
   - Examples: The Lost Sheep (Luke 15:3-7), David and Goliath (1 Samuel 17)

2. **New Required Fields**
   - `bibleStoryKey`: Stable canonical identifier (e.g., "lost_sheep", "jesus_calms_storm")
   - `bibleSourceRef`: Scripture reference (e.g., "Mark 4:35-41") — already existed but now strictly enforced

3. **One Bible Story Per Mood**
   - Each mood maps to exactly ONE `bibleStoryKey` for Traditional stories
   - Multiple renditions (kid/adult, short/long) share the same `bibleStoryKey`
   - Ensures predictable user experience: "joyful" always tells the same Bible story

4. **"Pizzazz" Constraints**
   - Allowed: pacing, sensory detail, emotional texture implied by scripture
   - Forbidden: new events, altered outcomes, invented theology, modern framing

5. **Reflection System (All Stories)**
   - Every story (Traditional AND Creative) has a reflection
   - Reflection audio uses same `narratorVoiceKey` as story (no separate PAL voice)
   - Reflection is NEVER auto-played — user taps "Hear Reflection" button
   - Scripture reference displayed AFTER story ends (Traditional only), NOT during

6. **Mode Persistence**
   - Default: Traditional
   - Persists across app restarts
   - Only two modes: Traditional and Creative

**Rationale:**
- **Clarity over ambiguity**: "Traditional = Bible story" is unambiguous and testable
- **User trust**: Users selecting Traditional mode rightfully expect actual Bible stories
- **One story per mood**: Prevents confusion about which Bible story matches a mood
- **Same narrator for reflection**: Voice continuity improves experience
- **Scripture after story**: Lets narrative breathe; scripture serves as closure/anchor
- **Opt-in reflection audio**: Respects user agency (MoDC principles)

**Alternatives Considered:**
1. **Allow devotional content in Traditional** — Rejected. Blurs the line, confuses users.
2. **Multiple Bible stories per mood** — Rejected. Creates unpredictability; user can't learn "joyful = Lost Sheep".
3. **Auto-play reflection** — Rejected. Violates MoDC non-directive principle.
4. **Different voice for reflection** — Rejected. Breaks immersion, adds complexity.
5. **Scripture during story narration** — Rejected. Interrupts narrative flow.

**Consequences:**
- New field `bibleStoryKey` added to Parable model
- Manifest schema requires `bibleStoryKey` for Traditional stories
- Build-failing tests enforce one-Bible-story-per-mood rule
- Player UI shows scripture ref after completion (Traditional) and "Hear Reflection" button
- Existing Traditional stories without `bibleStoryKey` need backfill
- Server generation scripts updated to generate reflection audio alongside story
- Mode persists via SharedPreferences (already worked, now documented)

**Files Modified:**
- `docs/SPEC.md` — Traditional contract, reflection system, mode persistence
- `docs/INVARIANTS.md` — New invariants for Traditional, reflection, mode persistence
- `lib/models/parable.dart` — `bibleStoryKey` field
- `lib/features/pals_parables/parable_player_screen.dart` — Scripture display, reflection button
- `lib/services/parable_service.dart` — `bibleStoryKey` validation
- `test/critical/traditional_bible_story_test.dart` — New test file
- `test/critical/reflection_system_test.dart` — New test file
- `test/critical/mode_persistence_test.dart` — New test file

---

## ADR-011: Debug-Only Reset First Launch Tool

**Date:** 2026-01-22
**Status:** Accepted
**Context:** On macOS (and other desktop platforms), SharedPreferences persists between app runs. This makes it impossible to re-test the onboarding flow without manually clearing app data or using special tools. Developers needed a quick way to reset onboarding state for verification and testing.

**Decision:** Add a "Reset First Launch (Dev)" button to the Diagnostics screen with the following properties:

1. **Debug-only visibility**: Guarded by `kDebugMode` — never visible in release builds
2. **Location**: Diagnostics screen (already a dev-focused area, requires DIAGNOSTICS_ENABLED)
3. **Scope of reset**:
   - Clears: `kFirstLaunchCompleteKey`, `hasCompletedOnboarding`, `userName`, all voice consent fields
   - Preserves: `bibleTranslation`, `languageStyle`, `storytellingMode`, `kidFriendlyOnly`, favorites, history
4. **Behavior after reset**: Shows message "Restart app to re-run onboarding" (no automatic navigation)
5. **Confirmation dialog**: Requires explicit user confirmation before reset

**Rationale:**
- **Debug-only over runtime toggle**: This is purely a developer tool. Users should never see or need it.
- **Diagnostics screen over Settings**: Settings is user-facing. Diagnostics is already dev-only.
- **Manual restart over auto-navigate**: Safer. Avoids state corruption from mid-session navigation reset.
- **Preserve preferences**: User's Bible translation, mode, and kid-friendly settings are deliberate choices. Don't discard them.
- **Preserve favorites/history**: These are user data, not onboarding state. Would be destructive to clear.
- **Clear voice consent**: Voice consent is part of the onboarding-adjacent flow. Resetting allows re-testing consent dialogs.

**Alternatives Considered:**
1. **Add to Settings screen** — Rejected. Settings is user-facing; this is dev-only.
2. **Auto-navigate to FirstLaunchScreen** — Rejected. Complex state management; could cause bugs.
3. **Clear all data** — Rejected. Destructive; loses user preferences and content.
4. **Use a CLI flag** — Rejected. Harder to use during manual testing sessions.

**Consequences:**
- Modified: `lib/features/diagnostics/diagnostics_screen.dart` (added reset button + logic)
- New test: `test/critical/reset_first_launch_test.dart` (5 tests)
- No changes to release build behavior
- Developers can now quickly verify onboarding flow on macOS/desktop

---

## ADR-012: Commit 1a7f117 Historical Clarification

**Date:** 2026-01-27
**Status:** Accepted (Historical Record)
**Context:** During the checkpoint commit process for typewriter click service and PAL intro features, commit `1a7f117` was created with a misleading commit message. The message states "chore: ignore and remove local test artifacts" but the commit also includes the initial TypewriterClickService source files.

**What Happened:**
The typewriter service files (`typewriter_click_service.dart`, `typewriter_click_fallback.dart`, etc.) had been staged in a previous session (shown as `AM` status in git — Added in index, Modified in working tree). When `.gitignore` was committed, these pre-staged files were swept into the same commit.

**Actual Contents of 1a7f117:**
- `.gitignore` — New patterns for `bp_*.mp3` and `audio_tests/`
- `lib/services/typewriter_click_service.dart` — Initial service (330 lines)
- `lib/services/typewriter_click_fallback.dart` — Abstract interface
- `lib/services/typewriter_click_fallback_just_audio.dart` — Desktop fallback
- `lib/services/typewriter_click_fallback_stub.dart` — Web stub

**Impact:** None. This is a documentation mismatch only:
- No behavior change
- No test impact
- Subsequent commit `97ce392` contains the remaining typewriter infrastructure (deps, WAV assets, plugin configs)
- All features work correctly

**Decision:** Document this discrepancy rather than rewrite history. The commit has been pushed and tagged (`checkpoint_typewriter_onboarding_v1`).

**Consequences:**
- This ADR serves as the historical record
- Future readers should consult both `1a7f117` and `97ce392` for complete typewriter service history
- No git history rewrite performed

---

## ADR-013: Defer External Crash Reporting for v1

**Date:** 2026-02-10
**Status:** Accepted
**Context:** Bible PAL needs robust diagnostics for debugging production issues, but users share vulnerable emotional states (anxiety, grief, loneliness) with the app. We needed to decide:

1. Should we integrate external crash reporting SDKs (Firebase Crashlytics, Sentry, etc.) in v1?
2. How do we balance diagnostic capabilities with privacy-first design?
3. What level of diagnostics is sufficient for pre-launch stability?

External crash reporting SDKs provide powerful diagnostics but introduce significant complexity:
- **Privacy risk**: SDKs send data to external servers; requires strict data contracts and legal review
- **Configuration overhead**: API keys, consent flows, privacy policy updates, SDK integration
- **Vendor lock-in**: Choosing Crashlytics vs Sentry is hard to reverse later
- **App size**: Additional dependencies increase APK/IPA size
- **Cost**: Most crash reporting services charge based on volume (unknown for v1)

**Decision:** Defer all external crash reporting SDK integration for Bible PAL v1. Instead, implement privacy-first local diagnostics:

1. **CrashLogStore** (local crash persistence)
   - Writes crash logs to disk (gated by `DIAGNOSTICS_ENABLED=true` compile flag)
   - In production builds, `DIAGNOSTICS_ENABLED` is false by default, so crash logs are not persisted unless explicitly enabled for diagnostic builds
   - Max 10 crash logs (FIFO), stored in app documents directory
   - Privacy firewall: whitelisted breadcrumb keys (41 allowed), path redaction, email/phone removal
   - Metadata-only: timestamp, error_type, breadcrumb_count, app_version
   - NO user text, story content, verse text, tokens, or file paths

2. **Support Bundle Export**
   - User-triggered clipboard export from diagnostics screen
   - Includes: crash summaries (last 5, metadata only), breadcrumbs, platform info, mode state
   - Safe metadata: session_id, platform, platform_version, app_version, storytellingMode, kidFriendlyOnly
   - NO PII or sensitive data

3. **Abstract CrashReporter interface**
   - All logging flows through `CrashReporter` abstraction
   - `NoopCrashReporter` is default (logs to console only)
   - Future SDK integration requires only implementing interface + calling `setCrashReporter()`

**Rationale:**
- **Privacy-first**: Local diagnostics have zero external data transmission. No privacy policy updates, no legal review, no compliance risk.
- **Data minimization**: User controls export. Support bundle is metadata-only. Designed to minimize risk of PII capture/transmission; enforced by allowlists, sanitizers, and 28 build-failing tests.
- **Sufficient for v1**: Crash logs + breadcrumbs provide enough context to debug most issues. Support bundle can be shared via email/GitHub issue.
- **Defers complexity**: No SDK integration, no API key management, no consent flows, no vendor lock-in decisions.
- **Defers cost**: External crash reporting services charge per event. Unknown v1 usage makes cost unpredictable.
- **Future-ready**: `CrashReporter` abstraction allows easy SDK swap when needed. All logging already flows through hooks.

**Alternatives Considered:**

1. **Firebase Crashlytics** — Rejected for v1.
   - Pros: Free tier, integrated with Firebase ecosystem, good Flutter support
   - Cons: Requires Google account, privacy policy updates, vendor lock-in, external data transmission
   - Decision: Defer until we have user consent flow and legal review

2. **Sentry** — Rejected for v1.
   - Pros: Privacy-focused, self-hostable option, powerful filtering
   - Cons: Paid service, requires credit card, configuration complexity, SDK size
   - Decision: Good option for future, but overkill for v1. Self-hosted Sentry may be reconsidered post-launch if it passes the same data contract requirements.

3. **No diagnostics at all** — Rejected.
   - Pros: Simplest implementation, zero complexity
   - Cons: Post-launch bugs would be undiagnosable
   - Decision: Local diagnostics provide enough value without external dependencies

4. **Build custom crash uploader** — Rejected.
   - Pros: Full control, no vendor lock-in
   - Cons: Requires backend infrastructure, security considerations, maintenance burden
   - Decision: Not worth the effort for v1

**Privacy & Security Notes:**

Hard privacy constraints enforced by CrashLogStore:
- **NO user-entered text**: No mood input, no reflection responses, no any text the user types
- **NO story content**: No parable text, no generated stories, no prompts
- **NO verse text**: No Bible verses, no Daily Bread content
- **NO tokens/keys**: No API keys, no session tokens, no authentication data
- **NO file paths**: Absolute paths redacted to `[PATH]` (preserves package:/dart: URIs only)
- **NO PII**: Email addresses → `[EMAIL]`, phone numbers → `[PHONE]`, paths sanitized

Support bundle export applies the same data-minimization rule: metadata-only; no content payloads.

Breadcrumb privacy firewall:
- Whitelisted keys only (41 allowed: event, story_id, length_bucket, kid_friendly, etc.)
- String values capped at 100 chars
- Complex types (Map, List) dropped
- Numbers, bools, nulls allowed
- Unknown keys silently dropped

Enforcement:
- 28 build-failing tests verify privacy constraints
- Tests check: whitelist enforcement, string caps, complex type dropping, path redaction, PII sanitization
- FIFO caps prevent unbounded storage (max 10 crash logs)

**Consequences:**

New files created:
- `lib/core/crash_log_store.dart` — Local crash persistence (494 lines)
- `test/core/crash_log_store_test.dart` — Privacy firewall tests (492 lines, 28 tests), tagged with `@Tags(['requires_diagnostics_define'])`
- `docs/DECISIONS.md` — This ADR

Modified files:
- `lib/features/diagnostics/diagnostics_screen.dart` — Support bundle enhancement
- `.github/workflows/flutter.yml` — Separate diagnostics test step

Test infrastructure:
- Default run: `flutter test --exclude-tags=requires_diagnostics_define` (667 tests)
- Diagnostics run: `flutter test --tags=requires_diagnostics_define --dart-define=DIAGNOSTICS_ENABLED=true` (28 tests)
- CI runs both separately

User experience:
- No external data transmission
- No consent dialogs required
- Support bundle export is user-triggered
- Crash logs survive app restart (when diagnostics enabled)
- Developers can debug issues from exported bundles

**When to Revisit:**

External crash reporting may be reconsidered only when ALL of these conditions are met:

1. **Explicit user opt-in implemented**
   - Consent dialog explaining what data is sent
   - Clear opt-out mechanism
   - GDPR/CCPA compliant consent flow

2. **Legal/privacy review completed**
   - Privacy policy updated
   - Data Processing Agreement (DPA) with vendor reviewed
   - GDPR Article 30 compliance verified

3. **SDK vetted and chosen**
   - Data minimization guarantees from vendor
   - Self-hosted option evaluated
   - SDK size impact acceptable
   - Cost model understood

4. **Written data contract**
   - Explicit list of what data is sent
   - Retention policy defined
   - Data deletion process documented
   - PII guarantees formalized

5. **Post-launch volume justifies cost**
   - Enough users to make crash reporting cost effective
   - Free tier limits understood
   - Budget allocated

**DO NOT** integrate external crash reporting without all 5 conditions met. The current local diagnostics + support bundle export is sufficient for v1 and preserves user privacy.

---

## ADR-014: Dual-Engine Story Pipeline (Traditional + Creative)

**Date:** 2026-02-22
**Status:** Accepted (Locked)
**Context:** Bible PAL needed a Creative story generation pipeline to complement the existing Traditional pipeline. The Traditional pipeline uses gpt-4.1 via OpenAI for faithful Bible retellings. Creative stories are original faith-themed narratives (parables, metaphor stories, modern faith fiction) that need a different engine assignment.

Key requirements:
1. Creative stories must be clearly distinct from Traditional (no Bible retellings)
2. Cost control — Creative stories could be generated at high volume
3. Vendor independence — avoid relying on a single cloud provider
4. Quality — Creative stories need warmth, emotional resonance, and variety
5. Safety — same kid safety, reflection safety, and anti-repetition standards

**Decision:** Implement a locked dual-engine architecture:

1. **Traditional Engine: gpt-4.1 (OpenAI Cloud)**
   - Script: `scripts/story_factory/generate_traditional_story.py`
   - Use for: Scripture-anchored Bible retellings
   - Registry: `used_scripture_anchors.json`
   - Output: `assets/stories/traditional/<id>/`
   - Forbidden: Gemma, local models

2. **Creative Engine: Gemma 7B (Ollama Local)**
   - Script: `scripts/story_factory/generate_creative_story.py`
   - Use for: Original parables, modern faith stories, metaphor narratives
   - Registry: `used_creative_themes.json`
   - Output: `assets/stories/creative/<id>/`
   - Forbidden: OpenAI API, cloud LLMs

3. **Shared Infrastructure**
   - Same word count ranges (locked spec)
   - Same meta-text blocklist
   - Same kid safety vocabulary
   - Same reflection language constraints
   - Same ElevenLabs TTS for audio
   - Same anti-repetition rules in prompts

4. **Creative-Specific Validation**
   - Creative compliance checker catches scripture retelling, authority claims,
     direct God dialogue, spiritual commands, fear framing
   - Sanitize-then-regenerate loop (same pattern as Traditional)
   - Max 5 attempts (slightly higher than Traditional due to local model variability)

5. **ID Space Separation**
   - Traditional: 801+
   - Creative: 501+

**Rationale:**
- **Gemma for Creative over OpenAI**: Zero API cost, runs offline, no vendor lock-in. Creative stories don't need the same scripture fidelity as Traditional — they need warmth and variety, which Gemma handles well.
- **gpt-4.1 for Traditional over Gemma**: Scripture accuracy is critical for Traditional mode. gpt-4.1 has proven reliability for faithful Bible retellings. The cost is justified by the doctrinal trust requirement.
- **Separate registries over shared**: Prevents any cross-contamination between modes. Theme uniqueness (Creative) and anchor uniqueness (Traditional) are independent concerns.
- **Separate output directories**: Clear physical separation. No risk of mode confusion in the asset pipeline.
- **Shared validation infrastructure**: Reduces code duplication. Meta-text, kid safety, and reflection constraints are mode-agnostic.
- **Locked engine assignment**: Prevents drift. Once you allow engine substitution, you lose the quality guarantees each engine was chosen for.

**Alternatives Considered:**
1. **Use gpt-4.1 for both modes** — Rejected. Unnecessary API cost for Creative stories. Creates full vendor dependency on OpenAI.
2. **Use Gemma for both modes** — Rejected. Gemma's scripture accuracy is insufficient for Traditional mode. Bible retellings require proven cloud model quality.
3. **Use Claude for Creative** — Rejected. Still a cloud dependency. Local model is preferable for Creative's volume needs and vendor independence.
4. **Single script with engine flag** — Rejected. The validation gates, prompts, and metadata are sufficiently different to warrant separate scripts. Cleaner separation of concerns.

**Consequences:**
- New files:
  - `scripts/story_factory/generate_creative_story.py` — Creative story generator
  - `scripts/story_factory/batch_generate_creative.py` — Creative batch orchestrator
  - `scripts/story_factory/test_creative_story_factory.py` — Creative pipeline tests
  - `used_creative_themes.json` — Creative theme registry (created on first run)
- Modified:
  - `docs/STORY_FACTORY.md` — Added Creative sections (12–22)
  - `docs/DECISIONS.md` — This ADR
- Creative stories require Ollama running locally with `gemma:7b` model
- Creative generation is slower than Traditional (local model vs cloud API)
- Creative generation has zero API cost
- Both pipelines share TTS costs (ElevenLabs)

**Prerequisites for Running Creative Pipeline:**
```bash
# Install Ollama
brew install ollama  # or download from ollama.com

# Pull Gemma model
ollama pull gemma:7b

# Start Ollama server
ollama serve

# Generate a single creative story
python3 scripts/story_factory/generate_creative_story.py \
  --story_id 501 --theme "a baker who feeds more than hunger" \
  --mood joyful --lane web --voice_key VOICE_JAMES_HUSKY

# Batch generate (all moods)
python3 scripts/story_factory/batch_generate_creative.py \
  --lane web --voice_key VOICE_JAMES_HUSKY

# Text-only (skip expensive TTS)
python3 scripts/story_factory/batch_generate_creative.py \
  --lane web --voice_key VOICE_JAMES_HUSKY --skip-audio
```

---

## ADR-015: PAL V2 — Check-In Prompts, Micro-Responses, and New Voices

**Date:** 2026-02-27
**Status:** Accepted
**Context:** The original PAL greeting system used 32 hardcoded time-windowed strings (GreetingService) + 20 audio-backed generic greetings + 45 compassionate replies across 3 mood buckets (positive/neutral/negative). This system felt repetitive and lacked emotional depth. PAL V2 replaces it with a more emotionally intelligent system.

**Decision:**
1. Replace `GreetingService` with `PalPromptService` — 96 time-aware, category-weighted check-in prompts (4 time windows × 4 categories × 6 lines)
2. Replace compassionate replies with micro-responses — 30 mood-specific responses (5 moods × 6 lines, all ≤ 12 words)
3. Add quick mood buttons (Joyful, Neutral, Weary, Anxious, Hurting) as an input method alongside text and voice
4. Replace 4 PAL voices (Sarah, Hannah, James, David) with new voices (Grace, Shepherd, Hope, Stillwater)
5. Move story length selector to main menu (session-scoped, not persisted)
6. Auto-start story after micro-response + verse display (~2s cancellable delay)
7. Use ElevenLabs Eleven v3 engine for PAL audio generation
8. Map 5 detected moods directly to 5 micro-response buckets (eliminating the previous 5→3 mood-to-bucket mapping)

**Rationale:**
- Category-weighted prompts make PAL feel more emotionally aware and less robotic
- Shorter micro-responses (≤12 words) feel more natural for a conversational companion
- Quick mood buttons reduce friction for users who don't want to type or speak
- Direct 5-mood mapping provides more targeted emotional responses
- Auto-start flow eliminates extra taps between mood input and story playback
- New voices tested against voice quality guardrails (conversational, warm, calm, grounded)

**Consequences:**
- `lib/services/greeting_service.dart` deleted
- `lib/services/pal_prompt_service.dart` created
- `assets/pal/pal_lines.json` schema updated to v2 (old keys removed, new keys added)
- `MoodService._compassionateReplies` replaced with ≤12-word micro-response text
- `PalAudioService` updated: `playGreeting()` → `playPrompt()`, `playCompassionateReply()` → `playMicroResponse()`, `moodToBucket()` removed
- `PalVoiceRegistry` updated with 4 new voices + emoji field; default changed to `VOICE_GRACE`
- Old PAL audio assets (greeting_*.mp3, comp_*.mp3) to be deleted in Phase 2
- 509 new MP3 files to be generated in Phase 2
- SPEC.md updated: Features 2.1, 4, 6, 17b

---

## ADR-016: Universal Model Router

**Date:** 2026-03-10
**Status:** Accepted
**Context:** Bible PAL's AI model selection is hardcoded in multiple places:
- `server/generate_v2_batch.sh` has `get_creative_model()` with a hardcoded fallback chain (mistral-nemo → llama3.1:8b → qwen2.5:7b → gemma:7b)
- `scripts/story_factory/generate_creative_story.py` hardcodes `MODEL = "gemma:7b"`
- Traditional stories hardcode `gpt-4.1` (correctly, as a locked requirement)

As the project grows to support new task types (coding assistance, reasoning, title generation, experimental generation), hardcoding model names in each script creates:
1. Duplication — every new script reinvents model selection
2. Drift — different scripts may fall out of sync on preferred models
3. Opacity — no central place to see or audit which models serve which tasks
4. Inflexibility — changing a model requires editing multiple scripts

**Decision:** Implement a Universal Model Router with:

1. **Config-driven model registry** (`server/model_router/model_registry.json`)
   - Declares all available models (local Ollama + remote OpenAI)
   - Defines task types with ordered fallback chains
   - Marks locked tasks (e.g., `traditional_story_remote`) that must never fall back

2. **Python router module** (`server/model_router/`)
   - Core resolution: task name → best available model
   - Ollama availability checking via `/api/tags`
   - Privacy-safe telemetry (no prompt/content logging)
   - CLI entry point for bash script integration
   - FastAPI prototype for future app integration

3. **Backward-compatible integration**
   - `generate_v2_batch.sh` tries the router first, falls back to existing hardcoded logic
   - Traditional pipeline is never touched — remains locked to gpt-4.1
   - All existing scripts continue to work if the router is not installed

4. **Task-driven routing** — scripts ask for a task (e.g., `creative_story`), not a model.
   The router decides which model to use based on availability and the registry.

**Key constraints:**
- `traditional_story_remote` is `locked: true` — hard-fails if gpt-4.1 is unavailable (no local fallback)
- Router decisions are logged but never include prompt content or user text
- The router is server-side infrastructure; no changes to the Flutter app

**Rationale:**
- **Config over code**: Model assignments in a JSON file are auditable, diffable, and changeable without editing scripts
- **Task abstraction**: Future scripts (title gen, coding tools, reasoning) can use the router without knowing model names
- **Fallback resilience**: If a preferred model is unloaded or unavailable, the router automatically selects the next best option
- **Preserves locks**: Traditional pipeline lockdown is enforced by the registry's `locked` flag, not just by convention
- **Local-first**: All Ollama routing happens on localhost; no new external dependencies

**Alternatives Considered:**
1. **Keep hardcoding per script** — Rejected. Doesn't scale as task types grow. Model preferences drift.
2. **Environment variables per model** — Rejected. Still requires each script to read/interpret env vars. No fallback logic.
3. **Docker-based orchestration** — Rejected. Adds complexity without clear benefit for a single-machine local setup.
4. **Integrate routing into Flutter app** — Rejected. Stories are pre-generated, not runtime. Router belongs in the server pipeline.

**Consequences:**
- New directory: `server/model_router/` (router module, registry, CLI, API, tests)
- New dependency: `requirements.txt` (fastapi, uvicorn — for API prototype only)
- Modified: `server/generate_v2_batch.sh` (augmented `get_creative_model()` with router-first + fallback)
- Modified: `docs/STORY_FACTORY.md` (Section 0 and 12 updated to reflect mistral-nemo as primary Creative model)
- New invariant: Model Router Traditional Engine Lock
- No changes to Flutter/Dart code
- No changes to Traditional pipeline behavior

---

## Template for Future Decisions

```
## ADR-XXX: [Title]

**Date:** YYYY-MM-DD
**Status:** [Proposed | Accepted | Deprecated | Superseded]
**Context:** [What is the issue?]

**Decision:** [What was decided?]

**Rationale:** [Why was this decided?]

**Consequences:** [What are the effects?]
```
