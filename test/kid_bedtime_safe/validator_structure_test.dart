/// Kid Bedtime Safe - Structure Validator Tests
///
/// Tests that the validator correctly checks for required story structure
/// as specified in the Kid Bedtime Contract (5-part structure, bedtime closing).
///
/// Spec clause: "Required structure headings or sections exist (5 sections)"
/// Spec clause: "Ending includes a 'calm bedtime closing' signal"
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

    test('fails when story lacks bedtime closing signals', () {
      const noBedtimeClosing = '''
Samuel was a young boy who lived in a very special place called the temple.
It was a quiet and peaceful building where many people came to pray each day.
Samuel had a small room where he stayed and he felt very comfortable there.

He helped the kind old priest named Eli with many daily tasks and chores.
Samuel would carry things carefully and keep everything clean and organized.
Eli appreciated Samuel's help very much and treated him like a grandson.

One quiet day, Samuel heard a mysterious voice calling out his name softly.
At first he was confused and thought it might be Eli calling for him.
But Eli told him it was not his voice and to listen more carefully next time.

Samuel learned to listen carefully to God's voice whenever it called to him.
He understood that God wanted to communicate with him about important things.
This made Samuel feel very special and honored to be chosen by God.

Samuel grew up to become a wise and respected leader among all the people.
He guided them with wisdom and helped them understand God's messages.
Everyone looked up to Samuel for guidance and advice on important matters.
''';
      final result = validator.validate(noBedtimeClosing);

      expect(result.isValid, isFalse);
      expect(
        result.otherViolations.any((v) => v.contains('bedtime')),
        isTrue,
      );
    });

    test('passes when story has proper sections and bedtime closing', () {
      const properStory = '''
Little Samuel lived in a very special place called the temple. It was
a quiet, peaceful building where many people came to pray each day. Samuel had
a small bed in a cozy corner, and he felt very safe and loved there always.

Every day, Samuel would wake up early to help the kind priest named Eli.
He would carry things carefully and keep everything clean and tidy. Eli was
like a grandfather to Samuel, always gentle, patient, and full of wisdom.
Samuel loved spending time with Eli and learning from him each day.

One quiet night, Samuel heard someone calling his name very softly.
At first he thought it was Eli calling for him, but Eli was sleeping.
Samuel felt curious but not afraid. He trusted that everything was okay.
The voice was gentle and kind, not scary at all.

Eli told Samuel that it might be God speaking to him directly.
Samuel felt very special knowing that God wanted to talk to him.
He felt loved and important, just like every child is to God.
This made Samuel very happy and grateful.

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

    test('detects various bedtime closing signals', () {
      final closingSignals = [
        'and he drifted off to sleep peacefully.',
        'the children rested quietly under the stars.',
        'feeling warm and safe, she closed her eyes to dream.',
        'the calm night brought peace to everyone.',
        'snuggled in his cozy blanket, he smiled softly.',
        'as the moon rose, all was quiet and peaceful.',
      ];

      for (final closing in closingSignals) {
        final story = '''
This is a wonderful story about a child who learned about God's amazing love.
The child was young and curious about the world around them. They asked many
questions about life and faith and always wanted to learn new things.

The child spent quiet time in prayer and reflection each and every day.
They would sit in a peaceful spot and think about all the good things in life.
Prayer became an important part of their daily routine and brought them joy.

The kind adults in the village taught the child many important lessons.
They shared stories of faith and hope that had been passed down through time.
The child listened carefully and remembered everything they were taught.

They learned to trust completely in God's loving care and protection always.
Knowing that God was watching over them made the child feel safe and secure.
This trust gave them courage to face each new day with confidence and hope.

$closing
''';
        final result = validator.validate(story);

        expect(
          result.otherViolations.any((v) => v.contains('bedtime')),
          isFalse,
          reason: 'Should accept closing: "$closing"',
        );
      }
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
