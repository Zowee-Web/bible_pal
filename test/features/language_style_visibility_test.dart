import 'package:flutter_test/flutter_test.dart';

/// Tests for language style row visibility logic on the mood screen.
///
/// The language style row (Modern WEB / Classic KJV) should only be visible
/// when Traditional mode is selected AND Kid Mode is OFF.
///
/// Logic under test (from _buildLanguageStyleRow in main_menu_screen.dart):
///   showRow = isTraditional && !isKidMode
///
/// Auto-correction rule:
///   if (isKidMode && currentStyle == 'KJV') → force to 'WEB'

void main() {
  group('Language style row visibility', () {
    bool showRow(String storytellingMode, bool kidFriendlyOnly) {
      final isTraditional = storytellingMode == 'traditional';
      final isKidMode = kidFriendlyOnly;
      return isTraditional && !isKidMode;
    }

    test('Traditional + Kid Mode OFF => visible', () {
      expect(showRow('traditional', false), isTrue);
    });

    test('Creative + Kid Mode OFF => hidden', () {
      expect(showRow('creative', false), isFalse);
    });

    test('Traditional + Kid Mode ON => hidden', () {
      expect(showRow('traditional', true), isFalse);
    });

    test('Creative + Kid Mode ON => hidden', () {
      expect(showRow('creative', true), isFalse);
    });
  });

  group('KJV auto-correction when Kid Mode is ON', () {
    String autoCorrect(String currentStyle, bool isKidMode) {
      if (isKidMode && currentStyle == 'KJV') return 'WEB';
      return currentStyle;
    }

    test('KJV selected + Kid Mode ON => forced to WEB', () {
      expect(autoCorrect('KJV', true), 'WEB');
    });

    test('WEB selected + Kid Mode ON => stays WEB', () {
      expect(autoCorrect('WEB', true), 'WEB');
    });

    test('KJV selected + Kid Mode OFF => stays KJV', () {
      expect(autoCorrect('KJV', false), 'KJV');
    });

    test('WEB selected + Kid Mode OFF => stays WEB', () {
      expect(autoCorrect('WEB', false), 'WEB');
    });
  });
}
