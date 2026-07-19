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

> **⚠️ PARTIALLY SUPERSEDED by ADR-030 (2026-07-19).**
> **Still valid:** the three-bucket UI, the enum values, the legacy-minute mapping, and the
> 250–600 / 601–1200 / 1201–2000 figures **as runtime classification and UI bounds** — these
> match `lib/core/story_length_bucket.dart` and remain authoritative for runtime behavior.
> **Superseded:** any reading of these ranges as *authoring* or production-validation bands.
> Adult Traditional authoring bands are Short 300–500, Full 501–900, Long 901–1500, specified
> in STORY_FACTORY.md §5. The two systems are distinct; see ADR-030.

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

3. **~~One Bible Story Per Mood~~** *(Superseded by ADR-022: Scripture Anchor Registry)*
   - ~~Each mood maps to exactly ONE `bibleStoryKey` for Traditional stories~~
   - Multiple renditions (kid/adult, short/long) of the same anchor share the same `bibleStoryKey`
   - See ADR-022 for the current multi-story-per-mood architecture

4. **"Pizzazz" Constraints**
   - Allowed: pacing, sensory detail, emotional texture implied by scripture
   - Forbidden: new events, altered outcomes, invented theology, modern framing

5. **Reflection System (All Stories)**
   - Every story (Traditional AND Creative) has a reflection
   - Reflection audio uses same `narratorVoiceKey` as story (no separate PAL voice)
   - Reflection is not auto-played by default — user taps "Hear Reflection" button. Exception: "Pause for Reflection" opt-in toggle (Feature 50.6d)
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
2. **Multiple Bible stories per mood** — ~~Rejected.~~ Now accepted via ADR-022. At scale (~1500 stories), variety outweighs predictability.
3. **Auto-play reflection** — Rejected by default. Violates MoDC non-directive principle. Exception added: "Pause for Reflection" (Feature 50.6d) is a session-scoped, default-OFF opt-in toggle that preserves user agency.
4. **Different voice for reflection** — Rejected. Breaks immersion, adds complexity.
5. **Scripture during story narration** — Rejected. Interrupts narrative flow.

**Consequences:**
- New field `bibleStoryKey` added to Parable model
- Manifest schema requires `bibleStoryKey` for Traditional stories
- Build-failing tests enforce scripture anchor uniqueness (see ADR-022)
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
**Status:** SUPERSEDED 2026-05-13 by Creative Retirement — see [archive/CREATIVE_RETIREMENT_2026_05_13.md](archive/CREATIVE_RETIREMENT_2026_05_13.md). The Traditional half of this ADR remains active; the Creative engine, scripts, and assets were archived to T9 and removed from the working tree. Reactivation requires a new SPEC update + restoration from archive or git tag `pre-creative-retirement-2026-05-13`.
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

## ADR-017: Model Router Phase 2A — Resolution to Execution Gateway

**Date:** 2026-03-10
**Status:** Accepted

**Context:** ADR-016 established the Universal Model Router as a resolution-only system — it maps task names to model names but never calls any AI provider. Generation scripts still independently implement HTTP calls to Ollama and OpenAI, creating duplication in error handling, timeout management, and response parsing.

Phase 2A answers the question: should the router also execute the model call, or remain resolution-only?

**Decision:** Evolve the router from "resolution-only" into a "resolution + controlled synchronous execution gateway" with:

1. **Provider abstraction layer** (`server/model_router/providers.py`)
   - `BaseProvider` ABC with `generate()` method
   - `OllamaProvider`: calls Ollama `/api/generate` via stdlib `urllib`
   - `OpenAIProvider`: calls OpenAI `/v1/chat/completions` via stdlib `urllib`
   - `get_provider()` factory function
   - Providers are thin transport adapters — no business logic, no prompt construction
   - No external HTTP libraries (consistent with `availability.py`)

2. **POST /generate endpoint** in the FastAPI API
   - Accepts task + prompt, routes through existing router, calls provider, returns result
   - Synchronous only, non-streaming
   - Input validation via Pydantic (max prompt 32k chars, temperature 0.0-2.0, max_tokens 1-4096)
   - Provider error mapping: 502 for upstream HTTP errors, 503 for unreachable providers, 500 for unknown providers

3. **API hardening**
   - **Breaking change**: All HTTP API responses now wrapped in `{"ok": true/false, ...}` envelopes
   - CLI output format is unchanged — only HTTP API contracts changed
   - API key auth middleware (`MODEL_ROUTER_API_KEY` env var)
   - Strict localhost bypass: only `request.client.host` in `{127.0.0.1, ::1}`, no forwarded header trust
   - If key not set, auth is disabled (dev mode)

4. **Traditional lock preserved**
   - Lock is enforced at the router level (unchanged from ADR-016)
   - Provider layer executes whatever the router resolves — cannot override model or provider
   - `traditional_story_remote` → `gpt-4.1` → `OpenAIProvider` — the only path

**What is NOT in Phase 2A:**
- Response caching (deferred)
- Job queue / async generation (deferred)
- Streaming responses (deferred)
- "ZauwieTech AI Core" rebranding (deferred)
- Docker orchestration (out of scope)
- Redis / Celery (out of scope)

**Rationale:**
- **Centralized execution reduces duplication**: Scripts can call one endpoint instead of implementing provider calls independently
- **Provider abstraction enables testing**: Mock providers in tests without mocking HTTP
- **Execution boundary at the router maintains lock enforcement**: The provider cannot choose a different model
- **stdlib-only providers**: Consistent with existing availability.py (no requests/httpx dependency)
- **Synchronous-first**: Matches existing batch generation patterns

**Consequences:**
- New file: `server/model_router/providers.py`
- Modified: `server/model_router/api.py` (auth, envelopes, /generate) — version bumped to 2.0.0
- Modified: `server/model_router/telemetry.py` (added `log_generation` event)
- New test files: `tests/test_providers.py`, `tests/test_api.py`
- Modified: `scripts/ai_health_check.sh` (envelope-aware parsing)
- Modified: `docs/ARCHITECTURE.md`, `server/model_router/README.md`
- HTTP API response shapes changed (breaking) — `{"ok": true, "data": ...}` envelopes
- CLI output format unchanged
- No changes to `router.py` core resolution logic
- No changes to `model_registry.json`

