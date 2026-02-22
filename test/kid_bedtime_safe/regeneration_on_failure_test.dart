/// Kid Bedtime Safe - Regeneration on Failure Tests
///
/// Tests that the harness correctly triggers regeneration when validation fails
/// and respects the maximum attempt limit.
///
/// Spec clause: "If validation fails, automatically regenerate with repair instruction"
/// Spec clause: "Max attempts: 3 (configurable constant)"
/// Spec clause: "If still failing, return best attempt marked unsafe"
@Tags(['kid-safety', 'critical'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/safety/kid_bedtime_validator.dart';

void main() {
  group('KidBedtimeHarness - Regeneration', () {
    late KidBedtimeValidator validator;

    setUp(() {
      validator = KidBedtimeValidator.withPatterns([
        'roar',
        'roared',
        'jaws',
        'terror',
        'crown',
        'throne',
        'king',
      ]);
    });

    test('accepts valid story on first attempt without regeneration', () {
      var regenerationCount = 0;

      // Note: Story must be >= 250 words (LOCKED SPEC short bucket minimum)
      const validStory = '''
Samuel was a young boy who lived in a special place called the temple. It was
a quiet and peaceful building where people came to pray. Samuel had a small
bed in a cozy corner, and he felt very safe and loved there every single day.
The temple was his home, and he loved it very much.

Every day, Samuel helped the kind old priest named Eli with daily tasks.
He would carry things carefully and keep everything clean and tidy.
Eli was like a grandfather to Samuel, always gentle, patient, and caring.
Everything was peaceful and calm in their little home together.
Samuel enjoyed every moment of helping his dear friend Eli.

One quiet night, Samuel heard a gentle voice calling his name softly.
At first he thought it was Eli, but Eli was sleeping peacefully.
Samuel felt curious but not afraid. He trusted that everything was okay.
The voice was soft and kind, like a loving parent speaking to a child.
Samuel listened carefully and wondered who could be calling.

Samuel learned to listen carefully to God. He felt so special knowing
that God wanted to talk with him. Samuel felt loved and important.
God cared for Samuel just like God cares for every child in the world.
This made Samuel happy and thankful for God's love.

The stars twinkled softly outside his window like tiny nightlights.
Samuel whispered a quiet prayer of thanks. His heart felt calm.
As Samuel closed his eyes to sleep, he smiled peacefully, knowing
tomorrow would bring more of God's gentle love and care for him.
''';

      final harness = KidBedtimeHarness(
        validator: validator,
        maxAttempts: 3,
      );

      final result = harness.run(
        storyText: validStory,
        regenerate: (instruction) {
          regenerationCount++;
          return validStory; // Won't be called
        },
      );

      expect(result.isKidSafe, isTrue);
      expect(result.attemptCount, equals(1));
      expect(regenerationCount, equals(0));
    });

    test('triggers regeneration when forbidden words detected', () {
      var regenerationCount = 0;
      final instructions = <String?>[];

      const badStory = '''
The lion let out a mighty roar that echoed through the valley. Its jaws
opened wide showing all its sharp teeth. The animals in the forest heard
the sound and trembled with fear. Even the bravest creatures were nervous.

Terror filled the hearts of all who saw the mighty lion walking through
the land. The people did not know what to do. They gathered together in
the village square to discuss what might happen to them all. They worried.

The people decided to make him king and gave him a golden crown. They
thought that if they honored the lion, he would protect them instead of
hurting them. It seemed like a good plan at the time to everyone there.

He sat upon the throne of the land and looked out at all his new subjects.
The people bowed before him hoping he would be kind. He was peaceful finally
and the villagers felt some relief. They hoped for the best outcome now.

The night was quiet and still. The stars twinkled in the dark sky above.
Everyone went home to their beds feeling tired from the long day. He closed
his eyes and drifted to a peaceful sleep under the moonlight.
''';

      const goodStory = '''
The gentle cat purred softly as it lay in the warm afternoon sunshine. It
nuzzled against the child with such tenderness and love. The cat's fur was
soft and warm to touch. The child giggled with delight as the cat rubbed
against her little hand. They were the best of friends, child and cat.

Peace filled the hearts of all who saw the sweet moment between child and
pet. The other children from the village gathered around to watch and smile.
They all wanted to pet the friendly cat too. Everyone waited patiently for
their turn. The cat enjoyed all the attention and purred even louder.

The people of the village celebrated with songs of joy and happiness together.
They sang about love and kindness and gratitude for all their blessings. The
music filled the air with beautiful melodies. Even the birds seemed to join
in the singing. It was a wonderful day for everyone in the little village.

Everyone felt happy and grateful for the wonderful day they had shared with
each other. They ate delicious food together and told stories about old times.
All was peaceful and calm in the village. The children played games happily
while their parents watched over them with loving smiles on their faces.

The night was quiet and the stars twinkled softly overhead like tiny lights.
The children yawned and rubbed their sleepy eyes. It was time for bed now.
They said goodnight to each other and drifted to restful, peaceful sleep.
''';

      final harness = KidBedtimeHarness(
        validator: validator,
        maxAttempts: 3,
      );

      final result = harness.run(
        storyText: badStory,
        regenerate: (instruction) {
          regenerationCount++;
          instructions.add(instruction);
          // Second attempt returns good story
          return goodStory;
        },
      );

      expect(result.isKidSafe, isTrue);
      expect(result.attemptCount, equals(2));
      expect(regenerationCount, equals(1));

      // Check repair instruction was provided
      expect(instructions.first, isNotNull);
      expect(instructions.first, contains('FORBIDDEN WORDS DETECTED'));
      expect(instructions.first, contains('roar'));
      expect(instructions.first, contains('jaws'));
      expect(instructions.first, contains('terror'));
    });

    test('respects max attempts limit and marks as unsafe', () {
      var regenerationCount = 0;

      const alwaysBadStory = '''
The lion roared with great power that could be heard far and wide. Its jaws
gleamed in the sunlight as it walked through the land. All the animals ran
away in terror when they heard the mighty sound echoing through the valley.

The king wore his golden crown upon his head as he sat on the throne. He
looked out at all his subjects with pride and satisfaction. The people
bowed before him, hoping he would be a fair and kind ruler to them all.

More forbidden words appeared in the story like roar and terror and jaws.
The lion continued to frighten everyone it encountered on its journey.
The king commanded his servants to bring him food and drink immediately.

The villagers gathered together in the square to discuss what they should
do about the lion roaming their lands. They were worried and afraid. The
elders suggested asking the king for help but others were not so sure.

The night was quiet and still after the long eventful day. The moon rose
high in the sky and the stars twinkled softly. Sleep came peacefully to
all the tired villagers as they rested in their warm comfortable beds.
''';

      final harness = KidBedtimeHarness(
        validator: validator,
        maxAttempts: 3,
      );

      final result = harness.run(
        storyText: alwaysBadStory,
        regenerate: (instruction) {
          regenerationCount++;
          // Always return bad story
          return alwaysBadStory;
        },
      );

      expect(result.isKidSafe, isFalse);
      expect(result.attemptCount, equals(3));
      expect(
          regenerationCount, equals(2)); // 2 regenerations after first attempt
      expect(result.finalViolations, isNotEmpty);
    });

    test('final violations are logged for failed stories', () {
      const badStory = '''
The lion roared loudly at the great stone throne in the middle of the
palace courtyard. Terror was everywhere as people ran in all directions.
The sound echoed off the walls and could be heard throughout the land.

The king wore a beautiful golden crown upon his head as he watched from
his balcony above. He was not afraid of the lion below because he knew
his guards would protect him. The crown sparkled in the bright sunlight.

The lion's great jaws snapped shut with a loud click that made everyone
jump in surprise. The creature was hungry and looking for something to
eat. The servants quickly brought it some food to keep it satisfied.

The villagers watched from a safe distance as the scene unfolded before
them. They whispered to each other about what might happen next. Some
wanted to run away but others were too curious to leave just yet.

Night came eventually and sleep followed peacefully for everyone. The
moon rose high and the stars twinkled softly in the dark sky above.
All the tired people closed their eyes and drifted off to restful sleep.
''';

      final harness = KidBedtimeHarness(
        validator: validator,
        maxAttempts: 1, // Only one attempt
      );

      final result = harness.run(
        storyText: badStory,
        regenerate: (_) => badStory,
      );

      expect(result.isKidSafe, isFalse);
      expect(result.finalViolations, isNotEmpty);
      // Check that forbidden words are in violations (using 'roared' since that's the pattern)
      expect(
        result.finalViolations.any((v) => v.contains('roared')),
        isTrue,
      );
      expect(
        result.finalViolations.any((v) => v.contains('throne')),
        isTrue,
      );
    });

    test('repair instruction includes all failure reasons', () {
      const badStory =
          'The king roared.'; // Short, bad word

      final result = validator.validate(badStory);

      expect(result.isValid, isFalse);
      final repair = result.repairInstruction;

      // Should mention forbidden word (roared matches 'roared' pattern)
      expect(repair, contains('FORBIDDEN WORDS DETECTED'));
      expect(repair, contains('roared'));
      expect(repair, contains('king'));

      // Should mention structure issues
      expect(
        repair.contains('STRUCTURE PROBLEMS') || repair.contains('too short'),
        isTrue,
      );

      // Should include regeneration guidance
      expect(repair, contains('REWRITE'));
      expect(repair, contains('children ages 5-9'));
    });

    test('configurable max attempts works correctly', () {
      var regenerationCount = 0;

      const badStory = '''
The lion roared loudly in the middle of the forest clearing. The sound
echoed through the trees and could be heard from very far away. All the
small animals quickly hid in their burrows and nests for safety.

Terror filled the night as the great beast continued to prowl around
looking for food. The villagers stayed inside their homes with doors
locked tight. No one wanted to be outside when the lion was hunting.

The elders of the village gathered to discuss what they should do about
the dangerous situation. Some suggested sending hunters while others
wanted to wait and hope the lion would simply move on to another area.

Meanwhile the children were safely tucked into their warm beds by their
parents. They were told stories to help them feel less afraid of the
sounds outside. The parents promised everything would be okay.

But eventually peace came as the lion wandered away into the distance.
The village grew quiet once more. All the tired people finally relaxed
and slept peacefully through the rest of the calm quiet night.
''';

      // Test with different max attempts
      for (final maxAttempts in [1, 2, 5]) {
        regenerationCount = 0;

        final harness = KidBedtimeHarness(
          validator: validator,
          maxAttempts: maxAttempts,
        );

        final result = harness.run(
          storyText: badStory,
          regenerate: (_) {
            regenerationCount++;
            return badStory; // Always fail
          },
        );

        expect(result.attemptCount, equals(maxAttempts));
        expect(regenerationCount, equals(maxAttempts - 1));
        expect(result.isKidSafe, isFalse);
      }
    });

    test('default max attempts is 3', () {
      expect(kMaxRegenAttempts, equals(3));
    });
  });

  group('KidBedtimeHarness - Integration', () {
    test('mocked Gemma output with forbidden words triggers regeneration', () {
      // Simulates what would happen with actual Gemma output
      final validator = KidBedtimeValidator.withPatterns([
        'roar',
        'jaws',
        'devour',
        'crown',
        'king',
        'throne',
      ]);

      // Simulate Gemma's first attempt (contains problems - must be 200+ words)
      const gemmaAttempt1 = '''
Jonah was a man who lived in a small and quiet village by the beautiful sea.
One special day, God asked Jonah to go to the great city of Nineveh and tell
the people there to change their ways and be kind to each other. But Jonah
was afraid and did not want to go on this long and difficult journey.

Instead, Jonah got on a boat that was sailing far away from Nineveh. The sea
was calm and peaceful at first, with gentle waves rocking the boat softly.
But then a terrible storm arose from nowhere. The waves crashed loudly against
the ship. Jonah knew in his heart that the storm was because of him running
away from God's important task. He felt sorry for not listening to God.

Jonah was swallowed by a great and mighty fish. Its massive jaws opened wide
and Jonah found himself inside the dark belly of the creature. He prayed to
God for three long days and nights without stopping. God heard his sincere
prayer and the fish spit Jonah onto dry land safely. He was grateful.

Jonah finally went to the city of Nineveh just as God had asked him to do.
The people there listened carefully to his words and they all changed. God was
so happy that he made Jonah king of the city. He wore a golden shining crown
and sat upon the magnificent throne. Everyone celebrated his great victory.

The city was peaceful and quiet and everyone slept well that night under the
stars. The moon shone brightly in the sky. All were at rest.
''';

      // Simulate Gemma's second attempt after repair instruction (safe version, 200+ words)
      const gemmaAttempt2 = '''
Jonah was a man who lived in a small and quiet village by the beautiful sea.
One special day, God asked Jonah to go to a great city and tell the people
there to be kind and loving to each other. Jonah was unsure at first, but
he trusted in God's wonderful plan for him and his life's purpose.

Jonah went on a peaceful journey by boat across the calm waters. The sea was
calm and beautiful with gentle waves. The gentle waves rocked the boat softly
back and forth. Jonah watched the fluffy clouds drift slowly by in the sky
and thought about how much God loved everyone in the whole world.

Inside a safe and cozy place, Jonah prayed quietly and sincerely to God. He
felt very thankful for God's love and guidance every single day. God heard
his heartfelt prayer and filled his heart with peace, courage, and joy to
continue on his important journey. Jonah smiled feeling God's presence.

Jonah went to the city just as God had asked him to do. The people there
listened carefully and learned to be kind and loving to each other. Everyone
felt very happy and grateful for the new understanding. They shared delicious
meals together and helped all their neighbors. The whole city changed.

The city was peaceful and quiet as night fell gently upon the land. As the
bright stars twinkled softly overhead like many tiny lights, everyone closed
their eyes and drifted off to restful, peaceful sleep in their warm beds.
''';

      var attemptNumber = 0;
      final harness = KidBedtimeHarness(
        validator: validator,
        maxAttempts: 3,
      );

      final result = harness.run(
        storyText: gemmaAttempt1,
        regenerate: (instruction) {
          attemptNumber++;
          // Verify repair instruction is meaningful
          expect(instruction, isNotNull);
          expect(instruction, contains('FORBIDDEN WORDS'));
          // Return fixed version
          return gemmaAttempt2;
        },
      );

      expect(result.isKidSafe, isTrue);
      expect(result.attemptCount, equals(2));
      expect(attemptNumber, equals(1));
      expect(result.finalText, equals(gemmaAttempt2));
    });
  });
}
