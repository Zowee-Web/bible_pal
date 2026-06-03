import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bible_pal/widgets/name_prompt_overlay.dart';

/// Guards `NamePromptOverlay.shouldShow` so the post-onboarding bug
/// (prompt overlaying the Story Player) cannot regress: the overlay
/// must never report shouldShow=true once onboarding has completed,
/// regardless of name state or prior-seen flag.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('NamePromptOverlay.shouldShow', () {
    test('returns true when onboarding incomplete and no name set', () async {
      final result = await NamePromptOverlay.shouldShow(
        userName: null,
        hasCompletedOnboarding: false,
      );
      expect(result, isTrue);
    });

    test('returns true when onboarding incomplete and name is empty', () async {
      final result = await NamePromptOverlay.shouldShow(
        userName: '',
        hasCompletedOnboarding: false,
      );
      expect(result, isTrue);
    });

    test('returns false once onboarding is complete, even with no name',
        () async {
      final result = await NamePromptOverlay.shouldShow(
        userName: null,
        hasCompletedOnboarding: true,
      );
      expect(result, isFalse);
    });

    test('returns false once onboarding is complete, even with empty name',
        () async {
      final result = await NamePromptOverlay.shouldShow(
        userName: '',
        hasCompletedOnboarding: true,
      );
      expect(result, isFalse);
    });

    test('returns false when a name is already set', () async {
      final result = await NamePromptOverlay.shouldShow(
        userName: 'Adam',
        hasCompletedOnboarding: false,
      );
      expect(result, isFalse);
    });

    test('returns false when prompt has been seen before', () async {
      SharedPreferences.setMockInitialValues({kHasSeenNamePromptKey: true});
      final result = await NamePromptOverlay.shouldShow(
        userName: null,
        hasCompletedOnboarding: false,
      );
      expect(result, isFalse);
    });
  });
}
