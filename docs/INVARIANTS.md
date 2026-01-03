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

## Future Invariants

As the project evolves, additional invariants may be added here. Each invariant must:
- Be clearly stated as NON-NEGOTIABLE
- Have technical enforcement (not just documentation)
- Fail builds when violated
- Be documented with WHY it exists

---

**Last Updated**: 2025-12-28
**Maintained By**: Bible PAL Development Team
