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

## 🔒 Kid Bedtime Safe Generation Invariant (NON-NEGOTIABLE)

**Invariant**: All kid-mode story generations MUST pass the Kid Bedtime Validator before being saved to the kid library. Forbidden words MUST never appear in kid-safe output. Maximum regeneration attempts = 3. Unsafe stories MUST NOT be saved to kid library.

### Why This Exists

**Bedtime safety for children is paramount.**

- Children ages 5-9 may fall asleep while listening
- Parents may not be actively monitoring
- A startling word or scary image could disturb a sleeping child
- Biblical hallucinations (e.g., "Jonah was crowned king") confuse children about scripture
- Parents trust the "Kid Friendly" mode to be truly safe for unattended bedtime listening

### The Contract

When generating stories for kid mode, the system enters a **strict bedtime safety contract**:

1. **Contract Injection MUST occur**
   - Every Gemma prompt MUST include the Kid Bedtime Contract
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
   - Bedtime closing signal MUST be present

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
- [`docs/prompts/kid_bedtime_contract.txt`](prompts/kid_bedtime_contract.txt) - Contract text
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
- Bedtime closing signals
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

### Testing Kid Bedtime Safety

```bash
# Run all kid bedtime safety tests
flutter test test/kid_bedtime_safe/

# Test the validator script directly
./server/kid_bedtime_validator.sh assets/stories/some_story.txt

# Test the harness (requires Ollama running)
./server/kid_bedtime_harness.sh prompt.txt output.txt --max-attempts 3

# Run all tests (includes kid bedtime safety)
flutter test
```

### Maintenance Rules

**When modifying kid bedtime generation:**

1. **NEVER** bypass the Kid Bedtime Contract injection
2. **NEVER** skip post-generation validation
3. **NEVER** save stories with `kidSafe: false` to kid library
4. **ALWAYS** include repair instruction on regeneration
5. **ALWAYS** respect max attempts limit
6. **RUN** kid bedtime tests before committing
7. **DO NOT** weaken forbidden vocabulary list
8. **DO NOT** disable or weaken safety tests

**If a kid bedtime test fails:**
1. DO NOT disable the test
2. DO NOT weaken the validator
3. Fix the root cause (missing validation, weak pattern, etc.)
4. Verify all kid bedtime tests pass
5. Test with sample forbidden content manually

### Resources

- [Kid Bedtime Contract](prompts/kid_bedtime_contract.txt)
- [Forbidden Vocabulary](../server/kid_bedtime_forbidden.txt)
- [Bash Validator](../server/kid_bedtime_validator.sh)
- [Dart Validator](../lib/safety/kid_bedtime_validator.dart)
- [Harness Script](../server/kid_bedtime_harness.sh)
- [Kid Bedtime Tests](../test/kid_bedtime_safe/)
- [SPEC.md Kid Bedtime Section](SPEC.md#kid-bedtime-safe-harness)

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

## Future Invariants

As the project evolves, additional invariants may be added here. Each invariant must:
- Be clearly stated as NON-NEGOTIABLE
- Have technical enforcement (not just documentation)
- Fail builds when violated
- Be documented with WHY it exists

---

**Last Updated**: 2026-01-05
**Maintained By**: Bible PAL Development Team
