// Tests for the kid-ONLY mood bridges (MoodSimilarity.getSimilar kidMode).
//
// A scared child (anxious) or a sorry child (hurting) must be able to REACH the
// "triumphant" kid stories (Fiery Furnace = brave_courage, Loving Father =
// grateful) that the adult similarity map deliberately strands. The bridges open
// those paths for kids ONLY — adult selection (kidMode=false) is unchanged.

import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/mood_expansion_engine.dart';
import 'package:bible_pal/core/mood_similarity.dart';
import 'package:bible_pal/models/parable.dart';

Parable _p(String id, String mood) => Parable(
      storyId: id,
      title: 'Story $id',
      mood: mood,
      storyLength: 'short',
      storytellingMode: 'creative',
      kidFriendly: true,
    );

void main() {
  group('MoodSimilarity kid bridges', () {
    test('adult map is unchanged (kidMode defaults false)', () {
      expect(MoodSimilarity.getSimilar('anxious'),
          ['calm_peaceful', 'encouraging', 'weary']);
      expect(MoodSimilarity.getSimilar('hurting'),
          ['weary', 'encouraging', 'calm_peaceful']);
      // The triumphant moods are NOT reachable from distress for adults.
      expect(MoodSimilarity.getSimilar('anxious').contains('brave_courage'),
          isFalse);
      expect(MoodSimilarity.getSimilar('hurting').contains('grateful'), isFalse);
    });

    test('kidMode bridges anxious -> brave_courage (base preserved first)', () {
      final r = MoodSimilarity.getSimilar('anxious', kidMode: true);
      expect(r.take(3).toList(), ['calm_peaceful', 'encouraging', 'weary']);
      expect(r.contains('brave_courage'), isTrue);
    });

    test('kidMode bridges hurting -> brave_courage + grateful', () {
      final r = MoodSimilarity.getSimilar('hurting', kidMode: true);
      expect(r.contains('brave_courage'), isTrue);
      expect(r.contains('grateful'), isTrue);
    });

    test('kidMode no-ops for a mood without a bridge', () {
      expect(MoodSimilarity.getSimilar('joyful', kidMode: true),
          MoodSimilarity.getSimilar('joyful'));
    });

    test('no duplicate when a bridge mood is already in the base map', () {
      final r = MoodSimilarity.getSimilar('anxious', kidMode: true);
      expect(r.where((m) => m == 'brave_courage').length, 1);
    });
  });

  group('Engine: bridge reachability', () {
    const engine = MoodExpansionEngine();

    test('scared kid reaches a brave story ONLY in kidMode', () {
      final pool = [_p('furnace', 'brave_courage')];

      // Adult: anxious does not reach brave_courage -> nothing servable.
      final adult = engine.select(
        selectedMood: 'anxious',
        pool: pool,
        playedStoryIds: const {},
      );
      expect(adult, isNull);

      // Kid: bridge opens brave_courage -> served as a similar-mood (tier 2).
      final kid = engine.select(
        selectedMood: 'anxious',
        pool: pool,
        playedStoryIds: const {},
        kidMode: true,
      );
      expect(kid, isNotNull);
      expect(kid!.parable.storyId, 'furnace');
      expect(kid.servedMood, 'brave_courage');
      expect(kid.tier, 2); // similar-mood tier, never exact
    });

    test('exact-mood gentle story still serves BEFORE a bridged brave story',
        () {
      final pool = [
        _p('storm', 'anxious'), // exact
        _p('furnace', 'brave_courage'), // bridged (kid)
      ];
      final kid = engine.select(
        selectedMood: 'anxious',
        pool: pool,
        playedStoryIds: const {},
        kidMode: true,
      );
      expect(kid!.parable.storyId, 'storm'); // tier 1 exact wins
      expect(kid.tier, 1);
    });
  });
}
