import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/models/parable.dart';

/// Round-trip tests for PALs Paths metadata fields (SPEC Feature 50.9,
/// Feature 8 metadata extension). All 8 fields are optional; stories
/// without them must parse cleanly and must not acquire the fields on
/// toJson round-trip.
void main() {
  /// Minimal valid Traditional parable JSON — no PALs Paths fields.
  Map<String, dynamic> baseJson() => <String, dynamic>{
        'storyId': 'test_david_001',
        'title': 'David Anointed',
        'mood': 'brave_courage',
        'emotionalTags': <String>[],
        'length': 5,
        'storyLength': 'short',
        'storytellingMode': 'traditional',
        'translationId': 'WEB',
        'languageStyle': 'WEB',
        'kidFriendly': false,
        'scriptureSources': <String>[],
        'narratorVoiceKey': 'VOICE_JAMES_HUSKY',
        'bibleSourceRef': '1 Samuel 16:1-13',
        'bibleStoryKey': 'david_anointed',
      };

  group('Parable PALs Paths metadata (Feature 50.9)', () {
    test('legacy manifest without path fields parses with all nulls', () {
      final parable = Parable.fromJson(baseJson());

      expect(parable.primaryCharacterId, isNull);
      expect(parable.primaryCharacterDisplayName, isNull);
      expect(parable.characterIds, isNull);
      expect(parable.characterDisplayNames, isNull);
      expect(parable.bibleOrderIndex, isNull);
      expect(parable.timelineEra, isNull);
      expect(parable.themeTags, isNull);
      expect(parable.characterPathOrder, isNull);
    });

    test('toJson on legacy parable never emits path fields', () {
      final parable = Parable.fromJson(baseJson());
      final json = parable.toJson();

      expect(json.containsKey('primaryCharacterId'), isFalse);
      expect(json.containsKey('primaryCharacterDisplayName'), isFalse);
      expect(json.containsKey('characterIds'), isFalse);
      expect(json.containsKey('characterDisplayNames'), isFalse);
      expect(json.containsKey('bibleOrderIndex'), isFalse);
      expect(json.containsKey('timelineEra'), isFalse);
      expect(json.containsKey('themeTags'), isFalse);
      expect(json.containsKey('characterPathOrder'), isFalse);
    });

    test('full path metadata round-trips through fromJson/toJson', () {
      final input = baseJson()
        ..addAll({
          'primaryCharacterId': 'david',
          'primaryCharacterDisplayName': 'David',
          'characterIds': <String>['david', 'samuel'],
          'characterDisplayNames': <String>['David', 'Samuel'],
          'bibleOrderIndex': 142,
          'timelineEra': 'kingdom',
          'themeTags': <String>['courage', 'faith'],
          'characterPathOrder': 1,
        });

      final parable = Parable.fromJson(input);

      expect(parable.primaryCharacterId, 'david');
      expect(parable.primaryCharacterDisplayName, 'David');
      expect(parable.characterIds, <String>['david', 'samuel']);
      expect(parable.characterDisplayNames, <String>['David', 'Samuel']);
      expect(parable.bibleOrderIndex, 142);
      expect(parable.timelineEra, 'kingdom');
      expect(parable.themeTags, <String>['courage', 'faith']);
      expect(parable.characterPathOrder, 1);

      final roundTrip = parable.toJson();
      expect(roundTrip['primaryCharacterId'], 'david');
      expect(roundTrip['primaryCharacterDisplayName'], 'David');
      expect(roundTrip['characterIds'], <String>['david', 'samuel']);
      expect(roundTrip['characterDisplayNames'], <String>['David', 'Samuel']);
      expect(roundTrip['bibleOrderIndex'], 142);
      expect(roundTrip['timelineEra'], 'kingdom');
      expect(roundTrip['themeTags'], <String>['courage', 'faith']);
      expect(roundTrip['characterPathOrder'], 1);
    });

    test('empty themeTags / characterIds arrays round-trip correctly', () {
      final input = baseJson()
        ..addAll({
          'characterIds': <String>[],
          'themeTags': <String>[],
        });

      final parable = Parable.fromJson(input);
      expect(parable.characterIds, isEmpty);
      expect(parable.themeTags, isEmpty);

      final roundTrip = parable.toJson();
      expect(roundTrip['characterIds'], isEmpty);
      expect(roundTrip['themeTags'], isEmpty);
    });

    test('copyWith preserves and overrides path fields', () {
      final original = Parable.fromJson(baseJson()).copyWith(
        primaryCharacterId: 'moses',
        primaryCharacterDisplayName: 'Moses',
        timelineEra: 'exodus',
        themeTags: <String>['deliverance'],
        bibleOrderIndex: 50,
        characterPathOrder: 3,
      );

      expect(original.primaryCharacterId, 'moses');
      expect(original.timelineEra, 'exodus');
      expect(original.bibleOrderIndex, 50);
      expect(original.characterPathOrder, 3);

      final renamedPath = original.copyWith(timelineEra: 'judges');
      expect(renamedPath.timelineEra, 'judges');
      // Other fields preserved.
      expect(renamedPath.primaryCharacterId, 'moses');
      expect(renamedPath.bibleOrderIndex, 50);
      expect(renamedPath.themeTags, <String>['deliverance']);
    });

    test('partial metadata (only primaryCharacterId) round-trips', () {
      final input = baseJson()..['primaryCharacterId'] = 'ruth';

      final parable = Parable.fromJson(input);
      expect(parable.primaryCharacterId, 'ruth');
      expect(parable.primaryCharacterDisplayName, isNull);
      expect(parable.characterIds, isNull);
      expect(parable.bibleOrderIndex, isNull);
      expect(parable.timelineEra, isNull);
      expect(parable.themeTags, isNull);

      final json = parable.toJson();
      expect(json['primaryCharacterId'], 'ruth');
      expect(json.containsKey('primaryCharacterDisplayName'), isFalse);
      expect(json.containsKey('characterIds'), isFalse);
      expect(json.containsKey('bibleOrderIndex'), isFalse);
      expect(json.containsKey('timelineEra'), isFalse);
      expect(json.containsKey('themeTags'), isFalse);
    });

    test('Creative parable without path fields stays clean on round-trip', () {
      final input = baseJson()
        ..['storytellingMode'] = 'creative'
        ..remove('bibleSourceRef')
        ..remove('bibleStoryKey');

      final parable = Parable.fromJson(input);
      final json = parable.toJson();

      // Creative stories must not acquire any path fields on round-trip
      // (Story Mode Non-Blur Invariant — PALs Paths Traditional-Only
      // Enforcement, INVARIANTS.md #6).
      expect(json.containsKey('primaryCharacterId'), isFalse);
      expect(json.containsKey('characterIds'), isFalse);
      expect(json.containsKey('bibleOrderIndex'), isFalse);
      expect(json.containsKey('timelineEra'), isFalse);
      expect(json.containsKey('themeTags'), isFalse);
    });
  });
}
