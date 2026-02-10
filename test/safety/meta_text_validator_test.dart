import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/safety/meta_text_validator.dart';

void main() {
  late MetaTextValidator validator;

  setUp(() {
    validator = MetaTextValidator();
  });

  group('Meta-text blocklist rejection', () {
    test('CRITICAL: rejects output starting with "Here is"', () {
      final result = validator.validate(
        'Here is a retelling of the parable of the lost sheep...',
      );
      expect(result.isValid, isFalse);
      expect(result.violations, isNotEmpty);
    });

    test('CRITICAL: rejects output starting with "Certainly"', () {
      final result = validator.validate(
        'Certainly! The storm raged across the Sea of Galilee...',
      );
      expect(result.isValid, isFalse);
    });

    test('CRITICAL: rejects "This version" meta-text', () {
      final result = validator.validate(
        'This version uses the World English Bible translation...',
      );
      expect(result.isValid, isFalse);
    });

    test('CRITICAL: rejects "In this retelling" meta-text', () {
      final result = validator.validate(
        'In this retelling of David and Goliath, we explore...',
      );
      expect(result.isValid, isFalse);
    });

    test('CRITICAL: rejects "The following" meta-text', () {
      final result = validator.validate(
        'The following story is based on Luke 15...',
      );
      expect(result.isValid, isFalse);
    });

    test('CRITICAL: rejects "Expanded carefully" meta-text', () {
      final result = validator.validate(
        'Expanded carefully from the original text, this passage...',
      );
      expect(result.isValid, isFalse);
    });

    test('CRITICAL: rejects "Staying true to" meta-text', () {
      final result = validator.validate(
        'Staying true to the original Hebrew, this story...',
      );
      expect(result.isValid, isFalse);
    });

    test('CRITICAL: rejects "This passage" meta-text', () {
      final result = validator.validate(
        'This passage from Romans reminds us of God\'s love...',
      );
      expect(result.isValid, isFalse);
    });

    test('accepts clean Scripture narration', () {
      final result = validator.validate(
        'And we know that all things work together for good '
        'to those who love God, to those who are called '
        'according to His purpose.',
      );
      expect(result.isValid, isTrue);
    });

    test('accepts clean story opening', () {
      final result = validator.validate(
        'The shepherd counted his flock as evening fell. '
        'Ninety-nine stood huddled against the cooling wind, '
        'but one was missing.',
      );
      expect(result.isValid, isTrue);
    });

    test('rejects empty output', () {
      final result = validator.validate('');
      expect(result.isValid, isFalse);
    });

    test('rejects whitespace-only output', () {
      final result = validator.validate('   \n\n  ');
      expect(result.isValid, isFalse);
    });
  });

  group('DECLARATIVE_ONLY verse enforcement', () {
    test('CRITICAL: Romans 8:28 classified as DECLARATIVE_ONLY', () {
      expect(
        VerseClassification.classify('Romans 8:28'),
        equals(VerseType.declarativeOnly),
      );
    });

    test('rejects narrative scene-setting for declarative verse', () {
      final result = validator.validate(
        'And we know that all things work together for good. '
        'Long ago, in the time of the apostles, Paul wrote these words.',
        verseType: VerseType.declarativeOnly,
      );
      expect(result.isValid, isFalse);
      expect(
        result.violations.any((v) => v.contains('DECLARATIVE_ONLY')),
        isTrue,
      );
    });

    test('rejects imagined listeners for declarative verse', () {
      final result = validator.validate(
        'And we know that all things work together for good. '
        'The crowd gathered to hear these words of hope.',
        verseType: VerseType.declarativeOnly,
      );
      expect(result.isValid, isFalse);
    });

    test('accepts pure statement elevation for declarative verse', () {
      final result = validator.validate(
        'And we know that all things work together for good '
        'to those who love God, to those who are called '
        'according to His purpose. '
        'In every trial, in every sorrow, in every uncertainty — '
        'all things are held within the sovereign care of the Almighty.',
        verseType: VerseType.declarativeOnly,
      );
      expect(result.isValid, isTrue);
    });

    test('allows narrative for NARRATIVE_ELIGIBLE verse', () {
      final result = validator.validate(
        'Long ago, in the time of the judges, a great storm arose. '
        'The people gathered in the temple to pray.',
        verseType: VerseType.narrativeEligible,
      );
      // narrative patterns are fine for narrative-eligible
      expect(result.isValid, isTrue);
    });
  });

  group('Verse classification registry', () {
    test('unclassified verse defaults to NARRATIVE_ELIGIBLE', () {
      expect(
        VerseClassification.classify('Genesis 1:1'),
        equals(VerseType.narrativeEligible),
      );
    });

    test('null reference defaults to NARRATIVE_ELIGIBLE', () {
      expect(
        VerseClassification.classify(null),
        equals(VerseType.narrativeEligible),
      );
    });

    test('known declarative verses are classified correctly', () {
      final declarativeVerses = [
        'Romans 8:28',
        'Jeremiah 29:11',
        'Philippians 4:13',
        'Isaiah 41:10',
        'Matthew 11:28',
        'Psalm 46:10',
      ];
      for (final ref in declarativeVerses) {
        expect(
          VerseClassification.classify(ref),
          equals(VerseType.declarativeOnly),
          reason: '$ref should be DECLARATIVE_ONLY',
        );
      }
    });
  });

  group('Reflection firewall', () {
    test('CRITICAL: rejects comfort language in narration', () {
      final result = validator.validate(
        'The Lord is my shepherd. Take comfort in knowing '
        'that God walks beside you always.',
      );
      expect(result.isValid, isFalse);
      expect(
        result.violations.any((v) => v.contains('Reflection')),
        isTrue,
      );
    });

    test('CRITICAL: rejects explanation language in narration', () {
      final result = validator.validate(
        'For God so loved the world. This means us that '
        'salvation is freely given.',
      );
      // "this means us that" matches the pattern
      expect(result.isValid, isFalse);
    });

    test('CRITICAL: rejects application language in narration', () {
      final result = validator.validate(
        'Be still and know that I am God. '
        'When you face trials in your daily walk, remember these words.',
      );
      expect(result.isValid, isFalse);
    });

    test('accepts pure narration without reflection language', () {
      final result = validator.validate(
        'Jesus said unto them, "Come unto me, all ye that labour '
        'and are heavy laden, and I will give you rest. Take my yoke '
        'upon you, and learn of me; for I am meek and lowly in heart: '
        'and ye shall find rest unto your souls."',
      );
      expect(result.isValid, isTrue);
    });
  });

  group('Meta-text harness regeneration loop', () {
    test('passes on first attempt if clean', () {
      final harness = MetaTextHarness();
      final result = harness.run(
        storyText: 'The shepherd counted his sheep at dusk.',
        regenerate: (_) => throw StateError('Should not regenerate'),
      );
      expect(result.isClean, isTrue);
      expect(result.attemptCount, 1);
    });

    test('regenerates on meta-text and accepts clean retry', () {
      var callCount = 0;
      final harness = MetaTextHarness();
      final result = harness.run(
        storyText: 'Here is a story about the lost sheep...',
        regenerate: (repair) {
          callCount++;
          expect(repair, isNotNull);
          expect(repair, isNotEmpty);
          return 'The shepherd counted his sheep at dusk.';
        },
      );
      expect(result.isClean, isTrue);
      expect(callCount, 1);
      expect(result.attemptCount, 2);
    });

    test('marks as contaminated after max attempts', () {
      final harness = MetaTextHarness();
      final result = harness.run(
        storyText: 'Here is a story...',
        regenerate: (_) => 'Certainly! Let me tell you...',
      );
      expect(result.isClean, isFalse);
      expect(result.attemptCount, kMetaTextMaxRegenAttempts);
    });

    test('repair instruction is non-empty on failure', () {
      final result = validator.validate('Here is the story of David...');
      expect(result.isValid, isFalse);
      expect(result.repairInstruction, isNotEmpty);
      expect(result.repairInstruction, contains('REJECTED'));
    });
  });

  group('Custom blocklist', () {
    test('supports custom blocklist', () {
      final custom = MetaTextValidator(blocklist: ['CUSTOM_MARKER']);
      final result = custom.validate('CUSTOM_MARKER: the story begins...');
      expect(result.isValid, isFalse);
    });

    test('custom blocklist does not include defaults', () {
      final custom = MetaTextValidator(blocklist: ['CUSTOM_MARKER']);
      final result = custom.validate('Here is the story...');
      // "here is" not in custom blocklist, so it passes blocklist check
      expect(result.isValid, isTrue);
    });
  });
}
