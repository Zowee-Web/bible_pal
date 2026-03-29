// Tests for SPEC.md 15b: Mood Expansion Serving Rule
// and INVARIANTS.md: Mood Expansion Serving Invariant
//
// Tests the MoodExpansionEngine directly with controlled test data.
// Each test is named after the spec clause it enforces.

import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/mood_expansion_engine.dart';
import 'package:bible_pal/core/mood_similarity.dart';
import 'package:bible_pal/models/parable.dart';

/// Helper to build a minimal test Parable.
Parable _p(String id, String mood) => Parable(
      storyId: id,
      title: 'Story $id',
      mood: mood,
      storyLength: 'short',
      storytellingMode: 'creative',
      kidFriendly: true,
    );

void main() {
  const engine = MoodExpansionEngine();

  // ── Tier 1: exact mood + unseen ──────────────────────────────────────

  group('SPEC 15b — Tier 1: exact mood first', () {
    test('spec_15b_exact_first.succeeds', () {
      final pool = [
        _p('1', 'anxious'),
        _p('2', 'calm_peaceful'), // similar to anxious
        _p('3', 'anxious'),
      ];

      final result = engine.select(
        selectedMood: 'anxious',
        pool: pool,
        playedStoryIds: {},
      );

      expect(result, isNotNull);
      expect(result!.tier, 1, reason: 'Must pick from tier 1 (exact + unseen)');
      expect(result.parable.mood, 'anxious');
      expect(result.servedMood, 'anxious');
    });

    test('spec_15b_exact_unseen_preferred_over_similar_unseen.succeeds', () {
      final pool = [
        _p('1', 'calm_peaceful'), // similar to anxious
        _p('2', 'anxious'), // exact match
      ];

      final result = engine.select(
        selectedMood: 'anxious',
        pool: pool,
        playedStoryIds: {},
      );

      expect(result!.tier, 1);
      expect(result.parable.storyId, '2',
          reason: 'Exact unseen must beat similar unseen');
    });
  });

  // ── Tier 2: similar moods + unseen ───────────────────────────────────

  group('SPEC 15b — Tier 2: similar moods unseen', () {
    test('spec_15b_similar_unseen_when_exact_exhausted.succeeds', () {
      final pool = [
        _p('1', 'anxious'),
        _p('2', 'calm_peaceful'), // similar to anxious
        _p('3', 'encouraging'), // similar to anxious
      ];

      final result = engine.select(
        selectedMood: 'anxious',
        pool: pool,
        playedStoryIds: {'1'}, // exact mood played
      );

      expect(result, isNotNull);
      expect(result!.tier, 2, reason: 'Must fall to tier 2 (similar + unseen)');
      expect(
        MoodSimilarity.getSimilar('anxious'),
        contains(result.parable.mood),
        reason: 'Served story must be from a similar mood',
      );
    });

    test('spec_15b_served_mood_reflects_actual_story.succeeds', () {
      final pool = [
        _p('1', 'anxious'),
        _p('2', 'calm_peaceful'),
      ];

      final result = engine.select(
        selectedMood: 'anxious',
        pool: pool,
        playedStoryIds: {'1'},
      );

      expect(result!.servedMood, 'calm_peaceful',
          reason: 'servedMood must be the actual mood of the story returned');
    });
  });

  // ── Tier 3: exact mood + seen (LRP) ──────────────────────────────────

  group('SPEC 15b — Tier 3: exact seen LRP', () {
    test('spec_15b_exact_seen_lrp_when_all_unseen_exhausted.succeeds', () {
      final pool = [
        _p('1', 'joyful'),
        _p('2', 'joyful'),
        _p('3', 'grateful'), // similar to joyful
      ];

      // All stories played
      final result = engine.select(
        selectedMood: 'joyful',
        pool: pool,
        playedStoryIds: {'1', '2', '3'},
        playHistory: {
          '1': DateTime(2025, 1, 1),
          '2': DateTime(2025, 6, 1), // more recent
          '3': DateTime(2025, 3, 1),
        },
      );

      expect(result!.tier, 3,
          reason: 'Must pick tier 3 (exact + seen) before tier 4');
      expect(result.parable.storyId, '1',
          reason: 'Must pick least-recently-played exact-mood story');
      expect(result.servedMood, 'joyful');
    });
  });

  // ── Tier 4: similar moods + seen (LRP) ───────────────────────────────

  group('SPEC 15b — Tier 4: similar seen LRP', () {
    test('spec_15b_similar_seen_lrp_last_resort.succeeds', () {
      // No exact mood stories at all
      final pool = [
        _p('1', 'calm_peaceful'),
        _p('2', 'encouraging'),
      ];

      final result = engine.select(
        selectedMood: 'anxious',
        pool: pool,
        playedStoryIds: {'1', '2'},
        playHistory: {
          '1': DateTime(2025, 6, 1),
          '2': DateTime(2025, 1, 1), // older
        },
      );

      expect(result!.tier, 4);
      expect(result.parable.storyId, '2',
          reason: 'Must pick LRP among similar-mood seen stories');
    });
  });

  // ── No length fallback ───────────────────────────────────────────────

  group('SPEC 15b — Required filters', () {
    test('spec_15b_no_length_fallback.succeeds', () {
      // The engine receives a pre-filtered pool from getEligibleParables().
      // If a mismatched-length story leaks into the pool, the engine must not
      // filter it (that's the caller's job). This test verifies that the engine
      // only considers exact + similar moods — it never reaches beyond.
      //
      // Scenario: pool has a 'full' story with exact mood and a 'short' story
      // with similar mood. Both are in the pool (simulating caller passing both).
      // Engine should pick the exact-mood story regardless of length — proving
      // it doesn't do its own length filtering (correct separation of concerns).
      final pool = [
        Parable(
          storyId: '1',
          title: 'Full story',
          mood: 'anxious',
          storyLength: 'full',
          storytellingMode: 'creative',
          kidFriendly: true,
        ),
        Parable(
          storyId: '2',
          title: 'Short story',
          mood: 'calm_peaceful',
          storyLength: 'short',
          storytellingMode: 'creative',
          kidFriendly: true,
        ),
      ];

      final result = engine.select(
        selectedMood: 'anxious',
        pool: pool,
        playedStoryIds: {},
      );

      expect(result!.tier, 1, reason: 'Exact mood chosen first');
      expect(result.parable.storyId, '1');
      // The engine does NOT filter by length — that is the caller's responsibility.
      // This test proves the boundary: engine selects by mood tier only.
      expect(result.parable.storyLength, 'full',
          reason: 'Engine passes through whatever length the caller provided');
    });
  });

  // ── Exact mood protection ────────────────────────────────────────────

  group('SPEC 15b — Exact mood protection', () {
    test('spec_15b_never_serves_unrelated_mood.succeeds', () {
      // Pool has only an unrelated mood (not in similar map for anxious)
      final pool = [
        _p('1', 'brave_courage'), // NOT similar to calm_peaceful
      ];

      final result = engine.select(
        selectedMood: 'calm_peaceful',
        pool: pool,
        playedStoryIds: {},
      );

      // brave_courage is NOT in calm_peaceful's similar list
      expect(
        MoodSimilarity.getSimilar('calm_peaceful'),
        isNot(contains('brave_courage')),
        reason: 'Precondition: brave_courage is not similar to calm_peaceful',
      );
      expect(result, isNull,
          reason:
              'Must return null rather than serve an unrelated mood');
    });

    test('spec_15b_exact_mood_is_primary.succeeds', () {
      final pool = [
        _p('1', 'anxious'),
        _p('2', 'calm_peaceful'),
        _p('3', 'encouraging'),
      ];

      // Nothing played — should always pick exact mood
      final result = engine.select(
        selectedMood: 'anxious',
        pool: pool,
        playedStoryIds: {},
      );

      expect(result!.parable.mood, 'anxious',
          reason: 'Selected mood is always primary when unseen stories exist');
    });
  });

  // ── Similar mood map completeness ────────────────────────────────────

  group('INVARIANT — Mood Expansion Serving', () {
    test('invariant_similar_map_covers_all_8_moods.succeeds', () {
      const allMoods = [
        'joyful',
        'grateful',
        'weary',
        'anxious',
        'hurting',
        'brave_courage',
        'calm_peaceful',
        'encouraging',
      ];

      for (final mood in allMoods) {
        expect(
          MoodSimilarity.similarMoods.containsKey(mood),
          true,
          reason: '$mood must be in the similar mood map',
        );
        expect(
          MoodSimilarity.getSimilar(mood),
          isNotEmpty,
          reason: '$mood must have at least one similar mood',
        );
      }
    });

    test('invariant_similar_moods_are_valid_mood_ids.succeeds', () {
      const allMoods = {
        'joyful',
        'grateful',
        'weary',
        'anxious',
        'hurting',
        'brave_courage',
        'calm_peaceful',
        'encouraging',
      };

      for (final entry in MoodSimilarity.similarMoods.entries) {
        for (final similar in entry.value) {
          expect(
            allMoods.contains(similar),
            true,
            reason:
                '${entry.key} → $similar: similar mood must be a valid mood ID',
          );
        }
      }
    });

    test('invariant_no_self_reference_in_similar_map.succeeds', () {
      for (final entry in MoodSimilarity.similarMoods.entries) {
        expect(
          entry.value.contains(entry.key),
          false,
          reason: '${entry.key} must not list itself as similar',
        );
      }
    });
  });

  // ── LRP ordering ────────────────────────────────────────────────────

  group('SPEC 15b — LRP ordering', () {
    test('spec_15b_lrp_never_played_first.succeeds', () {
      final pool = [
        _p('1', 'anxious'),
        _p('2', 'anxious'),
        _p('3', 'anxious'),
      ];

      final result = engine.select(
        selectedMood: 'anxious',
        pool: pool,
        playedStoryIds: {'1'},
        playHistory: {'1': DateTime(2025, 1, 1)},
      );

      expect(result!.tier, 1);
      // stories 2 and 3 are unseen; should pick 2 (lower storyId tie-break)
      expect(result.parable.storyId, '2',
          reason: 'Unseen stories picked first, stable tie-break by storyId');
    });

    test('spec_15b_lrp_oldest_play_first.succeeds', () {
      final pool = [
        _p('1', 'anxious'),
        _p('2', 'anxious'),
      ];

      final result = engine.select(
        selectedMood: 'anxious',
        pool: pool,
        playedStoryIds: {'1', '2'},
        playHistory: {
          '1': DateTime(2025, 6, 1), // more recent
          '2': DateTime(2025, 1, 1), // older
        },
      );

      expect(result!.tier, 3);
      expect(result.parable.storyId, '2',
          reason: 'Least recently played must be served first');
    });
  });

  // ── Alias names for spec traceability ──────────────────────────────

  group('SPEC 15b — Alias test names', () {
    test('spec_15b_similar_used_when_exact_empty.succeeds', () {
      // Same clause as spec_15b_similar_unseen_when_exact_exhausted
      final pool = [
        _p('1', 'anxious'),
        _p('2', 'calm_peaceful'),
      ];

      final result = engine.select(
        selectedMood: 'anxious',
        pool: pool,
        playedStoryIds: {'1'},
      );

      expect(result!.tier, 2,
          reason: 'Similar mood used when exact pool is empty');
      expect(result.parable.mood, 'calm_peaceful');
    });

    test('spec_15b_lrp_used_after_exhaustion.succeeds', () {
      // Same clause as spec_15b_exact_seen_lrp_when_all_unseen_exhausted
      final pool = [
        _p('1', 'anxious'),
        _p('2', 'anxious'),
      ];

      final result = engine.select(
        selectedMood: 'anxious',
        pool: pool,
        playedStoryIds: {'1', '2'},
        playHistory: {
          '1': DateTime(2025, 6, 1),
          '2': DateTime(2025, 1, 1),
        },
      );

      expect(result!.tier, 3,
          reason: 'Falls to seen pool after unseen exhausted');
      expect(result.parable.storyId, '2',
          reason: 'LRP ordering: oldest play first');
    });
  });

  // ── tierCandidates contract ──────────────────────────────────────────

  group('SPEC 15b — tierCandidates', () {
    test('spec_15b_tier_candidates_contains_all_in_winning_tier.succeeds', () {
      final pool = [
        _p('1', 'anxious'),
        _p('2', 'anxious'),
        _p('3', 'calm_peaceful'),
      ];

      final result = engine.select(
        selectedMood: 'anxious',
        pool: pool,
        playedStoryIds: {},
      );

      expect(result!.tier, 1);
      expect(result.tierCandidates.length, 2,
          reason: 'Tier 1 has 2 exact-mood unseen stories');
      expect(result.tierCandidates.map((p) => p.storyId), ['1', '2']);
    });

    test('spec_15b_tier_candidates_lrp_sorted.succeeds', () {
      final pool = [
        _p('1', 'anxious'),
        _p('2', 'anxious'),
      ];

      final result = engine.select(
        selectedMood: 'anxious',
        pool: pool,
        playedStoryIds: {'1', '2'},
        playHistory: {
          '1': DateTime(2025, 6, 1),
          '2': DateTime(2025, 1, 1),
        },
      );

      expect(result!.tierCandidates.map((p) => p.storyId), ['2', '1'],
          reason: 'Candidates must be LRP-sorted (oldest first)');
    });
  });

  // ── Empty pool ───────────────────────────────────────────────────────

  group('SPEC 15b — Edge cases', () {
    test('spec_15b_empty_pool_returns_null.succeeds', () {
      final result = engine.select(
        selectedMood: 'anxious',
        pool: [],
        playedStoryIds: {},
      );

      expect(result, isNull);
    });
  });
}