**Freeze:** Verified 2026-03-10

- 77/77 tests passing
- smoke tests passing
- health check passing (API warning only when not started)

This freeze establishes the Phase 2A baseline:
- router.py remains the single source of truth for task resolution
- providers.py remains a thin transport-adapter layer
- the API layer performs controlled synchronous execution
- the Traditional OpenAI lock remains enforced by the router

Future work must preserve these guarantees unless explicitly revised by a later ADR.

---

## ADR-018: Model Router Phase 2B — Execution Enhancements Evaluation

**Date:** 2026-03-10
**Status:** Proposed

**Context:** Phase 2A (ADR-017) established the Model Router as a controlled synchronous execution gateway. The current architecture:

- `router.py` owns all task-to-model resolution (unchanged since ADR-016)
- `providers.py` contains thin transport adapters for Ollama and OpenAI (stdlib urllib only)
- `POST /generate` performs synchronous, non-streaming generation
- All responses use structured `{"ok": true/false, ...}` envelopes
- The Traditional OpenAI lock is enforced by the router, not the providers
- There is no response caching
- There is no job queue or async execution
- The module remains `server/model_router/` (no rebranding)

This ADR evaluates whether Phase 2B enhancements are justified now, or whether the current synchronous architecture is sufficient.

**Question to Decide:** Should Phase 2B introduce:
- Response caching
- Job lifecycle / async execution
- Both
- Or neither

### Option A — No Phase 2B Yet

The synchronous `POST /generate` endpoint may already be sufficient for current workloads:

- Bible PAL stories are batch-generated offline, not requested in real time by users
- The primary consumer is `generate_v2_batch.sh`, which processes stories sequentially
- Title generation and reasoning tasks complete in seconds
- There are no concurrent callers competing for the endpoint
- No repeated identical requests have been observed in practice

If no real performance or reliability problem exists, adding caching or async execution creates maintenance cost without delivering value. The simplest correct architecture is the one that already works.

### Option B — Minimal File-Based Caching

A small, reversible file-based cache could reduce redundant provider calls for safe, idempotent tasks.

**Design sketch:**
- Cache keyed on: task + normalized input hash + resolved model + provider
- Cache stored as JSON files in a local directory (e.g., `server/model_router/.cache/`)
- TTL-based expiration (e.g., 24 hours for `story_title`, no caching for story generation)
- Bypass flag: `"use_cache": false` in request options
- Only cache tasks explicitly marked as cacheable in the registry
- Never cache `traditional_story_remote` or `creative_story` unless explicitly safe

**When this would be justified:**
- Telemetry shows repeated identical `story_title` or `reasoning_fast` calls with the same input
- A batch run is restarted and re-processes already-completed items
- Provider latency is measurably impacting batch throughput

**When this is NOT justified:**
- Speculative "it might help someday" reasoning
- Hypothetical future apps that don't exist yet

### Option C — Minimal Job Lifecycle

A small, reversible job tracking layer could support longer-running generation tasks that don't fit synchronous request/response.

**Design sketch:**
- Job registry as an in-memory dict (no database, no Redis)
- Job states: `pending`, `running`, `completed`, `failed`
- `POST /generate` returns inline for fast tasks; returns a `job_id` for long tasks
- `GET /jobs/{job_id}` returns job status and result when complete
- Background execution via Python `threading` or `concurrent.futures` (no Celery, no external queue)
- Job results expire after a configurable TTL

**When this would be justified:**
- `longform_experimental` tasks with mixtral consistently exceed HTTP timeout thresholds
- A caller needs to fire-and-forget a generation and poll for results
- Synchronous generation blocks batch scripts for unacceptable durations

**When this is NOT justified:**
- All current tasks complete within the existing timeout windows (120s Ollama, 180s OpenAI)
- No caller currently needs async semantics

### Risks and Tradeoffs

1. **Premature scaffolding decays.** Code built for hypothetical workloads tends to rot. If caching or jobs are built now but not used for months, they become untested assumptions baked into the architecture.

2. **Complexity has maintenance cost.** Cache invalidation is a known source of subtle bugs. Job lifecycle state machines require careful error handling. Both increase the surface area that must be tested and understood.

3. **YAGNI applies strongly here.** The current synchronous architecture handles all known workloads. Adding infrastructure for workloads that don't exist yet violates the project's minimal-diff discipline.

4. **Reversibility is key.** If Phase 2B is eventually needed, both options (B and C) can be implemented as additive, single-file additions without modifying `router.py` or `providers.py`. There is no architectural reason to build them now to "prepare" — the current design already accommodates them.

### Recommendation

**Option A — No Phase 2B yet.**

The synchronous execution gateway is sufficient for all current Bible PAL workloads. No caching or async execution should be built until real-world evidence demonstrates a concrete need.

The strongest argument for waiting: both caching and jobs can be added later as additive, reversible changes. Nothing in the Phase 2A architecture forecloses them. Building them now would add code that passes tests against its own contract but has no real callers — the definition of speculative scaffolding.

### Revisit Triggers

Phase 2B should be reconsidered when any of these conditions are observed:

1. **Repeated identical requests:** Telemetry logs show the same task + input combination being sent to a provider multiple times in a batch run (caching signal)
2. **User-facing latency:** A generation task consistently exceeds acceptable response time for its caller, and the bottleneck is provider round-trip time rather than prompt quality (caching or async signal)
3. **Provider outages:** Ollama or OpenAI intermittent failures cause batch runs to fail without retry, and the failure rate is high enough to matter (retry/async signal)
4. **Timeout exhaustion:** `longform_experimental` or future tasks routinely hit the 120s/180s timeout limits (async signal)
5. **Concurrent callers:** Multiple scripts or services begin calling `POST /generate` simultaneously, creating contention (async signal)

Until at least one of these triggers fires with real data, Phase 2B should remain Proposed.

---

