import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/character_registry.dart';

/// Tests for the PALs Paths character registry (SPEC Feature 50.3 + 50.8).
/// Verifies disambiguation, the Jesus special-case reservation, and the
/// charactersForPathList filter that excludes reserved IDs from the
/// Characters path list.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    CharacterRegistry.resetForTest();
    await CharacterRegistry.ensureLoaded();
  });

  group('CharacterRegistry — seed contents (SPEC 50.8)', () {
    test('registry loads without error', () {
      expect(CharacterRegistry.allIds(), isNotEmpty);
    });

    test('david is registered with display name "David"', () {
      expect(CharacterRegistry.isKnown('david'), isTrue);
      expect(CharacterRegistry.getDisplayName('david'), 'David');
    });

    test('disambiguated name collisions are distinct IDs', () {
      expect(CharacterRegistry.isKnown('john_baptist'), isTrue);
      expect(CharacterRegistry.isKnown('john_disciple'), isTrue);

      expect(CharacterRegistry.isKnown('mary_mother_jesus'), isTrue);
      expect(CharacterRegistry.isKnown('mary_magdalene'), isTrue);
      expect(CharacterRegistry.isKnown('mary_sister_of_martha'), isTrue);

      expect(CharacterRegistry.isKnown('james_son_zebedee'), isTrue);
      expect(CharacterRegistry.isKnown('james_son_alphaeus'), isTrue);
      expect(CharacterRegistry.isKnown('james_brother_of_jesus'), isTrue);

      expect(CharacterRegistry.isKnown('simon_peter'), isTrue);
      expect(CharacterRegistry.isKnown('simon_zealot'), isTrue);

      expect(CharacterRegistry.isKnown('judas_iscariot'), isTrue);
      expect(CharacterRegistry.isKnown('judas_thaddaeus'), isTrue);
    });

    test('display name lookup returns the ID for unknown characters', () {
      // Safe fallback: never null, never empty.
      expect(CharacterRegistry.getDisplayName('made_up_id'), 'made_up_id');
    });
  });

  group('Jesus special-case reservation (SPEC 50.8 — LOCKED)', () {
    test('jesus is registered as a reserved ID', () {
      expect(CharacterRegistry.isKnown('jesus'), isTrue);
      expect(CharacterRegistry.isReservedForJesusLife('jesus'), isTrue);
    });

    test('non-reserved characters are not flagged reserved', () {
      expect(CharacterRegistry.isReservedForJesusLife('david'), isFalse);
      expect(CharacterRegistry.isReservedForJesusLife('moses'), isFalse);
      expect(CharacterRegistry.isReservedForJesusLife('john_baptist'), isFalse);
    });

    test('charactersForPathList excludes jesus', () {
      final list = CharacterRegistry.charactersForPathList();
      expect(list, isNotEmpty);
      expect(list, isNot(contains('jesus')));
      // And it still contains ordinary characters
      expect(list, contains('david'));
      expect(list, contains('moses'));
      expect(list, contains('john_baptist'));
      expect(list, contains('mary_magdalene'));
    });

    test('allIds includes jesus (for characterIds lookups)', () {
      // Jesus must be resolvable for secondary-character lookups even
      // though he's excluded from the Characters path list.
      expect(CharacterRegistry.allIds(), contains('jesus'));
    });
  });
}
