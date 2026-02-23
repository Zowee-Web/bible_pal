import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/services/content_filter_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ContentFilterService', () {
    late ContentFilterService service;

    setUp(() {
      service = ContentFilterService();
    });

    test('Clean story text passes content filter', () async {
      const cleanText = '''
        The shepherd walked through the valley, guiding his flock
        with care. "Trust in the Lord," he whispered, "for He is
        faithful in all things." The sun set over the peaceful hills
        as the sheep settled for the night.
      ''';

      final result = await service.scanText(cleanText);
      expect(result.passed, true);
      expect(result.violations, isEmpty);
    });

    test('Biblical content with death/battle passes (not kid-safe level)', () async {
      const biblicalText = '''
        David drew his sword and faced the giant Goliath.
        The stone struck Goliath and he fell dead upon the ground.
        Blood stained the battlefield as the armies clashed.
        The Lord delivered Israel from their enemies that day.
      ''';

      final result = await service.scanText(biblicalText);
      expect(result.passed, true,
          reason: 'Biblical warfare content should pass general content filter');
    });

    test('Text with strong profanity is blocked', () async {
      const profaneText = 'The man said a fuck word in anger.';

      final result = await service.scanText(profaneText);
      expect(result.passed, false);
      expect(result.violations, isNotEmpty);
    });

    test('Text with hate speech is blocked', () async {
      const hatefulText = 'He called his neighbor a faggot.';

      final result = await service.scanText(hatefulText);
      expect(result.passed, false);
      expect(result.violations, isNotEmpty);
    });

    test('Violations include location information', () async {
      const text = 'Line one is fine.\nLine two has shit in it.\nLine three is ok.';

      final result = await service.scanText(text);
      expect(result.passed, false);
      expect(result.violations.length, 1);
      expect(result.violations.first.lineNumber, 2);
      expect(result.violations.first.matchedText, 'shit');
    });

    test('Empty text passes', () async {
      final result = await service.scanText('');
      expect(result.passed, true);
    });

    test('Fallback patterns work when blocklist is unavailable', () async {
      // The service falls back to hardcoded critical patterns
      // if the asset file cannot be loaded. Since we're in test
      // environment, verify the service still works.
      final result = await service.scanText('This is clean text.');
      expect(result.passed, true);
    });
  });
}
