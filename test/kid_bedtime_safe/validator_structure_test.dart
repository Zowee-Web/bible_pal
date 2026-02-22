/// Kid Safe - Structure Validator Tests
///
/// Tests that the validator correctly checks for required story structure
/// as specified in the Kid Story Contract (5-part structure, gentle ending).
///
/// Spec clause: "Required structure headings or sections exist (5 sections)"
@Tags(['kid-safety', 'critical'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/safety/kid_bedtime_validator.dart';

void main() {
  group('KidBedtimeValidator - Structure', () {
    late KidBedtimeValidator validator;

    setUp(() {
      // Empty forbidden list to focus on structure tests
      validator = KidBedtimeValidator.withPatterns([]);
    });

    test('fails when story is too short', () {
      const tooShort = 'This is a very short story. The end.';
      final result = validator.validate(tooShort);

      expect(result.isValid, isFalse);
      expect(
        result.structureViolations.any((v) => v.contains('too short')),
        isTrue,
      );
    });

    test('fails when story lacks distinct sections', () {
      // One long paragraph with no breaks
      const noSections =
          'This is a story that goes on and on without any paragraph breaks. '
          'It just keeps going in one continuous block of text that never stops. '
          'There are no natural divisions or sections to help organize the content. '
          'The child would get confused listening to this without any pauses. '
          'We really should have multiple sections to make it easier to follow. '
          'But this story just rambles on without any structure at all. '
          'It continues and continues without giving the listener a break. '
          'This makes it hard to process and not suitable for bedtime listening. '
          'A proper bedtime story should have clear beginning, middle and end. '
          'But this one just goes on without any clear divisions whatsoever.';

      final result = validator.validate(noSections);

      expect(result.isValid, isFalse);
      expect(
        result.structureViolations.any((v) => v.contains('sections')),
        isTrue,
      );
    });

    test('passes when story has proper sections and gentle ending', () {
      // Note: Story must be >= 250 words (LOCKED SPEC short bucket minimum)
      const properStory = '''
Little Samuel lived in a very special place called the temple. It was
a quiet, peaceful building where many people came to pray each day. Samuel had
a small bed in a cozy corner, and he felt very safe and loved there always.
The temple was a wonderful home for the young boy.

Every day, Samuel would wake up early to help the kind priest named Eli.
He would carry things carefully and keep everything clean and tidy. Eli was
like a grandfather to Samuel, always gentle, patient, and full of wisdom.
Samuel loved spending time with Eli and learning from him each day.
They worked together happily in the peaceful temple.

One quiet night, Samuel heard someone calling his name very softly.
At first he thought it was Eli calling for him, but Eli was sleeping.
Samuel felt curious but not afraid. He trusted that everything was okay.
The voice was gentle and kind, not scary at all.

Eli told Samuel that it might be God speaking to him directly.
Samuel felt very special knowing that God wanted to talk to him.
He felt loved and important, just like every child is to God.
This made Samuel very happy and grateful for the blessing.

As the night grew quiet again, Samuel lay back down in his soft bed.
The stars twinkled through the window like many tiny nightlights.
He closed his eyes and smiled, feeling peaceful and safe in his room.
The gentle night wrapped around him like a warm, cozy blanket,
and Samuel drifted off to a restful, peaceful sleep.
''';
      final result = validator.validate(properStory);

      expect(result.isValid, isTrue);
      expect(result.structureViolations, isEmpty);
      expect(result.otherViolations, isEmpty);
    });

  });

  group('KidBedtimeValidator - Sentence Length', () {
    late KidBedtimeValidator validator;

    setUp(() {
      validator = KidBedtimeValidator.withPatterns([]);
    });

    test('passes when sentences are short and simple', () {
      const shortSentences = '''
Samuel was a little boy. He lived in the temple.
It was a quiet place. Samuel had a small bed.
He felt safe and loved. The temple was his home.

Every day Samuel helped Eli. He carried things with care.
Eli was kind to Samuel. They worked well together.
The temple stayed clean. Everyone was grateful.

Every night, he would sleep well. The temple was peaceful.
Samuel felt safe there. God watched over him always.
The stars twinkled outside. All was calm and still.

One night, Samuel heard a voice. It was soft and gentle.
Samuel was not afraid. He listened carefully.
The voice called his name. Samuel sat up slowly.

Eli told Samuel to listen. God was speaking to him.
Samuel felt special. He knew God loved him.
This made Samuel happy. He smiled in the darkness.

The voice was God speaking. Samuel felt loved and special.
He smiled and closed his eyes. Sleep came peacefully.
The night was quiet. Samuel rested well until morning.
''';
      final result = validator.validate(shortSentences);

      expect(result.avgWordsPerSentence, lessThanOrEqualTo(15));
      expect(
        result.otherViolations.any((v) => v.contains('Sentences too long')),
        isFalse,
      );
    });

    test('fails when sentences are too long', () {
      const longSentences = '''
Once upon a time there was a little boy named Samuel who lived in a very
special and sacred temple building where people would come from all around
the countryside to pray and worship and seek guidance from the Lord.

Samuel had many duties that he needed to perform each and every day including
cleaning and organizing and helping the elderly priest named Eli who was
getting old and could not see very well anymore.

One particularly quiet and peaceful evening when all the lamps had been
extinguished and the only light came from the stars twinkling through
the high temple windows, Samuel heard a mysterious voice calling out
his name in the darkness. He felt peaceful and drifted to sleep.
''';
      final result = validator.validate(longSentences);

      expect(result.avgWordsPerSentence, greaterThan(15));
      expect(
        result.otherViolations.any((v) => v.contains('Sentences too long')),
        isTrue,
      );
    });
  });
}
