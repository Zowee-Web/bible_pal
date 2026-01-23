import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/services/verse_service.dart';
import 'package:bible_pal/core/bible_translation_registry.dart';

/// SCRIPTURE LICENSING COMPLIANCE TESTS
/// These tests ensure Bible PAL NEVER uses copyrighted Bible translations
///
/// ABSOLUTE RULE: Only translations from BibleTranslationRegistry.allowedTranslations
/// are permitted. See lib/core/bible_translation_registry.dart for the canonical list.
///
/// NEVER ALLOWED: NIV, ESV, NLT, CSB, NASB, or any copyrighted translation
void main() {
  group('VerseService - Scripture Licensing Compliance', () {
    late VerseService verseService;

    setUp(() {
      verseService = VerseService();
    });

    test('Returns non-empty verse for joyful mood', () {
      final verse = verseService.getVerseForMood('joyful');

      expect(verse, isNotNull);
      expect(verse.reference, isNotEmpty);
      expect(verse.text, isNotEmpty);
      expect(verse.context, isNotEmpty);
      expect(verse.translation, equals('WEB'));
    });

    test('Returns non-empty verse for weary mood', () {
      final verse = verseService.getVerseForMood('weary');

      expect(verse, isNotNull);
      expect(verse.reference, isNotEmpty);
      expect(verse.text, isNotEmpty);
      expect(verse.context, isNotEmpty);
      expect(verse.translation, equals('WEB'));
    });

    test('Returns non-empty verse for anxious mood', () {
      final verse = verseService.getVerseForMood('anxious');

      expect(verse, isNotNull);
      expect(verse.reference, isNotEmpty);
      expect(verse.text, isNotEmpty);
      expect(verse.context, isNotEmpty);
      expect(verse.translation, equals('WEB'));
    });

    test('Returns non-empty verse for hurting mood', () {
      final verse = verseService.getVerseForMood('hurting');

      expect(verse, isNotNull);
      expect(verse.reference, isNotEmpty);
      expect(verse.text, isNotEmpty);
      expect(verse.context, isNotEmpty);
      expect(verse.translation, equals('WEB'));
    });

    test('Returns non-empty verse for neutral mood', () {
      final verse = verseService.getVerseForMood('neutral');

      expect(verse, isNotNull);
      expect(verse.reference, isNotEmpty);
      expect(verse.text, isNotEmpty);
      expect(verse.context, isNotEmpty);
      expect(verse.translation, equals('WEB'));
    });

    group('ESV Translation Fingerprint Detection (MUST FAIL IF FOUND)', () {
      // These are ESV-specific phrasings that should NOT appear in WEB verses
      // If any of these are found, it means copyrighted ESV text leaked into the code

      test('GUARD: No ESV fingerprint "heavy laden" found', () {
        final joyfulVerses = [
          verseService.getVerseForMood('joyful'),
          verseService.getVerseForMood('weary'),
          verseService.getVerseForMood('anxious'),
          verseService.getVerseForMood('hurting'),
          verseService.getVerseForMood('neutral'),
        ];

        for (final verse in joyfulVerses) {
          expect(
            verse.text.toLowerCase().contains('heavy laden'),
            isFalse,
            reason:
                'Found ESV fingerprint "heavy laden" in ${verse.reference}. '
                'This is a COMPLIANCE VIOLATION - copyrighted ESV text detected!',
          );
        }
      });

      test('GUARD: No ESV fingerprint "lowly in heart" found', () {
        final verses = [
          verseService.getVerseForMood('joyful'),
          verseService.getVerseForMood('weary'),
          verseService.getVerseForMood('anxious'),
          verseService.getVerseForMood('hurting'),
          verseService.getVerseForMood('neutral'),
        ];

        for (final verse in verses) {
          expect(
            verse.text.toLowerCase().contains('lowly in heart'),
            isFalse,
            reason:
                'Found ESV fingerprint "lowly in heart" in ${verse.reference}. '
                'This is a COMPLIANCE VIOLATION - copyrighted ESV text detected!',
          );
        }
      });

      test('GUARD: No ESV fingerprint "conviction of things" found', () {
        final verses = [
          verseService.getVerseForMood('joyful'),
          verseService.getVerseForMood('weary'),
          verseService.getVerseForMood('anxious'),
          verseService.getVerseForMood('hurting'),
          verseService.getVerseForMood('neutral'),
        ];

        for (final verse in verses) {
          expect(
            verse.text.toLowerCase().contains('conviction of things'),
            isFalse,
            reason:
                'Found ESV fingerprint "conviction of things" in ${verse.reference}. '
                'This is a COMPLIANCE VIOLATION - copyrighted ESV text detected!',
          );
        }
      });
    });

    group('WEB Translation Verification', () {
      test('All verses use WEB as translation', () {
        final allMoods = ['joyful', 'weary', 'anxious', 'hurting', 'neutral'];

        for (final mood in allMoods) {
          final verse = verseService.getVerseForMood(mood);
          expect(
            verse.translation,
            equals('WEB'),
            reason:
                'Verse for mood "$mood" must use WEB translation (public domain)',
          );
        }
      });

      test(
          'WEB translation confirmed (no banned fingerprints + allowlist check)',
          () {
        // Deterministic test: Verify WEB usage by checking:
        // 1. Translation field is in allowlist
        // 2. No banned fingerprints appear (using registry scanner)
        final allMoods = ['joyful', 'weary', 'anxious', 'hurting', 'neutral'];

        for (final mood in allMoods) {
          final verse = verseService.getVerseForMood(mood);

          // Check translation is in allowlist
          expect(
            BibleTranslationRegistry.isAllowed(verse.translation),
            isTrue,
            reason:
                'Verse ${verse.reference} for mood "$mood" uses translation "${verse.translation}" '
                'which is not in the allowlist!',
          );

          // Check translation is NOT banned
          expect(
            BibleTranslationRegistry.isBanned(verse.translation),
            isFalse,
            reason:
                'Verse ${verse.reference} for mood "$mood" uses BANNED translation "${verse.translation}"!',
          );

          // Scan for banned fingerprints using registry
          final detectedFingerprints =
              BibleTranslationRegistry.scanForBannedFingerprints(verse.text);
          expect(
            detectedFingerprints,
            isEmpty,
            reason:
                'Found banned fingerprints $detectedFingerprints in ${verse.reference} for mood "$mood". '
                'This indicates copyrighted translation text!',
          );
        }
      });
    });
  });
}
