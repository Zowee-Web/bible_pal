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

## Future Invariants

As the project evolves, additional invariants may be added here. Each invariant must:
- Be clearly stated as NON-NEGOTIABLE
- Have technical enforcement (not just documentation)
- Fail builds when violated
- Be documented with WHY it exists

---

**Last Updated**: 2025-12-16
**Maintained By**: Bible PAL Development Team
