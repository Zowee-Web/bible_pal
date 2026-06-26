import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/features/paths/theme_vocabulary.dart';

/// Tests for the PALs Paths theme vocabulary (SPEC Feature 50).
///
/// Expanded in PR β from the original locked-8 to 58 tags covering the
/// authored themes across the 1287-story corpus. These tests pin the new
/// expanded vocabulary so further drift is intentional rather than accidental.
void main() {
  group('ThemeTag wire ids — expanded vocabulary (SPEC 50, PR β)', () {
    test('exactly 146 theme tags exist', () {
      expect(ThemeTag.values.length, 146);
    });

    test('original locked-8 wire ids remain present and exact', () {
      final wireIds = ThemeTag.values.map((t) => t.wireId).toSet();
      const lockedV1 = {
        'faith',
        'hope',
        'mercy',
        'courage',
        'obedience',
        'provision',
        'patience',
        'forgiveness',
      };
      for (final id in lockedV1) {
        expect(wireIds, contains(id),
            reason: 'Locked-v1 tag "$id" must remain in expanded vocab');
      }
    });

    test('all 146 expanded wire ids are present and exact', () {
      final wireIds = ThemeTag.values.map((t) => t.wireId).toSet();
      expect(
        wireIds,
        equals({
          // Theme Vocabulary v2 (frozen 2026-06 test-health pass) — 146 tags.
          'abandonment', 'abundance', 'ark', 'authority', 'bereavement', 'birth',
          'blessing', 'blossoming', 'burden', 'calling', 'celebration', 'choice',
          'comfort', 'commission', 'commissioning', 'community', 'compassion', 'completion',
          'confession', 'consequence', 'conspiracy', 'courage', 'covenant', 'death',
          'decree', 'dedication', 'deliverance', 'desolation', 'destruction', 'devotion',
          'discipleship', 'doxology', 'elegy', 'endurance', 'evangelism', 'exhaustion',
          'exhortation', 'exile', 'expansion', 'faith', 'faithfulness', 'fasting',
          'fatherhood', 'fear', 'fellowship', 'flight', 'forgiveness', 'freedom',
          'friendship', 'fulfillment', 'futility', 'gathering', 'generosity', 'giving',
          'gratitude', 'grief', 'guidance', 'healing', 'homecoming', 'hope',
          'hospitality', 'household', 'humility', 'idolatry', 'injustice', 'intercession',
          'intervention', 'intimacy', 'journey', 'joy', 'judgment', 'justice',
          'kingdom', 'kingship', 'labor', 'lament', 'language', 'laughter',
          'leadership', 'legacy', 'loneliness', 'longing', 'loss', 'love',
          'loyalty', 'meditation', 'menace', 'mercy', 'miracles', 'music',
          'mystery', 'obedience', 'patience', 'peace', 'perseverance', 'petition',
          'pilgrimage', 'praise', 'prayer', 'presence', 'pride', 'promise',
          'protection', 'providence', 'provision', 'pursuit', 'rebuilding', 'redemption',
          'refuge', 'remembrance', 'repentance', 'resolve', 'rest', 'restoration',
          'revelation', 'righteousness', 'sacrifice', 'salvation', 'scattering', 'scripture',
          'service', 'shame', 'sleeplessness', 'song', 'sovereignty', 'sowing',
          'stewardship', 'stillness', 'suffering', 'testing', 'thanksgiving', 'toil',
          'transformation', 'trust', 'vanity', 'vindication', 'vision', 'waiting',
          'wedding', 'wilderness', 'wisdom', 'withdrawal', 'witness', 'worship',
          'worthiness', 'wrestling',
        }),
      );
    });

    test('individual tag wire ids match the locked v1 set', () {
      expect(ThemeTag.faith.wireId, 'faith');
      expect(ThemeTag.hope.wireId, 'hope');
      expect(ThemeTag.mercy.wireId, 'mercy');
      expect(ThemeTag.courage.wireId, 'courage');
      expect(ThemeTag.obedience.wireId, 'obedience');
      expect(ThemeTag.provision.wireId, 'provision');
      expect(ThemeTag.patience.wireId, 'patience');
      expect(ThemeTag.forgiveness.wireId, 'forgiveness');
    });

    test('display labels are Title Case', () {
      expect(ThemeTag.faith.displayLabel, 'Faith');
      expect(ThemeTag.hope.displayLabel, 'Hope');
      expect(ThemeTag.mercy.displayLabel, 'Mercy');
      expect(ThemeTag.courage.displayLabel, 'Courage');
      expect(ThemeTag.obedience.displayLabel, 'Obedience');
      expect(ThemeTag.provision.displayLabel, 'Provision');
      expect(ThemeTag.patience.displayLabel, 'Patience');
      expect(ThemeTag.forgiveness.displayLabel, 'Forgiveness');
      // Spot-check a few from the expansion
      expect(ThemeTag.gratitude.displayLabel, 'Gratitude');
      expect(ThemeTag.transformation.displayLabel, 'Transformation');
      expect(ThemeTag.joy.displayLabel, 'Joy');
    });

    test('wire ids are lowercase snake_case compatible', () {
      for (final tag in ThemeTag.values) {
        expect(
          RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(tag.wireId),
          isTrue,
          reason: 'Tag "${tag.wireId}" must be snake_case',
        );
      }
    });
  });

  group('fromWire parser', () {
    test('round-trips every tag', () {
      for (final tag in ThemeTag.values) {
        expect(ThemeTagParse.fromWire(tag.wireId), tag);
      }
    });

    test('returns null for unknown wire strings', () {
      // PR β expansion brought gratitude/joy/peace/love into the vocab.
      // These remain unknown:
      expect(ThemeTagParse.fromWire('FAITH'), isNull,
          reason: 'Wire IDs are case-sensitive');
      expect(ThemeTagParse.fromWire('not_a_real_tag'), isNull);
      expect(ThemeTagParse.fromWire(''), isNull);
      expect(ThemeTagParse.fromWire(null), isNull);
    });
  });

  group('isValid + allWireIds helpers', () {
    test('isValid matches expanded vocabulary', () {
      expect(ThemeTagParse.isValid('faith'), isTrue);
      expect(ThemeTagParse.isValid('courage'), isTrue);
      // PR β expansion additions:
      expect(ThemeTagParse.isValid('gratitude'), isTrue);
      expect(ThemeTagParse.isValid('joy'), isTrue);
      expect(ThemeTagParse.isValid('peace'), isTrue);
      expect(ThemeTagParse.isValid('love'), isTrue);
      // Still invalid:
      expect(ThemeTagParse.isValid(''), isFalse);
      expect(ThemeTagParse.isValid('not_a_real_tag'), isFalse);
    });

    test('allWireIds returns the full expanded set', () {
      final all = ThemeTagParse.allWireIds;
      expect(all.length, 146);
      // Sample membership across the v1 + expansion split
      expect(all, contains('faith'));
      expect(all, contains('forgiveness'));
      expect(all, contains('gratitude'));
      expect(all, contains('joy'));
      expect(all, contains('peace'));
      expect(all, contains('love'));
    });
  });
}
