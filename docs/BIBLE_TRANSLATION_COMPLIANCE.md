# Bible Translation Compliance Documentation

## Hard Invariant

**Bible PAL must NEVER use or offer any non-open-source / non-public-domain Bible translations.**

This is a non-negotiable legal and ethical requirement. All Bible text in the app must come from translations that are:
- Public domain, OR
- Released under an open-source license allowing free commercial use

## Implementation

The allowlist-only system is enforced at four layers:

### 1. Code-Level Allowlist Registry

**File**: [`lib/core/bible_translation_registry.dart`](../lib/core/bible_translation_registry.dart)

This is the **SINGLE SOURCE OF TRUTH** for all allowed and banned translations.

**Allowed Translations** (as of 2025):
- **WEB** - World English Bible (Public Domain, 2000)
- **KJV** - King James Version (Public Domain, 1611)
- **ASV** - American Standard Version (Public Domain, 1901)
- **YLT** - Young's Literal Translation (Public Domain, 1862)
- **DRA** - Douay-Rheims American Edition (Public Domain, 1899)

**Explicitly Banned Translations**:
- NIV, ESV, NRSV, NLT, NASB, CSB, MSG, HCSB, AMP, GNT
- And all others not explicitly listed in the allowlist

**Key Functions**:
```dart
// Validate a translation ID
BibleTranslationRegistry.isAllowed('WEB')  // true
BibleTranslationRegistry.isBanned('NIV')   // true

// Sanitize and reset invalid translations
BibleTranslationRegistry.validateAndSanitize('ESV')  // Returns 'WEB'

// Scan text for copyrighted phrases
BibleTranslationRegistry.scanForBannedFingerprints(text)
```

### 2. Runtime Guards

All models that handle Bible translations include automatic validation:

**UserPreferences** ([`lib/models/user_preferences.dart`](../lib/models/user_preferences.dart)):
- `fromJson()` - Validates translations loaded from storage
- `copyWith()` - Validates translations when updating preferences

**DailyBread** ([`lib/models/daily_bread.dart`](../lib/models/daily_bread.dart)):
- `fromJson()` - Validates translations in daily verse data

**Behavior**:
- If a banned translation is detected: Logs a COMPLIANCE VIOLATION and resets to WEB
- If an unknown translation is detected: Logs a WARNING and resets to WEB
- Allowed translations pass through unchanged

### 3. Build-Failing Tests

**File**: [`test/core/bible_translation_compliance_test.dart`](../test/core/bible_translation_compliance_test.dart)

Comprehensive test suite (24 tests) that enforces compliance at build time:

**Registry Tests**:
- Verifies allowlist contains only public domain translations
- Confirms no overlap between allowed and banned lists
- Validates default translation is in allowlist

**Runtime Guard Tests**:
- Tests that banned translations are rejected (NIV, ESV, NRSV, NLT, etc.)
- Tests that unknown translations default to WEB
- Tests model-level enforcement in UserPreferences and DailyBread

**Fingerprint Detection Tests**:
- Scans all VerseService verses for copyrighted phrases
- Detects ESV-specific phrasings like "heavy laden", "lowly in heart"
- Ensures WEB text doesn't trigger false positives

**Edge Case Tests**:
- Case sensitivity (niv, Niv, NIV all blocked)
- Whitespace handling (" NIV ", "\tESV\n")
- Empty string handling

**To run tests**:
```bash
# Run compliance tests only
flutter test test/core/bible_translation_compliance_test.dart

# Run all tests (including compliance)
flutter test
```

### 4. Strict Translation IDs in Metadata

All Scripture data uses validated translation IDs:

**VerseService** ([`lib/services/verse_service.dart`](../lib/services/verse_service.dart)):
- All verses hardcoded with `translation: 'WEB'`
- Uses World English Bible text exclusively
- Updated tests verify against BibleTranslationRegistry

**DailyBreadService** ([`lib/services/daily_bread_service.dart`](../lib/services/daily_bread_service.dart)):
- Reads translation from user preferences (automatically validated)
- Falls back to WEB if preferences corrupted

## How to Add a New Translation

**ONLY if it's public domain or open-source:**

1. **Verify License**: Confirm the translation is truly public domain or has an open-source license
2. **Add to Registry**: Edit `lib/core/bible_translation_registry.dart`
   ```dart
   BibleTranslation(
     id: 'NEW',
     name: 'New Translation Name',
     license: 'Public Domain',
     year: 1900,
     url: 'https://source.url',
     notes: 'Brief description',
   ),
   ```
3. **Run Tests**: `flutter test test/core/bible_translation_compliance_test.dart`
4. **Document**: Update this file and SPEC.md

## How to Remove UI References to Translations

There is currently **NO UI** for translation selection. The app uses:
- User preferences stored with validated translation IDs
- Default translation (WEB) for new users
- Automatic sanitization if invalid translation found in storage

If translation selection UI is added in the future, it MUST:
1. Query `BibleTranslationRegistry.allowedTranslations` for options
2. Display only allowed translations
3. Use `validateAndSanitize()` when saving user choice

## Testing Compliance

### Manual Testing

1. **Load banned translation from storage**:
   ```dart
   final prefs = UserPreferences.fromJson({
     'bibleTranslation': 'NIV',  // Should be reset to WEB
   });
   expect(prefs.bibleTranslation, equals('WEB'));
   ```

2. **Scan verses for fingerprints**:
   ```dart
   final verse = verseService.getVerseForMood('joyful');
   final fingerprints = BibleTranslationRegistry.scanForBannedFingerprints(verse.text);
   expect(fingerprints, isEmpty);  // Should have no copyrighted phrases
   ```

### Automated Testing

All tests run automatically in CI/CD:
```bash
flutter test
```

**Critical Tests** (these MUST pass):
- `CRITICAL: validateAndSanitize() rejects banned translations`
- `CRITICAL: No "NIV" string literal in UserPreferences model`
- `CRITICAL: All VerseService verses use WEB translation`
- `CRITICAL: VerseService contains no ESV fingerprints`
- `HARD INVARIANT: No overlap between allowed and banned`

## Compliance Violations

If a compliance violation is detected (banned translation in code or data):

**Build Time**:
- Tests WILL FAIL
- Build will not complete
- Pull request will be blocked

**Runtime**:
- Violation logged to console
- Translation automatically reset to WEB (default)
- App continues functioning with valid translation

**Example Runtime Log**:
```
⚠️ COMPLIANCE VIOLATION: Banned translation "NIV" detected. Resetting to WEB
```

## Legal Rationale

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

## Resources

- World English Bible: https://worldenglish.bible
- King James Version: https://www.kingjamesbibleonline.org
- American Standard Version: https://www.biblegateway.com/versions/American-Standard-Version-ASV-Bible
- Copyright information: https://www.copyright.gov/help/faq/faq-duration.html

## Maintenance

**This compliance system must be maintained as code evolves:**

1. **Never** add direct ElevenLabs calls to translations outside the registry
2. **Always** validate translation IDs before use
3. **Run tests** before merging any PR that touches:
   - Bible translation code
   - User preference handling
   - Verse/Scripture services
   - Data models containing translations

**If you see a compliance violation:**
1. DO NOT ignore it
2. DO NOT add the translation to the allowlist without verification
3. Fix the code to use an allowed translation
4. Verify tests pass

---

**Last Updated**: 2025-12-16
**Maintained By**: Bible PAL Development Team
