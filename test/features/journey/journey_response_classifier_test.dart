import 'package:flutter_test/flutter_test.dart';

import 'package:bible_pal/features/journey/journey_response_classifier.dart';

/// Journey Doctrine Slice 2 Phase 7 — classifier tests.
///
/// The classifier maps free-form STT text into one of four buckets the
/// cascade dispatches on. These tests pin the priority order:
///
///   ambiguous-markers > accept-start > mood-anywhere > decline-start > ambiguous-fallback
///
/// If you ever loosen this order, mood-laced affirmatives ("yes I'm
/// anxious") would mis-route to mood-flow and the user would be denied
/// the next-in-journey story they explicitly asked for. Don't.
void main() {
  const c = JourneyResponseClassifier();

  group('empty / whitespace', () {
    test('empty string → ambiguous with empty text', () {
      final r = c.classify('');
      expect(r.bucket, JourneyResponseBucket.ambiguous);
      expect(r.text, '');
    });

    test('whitespace-only → ambiguous with empty text', () {
      expect(c.classify('   ').bucket, JourneyResponseBucket.ambiguous);
      expect(c.classify('\t\n').bucket, JourneyResponseBucket.ambiguous);
    });
  });

  group('accept', () {
    test('single-word affirmatives', () {
      for (final t in const [
        'yes',
        'yeah',
        'yep',
        'yup',
        'sure',
        'ok',
        'okay',
        'alright',
        'continue',
        'please',
        'definitely',
        'absolutely',
      ]) {
        expect(c.classify(t).bucket, JourneyResponseBucket.accept,
            reason: '"$t" should classify as accept');
      }
    });

    test('multi-word affirmatives', () {
      for (final t in const [
        "let's hear it",
        "let's go",
        'tell me more',
        'tell me about David',
        'i would like to',
        "i'd like to",
        'keep going',
        'go on',
        'go ahead',
        'yes please',
        'of course',
        'sounds good',
        'sounds great',
      ]) {
        expect(c.classify(t).bucket, JourneyResponseBucket.accept,
            reason: '"$t" should classify as accept');
      }
    });

    test('case insensitivity', () {
      expect(c.classify('YES').bucket, JourneyResponseBucket.accept);
      expect(c.classify('Yes').bucket, JourneyResponseBucket.accept);
      expect(c.classify("LET'S HEAR IT").bucket, JourneyResponseBucket.accept);
    });

    test('accept-start beats trailing mood word', () {
      // User's first word answers the offer; trailing mood is flavor.
      final r = c.classify("yes I'm anxious");
      expect(r.bucket, JourneyResponseBucket.accept);
    });

    test('original casing preserved in result text', () {
      final r = c.classify('  Yes Please  ');
      expect(r.text, 'Yes Please');
    });
  });

  group('decline', () {
    test('single-word negatives', () {
      for (final t in const ['no', 'nope', 'nah', 'skip', 'pass']) {
        expect(c.classify(t).bucket, JourneyResponseBucket.decline,
            reason: '"$t" should classify as decline');
      }
    });

    test('multi-word negatives', () {
      for (final t in const [
        'no thanks',
        'not now',
        'not today',
        'not tonight',
        'not right now',
        'something else',
        'different',
      ]) {
        expect(c.classify(t).bucket, JourneyResponseBucket.decline,
            reason: '"$t" should classify as decline');
      }
    });

    test('decline at START only — trailing "no" does not flip an accept', () {
      // "yes, no really" → accept (start wins).
      expect(
          c.classify('yes, no really').bucket, JourneyResponseBucket.accept);
    });
  });

  group('moodRedirect', () {
    test('single mood words', () {
      for (final t in const [
        'anxious',
        'scared',
        'afraid',
        'sad',
        'lonely',
        'tired',
        'exhausted',
        'grateful',
        'happy',
        'overwhelmed',
        'stressed',
        'angry',
        'lost',
        'discouraged',
      ]) {
        expect(c.classify(t).bucket, JourneyResponseBucket.moodRedirect,
            reason: '"$t" should classify as moodRedirect');
      }
    });

    test('mood expressed in a sentence', () {
      for (final t in const [
        "i'm anxious",
        'i am anxious',
        "i'm so tired",
        'i feel sad',
        'i feel grateful',
        "i'm feeling overwhelmed",
        "i can't sleep",
        "i couldn't sleep last night",
        'had a rough day',
        'hard day',
        "i'm not okay",
        "i'm not ok",
        'i need help',
      ]) {
        expect(c.classify(t).bucket, JourneyResponseBucket.moodRedirect,
            reason: '"$t" should classify as moodRedirect');
      }
    });

    test('moodRedirect beats decline when mood word present', () {
      // Doctrine: when user gives a mood signal, route to mood-flow
      // silently — do NOT play the decline clip ("That's okay…")
      // on top of an already-mood expression.
      final r = c.classify("no I'm just tired");
      expect(r.bucket, JourneyResponseBucket.moodRedirect);
    });

    test('original text passed through for downstream mood detection', () {
      final r = c.classify("  I'm Anxious tonight  ");
      expect(r.bucket, JourneyResponseBucket.moodRedirect);
      // Trimmed but casing preserved — MoodService gets the user's
      // actual phrasing, not a flattened lowercase.
      expect(r.text, "I'm Anxious tonight");
    });
  });

  group('ambiguous', () {
    test('explicit "don\'t know" markers', () {
      for (final t in const [
        "i don't know",
        "don't know",
        'do not know',
        'not sure',
        'dunno',
        'i dunno',
        'i guess',
      ]) {
        expect(c.classify(t).bucket, JourneyResponseBucket.ambiguous,
            reason: '"$t" should classify as ambiguous');
      }
    });

    test('hesitation tokens', () {
      for (final t in const ['hmm', 'hmmm', 'um', 'umm', 'uh', 'uhhh']) {
        expect(c.classify(t).bucket, JourneyResponseBucket.ambiguous,
            reason: '"$t" should classify as ambiguous');
      }
    });

    test('"maybe" is ambiguous (not accept, not decline)', () {
      expect(c.classify('maybe').bucket, JourneyResponseBucket.ambiguous);
    });

    test('"I don\'t know" is ambiguous, NOT decline', () {
      // Regression guard: "don't" must not trigger decline-start. The
      // ambiguous-markers check runs BEFORE accept/mood/decline.
      expect(c.classify("i don't know").bucket,
          JourneyResponseBucket.ambiguous);
    });

    test('unrecognized utterance → ambiguous fallback', () {
      // No pattern matches → fall through to ambiguous.
      expect(c.classify('what is this').bucket,
          JourneyResponseBucket.ambiguous);
      expect(c.classify('purple monkey dishwasher').bucket,
          JourneyResponseBucket.ambiguous);
    });
  });

  group('priority order — locked', () {
    test('ambiguous-markers > everything', () {
      // "I don't know if I'm anxious" — contains both "don't know" and
      // mood word "anxious." Ambiguous wins because the user's primary
      // statement is uncertainty, not the mood.
      expect(
        c.classify("i don't know if i'm anxious").bucket,
        JourneyResponseBucket.ambiguous,
      );
    });

    test('accept-start > mood-anywhere', () {
      // Tested above; pinned here as the canonical example.
      expect(c.classify("yes I'm anxious").bucket,
          JourneyResponseBucket.accept);
    });

    test('mood-anywhere > decline-start', () {
      // Tested above; pinned here as the canonical example.
      expect(c.classify("no I'm just tired").bucket,
          JourneyResponseBucket.moodRedirect);
    });

    test('decline-start > ambiguous-fallback', () {
      expect(c.classify('no').bucket, JourneyResponseBucket.decline);
    });
  });

  group('JourneyResponseClassification equality', () {
    test('value equality on bucket + text', () {
      const a = JourneyResponseClassification(
          bucket: JourneyResponseBucket.accept, text: 'yes');
      const b = JourneyResponseClassification(
          bucket: JourneyResponseBucket.accept, text: 'yes');
      const cDiff = JourneyResponseClassification(
          bucket: JourneyResponseBucket.decline, text: 'yes');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(cDiff)));
    });
  });
}
