import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/bible_translation_registry.dart';
import 'package:bible_pal/models/user_preferences.dart';
import 'package:bible_pal/services/daily_bread_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DailyBreadService', () {
    late DailyBreadService service;

    setUp(() {
      service = DailyBreadService();
    });

    group('JSON Asset Parsing & Validation', () {
      test('CRITICAL: All verses must have WEB translation', () async {
        // Load the actual asset and verify WEB exists for all verses
        final jsonString = await rootBundle
            .loadString('assets/daily_bread/daily_bread_verses.json');
        final data = jsonDecode(jsonString) as Map<String, dynamic>;
        final verses = data['verses'] as List<dynamic>;

        expect(verses.isNotEmpty, true,
            reason: 'Asset must contain at least one verse');

        for (final verse in verses) {
          final id = verse['id'] as String;
          final text = verse['text'] as Map<String, dynamic>;

          expect(
            text.containsKey('WEB'),
            true,
            reason: 'Verse "$id" missing required WEB translation. '
                'WEB is the default fallback and must always be present.',
          );

          expect(
            (text['WEB'] as String).isNotEmpty,
            true,
            reason: 'Verse "$id" has empty WEB translation text.',
          );
        }
      });

      test('CRITICAL: All translation keys must be allowed translations',
          () async {
        final jsonString = await rootBundle
            .loadString('assets/daily_bread/daily_bread_verses.json');
        final data = jsonDecode(jsonString) as Map<String, dynamic>;
        final verses = data['verses'] as List<dynamic>;

        final allowedIds = BibleTranslationRegistry.allowedIds;

        for (final verse in verses) {
          final id = verse['id'] as String;
          final text = verse['text'] as Map<String, dynamic>;

          for (final translationKey in text.keys) {
            expect(
              allowedIds.contains(translationKey),
              true,
              reason: 'Verse "$id" contains unknown translation key '
                  '"$translationKey". Only allowed: $allowedIds',
            );
          }
        }
      });

      test('All verses must have valid structure', () async {
        final jsonString = await rootBundle
            .loadString('assets/daily_bread/daily_bread_verses.json');
        final data = jsonDecode(jsonString) as Map<String, dynamic>;
        final verses = data['verses'] as List<dynamic>;

        for (int i = 0; i < verses.length; i++) {
          final verse = verses[i] as Map<String, dynamic>;

          expect(verse.containsKey('id'), true,
              reason: 'Verse at index $i missing "id" field');
          expect(verse.containsKey('reference'), true,
              reason: 'Verse at index $i missing "reference" field');
          expect(verse.containsKey('text'), true,
              reason: 'Verse at index $i missing "text" field');

          expect(verse['id'], isA<String>(),
              reason: 'Verse at index $i: "id" must be a string');
          expect(verse['reference'], isA<String>(),
              reason: 'Verse at index $i: "reference" must be a string');
          expect(verse['text'], isA<Map>(),
              reason: 'Verse at index $i: "text" must be an object');
        }
      });

      test('Asset should have at least 120 verses', () async {
        final jsonString = await rootBundle
            .loadString('assets/daily_bread/daily_bread_verses.json');
        final data = jsonDecode(jsonString) as Map<String, dynamic>;
        final verses = data['verses'] as List<dynamic>;

        expect(
          verses.length >= 120,
          true,
          reason:
              'Asset should have at least 120 verses for variety, found ${verses.length}',
        );
      });

      test('CRITICAL: All verses must have all 5 translations', () async {
        final jsonString = await rootBundle
            .loadString('assets/daily_bread/daily_bread_verses.json');
        final data = jsonDecode(jsonString) as Map<String, dynamic>;
        final verses = data['verses'] as List<dynamic>;

        const requiredTranslations = ['WEB', 'KJV', 'ASV', 'YLT', 'DRA'];

        for (final verse in verses) {
          final id = verse['id'] as String;
          final reference = verse['reference'] as String;
          final text = verse['text'] as Map<String, dynamic>;

          for (final translation in requiredTranslations) {
            expect(
              text.containsKey(translation),
              true,
              reason:
                  'Verse "$id" ($reference) missing $translation translation.',
            );
            expect(
              (text[translation] as String).isNotEmpty,
              true,
              reason:
                  'Verse "$id" ($reference) has empty $translation translation.',
            );
          }
        }
      });
    });

    group('Deterministic Selection', () {
      test('Same date always returns same verse', () async {
        final prefs = UserPreferences(
          bibleTranslation: 'WEB',
          storytellingMode: 'creative',
        );

        final fixedDate = DateTime(2026, 6, 15); // Day 166 of year

        final result1 = await service.getVerseForDate(fixedDate, prefs);
        final result2 = await service.getVerseForDate(fixedDate, prefs);

        expect(result1.reference, result2.reference);
        expect(result1.verse, result2.verse);
      });

      test('Different dates return different verses (modulo verse count)',
          () async {
        final prefs = UserPreferences(
          bibleTranslation: 'WEB',
          storytellingMode: 'creative',
        );

        // Load verse count to ensure we test dates that map to different indices
        final jsonString = await rootBundle
            .loadString('assets/daily_bread/daily_bread_verses.json');
        final data = jsonDecode(jsonString) as Map<String, dynamic>;
        final verses = data['verses'] as List<dynamic>;
        final verseCount = verses.length;

        // Two consecutive days should give different verses (unless count is 1)
        if (verseCount > 1) {
          final date1 = DateTime(2026, 1, 1); // Day 1
          final date2 = DateTime(2026, 1, 2); // Day 2

          final result1 = await service.getVerseForDate(date1, prefs);
          final result2 = await service.getVerseForDate(date2, prefs);

          expect(result1.reference != result2.reference, true,
              reason:
                  'Consecutive days should return different verses when count > 1');
        }
      });

      test('Selection uses (dayOfYear - 1) modulo verse count formula',
          () async {
        final prefs = UserPreferences(
          bibleTranslation: 'WEB',
          storytellingMode: 'creative',
        );

        // Load verses to know what to expect
        final jsonString = await rootBundle
            .loadString('assets/daily_bread/daily_bread_verses.json');
        final data = jsonDecode(jsonString) as Map<String, dynamic>;
        final verses = data['verses'] as List<dynamic>;
        final verseCount = verses.length;

        // Jan 1 = day 1, so index = (1 - 1) % verseCount = 0 (first verse)
        final jan1 = DateTime(2026, 1, 1);
        final expectedIndex = (1 - 1) % verseCount; // = 0
        final expectedRef = verses[expectedIndex]['reference'] as String;

        final result = await service.getVerseForDate(jan1, prefs);
        expect(result.reference, expectedRef);
        expect(expectedIndex, 0, reason: 'Jan 1 should map to first verse');

        // Dec 31 (non-leap year 2026) = day 365, so index = (365 - 1) % verseCount
        final dec31 = DateTime(2026, 12, 31);
        final expectedIndexDec = (365 - 1) % verseCount;
        final expectedRefDec = verses[expectedIndexDec]['reference'] as String;

        final resultDec = await service.getVerseForDate(dec31, prefs);
        expect(resultDec.reference, expectedRefDec);
      });

      test('Leap year day 366 works correctly', () async {
        final prefs = UserPreferences(
          bibleTranslation: 'WEB',
          storytellingMode: 'creative',
        );

        // 2024 is a leap year, Dec 31 = day 366
        final dec31LeapYear = DateTime(2024, 12, 31);

        // Should not throw
        final result = await service.getVerseForDate(dec31LeapYear, prefs);
        expect(result.reference, isNotEmpty);
        expect(result.verse, isNotEmpty);
      });
    });

    group('Translation Selection', () {
      test('Returns verse in requested translation when available', () async {
        final prefsKJV = UserPreferences(
          bibleTranslation: 'KJV',
          storytellingMode: 'creative',
        );

        final prefsWEB = UserPreferences(
          bibleTranslation: 'WEB',
          storytellingMode: 'creative',
        );

        final date = DateTime(2026, 1, 1);

        final resultKJV = await service.getVerseForDate(date, prefsKJV);
        final resultWEB = await service.getVerseForDate(date, prefsWEB);

        // Same reference, different translation text
        expect(resultKJV.reference, resultWEB.reference);
        expect(resultKJV.translation, 'KJV');
        expect(resultWEB.translation, 'WEB');
        // Verse text should differ between translations (for most verses)
        // We don't assert inequality since some very short verses may match
      });

      test('All 5 allowed translations are available in asset', () async {
        final jsonString = await rootBundle
            .loadString('assets/daily_bread/daily_bread_verses.json');
        final data = jsonDecode(jsonString) as Map<String, dynamic>;
        final verses = data['verses'] as List<dynamic>;

        // Check that at least the first verse has all 5 translations
        final firstVerse = verses[0] as Map<String, dynamic>;
        final text = firstVerse['text'] as Map<String, dynamic>;

        for (final id in ['WEB', 'KJV', 'ASV', 'YLT', 'DRA']) {
          expect(
            text.containsKey(id),
            true,
            reason: 'First verse should have $id translation',
          );
        }
      });
    });

    group('Fallback to WEB', () {
      test('Falls back to WEB when requested translation is missing', () async {
        // Create a verse entry with only WEB translation
        final entry = DailyBreadEntry(
          id: 'test_001',
          reference: 'Test 1:1',
          text: {'WEB': 'This is the WEB text.'},
        );

        // Request KJV (which is missing)
        final text = entry.getText('KJV');

        expect(text, 'This is the WEB text.',
            reason: 'Should fall back to WEB when KJV is missing');
      });

      test('DailyBreadEntry.hasTranslation returns false for missing',
          () async {
        final entry = DailyBreadEntry(
          id: 'test_001',
          reference: 'Test 1:1',
          text: {'WEB': 'WEB text', 'KJV': 'KJV text'},
        );

        expect(entry.hasTranslation('WEB'), true);
        expect(entry.hasTranslation('KJV'), true);
        expect(entry.hasTranslation('ASV'), false);
        expect(entry.hasTranslation('YLT'), false);
      });

      test('Service returns WEB in translation field when fallback occurs',
          () async {
        // This tests that the DailyBread model correctly indicates fallback
        // We simulate by checking a verse with partial translations
        // Since our asset has all 5, we'll test the DailyBreadEntry directly
        final entry = DailyBreadEntry(
          id: 'partial',
          reference: 'Partial 1:1',
          text: {'WEB': 'WEB only text'},
        );

        expect(entry.hasTranslation('ASV'), false);
        expect(entry.getText('ASV'), 'WEB only text');
      });
    });

    group('Caching', () {
      test('Caches verses after first load', () async {
        final prefs = UserPreferences(
          bibleTranslation: 'WEB',
          storytellingMode: 'creative',
        );

        // First call loads from asset
        final result1 = await service.getDailyVerse(prefs);
        expect(result1.reference, isNotEmpty);

        // Second call should use cache (no way to directly verify,
        // but should not throw)
        final result2 = await service.getDailyVerse(prefs);
        expect(result2.reference, isNotEmpty);
      });

      test('clearCache() allows reload', () async {
        final prefs = UserPreferences(
          bibleTranslation: 'WEB',
          storytellingMode: 'creative',
        );

        await service.getDailyVerse(prefs);
        service.clearCache();

        // Should reload successfully
        final result = await service.getDailyVerse(prefs);
        expect(result.reference, isNotEmpty);
      });
    });
  });
}
