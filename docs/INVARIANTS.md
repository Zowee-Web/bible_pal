# Bible PAL Invariants

This document defines **hard invariants** — non-negotiable rules that must never be violated. These are not suggestions or best practices. They are absolute constraints enforced by code, tests, and CI.

---

## 🔒 Bible Translation Licensing Invariant (NON-NEGOTIABLE)

**Invariant**: Bible PAL must never display, quote, store, generate, or reference any Bible translation that is not explicitly public-domain or open-license.

### Why This Exists

Using copyrighted Bible translations without licensing:
- Violates copyright law
- Exposes the project to legal liability
- Requires expensive licensing fees (often $thousands per year)
- Restricts distribution and modification rights

Public domain translations:
- Free to use for any purpose
- No licensing fees
- No restrictions on distribution
- Can be freely modified and redistributed

### Allowed Translations (EXHAUSTIVE LIST)

ONLY the following translations are permitted:

- **WEB** (World English Bible) - Public Domain
- **KJV** (King James Version) - Public Domain
- **ASV** (American Standard Version) - Public Domain
- **YLT** (Young's Literal Translation) - Public Domain
- **DRA** (Douay-Rheims American Edition) - Public Domain

See [`lib/core/bible_translation_registry.dart`](../lib/core/bible_translation_registry.dart) for the canonical allowlist.

### Banned Translations (MUST NEVER APPEAR)

The following translations are **explicitly banned** and will cause build failures if detected:

- NIV (New International Version)
- ESV (English Standard Version)
- NRSV (New Revised Standard Version)
- NLT (New Living Translation)
- NASB (New American Standard Bible)
- CSB (Christian Standard Bible)
- MSG (The Message)
- HCSB (Holman Christian Standard Bible)
- AMP (Amplified Bible)
- GNT (Good News Translation)
- **And all others not explicitly listed in the allowlist**

### Enforcement Mechanisms

This invariant is enforced at **four layers**:

#### 1. Code-Level Allowlist Registry
**File**: [`lib/core/bible_translation_registry.dart`](../lib/core/bible_translation_registry.dart)

The single source of truth for all allowed and banned translations. All translation handling code MUST reference this registry.

#### 2. Runtime Guards
Automatic validation in:
- `UserPreferences.fromJson()` / `copyWith()`
- `DailyBread.fromJson()`
- `BibleTranslationRegistry.validateAndSanitize()`

Behavior:
- Banned translation detected → Logs COMPLIANCE VIOLATION → Resets to WEB
- Unknown translation detected → Logs WARNING → Resets to WEB
- Allowed translations pass through unchanged (after normalization)

#### 3. Build-Failing Tests
**Files**:
- [`test/core/bible_translation_compliance_test.dart`](../test/core/bible_translation_compliance_test.dart) - 24 tests validating registry, runtime guards, and fingerprint detection
- [`test/core/repo_wide_compliance_scan_test.dart`](../test/core/repo_wide_compliance_scan_test.dart) - Scans entire codebase for banned translation IDs

**Critical Tests** (MUST PASS):
- `CRITICAL: No banned translation IDs in lib/ directory`
- `CRITICAL: No banned translation IDs in test/ directory`
- `CRITICAL: No banned translation IDs in assets/ directory`
- `CRITICAL: No banned translation IDs in server/ scripts`
- `CRITICAL: validateAndSanitize() rejects banned translations`
- `CRITICAL: VerseService contains no ESV fingerprints`

If ANY banned translation ID appears in the codebase, the build FAILS.

#### 4. CI Enforcement
**File**: [`.github/workflows/flutter.yml`](../.github/workflows/flutter.yml)

GitHub Actions workflow automatically:
- Runs all tests on every PR and push
- Blocks merges if compliance tests fail
- Prevents accidental introduction of banned translations

### How to Add a New Translation

**ONLY if it's public domain or open-source:**

1. **Verify License**: Confirm the translation is truly public domain or has an open-source license (MIT, CC0, etc.)
2. **Add to Registry**: Edit [`lib/core/bible_translation_registry.dart`](../lib/core/bible_translation_registry.dart):
   ```dart
   BibleTranslation(
     id: 'NEW',
     name: 'New Translation Name',
     licenseType: LicenseType.publicDomain, // or LicenseType.openLicense
     licenseName: 'Public Domain (copyright expired)',
     year: 1900,
     url: 'https://source.url',
     notes: 'Brief description',
   ),
   ```
3. **Run Tests**: `flutter test test/core/bible_translation_compliance_test.dart`
4. **Document**: Update [`docs/BIBLE_TRANSLATION_COMPLIANCE.md`](BIBLE_TRANSLATION_COMPLIANCE.md) and this file

### Violation Response

**If a compliance violation is detected:**

**Build Time**:
- Tests FAIL immediately
- Build cannot complete
- PR cannot be merged (CI blocks it)

**Runtime**:
- Violation logged to console with ⚠️ COMPLIANCE VIOLATION message
- Translation automatically reset to WEB (default)
- App continues functioning with valid translation
- User sees no broken functionality (fail-safe behavior)

### Testing Compliance

```bash
# Run all compliance tests
flutter test test/core/bible_translation_compliance_test.dart test/core/repo_wide_compliance_scan_test.dart

# Run all tests (includes compliance)
flutter test

# Static analysis
flutter analyze
```

All three commands MUST pass for the build to succeed.

### Maintenance Rules

**When modifying code that touches Bible translations:**

1. **NEVER** bypass the registry or runtime guards
2. **ALWAYS** validate translation IDs before use
3. **RUN** compliance tests before committing
4. **DO NOT** weaken or remove compliance tests
5. **DO NOT** add exclusions to the compliance scan without documented justification

**If you see a compliance violation:**
1. DO NOT ignore it
2. DO NOT add the translation to the allowlist without verifying its license
3. Fix the code to use an allowed translation
4. Verify tests pass

### Resources

- [World English Bible](https://worldenglish.bible)
- [King James Version](https://www.kingjamesbibleonline.org)
- [American Standard Version](https://www.biblegateway.com/versions/American-Standard-Version-ASV-Bible)
- [U.S. Copyright Duration Info](https://www.copyright.gov/help/faq/faq-duration.html)
- [Full Compliance Documentation](BIBLE_TRANSLATION_COMPLIANCE.md)

---

## 🔒 Data Capacity Invariants (NON-NEGOTIABLE)

**Invariant**: User data collections must enforce strict capacity limits to prevent unbounded storage growth and maintain consistent UX.

### Why This Exists

- **Performance**: Unbounded lists degrade app performance (memory, storage, rendering)
- **UX Consistency**: Users should see predictable, manageable data collections
- **Storage Management**: Mobile devices have limited storage; we must be good citizens
- **FIFO Ordering**: Older entries naturally age out as new ones arrive

### Capacity Limits

The following hard caps are enforced:

| Collection | Max Entries | Enforcement | Ordering |
|------------|-------------|-------------|----------|
| **History** | 20 | Storage + Migration | FIFO (newest first) |
| **Favorites** | 100 | Storage + Migration | User-managed |
| **Pending Shares** | 50 | Storage + Migration | FIFO (oldest first) |

### Enforcement Mechanisms

This invariant is enforced at **three layers**:

#### 1. Storage Layer (Write-Time Enforcement)
**File**: [`lib/services/storage_service.dart`](../lib/services/storage_service.dart)

All write operations enforce caps:
```dart
// History: trim to 20 on write
Future<void> addToHistory(HistoryEntry entry) async {
  final history = await getHistory();
  history.insert(0, entry);
  final trimmed = history.take(20).toList(); // Enforce cap
  await _prefs.setString(_keyHistory, jsonEncode(trimmed));
}

// getHistory(): pure read with cap
Future<List<HistoryEntry>> getHistory() async {
  // ...
  return history.take(20).toList(); // Always capped
}
```

#### 2. Migration Layer (Startup Healing)
**File**: [`lib/services/storage_service.dart`](../lib/services/storage_service.dart)

One-time migration heals oversized legacy data:
```dart
Future<Map<String, int>> validateAndHealInvariants() async {
  // Heals History (20), Favorites (100), Pending Shares (50)
  // Called at app startup via service_providers.dart
  // Trims excess entries and returns report
}
```

Called from: [`lib/providers/service_providers.dart`](../lib/providers/service_providers.dart)

#### 3. UI Layer (Contract Enforcement)
**File**: [`lib/features/history/history_screen.dart`](../lib/features/history/history_screen.dart)

Fail-fast assertions detect violations:
```dart
assert(
  history.length <= 20,
  'History violated cap: ${history.length} items (expected ≤20). '
  'This indicates AppState.history is not properly capped by StorageService.',
);
```

These assertions:
- Fail immediately if cap is violated
- Provide clear error messages pointing to root cause
- Strip out in release builds (zero overhead)
- Serve as contract validation between layers

#### 4. Test Layer (Verification)
**File**: [`test/services/storage_service_caps_test.dart`](../test/services/storage_service_caps_test.dart)

Comprehensive tests verify:
- Write operations enforce caps
- Read operations return capped data
- Migration heals oversized legacy data
- FIFO ordering is maintained

**Critical Tests** (MUST PASS):
- `should enforce 20-entry cap on write (FIFO)`
- `should return at most 20 entries from storage`
- `should heal History cap violation (>20 entries)` (migration test)
- `should heal Favorites cap violation (>100 entries)` (migration test)
- `should enforce 50-share cap (FIFO)` (pending shares)

### Behavior Specifications

#### History (20 entries, FIFO)
- **Newest first**: Most recent entry at index 0
- **Auto-trim**: Oldest entries removed when cap exceeded
- **Read**: Pure function, always returns ≤20 items
- **Write**: Enforces cap immediately
- **Display**: UI shows exactly what storage provides

#### Favorites (100 entries)
- **User-managed**: Users can manually add/remove
- **No auto-trim on read**: Only enforced on write and migration
- **Ordering**: Preserved as added (not FIFO)

#### Pending Shares (50 entries, FIFO)
- **Oldest first**: Retry logic processes oldest shares first
- **Auto-trim**: Oldest entries removed when cap exceeded
- **Transport-dependent**: Only populated if transport layer enabled

### Testing Caps

```bash
# Run capacity enforcement tests
flutter test test/services/storage_service_caps_test.dart

# Run all tests (includes cap tests)
flutter test

# Verify in running app (debug mode)
# Check console for: "📜 History Screen: X items"
# Assert will fire if X > 20
flutter run --debug
```

### Maintenance Rules

**When modifying data storage code:**

1. **NEVER** bypass storage layer caps
2. **ALWAYS** use `getHistory()`, `getFavorites()`, etc. (don't read raw prefs)
3. **RUN** cap tests before committing
4. **DO NOT** weaken or remove cap enforcement
5. **DO NOT** add redundant `.take()` caps at UI layer (let assertions detect bugs)

**If a cap assertion fires:**
1. DO NOT add redundant UI-layer caps to mask the bug
2. Investigate WHY AppState has uncapped data
3. Fix the root cause (usually storage/migration layer)
4. Verify tests pass and assertion no longer fires

### Resources

- [Storage Service Implementation](../lib/services/storage_service.dart)
- [Migration Logic](../lib/services/storage_service.dart#L157-L197)
- [History Screen Contract](../lib/features/history/history_screen.dart#L121-L137)
- [Capacity Tests](../test/services/storage_service_caps_test.dart)

---

## 🔒 Kid Safety Contract Invariant (NON-NEGOTIABLE)

**Invariant**: When `UserPreferences.kidFriendlyOnly` is `true`, the app MUST NEVER serve, display, or recommend non-kid-friendly parables. All parables returned MUST have `kidFriendly = true`.

### Why This Exists

**Protecting children is paramount.**

- Children are vulnerable and must be shielded from inappropriate content
- Parents trust the "Kid Friendly" toggle to protect their children
- Violating this trust endangers children and destroys user confidence
- Legal liability if inappropriate content reaches children due to app malfunction

### The Contract

When a user enables "Kid Friendly" mode (Settings → Kid Friendly toggle), the app enters a **strict safety contract**:

1. **UserPreferences MUST store kidFriendlyOnly correctly**
   - Settings toggle must update `UserPreferences.kidFriendlyOnly`
   - Value must persist across app restarts
   - Value must survive serialization (toJson/fromJson)
   - Value must be preserved by `copyWith()`

2. **ParableService MUST enforce kid-friendly filtering**
   - `getEligibleParables()` must filter out `kidFriendly = false` parables
   - `selectParable()` must only return kid-friendly parables (or null)
   - Runtime assertion must verify no non-kid-friendly parables leak through
   - Debug logs must clearly indicate when kid mode is active

3. **All layers must respect kidFriendlyOnly**
   - Storage layer: Save/load correctly
   - State layer: Update UserPreferences properly
   - Service layer: Filter parables strictly
   - UI layer: Reflect correct toggle state

### Enforcement Mechanisms

This invariant is enforced at **four layers**:

#### 1. Settings UI → UserPreferences Sync

**File**: [`lib/features/settings/settings_screen.dart`](../lib/features/settings/settings_screen.dart)

```dart
Future<void> _setKidFriendlyOnly(bool on) async {
  setState(() => _kidFriendlyOnly = on);
  final appState = ref.read(appStateProvider.notifier);
  await appState.updateKidFriendlyOnly(on);  // Updates UserPreferences
}
```

**Contract**: Settings toggle MUST call `appStateNotifier.updateKidFriendlyOnly()` to update UserPreferences. Never save to separate SharedPreferences key.

#### 2. AppStateNotifier Update Method

**File**: [`lib/providers/app_state_notifier.dart`](../lib/providers/app_state_notifier.dart)

```dart
Future<void> updateKidFriendlyOnly(bool kidFriendlyOnly) async {
  final prefs = state.requireValue.userPreferences.copyWith(
    kidFriendlyOnly: kidFriendlyOnly,
  );
  await updateUserPreferences(prefs);
}
```

**Contract**: AppStateNotifier MUST provide `updateKidFriendlyOnly()` method that updates UserPreferences and persists to storage.

#### 3. ParableService Runtime Filtering

**File**: [`lib/services/parable_service.dart`](../lib/services/parable_service.dart)

```dart
// Match kid-friendly filter (CRITICAL FOR CHILD SAFETY)
if (userPrefs.kidFriendlyOnly && !p.kidFriendly) {
  debugPrint('    ✗ Not kid-friendly (BLOCKED for child safety)');
  return false;
}

// CRITICAL SAFETY CHECK: Verify no non-kid-friendly parables leaked through
if (userPrefs.kidFriendlyOnly) {
  final nonKidFriendlyCount = eligible.where((p) => !p.kidFriendly).length;
  if (nonKidFriendlyCount > 0) {
    debugPrint('🚨🚨🚨 CRITICAL KID SAFETY VIOLATION 🚨🚨🚨');
    assert(false, '🚨 KID SAFETY VIOLATION');  // Fail in debug
    return eligible.where((p) => p.kidFriendly).toList();  // Emergency filter in production
  }
}
```

**Contract**: ParableService MUST:
- Filter out `kidFriendly = false` parables when `userPrefs.kidFriendlyOnly = true`
- Run post-filter safety check to catch bugs
- Throw assertion in debug mode if violation detected
- Emergency-filter in production as last resort

#### 4. Build-Failing Tests

**File**: [`test/critical/kid_friendly_toggle_safety_test.dart`](../test/critical/kid_friendly_toggle_safety_test.dart)

**Critical Tests** (MUST PASS):
- `CRITICAL: Kid mode MUST filter out non-kid-friendly parables`
- `CRITICAL: selectParable() MUST enforce kid-friendly filter`
- `CRITICAL: UserPreferences.copyWith preserves kidFriendlyOnly`
- `CRITICAL: UserPreferences.fromJson/toJson preserves kidFriendlyOnly`
- `CRITICAL: Adult mode MUST allow non-kid-friendly parables`

If ANY test fails, the build FAILS and children are at risk.

### Violation Response

**If kid safety violation is detected:**

**Development Time**:
- Assertion fires immediately in debug mode
- Developer sees: `🚨 KID SAFETY VIOLATION: Non-kid-friendly parables returned when kidFriendlyOnly=true`
- App crashes to force immediate fix
- Test suite fails with detailed error messages

**Production (Emergency Fallback)**:
- Debug logs show: `🚨🚨🚨 CRITICAL KID SAFETY VIOLATION 🚨🚨🚨`
- Emergency filter removes non-kid-friendly parables
- App continues functioning (degraded but safe)
- Violation logged for post-release investigation

### Testing Kid Safety

```bash
# Run all kid safety tests
flutter test test/critical/kid_friendly_toggle_safety_test.dart

# Run all tests (includes kid safety)
flutter test

# Check debug logs when kid mode is on
# Look for: "🔒 KID-FRIENDLY MODE ENABLED"
# Look for: "✅ Kid safety check passed"
flutter run --debug
```

All tests MUST pass before release.

### Maintenance Rules

**When modifying code that touches kid-friendly filtering:**

1. **NEVER** bypass UserPreferences for kid mode setting
2. **ALWAYS** update UserPreferences when toggle changes
3. **ALWAYS** filter by `userPrefs.kidFriendlyOnly` in ParableService
4. **RUN** kid safety tests before committing
5. **DO NOT** weaken or remove safety assertions
6. **DO NOT** disable kid safety tests

**If a kid safety test fails:**
1. DO NOT disable the test
2. DO NOT weaken the assertion
3. Fix the root cause immediately
4. Verify all kid safety tests pass
5. Test manually with kid mode ON/OFF

### Resources

- [ParableService Implementation](../lib/services/parable_service.dart)
- [Settings Screen Toggle](../lib/features/settings/settings_screen.dart)
- [AppStateNotifier](../lib/providers/app_state_notifier.dart)
- [UserPreferences Model](../lib/models/user_preferences.dart)
- [Kid Safety Tests](../test/critical/kid_friendly_toggle_safety_test.dart)

---

## 🔒 Kid Safe Generation Invariant (NON-NEGOTIABLE)

**Invariant**: All kid-mode story generations MUST pass the Kid Safe Validator before being saved to the kid library. Forbidden words MUST never appear in kid-safe output. Maximum regeneration attempts = 3. Unsafe stories MUST NOT be saved to kid library.

### Why This Exists

**Safety for children is paramount.**

- Children ages 5-9 are the audience
- Parents may not be actively monitoring
- A startling word or scary image could upset a child
- Biblical hallucinations (e.g., "Jonah was crowned king") confuse children about scripture
- Parents trust the "Kid Friendly" mode to be truly safe for unattended listening

### The Contract

When generating stories for kid mode, the system enters a **strict safety contract**:

1. **Contract Injection MUST occur**
   - Every generation prompt MUST include the Kid Story Contract
   - Contract file: `docs/prompts/kid_bedtime_contract.txt`
   - No exceptions or bypasses permitted

2. **Forbidden Vocabulary MUST be blocked**
   - Source of truth: `server/kid_bedtime_forbidden.txt`
   - Post-generation scan MUST detect ANY forbidden word
   - Case-insensitive matching with word boundaries
   - Single violation = story rejected

3. **Structure Requirements MUST be met**
   - Minimum 3 distinct sections
   - Minimum 200 words
   - Average sentence length ≤15 words

4. **Regeneration MUST be bounded**
   - Maximum attempts: **3** (`kMaxRegenAttempts`)
   - Repair instruction MUST list all violations
   - Each retry MUST include repair instruction

5. **Unsafe stories MUST NOT enter kid library**
   - If validation fails after max attempts:
     - Mark as `kidSafe: false`
     - Log all violations
     - DO NOT save to kid library
     - DO NOT serve to children

### Enforcement Mechanisms

This invariant is enforced at **four layers**:

#### 1. Contract Injection (Generation Time)

**Files**:
- [`docs/prompts/kid_bedtime_contract.txt`](prompts/kid_bedtime_contract.txt) - Kid Story Contract
- [`server/kid_bedtime_harness.sh`](../server/kid_bedtime_harness.sh) - Injects contract

The harness script MUST inject the full contract into every kid-mode generation prompt.

#### 2. Post-Generation Validation

**Files**:
- [`server/kid_bedtime_validator.sh`](../server/kid_bedtime_validator.sh) - Bash validator
- [`lib/safety/kid_bedtime_validator.dart`](../lib/safety/kid_bedtime_validator.dart) - Dart validator
- [`server/kid_bedtime_forbidden.txt`](../server/kid_bedtime_forbidden.txt) - Forbidden vocabulary

Validators check:
- Forbidden words (160+ patterns)
- Story structure (sections, length)
- Sentence length averages

#### 3. Bounded Regeneration (Harness)

**File**: [`server/kid_bedtime_harness.sh`](../server/kid_bedtime_harness.sh)

```bash
MAX_ATTEMPTS=3  # Configurable, matches kMaxRegenAttempts

while [[ $ATTEMPT -le $MAX_ATTEMPTS ]]; do
    # Generate story
    # Validate story
    # If failed, build repair instruction and retry
done

# If still failing, mark as unsafe
echo '{"kidSafe": false, ...}' > "${OUTPUT_FILE}.meta.json"
```

#### 4. Build-Failing Tests

**Files**:
- [`test/kid_bedtime_safe/validator_forbidden_words_test.dart`](../test/kid_bedtime_safe/validator_forbidden_words_test.dart)
- [`test/kid_bedtime_safe/validator_structure_test.dart`](../test/kid_bedtime_safe/validator_structure_test.dart)
- [`test/kid_bedtime_safe/regeneration_on_failure_test.dart`](../test/kid_bedtime_safe/regeneration_on_failure_test.dart)

**Critical Tests** (MUST PASS):
- `fails when story contains "roar" or variants`
- `fails when story contains predator imagery (jaws, teeth, claws)`
- `fails when story contains crown/throne power rewards`
- `passes for a known-good kid-safe sample`
- `triggers regeneration when forbidden words detected`
- `respects max attempts limit and marks as unsafe`

### Forbidden Vocabulary Categories

The forbidden list includes (non-exhaustive):

| Category | Examples |
|----------|----------|
| Violence/Peril | roar, jaws, teeth, claws, devour, attack, battle, sword |
| Death/Dying | death, dead, died, perish, corpse |
| Fear/Terror | terror, horror, scream, nightmare, frightened |
| Punishment | punish, vengeance, wrath, doom, condemned |
| Power Rewards | crown, throne, king, ruler, reign, conquer |
| Predator Imagery | beast, monster, hunt, chase, flee, trap |
| Biblical Inaccuracies | "became king", "was crowned", "given the throne" |

Full list: [`server/kid_bedtime_forbidden.txt`](../server/kid_bedtime_forbidden.txt)

### Violation Response

**Generation Time**:
- Validator returns detailed violation list
- Repair instruction built from violations
- Regeneration attempted (up to max attempts)
- If all attempts fail, story marked unsafe

**Runtime (If Unsafe Story Escapes)**:
- KidSafetyService runtime scanner catches violations
- Story blocked from playback
- Error logged for investigation
- User sees "Content unavailable" message

### Testing Kid Safety

```bash
# Run all kid safety tests
flutter test test/kid_bedtime_safe/

# Test the validator script directly
./server/kid_bedtime_validator.sh assets/stories/some_story.txt

# Test the harness (requires Ollama running)
./server/kid_bedtime_harness.sh prompt.txt output.txt --max-attempts 3

# Run all tests (includes kid safety)
flutter test
```

### Maintenance Rules

**When modifying kid-mode generation:**

1. **NEVER** bypass the Kid Story Contract injection
2. **NEVER** skip post-generation validation
3. **NEVER** save stories with `kidSafe: false` to kid library
4. **ALWAYS** include repair instruction on regeneration
5. **ALWAYS** respect max attempts limit
6. **RUN** kid safety tests before committing
7. **DO NOT** weaken forbidden vocabulary list
8. **DO NOT** disable or weaken safety tests

**If a kid safety test fails:**
1. DO NOT disable the test
2. DO NOT weaken the validator
3. Fix the root cause (missing validation, weak pattern, etc.)
4. Verify all kid safety tests pass
5. Test with sample forbidden content manually

### Resources

- [Kid Story Contract](prompts/kid_bedtime_contract.txt)
- [Forbidden Vocabulary](../server/kid_bedtime_forbidden.txt)
- [Bash Validator](../server/kid_bedtime_validator.sh)
- [Dart Validator](../lib/safety/kid_bedtime_validator.dart)
- [Harness Script](../server/kid_bedtime_harness.sh)
- [Kid Safety Tests](../test/kid_bedtime_safe/)
- [SPEC.md Kid Safe Section](SPEC.md#kid-safe-harness)

---

## 🔒 Reflection Language Safety Invariant (NON-NEGOTIABLE)

**Invariant**: Post-story reflections MUST be descriptive, not prescriptive. Reflections MUST NOT give advice, make diagnostic claims, or promise outcomes. This is reflection, not therapy.

### Why This Exists

**User trust and safety are paramount.**

- Users may be in vulnerable emotional states after listening to stories about difficult topics
- Prescriptive language ("you should...") overreaches the app's role
- Diagnostic language ("you are feeling...") makes unqualified claims
- Therapeutic promises ("this will help you...") create false expectations
- The app is a storytelling companion, not a counselor or therapist

### The Contract

Post-story reflections MUST:
1. Use descriptive language only
2. Describe patterns and themes, not prescribe actions
3. Use phrases like: "often looks like", "can reflect", "stories like this show..."

Post-story reflections MUST NOT:
1. Give advice ("you should", "try to", "consider doing")
2. Make diagnostic claims ("you are feeling", "this means you")
3. Promise outcomes ("this will help", "you'll feel better")
4. Use therapeutic language ("healing", "therapy", "treatment", "cope")
5. Probe emotions ("how did that make you feel", "what emotions came up")

### Kid Mode Additional Constraints

When `kidFriendlyOnly` is enabled, reflections MUST also:
1. Use short, literal language (1-2 sentences max)
2. Avoid abstract concepts
3. Use age-appropriate vocabulary (5-9 year olds)
4. Not probe emotions or encourage self-analysis

### Enforcement Mechanisms

This invariant is enforced at **three layers**:

#### 1. Template-Based Reflection Content
**File**: [`lib/services/reflection_service.dart`](../lib/services/reflection_service.dart)

All reflections are pre-written templates that have been reviewed for compliance. No free-form AI generation at playback time.

#### 2. Build-Failing Tests
**File**: [`test/services/reflection_safety_test.dart`](../test/services/reflection_safety_test.dart)

Tests verify:
- No banned phrases appear in any reflection template
- Kid mode reflections meet length/complexity requirements
- All templates pass language compliance scan

#### 3. Code Review
All reflection template additions require review against this invariant.

### Banned Phrases (Non-Exhaustive)

The following phrases/patterns are BANNED from reflections:

| Category | Banned Examples |
|----------|-----------------|
| Advice | "you should", "try to", "consider", "it helps to" |
| Diagnosis | "you are feeling", "you seem", "this suggests you" |
| Promises | "will help you", "you'll feel", "this can heal" |
| Therapy | "cope", "healing", "therapy", "treatment", "process your" |
| Probing | "how did that make you feel", "what came up for you" |

### Testing Reflection Safety

```bash
# Run reflection safety tests
flutter test test/services/reflection_safety_test.dart

# Run all tests (includes reflection safety)
flutter test
```

### Maintenance Rules

**When modifying reflection templates:**

1. **NEVER** use banned phrases
2. **ALWAYS** use descriptive, not prescriptive language
3. **RUN** reflection safety tests before committing
4. **DO NOT** add free-form AI generation at playback time
5. **REVIEW** kid mode templates for age-appropriateness

**If a reflection safety test fails:**
1. DO NOT disable the test
2. Rewrite the reflection template to be descriptive only
3. Remove any advice, diagnosis, or therapeutic language
4. Verify all tests pass

### Resources

- [SPEC.md Reflection Section](SPEC.md#post-story-everyday-life-reflection)
- [Reflection Service](../lib/services/reflection_service.dart)
- [Reflection Safety Tests](../test/services/reflection_safety_test.dart)

---

## 🔒 Logging Privacy Invariant (NON-NEGOTIABLE)

**Invariant**: The logging system MUST NEVER log raw user-entered text, personally identifiable information (PII), or any data that could identify a user. All logs must be structured key/value pairs. Logging failures must never crash the app.

### Why This Exists

**User privacy and trust are paramount.**

- Users share vulnerable emotional states when using PAL's Parables
- Raw mood input text could reveal sensitive personal information
- PII exposure creates legal liability (GDPR, CCPA, etc.)
- Logging should aid debugging without compromising privacy
- App stability must never be sacrificed for observability

### The Contract

The logging system enforces these rules:

1. **PRIVACY: Never log user text or PII**
   - Blocked keys: `userText`, `prompt`, `transcript`, `message`, `email`, `phone`, `name`, etc.
   - Blocked patterns: email addresses, phone numbers
   - Values containing PII are redacted automatically

2. **STRUCTURED: All logs are key/value JSON**
   - No free-form paragraph logging
   - Required fields: `event`, `level`, `ts`
   - Machine-parseable format only

3. **LOW NOISE: Only log decision points**
   - Log: story selection, audio lifecycle, errors, mode changes
   - Don't log: every UI interaction, routine operations

4. **SAFE FAIL: Never crash the app**
   - All logging wrapped in try/catch
   - Failed logs are silently dropped
   - Malformed input is blocked, not thrown

5. **BUILD SAFE: Tests enforce constraints**
   - Tests verify blocked keys are rejected
   - Tests verify PII patterns are detected
   - Tests verify logging never throws

### Enforcement Mechanisms

This invariant is enforced at **three layers**:

#### 1. Code-Level Blocking
**File**: [`lib/core/app_logger.dart`](../lib/core/app_logger.dart)

```dart
// Blocked keys that are NEVER logged
static const Set<String> _blockedKeys = {
  'userText', 'user_text', 'message', 'prompt', 'transcript',
  'email', 'phone', 'name', 'password', 'token', 'secret', ...
};

// PII pattern detection
static final RegExp _emailPattern = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
static final RegExp _phonePattern = RegExp(r'(?:\+?1[-.\s]?)?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}');
```

If a blocked key or PII value is detected, the log is rejected and a warning is emitted instead.

#### 2. Safe-Fail Wrapper
All logging operations are wrapped in try/catch. Even if JSON encoding fails, the app continues normally.

#### 3. Build-Failing Tests
**File**: [`test/core/app_logger_test.dart`](../test/core/app_logger_test.dart)

**Critical Tests** (MUST PASS):
- `blocks raw text fields (userText, message, prompt, transcript)`
- `blocks values that look like emails`
- `blocks values that look like phone numbers`
- `never throws even with malformed input`
- `emits structured JSON format`

### Testing Logging Privacy

```bash
# Run logging tests
flutter test test/core/app_logger_test.dart

# Run all tests (includes logging)
flutter test
```

### Maintenance Rules

**When modifying logging code:**

1. **NEVER** add user text fields to logged data
2. **NEVER** remove keys from the blocked list
3. **NEVER** bypass the sanitization layer
4. **ALWAYS** use `logEvent()` or `logError()` — never direct print with user data
5. **RUN** logging tests before committing
6. **DO NOT** weaken or remove privacy tests

**If a logging privacy test fails:**
1. DO NOT disable the test
2. Fix the code to not log the blocked data
3. Verify all tests pass
4. Consider if additional blocked keys are needed

### Resources

- [SPEC.md Observability Section](SPEC.md#observability--logging-v1)
- [AppLogger Implementation](../lib/core/app_logger.dart)
- [Logging Tests](../test/core/app_logger_test.dart)

---

## 🔒 Golden Prompt Single-Shot Generation Invariant (NON-NEGOTIABLE)

**Invariant**: When `--golden-prompt` is enabled for adult traditional SHORT bucket generation:

1. **No continuation prompts may be used.** Each attempt is a fresh, complete generation.
2. **Attempt 1 MUST require exactly 10 paragraphs, 5 sentences each.**
3. **If attempt 1 fails min_words (< 250), attempt 2 MUST regenerate fresh requiring exactly 12 paragraphs, 5 sentences each.**
4. **If attempt 2 fails min_words, output MUST follow existing quarantine behavior.**
5. **Standard mode behavior MUST remain unchanged.**

### Why This Exists

Gemma-7B produces story repetition/duplication when given continuation prompts (e.g., "continue the story from here..."). Structure-based length control (paragraph × sentence counts) reliably produces target word counts without degrading narrative quality.

### Violation Response

- **CORRECT**: Attempt 1 produces 200 words → Attempt 2 regenerates fresh with 12 paragraphs
- **VIOLATION**: Attempt 1 produces 200 words → Attempt 2 appends "continue the story..."

### Resources

- [SPEC.md Golden Prompt Section](SPEC.md#golden-prompt-mode-adult-traditional-short-bucket-generation)
- [Generation Script](../server/generate_adult_traditional_stories.sh)
- [Golden Prompt Template](../server/prompts/golden_trad_adult_short.prompt.txt)
- [Legacy prompts](../server/prompts/legacy/)

---

## 🔒 Christian General Only Invariant (NON-NEGOTIABLE)

**Invariant**: Bible PAL MUST serve all users with a unified Christian General experience. No denomination-specific content, filtering, or UI selection is permitted. The codebase MUST NOT contain any faith tradition selection logic, denomination branching, or tradition-based filtering.

### Why This Exists

**Unity in Christ, not division by denomination.**

- Bible PAL is for ALL Christians, regardless of denominational background
- Denomination-specific content creates barriers and exclusion
- Tradition-based filtering fragments the content library unnecessarily
- Simplified UX: users don't need to know or declare their denomination
- Reduced complexity: single content path serves all users equally
- This is a **permanent design decision**, not a v1 deferral

### The Contract

1. **No tradition/denomination fields in models**
   - No `faithTradition` field in UserPreferences, Parable, Favorite, or HistoryEntry
   - No tradition-based filtering in ParableService
   - No tradition selection in onboarding or settings

2. **No tradition/denomination UI**
   - No tradition selector screens
   - No tradition options in settings
   - No tradition display in story metadata

3. **No tradition/denomination logic**
   - No branching based on user denomination
   - No content filtering by tradition
   - No analytics events for tradition changes

4. **Codebase cleanliness**
   - Source files MUST NOT contain tradition/denomination selection code
   - Manifest files MUST NOT contain `faithTradition` fields
   - Test files MUST NOT test tradition filtering (except negative tests verifying absence)

### Enforcement Mechanisms

This invariant is enforced at **three layers**:

#### 1. Repo-Wide Scan Tests
**File**: [`test/critical/christian_general_only_test.dart`](../test/critical/christian_general_only_test.dart)

Tests scan the entire codebase for forbidden patterns:
- `faithTradition` field definitions
- `tradition` selection/filtering code
- `denomination` references in code
- Tradition UI components

**Critical Tests** (MUST PASS):
- `CRITICAL: No faithTradition field in lib/ models`
- `CRITICAL: No tradition filtering in ParableService`
- `CRITICAL: No tradition selector UI`
- `CRITICAL: No faithTradition in manifest.json`

#### 2. Code Review
All PRs that touch models, services, or UI require review against this invariant.

#### 3. CI Enforcement
GitHub Actions runs the scan tests on every PR. Any tradition-related code causes build failure.

### Violation Response

**Build Time**:
- Tests FAIL immediately
- Build cannot complete
- PR cannot be merged (CI blocks it)

**If violation detected**:
1. Remove the tradition-related code
2. Run `flutter test test/critical/christian_general_only_test.dart`
3. Verify all tests pass

### Allowed Terminology

The following terms ARE allowed when used appropriately:
- "Christian" - when referring to the unified Christian General perspective
- "faith" - when not paired with "tradition" for selection purposes
- "tradition" - when referring to Biblical traditions (e.g., Jewish traditions mentioned in scripture)

### Banned Patterns

The following patterns MUST NOT appear in source code:
- `faithTradition` as a field or parameter
- `updateFaithTradition()` method
- `traditionSelector` or similar UI components
- Filtering by `p.faithTradition`
- `denomination` as user-selectable option

### Testing Christian General Only

```bash
# Run Christian General Only enforcement tests
flutter test test/critical/christian_general_only_test.dart

# Run all tests (includes this invariant)
flutter test
```

### Resources

- [SPEC.md Christian General Only Section](SPEC.md#onboarding)
- [Repo-Wide Scan Tests](../test/critical/christian_general_only_test.dart)

---

## 🔒 Story Mode Non-Blur Invariant (NON-NEGOTIABLE)

**Invariant**: Traditional and Creative storytelling modes MUST NEVER blur. Each mode has distinct authority, validation rules, and content requirements. No story may exhibit characteristics of both modes.

### Why This Exists

**Content integrity and user trust are paramount.**

- Traditional mode users expect faithful Bible retellings with scriptural authority
- Creative mode users expect original stories without false scriptural claims
- Blurring modes confuses users about the source and authority of content
- Mixed-mode content undermines the distinct value proposition of each mode
- Clear separation enables proper validation and quality gates

### The Contract

Story Mode Contracts v2 defines two orthogonal axes:

**Axis 1 — Story Mode (Authority)**: `storytellingMode: traditional | creative`
**Axis 2 — Language Style (Presentation)**: `languageStyle: WEB | KJV`

#### Traditional Mode Requirements

1. **Faithful Bible Retellings Only**
   - Must map to specific Bible passages
   - Preserve characters, events, outcomes, meaning
   - Third-person biblical narrative posture

2. **`bibleSourceRef` REQUIRED**
   - Field must contain valid scripture reference (e.g., "Luke 15:3-7")
   - Stories without `bibleSourceRef` are EXCLUDED from serving pool
   - Do NOT guess or invent references — exclude until manually provided

3. **Forbidden Patterns**
   - MoDC companionship voice ("I sit with you", "I am here with you")
   - Invented inner monologue not implied by scripture
   - Changed outcomes or reordered events
   - First/second-person spiritual guide posture
   - Devotional commentary within narrative
   - **Reflective narrator endings** in story body text:
     - Listener-directed comfort language ("rest now", "enough for today")
     - Implied moral summary not in scripture ("it was enough", "at last, peace")
     - Interpretive phrasing ("he felt", "she seemed", "rest at last") unless directly observable in scripture
     - Poetic or emotionally summarizing closings that shift from retelling to reflection
   - Reflective/poetic closing language belongs ONLY in reflection content (separate asset) or Creative mode

#### Creative Mode Requirements

1. **Original Stories Only**
   - NOT retellings of specific Bible stories
   - Biblical themes/values allowed, not specific narratives
   - MoDC rules apply (non-directive, optional, interruptible)

2. **`bibleSourceRef` FORBIDDEN**
   - Field must be absent or empty
   - Stories with `bibleSourceRef` fail validation

3. **Forbidden Patterns**
   - Scripture authority claims ("as the Bible says", "scripture tells us")
   - Teaching doctrine as fact
   - Commands/prescriptions ("you should", "you must")
   - Dependency language ("you need this", "come back tomorrow")
   - Retelling specific Bible stories (even loosely)

#### Creative + KJV Extra Restrictions

When `languageStyle=KJV` in Creative mode:
- Treat as poetic diction ONLY
- FORBIDDEN: "Thus saith", verse numbering, "this is the Word", chapter/verse recitations

### Enforcement Mechanisms

This invariant is enforced at **four layers**:

#### 1. Manifest Validation
**File**: [`test/critical/story_mode_contracts_test.dart`](../test/critical/story_mode_contracts_test.dart)

- All Traditional stories must have `bibleSourceRef`
- All Creative stories must NOT have `bibleSourceRef`
- Tests scan manifest and fail build on violations

#### 2. Service Layer Filtering
**File**: [`lib/services/parable_service.dart`](../lib/services/parable_service.dart)

```dart
// Traditional stories without bibleSourceRef are EXCLUDED
if (p.storytellingMode == 'traditional' &&
    (p.bibleSourceRef == null || p.bibleSourceRef!.isEmpty)) {
  // Log exclusion and skip this story
  return false;
}
```

#### 3. Story Mode Validator
**File**: [`lib/safety/story_mode_validator.dart`](../lib/safety/story_mode_validator.dart)

- `validateTraditional()`: Checks for required `bibleSourceRef`, forbidden MoDC patterns
- `validateCreative()`: Checks for forbidden `bibleSourceRef`, scripture authority claims
- Returns detailed violation list for generation repair

#### 4. Build-Failing Tests
**File**: [`test/critical/story_mode_contracts_test.dart`](../test/critical/story_mode_contracts_test.dart)

**Critical Tests** (MUST PASS):
- `CRITICAL: Traditional stories MUST have bibleSourceRef`
- `CRITICAL: Creative stories MUST NOT have bibleSourceRef`
- `CRITICAL: Mode filtering never cross-contaminates`
- `CRITICAL: No silent cross-mode fallback`
- `CRITICAL: Default storytellingMode is traditional`

#### 5. Story Asset Consistency
**File**: [`test/core/story_asset_consistency_test.dart`](../test/core/story_asset_consistency_test.dart)

Validates structural integrity of committed story assets:
- Every story directory has meta JSON with universal required fields (`storyId`, `mode`, `mood`, `languageStyle`, `voiceKey`, `files`, `lengths`)
- Story text files referenced in `meta.files` exist and are non-empty
- `meta.mode` matches directory lane (`traditional/` or `creative/`)
- `meta.lengths` entries have corresponding `meta.files` entries
- Traditional stories have `scriptureAnchor`
- `meta.storyId` matches directory name

### Violation Response

**Build Time**:
- Tests FAIL immediately
- Build cannot complete
- PR cannot be merged (CI blocks it)

**Runtime**:
- Traditional stories without `bibleSourceRef` are excluded from pool
- Creative stories with `bibleSourceRef` are excluded from pool
- Violation logged with detailed error message
- App continues with reduced pool (fail-safe)

### Testing Story Mode Contracts

```bash
# Run story mode contract tests
flutter test test/critical/story_mode_contracts_test.dart

# Run story asset consistency tests
flutter test test/core/story_asset_consistency_test.dart

# Run all tests (includes both)
flutter test
```

### Maintenance Rules

**When modifying story-related code:**

1. **NEVER** blur Traditional and Creative modes
2. **NEVER** guess or invent `bibleSourceRef` values
3. **NEVER** serve Traditional stories without `bibleSourceRef`
4. **NEVER** allow Creative stories with `bibleSourceRef`
5. **ALWAYS** validate mode-specific rules before serving
6. **RUN** story mode tests before committing
7. **DO NOT** weaken or remove mode validation tests

**If a story mode test fails:**
1. DO NOT disable the test
2. DO NOT add cross-mode content to pass
3. Fix the root cause (missing/extra bibleSourceRef, wrong mode assignment)
4. Verify all tests pass

### Resources

- [SPEC.md Story Mode Contracts v2](SPEC.md#story-mode-contracts-v2-locked)
- [Story Mode Validator](../lib/safety/story_mode_validator.dart)
- [Story Mode Tests](../test/critical/story_mode_contracts_test.dart)
- [Parable Service](../lib/services/parable_service.dart)

---

## 🔒 Language Style Presentation-Only Invariant (NON-NEGOTIABLE)

**Invariant**: The `languageStyle` field (WEB/KJV) controls ONLY presentation diction. It MUST NEVER change story mode authority, validation rules, or `bibleSourceRef` requirements. Language style is orthogonal to story mode.

### Why This Exists

**Separation of concerns prevents confusion.**

- Users should be able to choose KJV diction without implying scriptural authority
- Creative stories in KJV style are still original stories, not Bible retellings
- Traditional stories in WEB style are still faithful retellings
- Conflating presentation with authority creates validation loopholes

### The Contract

1. **languageStyle is Presentation Only**
   - WEB: Modern English diction
   - KJV: Classical/archaic English diction
   - Neither implies or changes scriptural authority

2. **Separate from translationId**
   - `translationId`: Used for Bible translation compliance (Daily Bread, scripture quotes)
   - `languageStyle`: Used for story narrative presentation style
   - These are independent fields with different purposes

3. **Mode Rules Apply Regardless of languageStyle**
   - Traditional + WEB: Faithful retelling, modern diction, `bibleSourceRef` required
   - Traditional + KJV: Faithful retelling, classical diction, `bibleSourceRef` required
   - Creative + WEB: Original story, modern diction, `bibleSourceRef` forbidden
   - Creative + KJV: Original story, poetic diction, `bibleSourceRef` forbidden + extra restrictions

### Enforcement Mechanisms

#### 1. Code-Level Separation
- `languageStyle` field on Parable model (presentation)
- `translationId` field on Parable model (Bible compliance)
- Never conflate these fields in filtering or validation

#### 2. Build-Failing Tests
**File**: [`test/critical/story_mode_contracts_test.dart`](../test/critical/story_mode_contracts_test.dart)

**Critical Tests** (MUST PASS):
- `CRITICAL: languageStyle does not affect bibleSourceRef requirements`
- `CRITICAL: Traditional+KJV still requires bibleSourceRef`
- `CRITICAL: Creative+KJV still forbids bibleSourceRef`

### Resources

- [SPEC.md Story Mode Contracts v2](SPEC.md#story-mode-contracts-v2-locked)

---

## 🔒 StoryLengthBucket-Only Invariant (NON-NEGOTIABLE)

**Invariant**: All story length logic MUST use `StoryLengthBucket` (short/full/long). Minute-based values are for legacy compatibility ONLY and must never appear in new code, UI, prompts, or user-facing features.

### Why This Exists

**Consistent user experience and clear contracts.**

- Users see "Short Story", "Full Story", "Long Story" — not minutes
- Word count ranges are locked spec (250-600, 601-1200, 1201-2000)
- Minute estimates are inaccurate (reading speed varies)
- Single source of truth prevents confusion

### The Contract

1. **UI shows bucket labels only**: "Short Story", "Full Story", "Long Story"
2. **Filtering uses StoryLengthBucket enum**
3. **Generation prompts use word ranges, not minutes**
4. **Legacy `length` field is read-only for backwards compatibility**

### Enforcement Mechanisms

**File**: [`test/core/story_length_test.dart`](../test/core/story_length_test.dart)

**Critical Tests** (MUST PASS):
- `CRITICAL: No minute-based UI labels`
- `CRITICAL: StoryLengthBucket word ranges match LOCKED SPEC`
- `CRITICAL: Legacy minute mapping is read-only`

### Resources

- [SPEC.md Story Length Buckets](SPEC.md#story-length--generation)
- [StoryLengthBucket Implementation](../lib/core/story_length_bucket.dart)

---

## 🔒 Traditional Mode = Real Bible Story Invariant (NON-NEGOTIABLE)

**Invariant**: Traditional stories MUST be faithful retellings of actual Bible stories. They are NOT devotional content, NOT original stories with biblical themes. Each Traditional story must have a `bibleStoryKey` identifying the specific Bible story being retold.

### Why This Exists

**Content integrity and user trust are paramount.**

- Users selecting Traditional mode expect ACTUAL Bible stories
- Generic "faith-based" content misleads users about what they're receiving
- Clear Bible story identification enables testing and validation
- One-to-one mood-to-story mapping ensures consistent experience

### The Contract

1. **Traditional = Real Bible Story**
   - Every Traditional story retells a specific, identifiable Bible narrative
   - NOT a devotional, NOT an original story with biblical themes
   - Examples: The Lost Sheep, Jesus Calms the Storm, David and Goliath

2. **`bibleStoryKey` REQUIRED for Traditional**
   - Every Traditional story MUST have a `bibleStoryKey` field
   - Format: snake_case identifier (e.g., "lost_sheep", "jesus_calms_storm")
   - Stories without `bibleStoryKey` are EXCLUDED from serving pool

3. **`bibleSourceRef` REQUIRED for Traditional**
   - Every Traditional story MUST have a `bibleSourceRef` field
   - Format: Book Chapter:Verse-Verse (e.g., "Luke 15:3-7")

4. **Scripture Anchor Registry** (ADR-022)
   - Each anchor has a `scriptureAnchorId` identifying one canonical narrative unit
   - No two registry entries share the same `scriptureAnchorId` (primary no-reuse invariant)
   - No two registry entries share the same `bibleStoryKey`
   - Each of the 8 moods appears in at least one entry's `moodTags`
   - `bibleSourceRef` must be specific enough to represent one narrative unit
   - Registry is declarative — no mutable state (no status, priority, etc.)
   - Multiple Traditional stories may exist for a mood (different anchors, lengths, kid/adult)

5. **"Pizzazz" is Style, Not License**
   - Allowed: pacing, sensory detail, emotional texture implied by text
   - Forbidden: new events, altered outcomes, invented theology, modern framing

### Enforcement Mechanisms

**File**: [`test/critical/traditional_bible_story_test.dart`](../test/critical/traditional_bible_story_test.dart)

**Critical Tests** (MUST PASS):
- `CRITICAL: Traditional stories MUST have bibleStoryKey`
- `CRITICAL: Traditional stories MUST have bibleSourceRef`
- `CRITICAL: Each scriptureAnchorId is globally unique in registry`
- `CRITICAL: Each bibleStoryKey is globally unique in registry`
- `CRITICAL: Each Traditional story's bibleStoryKey exists in registry`
- `CRITICAL: No Traditional story without valid bibleStoryKey in manifest`

### Testing

```bash
# Run Traditional Bible story tests
flutter test test/critical/traditional_bible_story_test.dart

# Run all tests (includes Traditional tests)
flutter test
```

### Resources

- [SPEC.md Traditional Mode Contract](SPEC.md#traditional-mode-contract-default)
- [Parable Model](../lib/models/parable.dart)

---

## 🔒 Reflection System Invariant (NON-NEGOTIABLE)

**Invariant**: Every story (Traditional AND Creative) MUST have a reflection. Reflection audio MUST use the same narrator voice as the story. Reflection is NEVER auto-played.

### Why This Exists

**Consistent user experience and voice continuity.**

- Reflections are part of the complete story experience
- Using different voices for reflection breaks immersion
- Auto-playing reflection without consent violates MoDC principles
- Every story deserves a reflection, not just some

### The Contract

1. **Every Story Has a Reflection**
   - Both Traditional and Creative stories MUST have `reflectionAudioPath`
   - Stories without reflection audio are incomplete
   - Reflection text (`reflectionTextPath`) is optional but encouraged

2. **Same Narrator Voice**
   - Reflection audio MUST be generated with the same `narratorVoiceKey` as the story
   - No separate "PAL voice" for reflections
   - Enforced via manifest validation: `reflectionNarratorVoiceKey == narratorVoiceKey`

3. **Never Auto-Play Reflection**
   - After story ends, show "Hear Reflection" button
   - User MUST tap to hear reflection
   - No automatic playback of reflection audio

4. **Reflection Content is Separate from Story Body**
   - Reflection text is a distinct asset file, never merged into or appended to story body text
   - Traditional story body MUST NOT contain reflective narrator language (see Story Mode Non-Blur Invariant)
   - Poetic, emotionally resonant closing language is valid ONLY in reflection content or Creative mode
   - Enforced by automated test scan of Traditional story text files

5. **Scripture Reference Display (Traditional Only)**
   - Scripture reference shown AFTER story completes, NOT during
   - Display `bibleSourceRef` prominently
   - Scripture reference is NOT narrated

6. **`meta.reflectionText` is Canonical**
   - `meta_*.json.reflectionText` is the single source of truth for reflection content
   - `reflection_*.txt` must exactly match `meta.reflectionText` (after trim)
   - Active `reflectionAudioStale: true` flags must not be committed — regenerate audio first
   - Enforced by [`test/core/reflection_consistency_test.dart`](../test/core/reflection_consistency_test.dart)

7. **Audio Asset Consistency**
   - Any audio path referenced in `meta.files` must resolve to a non-empty file in the repo
   - Applies to both story audio (`meta.files.{length}.storyAudio`) and reflection audio
   - Supports standard reflection pattern (`meta.files.reflection.reflectionAudio`) and legacy per-length pattern (`meta.files.{length}.reflectionAudio`)
   - Active stale-audio flags are not allowed in committed content
   - Enforced by [`test/core/audio_asset_consistency_test.dart`](../test/core/audio_asset_consistency_test.dart)

### Enforcement Mechanisms

**File**: [`test/critical/reflection_system_test.dart`](../test/critical/reflection_system_test.dart)

**Critical Tests** (MUST PASS):
- `CRITICAL: All stories have reflectionAudioPath`
- `CRITICAL: Reflection narrator voice matches story narrator voice`
- `CRITICAL: Reflection is never auto-played (UI test)`
- `CRITICAL: Traditional stories show scripture ref after completion`

**File**: [`test/core/reflection_consistency_test.dart`](../test/core/reflection_consistency_test.dart)

**Critical Tests** (MUST PASS):
- `CRITICAL: All meta JSON files have reflectionText`
- `CRITICAL: Every story has a reflection .txt file`
- `CRITICAL: Reflection .txt content exactly matches meta.reflectionText`
- `CRITICAL: No active reflectionAudioStale flags in committed meta`

### Testing

```bash
# Run reflection system tests
flutter test test/critical/reflection_system_test.dart

# Run reflection consistency tests
flutter test test/core/reflection_consistency_test.dart

# Run audio asset consistency tests
flutter test test/core/audio_asset_consistency_test.dart

# Run all tests (includes all reflection + audio tests)
flutter test
```

### Resources

- [SPEC.md Post-Story Reflection](SPEC.md#post-story-everyday-life-reflection)
- [Player Screen](../lib/features/pals_parables/parable_player_screen.dart)

---

## 🔒 Mode Persistence Invariant (NON-NEGOTIABLE)

**Invariant**: Storytelling mode (Traditional/Creative) persists across app restarts. Default is Traditional. Only two modes exist.

### Why This Exists

**User expectation and session continuity.**

- Users expect their mode choice to be remembered
- Traditional is the safer default (actual Bible stories)
- Only two modes simplifies UX and code

### The Contract

1. **Default is Traditional**
   - New users and unset preferences default to Traditional
   - `UserPreferences.defaults().storytellingMode == 'traditional'`

2. **Persistence Across Restarts**
   - Mode change in Settings persists to SharedPreferences
   - On app restart, mode is restored from storage
   - No session-scoped mode that resets on restart

3. **Only Two Modes**
   - `'traditional'` and `'creative'` are the only valid values
   - No other modes exist or will be added
   - Invalid values reset to Traditional

### Enforcement Mechanisms

**File**: [`test/critical/mode_persistence_test.dart`](../test/critical/mode_persistence_test.dart)

**Critical Tests** (MUST PASS):
- `CRITICAL: Default storytelling mode is traditional`
- `CRITICAL: Mode persists after simulated restart`
- `CRITICAL: Invalid mode values reset to traditional`

### Resources

- [SPEC.md Settings](SPEC.md#settings)
- [UserPreferences Model](../lib/models/user_preferences.dart)

---

## 🔒 Telemetry: No Minute-Based Length Fields (NON-NEGOTIABLE)

**Invariant**: Telemetry events, allowlists, support bundles, and filter tracking MUST NEVER contain minute-based story length fields. Only `length_bucket` (short/full/long) is permitted.

### Why This Exists

**Consistent data model and privacy.**

- `StoryLengthBucket` (short/full/long) is the canonical representation
- Minute-based fields leak implementation details into telemetry
- Mixed field usage creates confusing analytics
- Word count ranges (not minutes) define buckets per SPEC.md
- Prevents reintroduction of legacy minute-based filtering

### Forbidden Fields

The following fields MUST NEVER appear in telemetry code:

| Field | Reason |
|-------|--------|
| `length_min` | Legacy minute-based field |
| `length_max` | Legacy minute-based field |
| `duration_minutes` | Minute-based duration |
| `story_length_minutes` | Minute-based story length |
| `length_minutes` | Minute-based length |
| `duration_min` | Minute-based duration |
| `minutes` | When used as telemetry field for story length |

### Also Forbidden (Christian General Only)

Per the Christian General Only invariant, these fields are also banned from telemetry:

- `tradition`
- `denomination`
- `faith_tradition`

### Allowed Field

**Use `length_bucket` only** with values: `short`, `full`, `long`

### Enforcement Mechanisms

#### 1. Repo-Wide Scan Test
**File**: [`test/critical/telemetry_forbidden_tokens_test.dart`](../test/critical/telemetry_forbidden_tokens_test.dart)

Scans all source files in `lib/` and `test/` for:
- Forbidden tokens in telemetry code
- Forbidden tokens in allowlist definitions
- Misleading backwards-compatibility comments

**Critical Tests** (MUST PASS):
- `CRITICAL: No minute-based length tokens in lib/ directory`
- `CRITICAL: No minute-based length tokens in telemetry allowlists`
- `CRITICAL: No backwards-compatibility comments for minute-based fields`
- `CRITICAL: No minute tokens in support bundle serialization`
- `CRITICAL: No minute tokens in ParableService telemetry`

#### 2. Allowlist Validation
**File**: [`test/core/support_bundle_test.dart`](../test/core/support_bundle_test.dart)

Tests verify:
- `length_min` is NOT in any allowlist
- `length_bucket` IS in filter allowlists
- No minute-based fields in any allowlist

#### 3. CI Enforcement
**File**: [`.github/workflows/flutter.yml`](../.github/workflows/flutter.yml)

GitHub Actions runs a forbidden token scan step that fails if minute-based tokens are found.

### Testing

```bash
# Run telemetry forbidden tokens test
flutter test test/critical/telemetry_forbidden_tokens_test.dart

# Run support bundle tests (includes allowlist validation)
flutter test test/core/support_bundle_test.dart

# Run all tests (includes telemetry invariant)
flutter test

# Manual verification (should return no matches)
grep -RInE "length_min|length_max|duration_minutes|story_length_minutes" lib || echo "✅ No forbidden tokens"
```

### Violation Response

**Build Time**:
- Tests FAIL immediately
- CI fails with detailed error message showing file:line
- PR cannot be merged

**Example Failure**:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🚨 TELEMETRY INVARIANT VIOLATION: Minute-Based Length Fields
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Minute-based length fields are BANNED from telemetry.
Use StoryLengthBucket (short/full/long) via length_bucket only.

Violations found:
  ❌ lib/services/parable_service.dart:142: Found "length_min"
      Line: 'length_min': bucket.minMinutes,

See: docs/INVARIANTS.md - Telemetry: No minute-based length fields
Test: test/critical/telemetry_forbidden_tokens_test.dart
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Maintenance Rules

**When modifying telemetry code:**

1. **NEVER** add minute-based length fields to telemetry events
2. **NEVER** add minute-based fields to allowlists
3. **ALWAYS** use `length_bucket` for story length tracking
4. **RUN** `flutter test test/critical/telemetry_forbidden_tokens_test.dart` before committing
5. **DO NOT** weaken or remove telemetry invariant tests
6. **DO NOT** add "backwards compatibility" comments suggesting minute fields should be kept

**If a telemetry invariant test fails:**
1. DO NOT disable the test
2. Remove the minute-based field
3. Replace with `length_bucket` if needed
4. Verify all tests pass

### Resources

- [StoryLengthBucket Implementation](../lib/core/story_length_bucket.dart)
- [SPEC.md Story Length Buckets](SPEC.md#story-length--generation)
- [Telemetry Forbidden Tokens Test](../test/critical/telemetry_forbidden_tokens_test.dart)
- [Support Bundle Tests](../test/core/support_bundle_test.dart)

---

## 🔒 Meta-Text Prevention Invariant (NON-NEGOTIABLE)

**Invariant**: Generated Scripture narration output MUST NEVER contain meta-commentary, introductions, disclaimers, process language, or LLM preamble. Violations are silently rejected and regenerated. Declarative verses MUST NOT be narrativized. Reflection/interpretation language MUST only appear in the post-story reflection system.

### Why This Exists

**Content purity and immersion are paramount.**

- Meta-text ("Here is a retelling…", "Certainly!") breaks the narration experience
- LLMs frequently prepend process language despite prompt instructions
- Declarative Scripture (e.g., Romans 8:28) must not be turned into scenes with imagined characters
- Comfort, explanation, application, and interpretation belong in reflections, not narration
- Deterministic validation catches failures that prompt-only fixes cannot prevent

### The Contract

1. **Meta-Text Kill Switch**
   - A configurable blocklist of meta-phrases is checked against the opening of all generated output
   - ANY match → output rejected, silent regeneration triggered
   - Blocklist includes: "Here is", "Certainly", "This version", "In this retelling", "The following", "This passage", etc.

2. **Scripture-First Enforcement**
   - The first non-whitespace characters must be story/Scripture prose
   - No preamble, no disclaimers, no process language

3. **Verse Classification**
   - `DECLARATIVE_ONLY`: Statement-level elevation only. No scene, people, setting, emotional atmosphere, imagined listeners, or historical framing (e.g., Romans 8:28, Jeremiah 29:11)
   - `NARRATIVE_ELIGIBLE`: May include scene-setting, characters, setting (e.g., narrative Bible stories)

4. **Reflection Firewall**
   - Comfort, explanation, application, and interpretation language is forbidden in Scripture narration
   - These patterns may ONLY appear in the post-story reflection system

5. **Regeneration Loop**
   - On validation failure: discard output, regenerate with stricter reminder
   - Maximum 3 attempts (configurable via `kMetaTextMaxRegenAttempts`)
   - No apologies, no explanations surfaced to user
   - After max attempts: output marked as contaminated, not served

### Enforcement Mechanisms

#### 1. Dart Validator
**File**: [`lib/safety/meta_text_validator.dart`](../lib/safety/meta_text_validator.dart)

- `MetaTextValidator` — blocklist + declarative + reflection firewall checks
- `VerseClassification` — registry of verse types (declarative vs narrative)
- `MetaTextHarness` — validate-reject-regenerate loop

#### 2. Build-Failing Tests
**File**: [`test/safety/meta_text_validator_test.dart`](../test/safety/meta_text_validator_test.dart)

**Critical Tests** (MUST PASS):
- `CRITICAL: rejects output starting with "Here is"`
- `CRITICAL: Romans 8:28 classified as DECLARATIVE_ONLY`
- `CRITICAL: rejects comfort language in narration`
- `CRITICAL: rejects explanation language in narration`
- `CRITICAL: rejects application language in narration`

### Testing

```bash
# Run meta-text prevention tests
flutter test test/safety/meta_text_validator_test.dart

# Run all tests (includes meta-text prevention)
flutter test
```

### Maintenance Rules

1. **NEVER** weaken or remove blocklist entries
2. **NEVER** bypass the validator for generated output
3. **ALWAYS** run meta-text tests before committing
4. **DO NOT** add reflection/interpretation language to narration content
5. **DO NOT** narrativize DECLARATIVE_ONLY verses

### Resources

- [Meta-Text Validator](../lib/safety/meta_text_validator.dart)
- [Meta-Text Tests](../test/safety/meta_text_validator_test.dart)

---

## 🔒 Voice Transcript Privacy & Input Equivalence Invariant (NON-NEGOTIABLE)

**Invariant**: Voice transcripts are private, ephemeral, and equivalent to typed input. A voice transcript must never be logged, persisted, transmitted, or included in diagnostics/support bundles, and must be processed through the exact same mood pipeline as typed text. Microphone capture must require explicit user action.

### Why This Exists

**Voice is high-risk data. We protect users by making transcripts ephemeral and non-observable.**

- A transcript can contain sensitive personal information (PII, mental health details, names, locations)
- Logging or persisting transcripts creates unnecessary privacy and compliance risk
- Divergent "voice-only" logic increases bugs, regressions, and kid-mode inconsistencies
- Explicit consent is required to maintain user trust and platform compliance

### The Contract

1. **Input Equivalence**
   - Voice transcripts must be inserted into the same UI field used for typed input (the mood TextField)
   - Submission must call the same handler used for typing: `_handleMoodSubmission()` → `MoodService.detectMood()`
   - No separate "voice mood detection" path may exist in code

2. **Transcript Privacy**
   - Voice transcripts must never be:
     - logged (including AppLogger events, breadcrumbs, and `debugPrint()` calls)
     - persisted (SharedPreferences, files, SQLite, caches)
     - transmitted externally (network calls, analytics payloads, remote services)
     - included in diagnostics/support bundles or crash logs
   - Transcripts may exist only in-memory for the current screen session and must be discarded when leaving the screen

3. **Microphone Consent**
   - Microphone capture must not start without user-initiated action
   - On the PalsParablesScreen, capture requires an explicit tap on the mic control
   - On the MainMenuScreen conversational flow, tapping the PAL button serves as consent; the mic may auto-activate after PAL's greeting audio completes
   - If permissions are denied, the system must fall back to typing without blocking the feature

### Enforcement Mechanisms

- **Logging guardrails:**
  - AppLogger must block keys that could contain transcript data (including but not limited to: `transcript`, `recognized_text`, `speech_result`, `voice_text`, `userText`)
  - No `logEvent()` calls may include transcript strings (even under "debug")
- **Storage guardrails:**
  - No StorageService / SharedPreferences writes may store transcript data
  - Diagnostics/support bundle generation must not include transcript fields or raw mood input text
- **Architecture guardrails:**
  - Voice path must terminate in the same text submission handler as typed input
- **Repo-wide scan:**
  - `test/critical/voice_privacy_scan_test.dart` scans all `lib/` files for patterns that could leak transcript data (e.g., `logEvent.*transcript`, `debugPrint.*transcript`, `SharedPreferences.*transcript`)

### Testing

```bash
# Run voice transcript privacy tests
flutter test test/critical/voice_transcript_privacy_test.dart

# Run voice mic consent tests
flutter test test/critical/voice_mic_consent_test.dart

# Run voice mood pipeline equivalence tests
flutter test test/services/voice_mood_pipeline_test.dart

# Run repo-wide voice privacy scan
flutter test test/critical/voice_privacy_scan_test.dart
```

### Maintenance Rules

1. **NEVER** add transcript-like payloads to telemetry, breadcrumbs, crash logs, debugPrint, or support bundles
2. **ALWAYS** route voice input through the existing typed mood submission pipeline
3. **ALWAYS** require explicit mic tap prior to any recording/listening
4. **DO NOT** create voice-specific mood detection logic

### Resources

- [AppLogger blocked-keys policy](../lib/core/app_logger.dart)
- [Permission handling pattern reference](../lib/features/whisper/whisper_screen.dart)
- [Voice consent patterns](../lib/services/voice_consent_gate.dart)

---

## 🔒 Analytics Telemetry Privacy Invariant (NON-NEGOTIABLE)

**Invariant**: Analytics events MUST only contain allowlisted payload fields. No user text, PII, minute-based length fields, or tradition/denomination fields may appear in analytics payloads. Analytics emission MUST be fire-and-forget and MUST NEVER block user-facing operations.

### Why This Exists

**Privacy-safe telemetry enables content insights without tracking users.**

- Aggregate favorite patterns reveal which stories resonate (mood, mode, length)
- No user identification or tracking is needed for this insight
- Allowlisted payloads prevent accidental PII leakage as new fields are added
- Fire-and-forget ensures analytics never degrades user experience
- Existing `AppLogger` provides all needed infrastructure — no external vendors required

### The Contract

1. **Allowlisted Payload Only**
   - Only keys in `analyticsAllowedKeys` (defined in `lib/core/analytics_events.dart`) may appear
   - Adding new keys requires updating the allowlist, tests, AND this document
   - Keys not in the allowlist are a test failure

2. **Disallowed Fields MUST NOT Appear**
   - PII keys: `userText`, `email`, `phone`, `name`, `title`, etc.
   - Minute-based keys: `length_min`, `duration_minutes`, etc. (per Telemetry invariant)
   - Tradition keys: `tradition`, `denomination`, `faith_tradition` (per Christian General Only invariant)

3. **Fire-and-Forget Emission**
   - `AnalyticsEvents` methods return `LogResult` for testability but callers MUST NOT branch on it
   - Emission failure MUST NEVER prevent the user action (e.g., adding a favorite)
   - All emission is delegated to `AppLogger.logEvent()` which is already safe-fail

4. **Single Emission Per Action**
   - Each user action (e.g., one `addFavorite()` call) emits exactly one analytics event
   - No duplicate emissions, no batching, no deferred emission

5. **No External Vendors**
   - Analytics uses `AppLogger.logEvent()` only
   - No Firebase Analytics, no Mixpanel, no Amplitude
   - Future vendor integration (if needed) goes through `AppLogger`, not around it

### Enforcement Mechanisms

#### 1. Allowlist Validation (Compile-Time)
**File**: [`lib/core/analytics_events.dart`](../lib/core/analytics_events.dart)

```dart
const Set<String> analyticsAllowedKeys = {
  'story_id', 'mood', 'mode', 'length_bucket',
  'kid_friendly', 'translation_id', 'language_style', 'voice_key',
};
```

#### 2. Build-Failing Tests
**File**: [`test/core/analytics_events_test.dart`](../test/core/analytics_events_test.dart)

**Critical Tests** (MUST PASS):
- `CRITICAL: story_favorited payload contains only allowlisted keys`
- `CRITICAL: disallowed keys are never in analytics payload`
- `CRITICAL: kidFriendly field is populated correctly`
- `CRITICAL: length_bucket uses StoryLengthBucket (not minutes)`
- `CRITICAL: logStoryFavorited never throws`

#### 3. AppLogger Privacy Layer
All payloads pass through `AppLogger._sanitizeData()` which blocks PII keys and patterns as a second safety net.

### Testing

```bash
# Run analytics event tests
flutter test test/core/analytics_events_test.dart

# Run all tests (includes analytics)
flutter test
```

### Maintenance Rules

**When adding new analytics events:**

1. **ALWAYS** add payload keys to `analyticsAllowedKeys`
2. **ALWAYS** add tests verifying the new event's payload
3. **NEVER** include user text, PII, or minute-based fields
4. **NEVER** add external analytics vendors without updating this invariant
5. **RUN** analytics tests before committing

**If an analytics test fails:**
1. DO NOT disable the test
2. Remove the disallowed field from the payload
3. Verify all tests pass

### Resources

- [SPEC.md Analytics Section](SPEC.md#anonymous-usage-telemetry--favorites)
- [AnalyticsEvents Implementation](../lib/core/analytics_events.dart)
- [Analytics Tests](../test/core/analytics_events_test.dart)
- [AppLogger](../lib/core/app_logger.dart)

---

## 🔒 Model Router Traditional Engine Lock (NON-NEGOTIABLE)

**Invariant**: The Universal Model Router MUST NEVER route `traditional_story_remote` tasks to any model other than gpt-4.1 via OpenAI. The router MUST hard-fail (not silently fall back) if gpt-4.1 is unavailable for Traditional tasks.

### Why This Exists

**Scripture fidelity and doctrinal trust are paramount.**

- Traditional stories require proven scripture accuracy from gpt-4.1
- Substituting a local model risks doctrinal inaccuracy in Bible retellings
- The dual-engine architecture is a locked design decision (ADR-014)
- Silent degradation to a weaker model would violate user trust

### The Contract

1. **`traditional_story_remote` MUST have `locked: true`** in `model_registry.json`
2. **Router MUST raise an error** (not silently degrade) if locked task cannot be fulfilled
3. **Router MUST NOT allow fallback** to Ollama models for Traditional tasks
4. **`provider_constraint: "openai"` MUST be set** for `traditional_story_remote`
5. **Router is not used by the Traditional pipeline today** — Traditional scripts call OpenAI directly. This invariant prevents future misuse.

### Enforcement Mechanisms

#### 1. Registry Validation
**File**: `server/model_router/model_registry.json`

The `traditional_story_remote` task definition includes `"locked": true` and `"provider_constraint": "openai"`.

#### 2. Router Logic
**File**: `server/model_router/router.py`

Locked tasks hard-fail with an explicit error when the required model is unavailable. No fallback chain is attempted.

#### 3. Unit Tests
**File**: `server/model_router/tests/test_router.py`

- Registry validation test checks `locked` flag on `traditional_story_remote`
- Router test verifies hard-fail behavior for unavailable locked tasks
- Router test verifies no local model is ever returned for Traditional tasks

### Testing

```bash
# Run router unit tests
cd /Volumes/T9-AI/bible_pal && python3 -m pytest server/model_router/tests/ -v

# Verify Traditional lock in registry
python3 -c "import json; r=json.load(open('server/model_router/model_registry.json')); assert r['tasks']['traditional_story_remote']['locked']==True; print('✅ Traditional lock verified')"
```

### Maintenance Rules

1. **NEVER** remove the `locked: true` flag from `traditional_story_remote`
2. **NEVER** add Ollama models to the `traditional_story_remote` fallback chain
3. **NEVER** change the router to silently degrade locked tasks
4. **DO NOT** modify the Traditional pipeline to call the router for model selection

---

## 🔒 Mood System Invariant (NON-NEGOTIABLE)

**Invariant**: The allowed mood IDs are exactly: `joyful`, `grateful`, `weary`, `anxious`, `hurting`, `brave_courage`, `calm_peaceful`, `encouraging`. The legacy value `neutral` is no longer valid and must map to `calm_peaceful` in migration.

### Why This Exists
- Mood IDs flow through story generation, manifest entries, telemetry, and user preferences
- Adding or removing moods without updating all touchpoints causes silent failures in story selection
- `neutral` was removed because it produced generic stories — `calm_peaceful` better serves users who don't express a specific mood

### Enforcement
- `allowedMoodIds` in `user_preferences.dart` is the canonical allowlist
- `MoodService.detectMood()` returns only allowed moods
- Default mood for empty input is `calm_peaceful` (not neutral)
- All micro-response maps must have entries for all 8 moods
- Test: every micro-response must contain a transition indicator (story/listen/play/share/hear/something/here's)

---

## 🔒 Mood Expansion Serving Invariant (NON-NEGOTIABLE)

**Invariant**: When serving stories, the engine must follow this exact priority order: (1) exact selected mood + unseen, (2) similar moods + unseen, (3) exact selected mood + seen (least-recently-played), (4) similar moods + seen (least-recently-played). The system must never silently switch to unrelated moods.

### Why This Exists
- A small story library leads to fast repetition if serving is limited to exact mood matches
- Users trust the mood they selected — expanding to unrelated moods violates that trust
- Controlled expansion to emotionally adjacent moods makes the library feel larger without confusing the user
- Tracking `selectedMood` vs `servedMood` separately enables analytics on expansion usage

### Similar Mood Map (Canonical)
- `anxious` → `calm_peaceful`, `encouraging`, `weary`
- `calm_peaceful` → `anxious`, `grateful`, `encouraging`
- `brave_courage` → `encouraging`, `hurting`, `anxious`
- `encouraging` → `brave_courage`, `calm_peaceful`, `grateful`
- `grateful` → `joyful`, `calm_peaceful`, `encouraging`
- `hurting` → `weary`, `encouraging`, `calm_peaceful`
- `joyful` → `grateful`, `encouraging`, `calm_peaceful`
- `weary` → `hurting`, `calm_peaceful`, `encouraging`

### Enforcement
- Story must have the requested `StoryLengthBucket` available (no fallback to other lengths)
- Active mode/settings must match at every priority stage
- The selected mood remains primary — similar moods are a fallback expansion layer only
- All existing serving invariants (Non-Repeat, Kid Safety, Mode Separation) still apply at every stage
- `servedMood` must reflect the actual mood of the story returned, not the user's selection
- Modifying the similar mood map requires owner approval

---

## 🔒 Story Length Label Invariant (NON-NEGOTIABLE)

**Invariant**: User-facing story length labels must be exactly: "Short Story", "Full Story", "Long Story". Internal enum values remain `short`, `full`, `long`. No duration or minute-based text may appear in the UI.

### Why This Exists
- Clear bucket labels match the internal system and reduce ambiguity
- Consistency between PAL picker and main menu selector prevents user confusion
- No duration estimates — word count ranges define length, not minutes

### Enforcement
- `StoryLengthBucket.displayLabel` getter is the single source of truth
- Test: labels are exactly these three strings (no minutes, no parentheses, no notes)

---

## 🔒 Preferred Length Persistence Invariant (NON-NEGOTIABLE)

**Invariant**: Once a user selects a story length via the PAL picker, their choice is persisted in `UserPreferences.preferredLengthBucket` and used automatically for all subsequent mood-to-story flows. The PAL picker only shows when no preference is saved.

### Why This Exists
- Reduces friction — the most-loved apps remember your preferences
- The PAL picker is a first-impression moment, not a recurring gate
- Session-scoped length still exists for manual override via the main menu selector

---

## 🔒 Journal Privacy Invariant (NON-NEGOTIABLE)

**Invariant**: Reflection journal entries are local-only, write-once, and never synced, logged, or included in diagnostics/support bundles.

### Why This Exists
- Journal entries contain personal spiritual reflections — the most sensitive user data in the app
- Users must trust that their private thoughts stay private
- This follows the same principle as voice transcript privacy (Feature 2.2)

### Enforcement
- `StorageService.addJournalEntry()` writes to SharedPreferences only
- No journal data in crash logs, analytics, or telemetry
- No cloud sync of journal entries

---

## 🔒 Bedtime Mode Safety Invariant (NON-NEGOTIABLE)

**Invariant**: Bedtime mode is always user-controlled (never auto-activates). Volume is always reset to 1.0 after fade-out. The dim overlay never blocks touch interaction.

### Why This Exists
- Auto-activating bedtime mode based on time could surprise users during legitimate evening use
- If volume isn't reset, next playback would be silent — a confusing, hard-to-debug experience
- If the overlay blocks touch, users can't dismiss/navigate

---

## 🔒 Pray With Me Non-Directive Invariant (NON-NEGOTIABLE)

**Invariant**: Prayer text must be personal and non-prescriptive. Prayers are first-person ("Lord, I am tired"), never second-person directive ("You should pray"), never doctrinal ("According to theology X").

### Why This Exists
- Follows the same MoDC (Mode of Companionship) rules as story content
- Users of diverse Christian traditions must feel welcome
- Prayers model a posture, not a prescription

### Enforcement
- Prayer text is hardcoded (not generated) — each mood has exactly one reviewed prayer
- No prayer contains commands, advice, or doctrinal claims

---

## Story Length Availability Invariant (NON-NEGOTIABLE)

**Invariant**: Each story MUST explicitly declare its available lengths, and declarations MUST match what exists on disk.

### Rules
- If a length file is not present on disk, it MUST NOT appear in `availableLengths` or `lengths`
- If a length file exists on disk, it MUST be listed in `availableLengths` and `lengths`
- The serving system MUST only select stories that support the requested length
- Short and Full are REQUIRED for every story; Long is OPTIONAL (ADR-027)

### Why This Exists
- Prevents the app from requesting a story length that doesn't exist
- Ensures manifest and meta files are always in sync with actual content
- Long stories were made optional (2026-03-29) because forcing length caused quality degradation

### Enforcement
- Manifest build script scans on-disk files to determine available lengths
- Meta JSON `lengths` field must match files in the story directory
- Manifest `availableLengths` field must match meta `lengths`

---

## File Integrity Invariant (NON-NEGOTIABLE)

**Invariant**: All files referenced in `manifest_opus.json` MUST exist on disk.

### Rules
- No manifest entry may reference a missing text file via `textFilePath`
- No manifest entry may reference a missing reflection file
- No manifest entry may reference a missing audio file via `audioFilePath`
- No manifest entry may reference a length that does not exist on disk
- If a file is removed (e.g., long dropped for quality), the manifest MUST be updated accordingly

### Why This Exists
- Broken file references cause runtime crashes in the app
- During the review pipeline, long files may be dropped — the manifest must stay in sync
- The legacy system had known issues with broken file references — the Opus system must not repeat this

### Enforcement
- Manifest is built by scanning on-disk files (never from assumptions)
- Post-build validation checks every `textFilePath` and `audioFilePath` reference
- Any broken reference is a hard failure that blocks the batch

---

## Future Invariants

As the project evolves, additional invariants may be added here. Each invariant must:
- Be clearly stated as NON-NEGOTIABLE
- Have technical enforcement (not just documentation)
- Fail builds when violated
- Be documented with WHY it exists

---

**Last Updated**: 2026-03-29
**Maintained By**: Bible PAL Development Team
