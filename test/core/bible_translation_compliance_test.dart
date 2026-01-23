import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/bible_translation_registry.dart';
import 'package:bible_pal/models/user_preferences.dart';
import 'package:bible_pal/models/daily_bread.dart';
import 'package:bible_pal/services/verse_service.dart';

/// BIBLE TRANSLATION COMPLIANCE TESTS
///
/// HARD INVARIANT: Bible PAL must NEVER use or offer any non-open-source /
/// non-public-domain Bible translations.
///
/// These tests enforce the allowlist-only system at multiple layers:
/// 1. Registry validation
/// 2. Model-level runtime guards
/// 3. Text fingerprint detection
/// 4. Build-time enforcement
///
/// IF ANY OF THESE TESTS FAIL, THE BUILD MUST FAIL.

void main() {
  group('BibleTranslationRegistry - Allowlist Enforcement', () {
    test('Registry contains only allowed translations', () {
      // Verify that the allowlist is not empty
      expect(BibleTranslationRegistry.allowedTranslations, isNotEmpty);

      // Verify all allowed translations have required metadata
      for (final translation in BibleTranslationRegistry.allowedTranslations) {
        expect(translation.id, isNotEmpty,
            reason: 'Translation must have an ID');
        expect(translation.id, equals(translation.id.toUpperCase()),
            reason: 'Translation ID must be UPPERCASE');
        expect(translation.name, isNotEmpty,
            reason: 'Translation must have a name');

        // Check structured license type (not string matching)
        expect(
          translation.licenseType == LicenseType.publicDomain ||
              translation.licenseType == LicenseType.openLicense,
          isTrue,
          reason:
              'Translation must have valid LicenseType (publicDomain or openLicense)',
        );
        expect(translation.licenseName, isNotEmpty,
            reason: 'Translation must have a license name');

        expect(translation.year, greaterThan(0),
            reason: 'Translation must have a valid year');
        expect(translation.url, isNotEmpty,
            reason: 'Translation must have a source URL');
      }
    });

    test('Default translation is in allowlist', () {
      expect(
        BibleTranslationRegistry.isAllowed(
            BibleTranslationRegistry.defaultTranslationId),
        isTrue,
        reason: 'Default translation must be in the allowlist',
      );
    });

    test('Banned translations list is comprehensive', () {
      final bannedIds = BibleTranslationRegistry.bannedIds;

      // Verify critical banned translations are present
      expect(bannedIds, contains('NIV'),
          reason: 'NIV must be explicitly banned');
      expect(bannedIds, contains('ESV'),
          reason: 'ESV must be explicitly banned');
      expect(bannedIds, contains('NRSV'),
          reason: 'NRSV must be explicitly banned');
      expect(bannedIds, contains('NLT'),
          reason: 'NLT must be explicitly banned');
      expect(bannedIds, contains('NASB'),
          reason: 'NASB must be explicitly banned');
      expect(bannedIds, contains('CSB'),
          reason: 'CSB must be explicitly banned');
    });

    test('HARD INVARIANT: No overlap between allowed and banned', () {
      final allowed = BibleTranslationRegistry.allowedIds;
      final banned = BibleTranslationRegistry.bannedIds;

      for (final id in allowed) {
        expect(
          banned.contains(id),
          isFalse,
          reason: 'Translation "$id" cannot be both allowed AND banned!',
        );
      }
    });
  });

  group('Translation Validation - Runtime Guards', () {
    test('isAllowed() correctly identifies allowed translations', () {
      expect(BibleTranslationRegistry.isAllowed('WEB'), isTrue);
      expect(BibleTranslationRegistry.isAllowed('KJV'), isTrue);
      expect(BibleTranslationRegistry.isAllowed('ASV'), isTrue);
    });

    test('isBanned() correctly identifies banned translations', () {
      expect(BibleTranslationRegistry.isBanned('NIV'), isTrue);
      expect(BibleTranslationRegistry.isBanned('ESV'), isTrue);
      expect(BibleTranslationRegistry.isBanned('NRSV'), isTrue);
      expect(BibleTranslationRegistry.isBanned('NLT'), isTrue);
    });

    test('CRITICAL: validateAndSanitize() rejects banned translations', () {
      // Attempt to use banned translations - MUST be reset to default
      expect(
          BibleTranslationRegistry.validateAndSanitize('NIV'), equals('WEB'));
      expect(
          BibleTranslationRegistry.validateAndSanitize('ESV'), equals('WEB'));
      expect(
          BibleTranslationRegistry.validateAndSanitize('NRSV'), equals('WEB'));
      expect(
          BibleTranslationRegistry.validateAndSanitize('NLT'), equals('WEB'));
      expect(
          BibleTranslationRegistry.validateAndSanitize('NASB'), equals('WEB'));
      expect(
          BibleTranslationRegistry.validateAndSanitize('CSB'), equals('WEB'));
    });

    test('validateAndSanitize() accepts allowed translations', () {
      expect(
          BibleTranslationRegistry.validateAndSanitize('WEB'), equals('WEB'));
      expect(
          BibleTranslationRegistry.validateAndSanitize('KJV'), equals('KJV'));
      expect(
          BibleTranslationRegistry.validateAndSanitize('ASV'), equals('ASV'));
    });

    test('validateAndSanitize() resets unknown translations to default', () {
      expect(BibleTranslationRegistry.validateAndSanitize('UNKNOWN'),
          equals('WEB'));
      expect(BibleTranslationRegistry.validateAndSanitize(''), equals('WEB'));
      expect(
          BibleTranslationRegistry.validateAndSanitize('FAKE'), equals('WEB'));
    });
  });

  group('UserPreferences - Runtime Guard Enforcement', () {
    test('fromJson() blocks banned translations', () {
      // Attempt to load user preferences with banned translation
      final prefs = UserPreferences.fromJson({
        'bibleTranslation': 'NIV', // BANNED
        'storytellingMode': 'creative',
      });

      // MUST be sanitized to default
      expect(
        prefs.bibleTranslation,
        equals('WEB'),
        reason: 'Banned translation NIV must be reset to WEB',
      );
    });

    test('fromJson() allows valid translations', () {
      final prefs = UserPreferences.fromJson({
        'bibleTranslation': 'KJV',
        'storytellingMode': 'creative',
      });

      expect(prefs.bibleTranslation, equals('KJV'));
    });

    test('copyWith() blocks banned translations', () {
      final originalPrefs = UserPreferences.defaults();

      // Attempt to update with banned translation
      final updatedPrefs = originalPrefs.copyWith(
        bibleTranslation: 'ESV', // BANNED
      );

      // MUST be sanitized to default
      expect(
        updatedPrefs.bibleTranslation,
        equals('WEB'),
        reason: 'Banned translation ESV must be reset to WEB',
      );
    });
  });

  group('DailyBread - Runtime Guard Enforcement', () {
    test('fromJson() blocks banned translations', () {
      final dailyBread = DailyBread.fromJson({
        'verse': 'For God so loved the world',
        'reference': 'John 3:16',
        'translation': 'NIV', // BANNED
        'date': '2025-01-01T00:00:00.000Z',
      });

      // MUST be sanitized to default
      expect(
        dailyBread.translation,
        equals('WEB'),
        reason: 'Banned translation NIV must be reset to WEB',
      );
    });

    test('fromJson() allows valid translations', () {
      final dailyBread = DailyBread.fromJson({
        'verse': 'For God so loved the world',
        'reference': 'John 3:16',
        'translation': 'WEB',
        'date': '2025-01-01T00:00:00.000Z',
      });

      expect(dailyBread.translation, equals('WEB'));
    });
  });

  group('Fingerprint Detection - Text Scanning', () {
    test('scanForBannedFingerprints() detects ESV phrases', () {
      const esvText = 'Come to me, all who are heavy laden';
      final detected =
          BibleTranslationRegistry.scanForBannedFingerprints(esvText);

      expect(
        detected,
        contains('heavy laden'),
        reason: 'ESV fingerprint "heavy laden" must be detected',
      );
    });

    test('scanForBannedFingerprints() returns empty for WEB text', () {
      const webText = 'Come to me, all you who labor and are heavily burdened';
      final detected =
          BibleTranslationRegistry.scanForBannedFingerprints(webText);

      expect(
        detected,
        isEmpty,
        reason: 'WEB text should not trigger any fingerprint matches',
      );
    });

    test('CRITICAL: VerseService contains no banned fingerprints', () {
      final verseService = VerseService();
      final allMoods = ['joyful', 'weary', 'anxious', 'hurting', 'neutral'];

      // Scan all verses across all moods
      for (final mood in allMoods) {
        final verse = verseService.getVerseForMood(mood);

        final detectedFingerprints =
            BibleTranslationRegistry.scanForBannedFingerprints(verse.text);

        expect(
          detectedFingerprints,
          isEmpty,
          reason:
              'Verse ${verse.reference} for mood "$mood" contains banned fingerprints: $detectedFingerprints. '
              'This indicates copyrighted translation text!',
        );
      }
    });
  });

  group('BUILD-FAILING GUARD: Banned Translation Detection', () {
    test('CRITICAL: No "NIV" string literal in UserPreferences model', () {
      // This test would ideally scan the actual source code
      // For now, we verify the model only accepts allowed translations
      final testCases = ['NIV', 'ESV', 'NRSV', 'NLT', 'NASB', 'CSB'];

      for (final banned in testCases) {
        final prefs = UserPreferences.fromJson({
          'bibleTranslation': banned,
        });

        expect(
          prefs.bibleTranslation,
          isNot(equals(banned)),
          reason:
              'UserPreferences must NEVER contain banned translation "$banned"',
        );
      }
    });

    test('CRITICAL: All VerseService verses use WEB translation', () {
      final verseService = VerseService();
      final allMoods = ['joyful', 'weary', 'anxious', 'hurting', 'neutral'];

      for (final mood in allMoods) {
        final verse = verseService.getVerseForMood(mood);

        expect(
          verse.translation,
          equals('WEB'),
          reason: 'All verses must use WEB translation (public domain)',
        );

        expect(
          BibleTranslationRegistry.isAllowed(verse.translation),
          isTrue,
          reason:
              'Verse translation "${verse.translation}" must be in allowlist',
        );
      }
    });

    test('CRITICAL: VerseService contains no ESV fingerprints', () {
      final verseService = VerseService();
      final allMoods = ['joyful', 'weary', 'anxious', 'hurting', 'neutral'];

      // ESV-specific phrasings that should NOT appear
      const esvFingerprints = [
        'heavy laden',
        'lowly in heart',
        'conviction of things',
      ];

      for (final mood in allMoods) {
        final verse = verseService.getVerseForMood(mood);
        final lowerText = verse.text.toLowerCase();

        for (final fingerprint in esvFingerprints) {
          expect(
            lowerText.contains(fingerprint.toLowerCase()),
            isFalse,
            reason:
                'Found ESV fingerprint "$fingerprint" in ${verse.reference}. '
                'This is a COMPLIANCE VIOLATION - copyrighted ESV text detected!',
          );
        }
      }
    });
  });

  group('Edge Cases and Data Integrity', () {
    test('Empty translation string defaults to WEB', () {
      expect(BibleTranslationRegistry.validateAndSanitize(''), equals('WEB'));
    });

    test('Normalization: Case sensitivity does not bypass validation', () {
      // Try various casings of banned translations - all should be normalized and blocked
      expect(
          BibleTranslationRegistry.validateAndSanitize('niv'), equals('WEB'));
      expect(
          BibleTranslationRegistry.validateAndSanitize('Niv'), equals('WEB'));
      expect(
          BibleTranslationRegistry.validateAndSanitize('esv'), equals('WEB'));
      expect(
          BibleTranslationRegistry.validateAndSanitize('Esv'), equals('WEB'));
    });

    test('Normalization: Whitespace does not bypass validation', () {
      // Whitespace should be trimmed before checking
      expect(
          BibleTranslationRegistry.validateAndSanitize(' NIV '), equals('WEB'));
      expect(BibleTranslationRegistry.validateAndSanitize('\tESV\n'),
          equals('WEB'));
      expect(BibleTranslationRegistry.validateAndSanitize('  nlt  '),
          equals('WEB'));
    });

    test('Normalization: Allowed translations are normalized to uppercase', () {
      // Lowercase allowed translations should be normalized and accepted
      expect(
          BibleTranslationRegistry.validateAndSanitize('web'), equals('WEB'));
      expect(
          BibleTranslationRegistry.validateAndSanitize('kjv'), equals('KJV'));
      expect(
          BibleTranslationRegistry.validateAndSanitize(' asv '), equals('ASV'));
    });

    test('UserPreferences.defaults() uses allowed translation', () {
      final defaults = UserPreferences.defaults();
      expect(BibleTranslationRegistry.isAllowed(defaults.bibleTranslation),
          isTrue);
      expect(defaults.bibleTranslation, equals('WEB'));
    });
  });
}