## ADR-019: AI Command Center Developer Dashboard

**Date:** 2026-03-11
**Status:** Accepted

**Context:** The Model Router infrastructure (ADR-016, ADR-017) provides JSON API endpoints for health, models, tasks, and routing — but developers must use CLI commands or raw `curl` calls to inspect system state. A simple read-only dashboard would make operational status visible at a glance during development.

Key design questions:
1. How should the dashboard access the `ModelRouter` instance without circular imports?
2. Should it be a separate service or part of the existing FastAPI app?
3. What rendering approach (SPA, server-rendered, templates)?

**Decision:** Implement a Jinja2-based developer dashboard mounted on the existing FastAPI app at `/dashboard`:

1. **Three pages (Phase 1):** Mission Control (system status + disk usage), Models (table), Router (interactive task resolution)
2. **`app.state` dependency injection:** Dashboard routes access the `ModelRouter` via `request.app.state.router`, avoiding circular imports between `api.py` and the dashboard module
3. **Server-rendered HTML:** Jinja2 templates with embedded CSS, no frontend framework
4. **Hybrid data access:** Pages call `ModelRouter` directly for server-rendered content; Router page uses vanilla JS `fetch()` to call the existing `/resolve/{task}` API for interactive resolution
5. **Read-only:** No mutations, no configuration changes, no model management

**Rationale:**
- **`app.state` over direct import:** Idiomatic FastAPI pattern. No circular imports. Dashboard modules import `ModelRouter` type from `server.model_router.router` for type hints, never from `api.py`.
- **Mount on existing app:** Shares auth middleware, avoids port conflicts, simpler deployment. Dashboard is just 3 additional routes.
- **Jinja2 over SPA:** Three static pages with one interactive element. A full SPA framework would be overengineered.
- **No CSS framework:** Internal tool with cards and tables. Embedded styles are sufficient.

**Consequences:**
- New module: `server/dashboard/` (routes, views, templates, tests)
- Modified: `server/model_router/api.py` (add `app.state.router`, mount dashboard router — 4 lines)
- Modified: `server/model_router/requirements.txt` (add `jinja2>=3.1.0`)
- Dashboard at `http://127.0.0.1:8181/dashboard/` when API server is running
- Auth middleware applies to dashboard routes (localhost bypass works for local dev)
- No changes to `router.py`, `model_registry.json`, or generation scripts

**Phase 1 frozen:** 2026-03-11 — commit `af8b442`. Three pages live, 14 tests, zero regressions.

**Phase 2 backlog** (do not implement until prerequisites exist):
1. **Router Logs page** — prerequisite: persist telemetry to file/SQLite instead of stderr-only
2. **Story Activity page** — prerequisite: add structured generation event logging to story scripts
3. **Storage deep-dive page** — model storage breakdown, story asset sizes by mode/bucket
4. **Alerts panel** — surface warnings when Ollama is down, disk > 90%, or models missing from fallback chains
5. **Story Factory page** — batch generation status, last run results, queue visibility

Each item should only be built when its data source exists and a real operational need is demonstrated.

---

## ADR-020: Creative Story DNA Diversity System

**Date:** 2026-03-14
**Status:** SUPERSEDED 2026-05-13 by Creative Retirement — see [archive/CREATIVE_RETIREMENT_2026_05_13.md](archive/CREATIVE_RETIREMENT_2026_05_13.md). The Story DNA system was Creative-only; all referenced scripts and data files (`server/story_dna.sh`, `server/data/creative_place_names_avoid.txt`, `server/prompts/creative_prompt.template.txt`) have been archived to T9 and removed.
**Context:** Creative stories generated by mistral-nemo showed repetitive structural patterns: most opened with location descriptions ("In a small village..."), reused fictional place names (Meadowgrove, Stonevale), and followed similar narrative arcs. The single-pass pipeline needed diversity injection without adding a second LLM pass or changing the model.

**Decision:** Implement a "Story DNA" planner that deterministically assigns structural attributes to each creative story before generation:

1. Shell-based planner (`server/story_dna.sh`) with rotating pools for opening type, structure type, setting emphasis, character archetype, and tone
2. Deterministic index-based rotation with prime-number offsets to prevent lockstep
3. Prompt template (`server/prompts/creative_prompt.template.txt`) enhanced with DNA variables
4. Place-name avoidance list (`server/data/creative_place_names_avoid.txt`) injected into prompts
5. Repetition guard prevents 3+ consecutive stories with identical opening or structure type
6. DNA metadata stored in `meta_*.json` under `storyDna` key

**Rationale:**
- Deterministic over random: testable, reproducible, auditable
- Shell functions sourced into existing batch script: minimal structural change
- Prompt injection over model change: works with any LLM in the fallback chain
- Additive metadata: existing pipeline and app code unaffected
- `setting_emphasis=low` explicitly forbids place descriptions, breaking the "In a small village" pattern
- Guard is batch-local (`.dna_history.json` reset per batch), but seeds from existing metadata for cross-batch awareness

**Consequences:**
- New: `server/story_dna.sh`, `server/data/creative_place_names_avoid.txt`, `server/test_story_dna.sh`
- New test: `test/core/story_dna_metadata_test.dart`
- Modified: `server/generate_v2_batch.sh`, `server/prompts/creative_prompt.template.txt`
- Modified docs: `docs/SPEC.md` (Creative Mode Contract section), `docs/DECISIONS.md`
- No changes to Flutter/Dart app code, model router, Traditional pipeline, or manifest schema
- Future: Design is open for optional multi-model experiments (e.g., adding `storyteller_model` to DNA) without restructuring

---

## ADR-021: Narrator Voice + Opening Validation

**Date:** 2026-03-14
**Status:** Accepted
**Context:** Phase 1 verification of ADR-020 (Story DNA) revealed two compliance gaps: (1) mistral-nemo consistently ignored `opening_type` instructions for dialogue and question, prepending a setting clause before the target opening element; (2) `setting_emphasis=low` was too strict ("invisible setting") and the model ignored it. Additionally, the 5 existing DNA dimensions provided structural diversity but stories still sounded similar in prose style — a 6th dimension for narrative voice was needed.

