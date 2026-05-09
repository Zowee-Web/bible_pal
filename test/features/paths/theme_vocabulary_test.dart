import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/features/paths/theme_vocabulary.dart';

/// Tests for the PALs Paths theme vocabulary (SPEC Feature 50).
///
/// Expanded in PR β from the original locked-8 to 58 tags covering the
/// authored themes across the 1287-story corpus. These tests pin the new
/// expanded vocabulary so further drift is intentional rather than accidental.
void main() {
  group('ThemeTag wire ids — expanded vocabulary (SPEC 50, PR β)', () {
    test('exactly 58 theme tags exist', () {
      expect(ThemeTag.values.length, 58);
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

    test('all 58 expanded wire ids are present and exact', () {
      final wireIds = ThemeTag.values.map((t) => t.wireId).toSet();
      expect(
        wireIds,
        equals({
          // v1 locked-8
          'faith',
          'hope',
          'mercy',
          'courage',
          'obedience',
          'provision',
          'patience',
          'forgiveness',
          // PR β expansion (corpus-canonical themes)
          'promise',
          'presence',
          'trust',
          'guidance',
          'prayer',
          'calling',
          'lament',
          'gratitude',
          'suffering',
          'praise',
          'deliverance',
          'love',
          'perseverance',
          'restoration',
          'endurance',
          'faithfulness',
          'transformation',
          'rest',
          'fear',
          'healing',
          'rebuilding',
          'blessing',
          'celebration',
          'wisdom',
          'peace',
          'waiting',
          'freedom',
          'testing',
          'covenant',
          'longing',
          'redemption',
          'comfort',
          'repentance',
          'sacrifice',
          'protection',
          'refuge',
          'witness',
          'scripture',
          'humility',
          'service',
          'kingdom',
          'loyalty',
          'shame',
          'abandonment',
          'justice',
          'wrestling',
          'grief',
          'joy',
          'hospitality',
          'devotion',
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
      expect(all.length, 58);
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
