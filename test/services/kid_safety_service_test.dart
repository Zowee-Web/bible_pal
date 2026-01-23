// Unit tests for Kid Safety Service
// Tests Layer 3 of Kid Safety Contract Invariant
// See docs/INVARIANTS.md for complete specification

import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/services/kid_safety_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KidSafetyService', () {
    late KidSafetyService service;

    setUp(() {
      service = KidSafetyService();
    });

    group('Initialization', () {
      test('initializes successfully', () async {
        await service.initialize();
        // If no exception thrown, initialization succeeded
        expect(true, true);
      });

      test('can initialize multiple times safely', () async {
        await service.initialize();
        await service.initialize(); // Should not throw
        expect(true, true);
      });
    });

    group('Scanner - Profanity Detection', () {
      test('CRITICAL: blocks profanity (damn)', () async {
        await service.initialize();

        final result = await service.scanStoryText(
          'The man said damn and continued walking.',
        );

        expect(result.passed, false);
        expect(result.violations.length, greaterThan(0));
        expect(
            result.violations[0].matchedText.toLowerCase(), contains('damn'));
      });

      test('CRITICAL: blocks profanity (hell)', () async {
        await service.initialize();

        final result = await service.scanStoryText(
          'He went to hell for his sins.',
        );

        expect(result.passed, false);
        expect(result.violations.length, greaterThan(0));
      });

      test('CRITICAL: blocks vulgar language', () async {
        await service.initialize();

        final result = await service.scanStoryText(
          'You are such a bastard and a bitch.',
        );

        expect(result.passed, false);
        expect(result.violations.length, greaterThan(0));
      });
    });

    group('Scanner - Sexual Content Detection', () {
      test('CRITICAL: blocks explicit sexual content', () async {
        await service.initialize();

        final result = await service.scanStoryText(
          'They had sex in the temple.',
        );

        expect(result.passed, false);
        expect(result.violations.length, greaterThan(0));
      });

      test('CRITICAL: blocks sexual assault references', () async {
        await service.initialize();

        final result = await service.scanStoryText(
          'The woman was raped by the soldiers.',
        );

        expect(result.passed, false);
        expect(result.violations.length, greaterThan(0));
      });

      test('CRITICAL: blocks explicit anatomy terms', () async {
        await service.initialize();

        final result = await service.scanStoryText(
          'The doctor examined the penis and vagina.',
        );

        expect(result.passed, false);
        expect(result.violations.length, greaterThan(0));
      });
    });

    group('Scanner - Graphic Violence Detection', () {
      test('CRITICAL: blocks gore descriptions', () async {
        await service.initialize();

        final result = await service.scanStoryText(
          'Blood was gushing from the wound as he was dismembered.',
        );

        expect(result.passed, false);
        expect(result.violations.length, greaterThan(0));
      });

      test('CRITICAL: blocks torture references', () async {
        await service.initialize();

        final result = await service.scanStoryText(
          'They tortured him for hours in the dungeon.',
        );

        expect(result.passed, false);
        expect(result.violations.length, greaterThan(0));
      });

      test('CRITICAL: blocks decapitation/execution', () async {
        await service.initialize();

        final result = await service.scanStoryText(
          'The king was executed and beheaded in public.',
        );

        expect(result.passed, false);
        expect(result.violations.length, greaterThan(0));
      });
    });

    group('Scanner - Self-Harm Detection', () {
      test('CRITICAL: blocks suicide references', () async {
        await service.initialize();

        final result = await service.scanStoryText(
          'He committed suicide by hanging himself.',
        );

        expect(result.passed, false);
        expect(result.violations.length, greaterThan(0));
      });

      test('CRITICAL: blocks self-harm actions', () async {
        await service.initialize();

        final result = await service.scanStoryText(
          'She cut herself with the knife repeatedly.',
        );

        expect(result.passed, false);
        expect(result.violations.length, greaterThan(0));
      });
    });

    group('Scanner - Substance Abuse Detection', () {
      test('CRITICAL: blocks drug references', () async {
        await service.initialize();

        final result = await service.scanStoryText(
          'The man was high on cocaine and heroin.',
        );

        expect(result.passed, false);
        expect(result.violations.length, greaterThan(0));
      });

      test('CRITICAL: blocks intoxication', () async {
        await service.initialize();

        final result = await service.scanStoryText(
          'He was drunk and stoned at the party.',
        );

        expect(result.passed, false);
        expect(result.violations.length, greaterThan(0));
      });
    });

    group('Scanner - Case Insensitivity', () {
      test('detects uppercase violations', () async {
        await service.initialize();

        final result = await service.scanStoryText(
          'DAMN that was close!',
        );

        expect(result.passed, false);
      });

      test('detects mixed case violations', () async {
        await service.initialize();

        final result = await service.scanStoryText(
          'He was TorTuReD for information.',
        );

        expect(result.passed, false);
      });
    });

    group('Scanner - Clean Content (Should Pass)', () {
      test('allows kid-friendly Bible story (David and Goliath)', () async {
        await service.initialize();

        final result = await service.scanStoryText('''
David was a young shepherd who loved his sheep. One day, a giant
named Goliath challenged the Israelites. David, filled with courage
and faith, used his sling to stop the giant. Goliath fell down, and
David became a hero. The people celebrated David's bravery and trust in God.
        ''');

        expect(result.passed, true);
        expect(result.violations.length, 0);
      });

      test('allows gentle conflict resolution', () async {
        await service.initialize();

        final result = await service.scanStoryText('''
The two brothers argued about the land. Their father helped them
find a peaceful solution. They learned to share and forgive each other.
Everyone was happy with the outcome.
        ''');

        expect(result.passed, true);
        expect(result.violations.length, 0);
      });

      test('allows emotional content without violence', () async {
        await service.initialize();

        final result = await service.scanStoryText('''
Sarah felt sad when her friend moved away. She cried and missed her terribly.
But her mother comforted her and reminded her that true friends stay close
in their hearts even when far apart.
        ''');

        expect(result.passed, true);
        expect(result.violations.length, 0);
      });
    });

    group('Scanner - Line Number Reporting', () {
      test('reports correct line numbers for violations', () async {
        await service.initialize();

        final result = await service.scanStoryText(
          'This is line one with safe content.\n'
          'This is line two with the word damn in it.\n'
          'This is line three with more safe content.',
        );

        expect(result.passed, false);
        expect(result.violations.length, greaterThan(0));
        // Line 2 contains "damn"
        expect(result.violations[0].lineNumber, 2);
      });

      test('reports multiple violations with correct line numbers', () async {
        await service.initialize();

        final result = await service.scanStoryText(
          'Safe line one.\n'
          'This damn line has profanity.\n'
          'Another safe line.\n'
          'This line mentions hell.',
        );

        expect(result.passed, false);
        expect(result.violations.length, 2);
        // Line 2 for "damn", line 4 for "hell"
        expect(result.violations[0].lineNumber, 2);
        expect(result.violations[1].lineNumber, 4);
      });
    });

    group('Fallback Story Configuration', () {
      test('fallback story ID is configured', () {
        expect(KidSafetyService.fallbackStoryId, '101');
      });
    });

    group('ML Classifier Hook (Future)', () {
      test('classifier returns PASS when disabled', () async {
        await service.initialize();

        final result = await service.classifyContent(
          'Any content here',
          enabled: false,
        );

        expect(result.passed, true);
        expect(result.violations.length, 0);
      });
    });
  });
}
