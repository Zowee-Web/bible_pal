import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/models/user_preferences.dart';

void main() {
  group('palVoiceEnabled', () {
    test('defaults to true', () {
      final prefs = UserPreferences.defaults();
      expect(prefs.palVoiceEnabled, true);
    });

    test('fromJson defaults to true when field is absent', () {
      final prefs = UserPreferences.fromJson({'bibleTranslation': 'WEB'});
      expect(prefs.palVoiceEnabled, true);
    });

    test('fromJson reads false', () {
      final prefs = UserPreferences.fromJson({
        'bibleTranslation': 'WEB',
        'palVoiceEnabled': false,
      });
      expect(prefs.palVoiceEnabled, false);
    });

    test('toJson serializes palVoiceEnabled', () {
      final prefs = UserPreferences.defaults();
      final json = prefs.toJson();
      expect(json['palVoiceEnabled'], true);
    });

    test('copyWith preserves palVoiceEnabled by default', () {
      final prefs = UserPreferences.defaults();
      final copy = prefs.copyWith(userName: 'Test');
      expect(copy.palVoiceEnabled, true);
    });

    test('copyWith can set palVoiceEnabled to false', () {
      final prefs = UserPreferences.defaults();
      final copy = prefs.copyWith(palVoiceEnabled: false);
      expect(copy.palVoiceEnabled, false);
    });

    test('round-trip through toJson/fromJson preserves value', () {
      final prefs =
          UserPreferences.defaults().copyWith(palVoiceEnabled: false);
      final json = prefs.toJson();
      final restored = UserPreferences.fromJson(json);
      expect(restored.palVoiceEnabled, false);
    });
  });
}
