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

## ADR-002: Multi-Voice Playback Deferred

**Date:** 2026-01-03
**Status:** Deferred
**Context:** SPEC.md §17 originally specified "Multiple voices per story" as a feature. Testing revealed quality issues with child voices (Grant, Abilene) and multi-voice coordination complexity.

**Decision:** Defer multi-voice playback. Use single narrator voice per story.

**Rationale:**
- Child voices (Grant, Abilene) did not sound natural in stories
- Multi-voice coordination adds production complexity
- Single narrator provides consistent, high-quality experience
- Feature can be revisited when voice quality improves

**Consequences:**
- SPEC.md §17 updated: "Single narrator voice per story (multi-voice deferred)"
- Multi-voice generation scripts disabled (.DISABLED suffix)
- Existing multi-voice test story removed from manifest
- Grant and Abilene voices commented out in .env

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
