// Verifies the Kids-mode tap-a-feeling cards (SPEC Feature 51.3).
//
// Each card submits a fixed canonical phrase as userText. These tests assert
// the engine contract the design relies on:
//   1. mood  — MoodService.detectMood(phrase) yields the intended mood and
//      never the low-confidence no-match default (the LOCKED design rule).
//   2. tags  — RelatabilityMatcher.extractTags(phrase) yields the situation
//      tags that bias ranking.
//   3. reach — under kidFriendlyOnly, the kid candidate pool (exact mood +
//      kid bridges) ranked by relatability puts the intended kid story first.
//   4. fallback — kidFallbackMood maps the no-match default to joyful for kids
//      while leaving real moods (and the adult path) untouched.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_pal/core/kid_feeling_cards.dart';
import 'package:bible_pal/core/mood_similarity.dart';
import 'package:bible_pal/core/story_length_bucket.dart';
import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/models/user_preferences.dart';
import 'package:bible_pal/services/mood_service.dart';
import 'package:bible_pal/services/parable_service.dart';
import 'package:bible_pal/services/relatability_matcher.dart';
import 'package:bible_pal/services/storage_service.dart';

/// Look up a card by its label for readable test cases.
KidFeelingCard _card(String label) =>
    kidFeelingCards.firstWhere((c) => c.label == label);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mood = MoodService();
  final matcher = RelatabilityMatcher();

  group('51.3 card → mood (LOCKED design rule: never the no-match default)', () {
    const expected = {
      "I'm scared": 'anxious',
      'I feel lonely': 'hurting',
      'I got in trouble': 'hurting',
      'I feel little': 'anxious',
      'I miss someone': 'hurting',
      "I'm happy": 'joyful',
      "I'm thankful": 'grateful',
      "I'm tired": 'weary',
    };

    for (final entry in expected.entries) {
      test('${entry.key} → ${entry.value}', () {
        final card = _card(entry.key);
        final result = mood.detectMood(card.canonicalPhrase);
        expect(result.mood, entry.value);
        // Design rule: a real keyword match, not the weary@0.4 default.
        expect(result.confidenceScore, greaterThan(0.4),
            reason: 'Phrase "${card.canonicalPhrase}" fell to the no-match '
                'default — it must contain a MoodService keyword.');
      });
    }
  });

  group('51.3 card → relatability tags', () {
    final expected = {
      "I'm scared": {'anxious'},
      'I feel lonely': {'lonely', 'rejection'},
      'I got in trouble': {'in_trouble'},
      'I feel little': {'anxious', 'feeling_small'},
      'I miss someone': {'lonely', 'missing_someone'},
      "I'm happy": <String>{},
      "I'm thankful": {'grateful'},
      "I'm tired": {'overwhelmed'},
    };

    for (final entry in expected.entries) {
      test('${entry.key} → ${entry.value}', () {
        final card = _card(entry.key);
        expect(matcher.extractTags(card.canonicalPhrase), entry.value);
      });
    }
  });

  group('51.3 kidFallbackMood', () {
    test('no-match default (weary @ 0.4) → joyful', () {
      expect(
        kidFallbackMood(detectedMood: 'weary', confidenceScore: 0.4),
        'joyful',
      );
    });

    test('real weary (@ 0.75) is preserved — "I\'m tired" still works', () {
      expect(
        kidFallbackMood(detectedMood: 'weary', confidenceScore: 0.75),
        'weary',
      );
    });

    test('other detected moods pass through unchanged', () {
      for (final m in ['anxious', 'hurting', 'grateful', 'joyful']) {
        expect(kidFallbackMood(detectedMood: m, confidenceScore: 0.8), m);
      }
    });
  });

  group('51.3 card reaches the intended kid story (kidFriendlyOnly)', () {
    late ParableService service;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      final storage = await StorageService.create();
      service = ParableService(storage, null, true); // test mode
    });

    final kidPrefs = UserPreferences(
      kidFriendlyOnly: true,
      bibleTranslation: 'WEB',
      storytellingMode: 'traditional',
    );

    /// Rebuild the kid candidate pool exactly as selectParable does
    /// (exact mood + kid bridges), then rank deterministically by relatability.
    Future<List<Parable>> rankedPool(String detectedMood, String phrase) async {
      final pool = <String, Parable>{};
      for (final m in [
        detectedMood,
        ...MoodSimilarity.getSimilar(detectedMood, kidMode: true),
      ]) {
        final eligible = await service.getEligibleParables(
          mood: m,
          lengthBucket: StoryLengthBucket.short,
          userPrefs: kidPrefs,
        );
        for (final p in eligible) {
          pool[p.storyId] = p;
        }
      }
      return matcher.rankByRelatability(phrase, pool.values.toList());
    }

    // label → expected top kid story title (deterministic: relatability score,
    // then storyId-ascending tie-break).
    final cases = {
      "I'm scared": 'Jesus Calms the Storm',
      'I feel lonely': 'The Lost Sheep',
      'I got in trouble': 'The Loving Father',
      'I feel little': 'The Walls of Jericho',
      'I miss someone': 'The Lost Sheep',
    };

    for (final entry in cases.entries) {
      test('${entry.key} → "${entry.value}"', () async {
        final card = _card(entry.key);
        final detected = mood.detectMood(card.canonicalPhrase).mood;
        final ranked = await rankedPool(detected, card.canonicalPhrase);
        expect(ranked, isNotEmpty);
        // Every candidate is kid-safe (Kid Safety Contract Invariant).
        expect(ranked.every((p) => p.kidFriendly), isTrue);
        expect(ranked.first.title, entry.value);
      });
    }
  });
}
