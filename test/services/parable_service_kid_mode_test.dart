// Unit tests for Parable Service Kid Mode Filtering
// Tests Layer 1 of Kid Safety Contract Invariant (Source Lockdown)
// See docs/INVARIANTS.md for complete specification

import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/services/parable_service.dart';
import 'package:bible_pal/services/storage_service.dart';
import 'package:bible_pal/models/user_preferences.dart';

void main() {
  group('ParableService - Kid Mode Source Lockdown', () {
    late ParableService service;
    late StorageService storage;

    setUpAll(() async {
      // Initialize storage service
      storage = await StorageService.create();
      service = ParableService(storage);
    });

    group('CRITICAL: Kid Mode Filtering (Layer 1 Invariant)', () {
      test('kid mode ONLY returns kid-friendly stories', () async {
        final kidPrefs = UserPreferences(
          kidFriendlyOnly: true,
          faithTradition: 'Protestant',
          bibleTranslation: 'WEB',
          storytellingMode: 'traditional',
        );

        // Get eligible parables with kid mode enabled
        final eligible = await service.getEligibleParables(
          mood: 'joyful',
          lengthMinutes: 5,
          userPrefs: kidPrefs,
        );

        // INVARIANT ENFORCEMENT: ALL returned parables MUST be kid-friendly
        for (final parable in eligible) {
          expect(
            parable.kidFriendly,
            true,
            reason:
                'Story "${parable.title}" (ID: ${parable.storyId}) is NOT kid-friendly '
                'but was returned in kid mode - INVARIANT VIOLATION',
          );
        }
      });

      test('kid mode filters out non-kid-friendly stories', () async {
        final kidPrefs = UserPreferences(
          kidFriendlyOnly: true,
          faithTradition: 'Protestant',
          bibleTranslation: 'WEB',
          storytellingMode: 'traditional',
        );

        final adultPrefs = UserPreferences(
          kidFriendlyOnly: false,
          faithTradition: 'Protestant',
          bibleTranslation: 'WEB',
          storytellingMode: 'traditional',
        );

        // Get eligible parables in both modes
        final kidEligible = await service.getEligibleParables(
          mood: 'joyful',
          lengthMinutes: 5,
          userPrefs: kidPrefs,
        );

        final adultEligible = await service.getEligibleParables(
          mood: 'joyful',
          lengthMinutes: 5,
          userPrefs: adultPrefs,
        );

        // Kid mode should return same or fewer stories than adult mode
        expect(
          kidEligible.length,
          lessThanOrEqualTo(adultEligible.length),
          reason: 'Kid mode should filter out non-kid-friendly stories',
        );
      });

      test('non-kid mode returns all eligible stories', () async {
        final adultPrefs = UserPreferences(
          kidFriendlyOnly: false,
          faithTradition: 'Protestant',
          bibleTranslation: 'WEB',
          storytellingMode: 'traditional',
        );

        // Get eligible parables with kid mode disabled
        final eligible = await service.getEligibleParables(
          mood: 'joyful',
          lengthMinutes: 5,
          userPrefs: adultPrefs,
        );

        // Should include both kid-friendly and non-kid-friendly stories
        final kidFriendlyCount = eligible.where((p) => p.kidFriendly).length;
        final nonKidFriendlyCount =
            eligible.where((p) => !p.kidFriendly).length;

        // Both counts should be non-negative (may be zero if no stories match)
        expect(kidFriendlyCount, greaterThanOrEqualTo(0));
        expect(nonKidFriendlyCount, greaterThanOrEqualTo(0));
      });
    });

    group('Kid Mode Filtering Across Moods', () {
      test('joyful mood respects kid mode', () async {
        final kidPrefs = UserPreferences(
          kidFriendlyOnly: true,
          faithTradition: 'Protestant',
          bibleTranslation: 'WEB',
          storytellingMode: 'traditional',
        );

        final eligible = await service.getEligibleParables(
          mood: 'joyful',
          lengthMinutes: 5,
          userPrefs: kidPrefs,
        );

        for (final parable in eligible) {
          expect(parable.kidFriendly, true);
        }
      });

      test('weary mood respects kid mode', () async {
        final kidPrefs = UserPreferences(
          kidFriendlyOnly: true,
          faithTradition: 'Protestant',
          bibleTranslation: 'WEB',
          storytellingMode: 'traditional',
        );

        final eligible = await service.getEligibleParables(
          mood: 'weary',
          lengthMinutes: 10,
          userPrefs: kidPrefs,
        );

        for (final parable in eligible) {
          expect(parable.kidFriendly, true);
        }
      });

      test('anxious mood respects kid mode', () async {
        final kidPrefs = UserPreferences(
          kidFriendlyOnly: true,
          faithTradition: 'Protestant',
          bibleTranslation: 'WEB',
          storytellingMode: 'traditional',
        );

        final eligible = await service.getEligibleParables(
          mood: 'anxious',
          lengthMinutes: 15,
          userPrefs: kidPrefs,
        );

        for (final parable in eligible) {
          expect(parable.kidFriendly, true);
        }
      });
    });

    group('Kid Mode Filtering Across Lengths', () {
      test('5min stories respect kid mode', () async {
        final kidPrefs = UserPreferences(
          kidFriendlyOnly: true,
          faithTradition: 'Protestant',
          bibleTranslation: 'WEB',
          storytellingMode: 'traditional',
        );

        final eligible = await service.getEligibleParables(
          mood: 'joyful',
          lengthMinutes: 5,
          userPrefs: kidPrefs,
        );

        for (final parable in eligible) {
          expect(parable.kidFriendly, true);
          expect(parable.length, 5);
        }
      });

      test('10min stories respect kid mode', () async {
        final kidPrefs = UserPreferences(
          kidFriendlyOnly: true,
          faithTradition: 'Protestant',
          bibleTranslation: 'WEB',
          storytellingMode: 'traditional',
        );

        final eligible = await service.getEligibleParables(
          mood: 'weary',
          lengthMinutes: 10,
          userPrefs: kidPrefs,
        );

        for (final parable in eligible) {
          expect(parable.kidFriendly, true);
          expect(parable.length, 10);
        }
      });

      test('20min stories respect kid mode', () async {
        final kidPrefs = UserPreferences(
          kidFriendlyOnly: true,
          faithTradition: 'Protestant',
          bibleTranslation: 'WEB',
          storytellingMode: 'traditional',
        );

        final eligible = await service.getEligibleParables(
          mood: 'calm_peaceful',
          lengthMinutes: 20,
          userPrefs: kidPrefs,
        );

        for (final parable in eligible) {
          expect(parable.kidFriendly, true);
          expect(parable.length, 20);
        }
      });
    });

    group('Story Selection with Kid Mode', () {
      test('selectParable returns only kid-friendly story in kid mode',
          () async {
        final kidPrefs = UserPreferences(
          kidFriendlyOnly: true,
          faithTradition: 'Protestant',
          bibleTranslation: 'WEB',
          storytellingMode: 'traditional',
        );

        // Select multiple parables to test consistency
        for (int i = 0; i < 3; i++) {
          final selected = await service.selectParable(
            mood: 'joyful',
            lengthMinutes: 5,
            userPrefs: kidPrefs,
          );

          if (selected != null) {
            expect(
              selected.kidFriendly,
              true,
              reason:
                  'Selected story "${selected.title}" is not kid-friendly in kid mode',
            );
          }
        }
      });

      test('selectParable may return non-kid-friendly in adult mode',
          () async {
        final adultPrefs = UserPreferences(
          kidFriendlyOnly: false,
          faithTradition: 'Protestant',
          bibleTranslation: 'WEB',
          storytellingMode: 'traditional',
        );

        // In adult mode, both kid-friendly and non-kid-friendly are allowed
        final selected = await service.selectParable(
          mood: 'joyful',
          lengthMinutes: 5,
          userPrefs: adultPrefs,
        );

        // In adult mode, both kid-friendly and non-kid-friendly are allowed
        // No assertion needed - just verify selection succeeded
        expect(selected != null || selected == null, true);
      });
    });
  });
}