**Decision:** Two-phase enhancement to the Story DNA system:

Phase 1 — Opening Compliance:
1. Revised `setting_emphasis=low` from "invisible" to "minimal" (one brief environmental detail allowed)
2. Added `validate_and_retry_opening()` to `generate_v2_batch.sh` — regex-based first-sentence validation for dialogue (starts with `"`), question (first sentence contains `?`), and memory (time references). On failure, regenerates once with a forceful anchor instruction. Accepts result regardless.
3. Fixed dialogue validator bug (was checking ALL lines, not first line) and broadened memory regex

Phase 2 — Narrator Voice:
4. Added `narrator_voice` as 6th DNA dimension with 4 maximally distinct voices: `fireside` (warm, direct address), `literary` (elegant, metaphor-rich), `folk_tale` (oral tradition conventions), `spare` (minimalist, restrained)
5. Prime offset 13 in rotation prevents lockstep with other dimensions
6. Prompt template instructs the model on each voice's distinguishing features

**Rationale:**
- Retry-based validation over two-pass architecture: adds ~20 minutes to a full batch but avoids architectural complexity. Phase 1 gate showed 9/9 post-retry compliance (dialogue 3/3, question 3/3, memory 3/3)
- "Minimal" over "invisible" setting: realistic for narrative fiction, model compliance improved from 0% to acceptable
- 4 voices over more: maximally distinct so a 7B model can differentiate. Deliberately few to prove compliance before expanding
- Narrator voice over pivot_type or scene_motif: highest signal-to-noise ratio for prose variety; other dimensions deferred until compliance is proven

**Consequences:**
- Modified: `server/story_dna.sh` (new pool + rotation), `server/generate_v2_batch.sh` (validation function + narrator injection), `server/prompts/creative_prompt.template.txt` (narrator voice block + setting revision)
- Modified tests: `server/test_story_dna.sh` (narrator pool coverage + anti-lockstep), `test/core/story_dna_metadata_test.dart` (narrator_voice validation, optional field)
- `narrator_voice` is additive metadata — existing stories without it are unaffected
- Retry cost: ~78% of dialogue/question/memory outputs need one retry (~20-40s each)
- No changes to Flutter/Dart app code, Traditional pipeline, model router, or manifest schema

---

## Template for Future Decisions

