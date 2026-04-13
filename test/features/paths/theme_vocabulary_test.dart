import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/features/paths/theme_vocabulary.dart';

/// Tests for the PALs Paths theme vocabulary (SPEC Feature 50 — LOCKED).
/// The 8-tag list is LOCKED for v1; any change requires owner-approved
/// SPEC update. These tests pin the exact list and its wire IDs.
void main() {
  group('ThemeTag wire ids (SPEC 50 — LOCKED)', () {
    test('exactly 8 theme tags exist', () {
      expect(ThemeTag.values.length, 8);
    });

    test('all 8 locked wire ids are present and exact', () {
      final wireIds = ThemeTag.values.map((t) => t.wireId).toSet();
      expect(
        wireIds,
        equals({
          'faith',
          'hope',
          'mercy',
          'courage',
          'obedience',
          'provision',
          'patience',
          'forgiveness',
        }),
      );
    });

    test('individual tag wire ids match the locked vocabulary', () {
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
      expect(ThemeTagParse.fromWire('gratitude'), isNull);
      expect(ThemeTagParse.fromWire('joy'), isNull);
      expect(ThemeTagParse.fromWire('peace'), isNull);
      expect(ThemeTagParse.fromWire('FAITH'), isNull);
      expect(ThemeTagParse.fromWire(''), isNull);
      expect(ThemeTagParse.fromWire(null), isNull);
    });
  });

  group('isValid + allWireIds helpers', () {
    test('isValid matches known vocabulary', () {
      expect(ThemeTagParse.isValid('faith'), isTrue);
      expect(ThemeTagParse.isValid('courage'), isTrue);
      expect(ThemeTagParse.isValid('gratitude'), isFalse);
      expect(ThemeTagParse.isValid(''), isFalse);
    });

    test('allWireIds returns the full locked set', () {
      final all = ThemeTagParse.allWireIds;
      expect(all.length, 8);
      expect(all, contains('faith'));
      expect(all, contains('forgiveness'));
    });
  });

  group('banned tag negative guards', () {
    // These words MUST NOT appear in the locked v1 vocabulary.
    // Adding any of them requires an owner-approved SPEC update.
    test('gratitude is NOT in the locked v1 vocabulary', () {
      expect(ThemeTag.values.any((t) => t.wireId == 'gratitude'), isFalse);
    });

    test('joy is NOT in the locked v1 vocabulary', () {
      expect(ThemeTag.values.any((t) => t.wireId == 'joy'), isFalse);
    });

    test('peace is NOT in the locked v1 vocabulary', () {
      expect(ThemeTag.values.any((t) => t.wireId == 'peace'), isFalse);
    });

    test('love is NOT in the locked v1 vocabulary', () {
      expect(ThemeTag.values.any((t) => t.wireId == 'love'), isFalse);
    });
  });
}
