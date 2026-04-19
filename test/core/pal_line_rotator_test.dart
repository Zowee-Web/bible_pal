import 'dart:convert';
import 'dart:math';

import 'package:bible_pal/core/pal_line_rotator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PalLineRotator — in-memory', () {
    test('never returns the same index consecutively when pool > 1', () {
      final rotator = PalLineRotator(Random(42));
      int? prev;
      for (var i = 0; i < 50; i++) {
        final idx = rotator.pick('mood', 4);
        if (prev != null) {
          expect(idx, isNot(equals(prev)),
              reason: 'consecutive repeat at iteration $i');
        }
        prev = idx;
      }
    });

    test('exhausts entire pool before repeating any index', () {
      final rotator = PalLineRotator(Random(42));
      final seen = <int>{};
      // Pick poolSize times — should see every index exactly once.
      for (var i = 0; i < 4; i++) {
        seen.add(rotator.pick('mood', 4));
      }
      expect(seen, {0, 1, 2, 3});
    });

    test('resets and continues after pool exhaustion', () {
      final rotator = PalLineRotator(Random(42));
      // Exhaust pool of size 3.
      for (var i = 0; i < 3; i++) {
        rotator.pick('m', 3);
      }
      // Next pick should still succeed (pool resets internally).
      final next = rotator.pick('m', 3);
      expect(next, inInclusiveRange(0, 2));
    });

    test('separate context keys maintain independent history', () {
      final rotator = PalLineRotator(Random(42));
      // Exhaust pool for 'joyful'.
      final joyful = <int>{};
      for (var i = 0; i < 3; i++) {
        joyful.add(rotator.pick('joyful', 3));
      }
      expect(joyful, {0, 1, 2}, reason: 'joyful pool not fully cycled');

      // 'weary' should independently cycle its own pool.
      final weary = <int>{};
      for (var i = 0; i < 3; i++) {
        weary.add(rotator.pick('weary', 3));
      }
      expect(weary, {0, 1, 2}, reason: 'weary pool not fully cycled');
    });

    test('handles pool size of 1 without crashing', () {
      final rotator = PalLineRotator(Random(42));
      for (var i = 0; i < 5; i++) {
        expect(rotator.pick('single', 1), 0);
      }
    });

    test('reset clears in-memory history', () {
      final rotator = PalLineRotator(Random(0));
      rotator.pick('m', 4);
      rotator.reset();
      // After reset, the first index chosen could be the same as before
      // (since history is cleared), but more importantly the rotator works.
      final afterReset = rotator.pick('m', 4);
      expect(afterReset, inInclusiveRange(0, 3));
      // Verify the full pool is available again by checking we can exhaust it.
      final seen = <int>{afterReset};
      for (var i = 0; i < 3; i++) {
        seen.add(rotator.pick('m', 4));
      }
      expect(seen, {0, 1, 2, 3});
    });
  });

  group('PalLineRotator — persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('persisted history survives simulated restart', () async {
      final prefs = await SharedPreferences.getInstance();

      // Session 1: pick some lines.
      final r1 = PalLineRotator(Random(42));
      r1.enablePersistence(prefs, 'reflection');
      final pick1 = r1.pick('joyful', 4);
      final pick2 = r1.pick('joyful', 4);

      // Session 2: new rotator instance, same prefs.
      final r2 = PalLineRotator(Random(99));
      r2.enablePersistence(prefs, 'reflection');
      // Should avoid pick1 and pick2.
      final pick3 = r2.pick('joyful', 4);
      expect(pick3, isNot(equals(pick1)),
          reason: 'should avoid first used index');
      expect(pick3, isNot(equals(pick2)),
          reason: 'should avoid second used index');
    });

    test('separate families have independent persistence', () async {
      final prefs = await SharedPreferences.getInstance();

      // Exhaust pool in family 'reflection'.
      final r1 = PalLineRotator(Random(42));
      r1.enablePersistence(prefs, 'reflection');
      final reflectionPicks = <int>{};
      for (var i = 0; i < 3; i++) {
        reflectionPicks.add(r1.pick('joyful', 3));
      }
      expect(reflectionPicks, {0, 1, 2});

      // Family 'creative' should have its own clean history.
      final r2 = PalLineRotator(Random(42));
      r2.enablePersistence(prefs, 'creative');
      final creativePicks = <int>{};
      for (var i = 0; i < 3; i++) {
        creativePicks.add(r2.pick('joyful', 3));
      }
      expect(creativePicks, {0, 1, 2},
          reason: 'creative family should cycle independently');
    });

    test('handles pool-size shrink gracefully', () async {
      final prefs = await SharedPreferences.getInstance();

      // Session 1: pick with pool of 5.
      final r1 = PalLineRotator(Random(42));
      r1.enablePersistence(prefs, 'test');
      for (var i = 0; i < 4; i++) {
        r1.pick('m', 5); // stores indices 0-4
      }

      // Session 2: pool shrunk to 3 — stored indices >= 3 should be filtered.
      final r2 = PalLineRotator(Random(42));
      r2.enablePersistence(prefs, 'test');
      final pick = r2.pick('m', 3);
      expect(pick, inInclusiveRange(0, 2));
    });

    test('persistence failure does not crash selection', () async {
      // No prefs set up — rotator should work in memory-only mode.
      final rotator = PalLineRotator(Random(42));
      // enablePersistence is never called, so picks are memory-only.
      final pick = rotator.pick('m', 4);
      expect(pick, inInclusiveRange(0, 3));
    });

    test('clearPersistedHistory removes stored keys', () async {
      final prefs = await SharedPreferences.getInstance();

      final r1 = PalLineRotator(Random(42));
      r1.enablePersistence(prefs, 'reflection');
      r1.pick('joyful', 4);
      r1.pick('weary', 4);

      // Verify keys exist.
      expect(prefs.getString('pal_line_history_reflection_joyful'), isNotNull);
      expect(prefs.getString('pal_line_history_reflection_weary'), isNotNull);

      r1.clearPersistedHistory();

      // Keys should be removed.
      expect(prefs.getString('pal_line_history_reflection_joyful'), isNull);
      expect(prefs.getString('pal_line_history_reflection_weary'), isNull);
    });

    test('reset does NOT remove persisted keys', () async {
      final prefs = await SharedPreferences.getInstance();

      final r1 = PalLineRotator(Random(42));
      r1.enablePersistence(prefs, 'reflection');
      r1.pick('joyful', 4);

      // Verify key exists.
      expect(prefs.getString('pal_line_history_reflection_joyful'), isNotNull);

      r1.reset();

      // Persisted key should still be there.
      expect(prefs.getString('pal_line_history_reflection_joyful'), isNotNull);
    });

    test('persistence is bounded by pool size', () async {
      final prefs = await SharedPreferences.getInstance();

      final rotator = PalLineRotator(Random(42));
      rotator.enablePersistence(prefs, 'test');

      // Pick many times from a pool of 4.
      for (var i = 0; i < 20; i++) {
        rotator.pick('m', 4);
      }

      // The stored JSON should never have more entries than poolSize.
      final stored = prefs.getString('pal_line_history_test_m');
      expect(stored, isNotNull);
      // After 20 picks from pool of 4, the list resets every 4 picks.
      // The stored list should have at most 4 entries.
      final list = (jsonDecode(stored!) as List).cast<int>();
      expect(list.length, lessThanOrEqualTo(4));
    });
  });
}
