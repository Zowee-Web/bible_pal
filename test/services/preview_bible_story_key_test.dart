import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bible_pal/services/parable_service.dart';
import 'package:bible_pal/models/user_preferences.dart';
import 'package:bible_pal/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ParableService service;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.create();
    service = ParableService(storage, null, true);
  });

  test('previewBibleStoryKey returns a key for hurting mood with text', () async {
    final prefs = UserPreferences.defaults();
    final key = await service.previewBibleStoryKey(
      mood: 'hurting',
      userPrefs: prefs,
      userText: 'I feel really alone and hurt',
    );

    print('Preview key for hurting + "alone and hurt": $key');
    expect(key, isNotNull);
    expect(key, isA<String>());
  });

  test('previewBibleStoryKey returns a key for anxious mood', () async {
    final prefs = UserPreferences.defaults();
    final key = await service.previewBibleStoryKey(
      mood: 'anxious',
      userPrefs: prefs,
      userText: 'I feel really anxious about tomorrow',
    );

    print('Preview key for anxious: $key');
    expect(key, isNotNull);
  });

  test('previewBibleStoryKey returns null for creative mode', () async {
    final prefs = UserPreferences.defaults().copyWith(
      storytellingMode: 'creative',
    );
    final key = await service.previewBibleStoryKey(
      mood: 'hurting',
      userPrefs: prefs,
      userText: 'I feel really alone',
    );

    print('Preview key for creative mode: $key');
    // Creative stories have no bibleStoryKey
    expect(key, isNull);
  });
}