```
## ADR-022: Scripture Anchor Registry — Canonical Traditional Story System

**Date:** 2026-03-18
**Status:** Accepted (supersedes ADR-010 section 3 only)
**Context:** ADR-010 established a 1:1 mapping between mood and `bibleStoryKey` for Traditional stories. This was appropriate for first-pass coverage (8 moods × 1 story each) but blocks scaling toward ~1500 unique Traditional stories. At scale, variety matters more than predictability — users should never hear the same Bible story twice until the pool is exhausted.

The core question: How do we identify, track, and prevent reuse of Bible narratives across hundreds of Traditional stories?

**Decision:**

1. **Scripture Anchor Registry** — A standalone JSON file (`assets/stories/scripture_anchor_registry.json`) is the canonical source of truth for all approved Traditional Bible story anchors.

2. **`scriptureAnchorId` is the primary uniqueness key** — A normalized identifier for one canonical narrative unit (e.g., `mark_4_35-41`, `1kgs_19_9-18`). No two registry entries may share the same `scriptureAnchorId`, even if `bibleStoryKey` wording differs. This is the true no-repeat identity.

3. **Registry entries are minimal and declarative** — Each entry has exactly 4 fields:
   - `scriptureAnchorId` — primary uniqueness key
   - `bibleStoryKey` — human-readable label (globally unique)
   - `bibleSourceRef` — display-friendly scripture reference
   - `moodTags` — array of moods this anchor can serve (mood is a tag, not an identity)

4. **No mutable or derived fields** — The registry stores no `status`, `priority`, `tier`, `complexity`, or `testament`. "Used" status is derived from whether `bibleStoryKey` appears in `manifest.json`.

5. **Mood is a tag, not a grouping key** — One anchor may serve multiple moods via `moodTags`. Identity is the scripture anchor, not the mood. No mood-first assumptions in tests or tooling.

6. **Dart code parses, does not own** — The JSON registry is canonical. Dart test helpers parse it for validation; the app runtime has zero dependency on loading it. Manifest entries retain a single `mood` field for runtime compatibility.

**What stays from ADR-010:**
- Traditional = real Bible story retelling (sections 1, 2, 4, 5, 6 unchanged)
- `bibleStoryKey` and `bibleSourceRef` required on all Traditional stories
- Pizzazz constraints, reflection system, mode persistence

**What changes:**
- Section 3 ("One Bible Story Per Mood") is **superseded** — multiple stories per mood are now allowed
- The `Map<String, String>` canonical map (`traditional_canonical_story_map.dart`) is replaced by the JSON registry
- Alternative #2 from ADR-010 ("Multiple Bible stories per mood — Rejected") is now the accepted path

**Rationale:**
- **Scale**: 1500 unique stories across 8 moods requires ~188 stories per mood — a 1:1 map cannot express this
- **No-repeat guarantee**: `scriptureAnchorId` provides a machine-comparable uniqueness key that prevents reuse of the same narrative even under different names
- **Declarative registry**: JSON is readable by both Dart tests and bash generation scripts (`jq`)
- **Minimal runtime impact**: Manifest schema and serving logic are unchanged in this pass

**Consequences:**
- New file: `assets/stories/scripture_anchor_registry.json`
- Deleted file: `lib/core/traditional_canonical_story_map.dart` (superseded)
- New test helper: `test/helpers/scripture_anchor_registry_loader.dart`
- Tests rewritten: `traditional_canonical_story_map_test.dart`, `traditional_bible_story_test.dart`
- Docs updated: SPEC.md, INVARIANTS.md, ARCHITECTURE.md
- Future path: `scriptureAnchorId` may be added to manifest/meta.json entries directly (separate change)

---

## ADR-023: Story Quality Over Strict Word Count Compliance

**Date:** 2026-03-19
**Status:** Accepted
**Context:** Traditional stories generated by gpt-4.1 sometimes exceed their generation target word counts but produce high-quality, well-paced narrative. Story 826 (David and Goliath) landed at 588 words (short target: 550) and 1167 words (full target: 1000) — both excellent retellings that fit their intended bucket experience. The audio gate was rejecting these stories, wasting good text and blocking audio generation.

**Decision:** Traditional stories should be generated toward their target word-count ranges, but final acceptance must prioritize story quality and bucket identity over strict count compliance. Stories must never be manually trimmed solely to satisfy target counts. If a generated story modestly exceeds its target yet still clearly fits its intended bucket experience, it should be accepted as-is and allowed through audio generation. Only stories that drift so far that they no longer match the intended bucket should be regenerated or flagged.

> **⚠️ PARTIALLY SUPERSEDED by ADR-030 (2026-07-19).**
> **Still valid:** quality and bucket identity over strict count compliance; never trim solely
> to satisfy a count; the separation between prompt targets and acceptance ranges.
> **Superseded:** this ADR's Rationale cites the canonical SPEC bucket boundaries
> (250-600, 601-1200, 1201-2000) as acceptance ranges for authoring. Those figures are
> **runtime classification / UI bounds**, not authoring-validation bands. Adult Traditional
> authoring bands are Short 300–500, Full 501–900, Long 901–1500, specified in
> STORY_FACTORY.md §5. The two systems are distinct; see ADR-030.

**Implementation:**
- **Prompt targets** (what the LLM is told to aim for): tighter sweet-spot ranges (short ≤500, full ≤950, long ≤1500)
- **Acceptance ranges** (audio gate + validation): full canonical bucket boundaries (short ≤600, full ≤1200, long ≤1800)
- **Word count flags**: when a story exceeds its prompt target but is accepted within the bucket, `meta_XXX.json` records a `wordCountFlags` entry with promptTarget, actual count, bucketMax, and acceptance status
- **Generation log**: `.generation_log.json` in the stories directory appends one entry per generation run for batch-level trend tracking

**Rationale:**
- The canonical SPEC bucket boundaries (250-600, 601-1200, 1201-2000) define the user experience — a "short" story should feel short, not hit an exact number
- gpt-4.1 produces rich traditional narrative; artificially tight ranges were cutting off strong passages
- Trimming stories to hit arbitrary targets risks degrading quality — the LLM wrote the text as a coherent piece
- The separation between prompt targets and acceptance ranges lets us aim for the sweet spot while accepting natural variation
- Word count flags provide observability without blocking good stories

**Consequences:**
- `server/story_calibration.sh`: Traditional acceptance ranges widened to canonical bucket boundaries; new prompt target constants and `get_prompt_target_max_for_mode()` function added
- `server/generate_v2_batch.sh`: Audio gate uses acceptance ranges; prompt injection uses prompt targets; word count flags tracked in meta.json and generation log
- `meta_XXX.json`: New optional `wordCountFlags` field records per-length overages
- `assets/stories/.generation_log.json`: New file, appended per generation run
- No existing stories are affected — only future generations use the new ranges

---

## ADR-024: LLM-Generated Reflections with Template Fallback

**Date:** 2026-03-19
**Status:** Accepted
**Context:** Post-story reflections were 16 hardcoded templates (8 moods x adult/kid) that read like category descriptions ("Stories of courage often reflect..."). They were generic, abstract, and disconnected from the specific story just heard. A David and Goliath story got the same reflection as a Daniel in the lion's den story — both just "brave_courage" bucket text.

**Decision:** Two-phase improvement:
1. Rewrite all 16 templates to be direct, personal, and grounded (Option 2 / "gentle exhale" style)
2. Add LLM-generated reflections tied to the specific story content, with the rewritten templates as automatic fallback

LLM reflections are generated after story text, validated strictly, and the final resolved text + source are stored in meta.json.

**Implementation:**
- **Rewritten templates**: `get_reflection_text()` in `generate_v2_batch.sh` — all 16 rewritten to be direct and personal
- **Prompt template**: `server/prompts/reflection_prompt.template.txt` — grounded in specific story text, strict guardrails
- **Validation**: `validate_reflection()` — 15-60 words, no theology/doctrine, no preaching, no questions, no exclamation marks
- **Pipeline**: LLM generation attempted first (2 retries), falls back to template on validation failure
- **Meta.json**: New fields `reflectionSource` ("llm" or "template") and `reflectionText` (final resolved text)
- **Backward compatibility**: Existing `reflectionQuestion` field preserved; new fields added alongside

**Validation guardrails:**
- Word count: 15-60 words
- Banned: theology ("God's plan", "His grace"), preaching ("We should", "You can learn"), story-shows openers, questions, exclamation marks
- Must be grounded in something specific from the story
- Written for spoken audio — natural rhythm, short sentences

**Rationale:**
- Reflections are the last thing a listener hears — they should feel personal, not templated
- Story-specific reflections create a stronger emotional arc (David's stone, Elijah's whisper)
- Strict validation prevents theological drift while allowing creative grounding
- Template fallback ensures every story always has a reflection, even if LLM fails
- Storing source + text in meta.json provides full observability

**Consequences:**
- `server/generate_v2_batch.sh`: Rewritten templates, new functions `validate_reflection()` + `generate_llm_reflection()`, updated PHASE 2
- `server/prompts/reflection_prompt.template.txt`: New prompt template file
- `meta_XXX.json`: New optional fields `reflectionSource` and `reflectionText`
- Small additional LLM cost per story (~200 tokens for reflection generation)
- Small additional ElevenLabs cost only if reflection text changes (same audio pipeline)

---

## ADR-025: Traditional Mode Boundary Enforcement

**Date:** 2026-03-19
**Status:** Accepted
**Context:** Story 827 (Mary and Martha, Luke 10:38-42) exhibited boundary drift in full and long lengths. After Jesus' final words, the generated text continued with invented scenes: Martha sitting down next to Mary, sisters holding hands, Jesus teaching about lilies and sparrows (imported from other passages), evening departure, "in the days that followed" reflections. The short version was clean. Root cause: (1) no hard-stop rule in the Traditional prompt, and (2) the continuation prompt had zero Traditional guardrails — when a story was too short, the continuation naturally completed the narrative beyond the Scripture boundary.

**Decision:** Traditional stories must stop at the Scripture passage boundary. Three-layer enforcement:
1. **Prompt-level**: Hard stop rule in the prompt template with passage-specific final line
2. **Continuation-level**: Traditional-aware continuation prompt that enforces the same boundary rules
3. **Validation-level**: Post-generation boundary drift detector + Dart regression test

**Implementation:**
- `server/prompts/traditional_prompt.template.txt`: New SCRIPTURE BOUNDARY section with `{{PASSAGE_FINAL_LINE}}` variable and explicit DO NOT list
- `server/seeds/traditional_seeds.json`: New `passageFinalLine` field on all 16 story seeds (WEB translation final verse text)
- `server/generate_v2_batch.sh`: `passageFinalLine` injected into prompt; continuation prompt is now mode-aware with Traditional boundary rules; new `check_boundary_drift()` function scans for continuation phrases; results logged to `meta.json` as `boundaryValidation`
- `test/critical/traditional_boundary_enforcement_test.dart`: Dart regression test — strict for post-ADR-025 stories (>= 826), informational audit for legacy stories

**Boundary validator patterns:** "as evening fell", "later that day", "in the days that followed", "when they departed", "the lesson lingered", "long after", "from then on", "she/he would find herself/himself", and similar post-boundary continuation phrases.

**Rationale:**
- Traditional mode contract requires Scripture fidelity — extending past the passage is functionally Creative mode
- The continuation prompt was the main failure point: it had no concept of Scripture boundaries
- Providing the exact final line gives the LLM a concrete stopping point
- Regex-based validation catches obvious drift without over-engineering
- Non-blocking validation prevents false-positive rejection while maintaining observability

**Consequences:**
- Story 827 regenerated: all 3 lengths now pass boundary validation (short 502w, full 819w, long 1235w)
- 8 legacy stories (pre-ADR-025) flagged for potential drift — informational only, future cleanup
- All future Traditional stories run through boundary validation automatically
- `meta_XXX.json`: New `boundaryValidation` field records per-length pass/flagged status

---

## ADR-026: Traditional Passage Length Capability System

**Date:** 2026-03-20
**Status:** Accepted
**Context:** After implementing strict Scripture boundary enforcement (ADR-025) and termination rules, story 827 (Mary and Martha, Luke 10:38-42 — 5 verses) could only generate a clean short version (362-402 words). Full and long variants failed word count minimums because the model correctly stopped at the passage boundary but couldn't fill the required word count from 5 verses of source material. The model was doing the right thing — the bucket requirement was wrong for this passage.

**Decision:** In Traditional mode, each Scripture anchor has a maximum supported length based on passage scope and proven generation quality. Requested lengths above that cap are intentionally unavailable, not generation failures. The app must only present lengths actually supported by the story anchor and must not silently substitute a different length.

**Policy:** In Traditional mode, Scripture anchor integrity takes priority over bucket completeness. If a passage cannot naturally support a requested bucket length without padding, repetition, imported material, or post-boundary drift, that bucket must be omitted for that passage. Unsupported lengths are considered intentionally unavailable, not generation failures.

**Implementation:**
- `server/seeds/traditional_seeds.json`: New `supportedLengths` array per passage (e.g., `["short"]`, `["short", "full"]`, `["short", "full", "long"]`)
- `server/generate_v2_batch.sh`: Pipeline reads `supportedLengths` from seed, skips unsupported lengths with clear logging, records skipped lengths in meta.json
- `meta_XXX.json`: New `skippedLengths` field records intentionally unavailable lengths with reason
- Manifest: Only generated lengths appear — unsupported lengths have no manifest entry
- App selection: `ParableService.getEligibleParables()` already filters by `lengthBucket` — stories without a manifest entry for a given length are automatically excluded from selection

**Length assignments (initial):**
- Short only (1-5 verses): lost_sheep, rest_for_the_weary, mary_and_martha
- Short + Full (6-10 verses): jesus_calms_storm, elijah_at_horeb, hagar_in_wilderness
- All three (11+ verses): woman_at_well, road_to_emmaus, daniel_lions_den, samuel_listens, queen_esther, david_and_goliath, ruth_and_naomi, prodigal_son, joseph_interprets_pharaohs_dreams, moses_and_jethro

**Rationale:**
- A good 362-word Mary/Martha story is far better than a fake 1200-word one
- Padding, repetition, and post-boundary drift are all symptoms of forcing a passage beyond its natural scope
- The app selector naturally routes around missing lengths — user gets a different story of the right mood and length
- No UI changes needed — the constraint is invisible to the user

**Consequences:**
- Story 827 regenerated as short-only (402 words, boundary PASS)
- 3 passages marked short-only, 3 marked short+full, 10 marked all three
- Future passages should be assessed for `supportedLengths` when added to the registry
- Lengths can be upgraded if a post-termination-fix generation proves the passage can support it

---

## ADR-027: Opus Batch System — Long Stories Optional

**Date:** 2026-03-29
**Status:** Accepted
**Context:** During PAL_OPUS_BATCH_01 generation, many stories exceeded long word count targets (some creative kids hit 1800w vs 1050 max). Forcing every story to have a long version led to padding, repetition, and quality degradation. Some Bible passages are too concise to support a 1201-1400 word retelling without invention.

**Decision:** Long stories are now OPTIONAL. Short and Full remain required. If a story cannot support a strong long version without padding or quality loss, the long file is not created. Each story declares `availableLengths` in meta and manifest.

> **⚠️ PARTIALLY SUPERSEDED by ADR-030 (2026-07-19).**
> **Still valid:** the core principle — quality over length uniformity; never pad, repeat, or
> invent to satisfy a bucket; unsupported lengths are omitted; `availableLengths`/`lengths`
> declare what exists.
> **Superseded:** "Short and Full remain required." For adult Traditional content, **Full is
> now conditional** on what the approved anchor honestly supports, exactly as Long has been
> since this ADR. ADR-030 generalizes this ADR's no-padding rule from Long to **both Full and
> Long**. Short remains the default expected version.

**Rationale:**
- Quality is the top priority — padded stories sound worse in TTS
- Some passages (e.g., Genesis 32:22-32 for kids) can't sustain 1200+ words
- The serving system can skip stories that don't support the requested length
- This matches real-world usage: most listeners use short or full

**Consequences:**
- Meta JSON `lengths` field reflects only available lengths
- Manifest entries include `availableLengths` for each story
- PAL_OPUS_BATCH_01: 10 of 32 stories retained long, 22 dropped for quality
- Future batches should evaluate long viability per-story during generation

---

## ADR-028: Opus Batch System — Permanent Generation Contract

**Date:** 2026-03-29
**Status:** Accepted
**Context:** Bible PAL story generation was ad-hoc across sessions, leading to inconsistency in quality, word counts, file structure, and manifest management. The Opus 4.6 system needed a locked, repeatable contract.

**Decision:** Created `docs/OPUS_BATCH_SYSTEM.md` as the permanent source of truth for all Opus story generation. Created reusable prompt files (`docs/prompts/opus_batch_*.txt`) for session initialization, execution, and review. All future batches must follow this system exactly.

**Rationale:**
- Zero drift across sessions — every batch follows identical rules
- Explicit review pipeline catches quality and word count issues before manifest build
- Separation from legacy system prevents accidental modification of production stories
- Reusable prompts ensure Claude starts each session with the full context

**Consequences:**
- `docs/OPUS_BATCH_SYSTEM.md` is the authoritative document for batch generation
- Three prompt files standardize the workflow: starter, execution, review
- Any deviation requires stopping and requesting clarification
- The system is versioned and tracked in DECISIONS.md

---

## ADR-029: Fourth PAL Voice — Miriam (Staged)

**Date:** 2026-07-14
**Status:** Accepted
**Context:** The active PAL roster (Hope, Shepherd, Stillwater) is 2 male / 1 female. The owner wants a fourth voice to balance the roster to 2/2, using the ElevenLabs source voice behind story narrator `VOICE_MIRIAM_JOYFUL` (in use by 24 stories), whose sound he specifically approved. SPEC 17b had also drifted from shipped code (it still listed retired VOICE_GRACE as a four-voice default).

**Decision:**
- Registered `VOICE_MIRIAM` (display "Miriam", 🌻, "Joyful spirit", female, ElevenLabs `XrExE9yKIg1WjnnlVkGX`) as a **staged** PAL voice: present in `PalVoiceRegistry.stagedVoices` and `server/voices.json` `palVoices`, but excluded from the active `voices` list — never shown in the Settings picker, never validates, and would migrate to the default like any unknown key.
- Minted a **distinct PAL key** rather than reusing the narrator key `VOICE_MIRIAM_JOYFUL`. The PAL/narrator systems stay key-disjoint (per the permanent separation rule in `story_voice_registry.py`); sharing the underlying ElevenLabs source voice across both systems is an owner-approved exception, a first.
- Corrected SPEC 17b to shipped reality (3 active voices, default `VOICE_STILLWATER`) and documented the staged voice and its activation criteria there.
- Replaced two lingering `?? 'VOICE_GRACE'` fallbacks (first_launch_screen, name_prompt_overlay) with `PalVoiceRegistry.defaultVoiceKey` — Grace was retired 2026-04-23, so those fallbacks generated name audio under a dead voice key.
- Fixed the stale roster in `server/generate_pal_audio_batch.sh`: it still listed retired VOICE_GRACE (as DEFAULT_VOICE, first in roster) — a re-run would have re-rendered ~127 Grace clips, recreated the forbidden `assets/pal/audio/VOICE_GRACE/` dir (failing `pal_v2_asset_verification_test.dart`), and produced zero Miriam audio. Roster is now HOPE/SHEPHERD/STILLWATER/MIRIAM with DEFAULT_VOICE=VOICE_STILLWATER; with skip-if-exists, a guarded run now fills exactly Miriam's gaps.
- Hardened `pal_voice_registry_test.dart` with a PAL/narrator key-disjointness test that reads the actual narrator pool from `server/voices.json` (active + staged PAL keys must never appear there).

**Rationale:**
- Staging lets all registry/SPEC/test plumbing land with zero runtime behavior change, before any audio spend. Activation is a one-entry move from `stagedVoices` to `voices` plus roster-test updates.
- Adding the voice before the journey expansion slate renders means its new framing lines can be rendered ×4 in one pass instead of ×3 plus a later backfill.
- Distinct keys prevent allowlist/banlist cross-contamination between the narrator validation system and PAL asset paths.

**Consequences:**
- Activation gate: render Miriam's full live audio surface (~515 clips ≈ 32–35K chars via eleven_v3: 12 canonical openings, 96 prompts, 30 micro-responses, 32 reflections, 120 tone-biased reflections, 12 transitions, preview, 212 figure framing lines), pass the PAL_VOICE.md eight-question audit, then move the entry to `voices` and update `pal_voice_registry_test.dart` (4 active, 2M/2F) and `pal_v2_asset_verification_test.dart`.
- The dead categories Hope/Shepherd still carry (60 legacy register openings, 24 Creative clips) are intentionally NOT part of Miriam's surface — no runtime references exist.
- Journey and memory audio remain Stillwater-first; Miriam follows Hope/Shepherd there.
- Users who pick Miriam as PAL may also hear her narrating one of the 24 stories she voices — accepted by owner.

**Activation (2026-07-14, same day):** Miriam's full live audio surface was rendered on `eleven_v3` — 515 clips, ~30.9K credits, 0 failures (127 core conversational + 176 openings/reflections/tone-biased/transitions + 212 figure-framing), acoustically verified. Owner listened to a representative spread and approved her tone (the PAL_VOICE.md audit's substance). She was then activated: moved from `stagedVoices` into `voices`, added to `pubspec.yaml` for bundling, and the roster tests updated to 4 active / 2 male / 2 female. The `stagedVoices` mechanism is retained (now empty) for the next voice. Journey/memory audio remains Stillwater-first, so Miriam — like Hope and Shepherd — resolves those surfaces to silence until rendered. Deferred: recompressing the distribution mirror is handled by the release bundle scripts at build time (the compressed mirror is not version-controlled).

---

## ADR-030: Two Length Systems + Supported-Length Policy (Adult Traditional)

**Date:** 2026-07-19
**Status:** Accepted
**Context:** Multiple active documentation surfaces conflated runtime classification, authoring-validation bands, and drafting targets. SPEC.md, ARCHITECTURE.md, INVARIANTS.md and DECISIONS.md carried 250–600 / 601–1200 / 1201–2000 (marked "LOCKED SPEC"); STORY_FACTORY.md and OPUS_BATCH_SYSTEM.md carried 350–450 / 700–850 / 1201–1400; STORY_NARRATION_STYLE_GUIDE.md carried 300–500 / 501–900 / 901–1500 — which is what `story_word_count_compliance_test.dart` actually enforces. Investigation showed the first set is not a stale duplicate: it is hard-coded in `lib/core/story_length_bucket.dart` and governs runtime classification and UI labelling. The documents were describing **two different systems** as if they were one.

Separately, story 1565 (Peter's Denial, Luke 22:54-62) rendered the complete nine-verse anchor at 173 words. Reaching the 300-word Short floor would have required inventing cold, night, torches, faces, and motive. The owner chose textual honesty and approved `shortScripture: true` — which SESSION_HANDOFF.md described as legacy-only, contradicting the decision actually made. The same evaluation showed 1563 and 1565 cannot honestly support a Full, making ADR-027's "Short and Full remain required" unsatisfiable without padding.

**Decision:**

1. **Two distinct systems, documented as such.**
   - *Runtime classification / UI* — `lib/core/story_length_bucket.dart`, unchanged and authoritative for runtime behavior. Nominal ranges Short 250–600, Full 601–1200, Long 1201–2000. `wordCountToBucket()` returns Short for any count ≤600 (including below 250), Full for 601–1200, Long for >1200. Determines labelling and serving only.
   - *Adult Traditional authoring compliance* — hard bands Short 300–500, Full 501–900, Long 901–1500, enforced by `story_word_count_compliance_test.dart`.

2. **Authority hierarchy for length ranges.**
   - INVARIANTS.md — states that the two systems are distinct (Two Length Systems Invariant).
   - SPEC.md + ARCHITECTURE.md — runtime/UI behavior, matching the shipped Dart exactly.
   - **STORY_FACTORY.md §5 — authoritative for adult Traditional authoring**: bands, drafting targets, supported-length process, exceptions.
   - STORY_NARRATION_STYLE_GUIDE.md + OPUS_BATCH_SYSTEM.md — cross-reference §5; no competing rules.
   - SESSION_HANDOFF.md — operational summary only.

3. **Drafting targets are guidance, not boundaries.** Short 350–450, Full 700–850, Long ~1200–1400 are preferred aims inside the hard bands. Falling outside a target is not a violation; falling outside a band is.

4. **Supported-length policy.** Every new adult Traditional anchor is evaluated for Short, Full, and Long. Short is the default expected version. Full and Long are conditional on what the approved anchor honestly supports; **neither is universally required**. Never pad, repeat propositions, invent physical detail, add unstated thoughts or motives, or insert theological explanation to reach a floor. Unsupported lengths are omitted with the reason documented in `editorialNotes`. Anchor widening requires a coherent continuous passage and owner approval **before** drafting. Raw scripture word count is an editorial warning signal, never an automatic eligibility formula.

5. **`shortScripture: true` is not legacy-only.** It is an explicit, owner-approved authoring exception permitting an adult Traditional Short below 300 words when the complete approved passage is faithfully rendered and further words would require padding, invention, or commentary. Each use requires owner approval. Runtime still classifies such a story as Short.

6. **Approved current story decisions.**
   - **1562** (John 1:1-18) — Short currently. Full requires a separate approved feasibility or anchor-width review; the prologue is theological poetry with little narrative, so expansion risks commentary.
   - **1563** (Matthew 16:13-20) — Short only.
   - **1564** (1 Samuel 24) — Short + Full + Long. The anchor holds substantial unused explicit material (vv9-15, 19, 21).
   - **1565** (Luke 22:54-62) — Short only; `shortScripture: true` owner-approved. WEB 173w / KJV 175w.

**Scope:** adult Traditional content only. Traditional Kid bands are separate and unchanged.

**Supersedes:** ADR-027's "Short and Full remain required" (Full is now conditional; ADR-027's no-padding principle is generalized from Long to both Full and Long). Also supersedes any reading of the 250–600 / 601–1200 / 1201–2000 figures as authoring bands — they remain valid as runtime/UI bounds.

**Rationale:**
- Rewriting the runtime numbers to match authoring numbers would make the docs describe an app that does not exist; the honest fix is to name the two systems.
- Requiring a Full for every anchor guarantees padding on concise passages — the exact failure ADR-027 identified for Long.
- A single authoritative section prevents the five-way drift that made every prior statement unreliable.

**Consequences:**
- No Dart, test, schema, story, manifest, audio, or metadata change — documentation only.
- `story_word_count_compliance_test.dart` remains the enforcement gate; its numbers are now the documented ones.
- Stories omitting Full or Long must say why in `editorialNotes`.
- Historical ADRs are annotated as partially superseded, not rewritten.
- Open follow-up: 1562 Full feasibility / anchor-width review (John 1:1-18 vs 1:1-34 vs other coherent candidate).

---

## ADR-XXX: [Title]

**Date:** YYYY-MM-DD
**Status:** [Proposed | Accepted | Deprecated | Superseded]
**Context:** [What is the issue?]

**Decision:** [What was decided?]

**Rationale:** [Why was this decided?]

**Consequences:** [What are the effects?]
```
