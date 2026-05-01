import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/services/mood_service.dart';

void main() {
  group('MoodService.getMicroResponseText', () {
    test('returns a non-empty response for each mood', () {
      final service = MoodService(random: Random(0));

      for (final mood in ['joyful', 'grateful', 'weary', 'anxious', 'hurting', 'brave_courage', 'calm_peaceful', 'encouraging']) {
        final text = service.getMicroResponseText(mood);
        expect(text.isNotEmpty, true,
            reason: '$mood response should not be empty');
      }
    });

    test('unknown mood falls back to neutral', () {
      final service = MoodService(random: Random(0));
      final text = service.getMicroResponseText('unknown_mood');
      expect(text.isNotEmpty, true);
    });

    test('all micro-response texts are 12 words or fewer', () {
      for (final mood in ['joyful', 'grateful', 'weary', 'anxious', 'hurting', 'brave_courage', 'calm_peaceful', 'encouraging']) {
        for (var seed = 0; seed < 50; seed++) {
          final s = MoodService(random: Random(seed));
          final text = s.getMicroResponseText(mood);
          final wordCount = text.split(RegExp(r'\s+')).length;
          expect(wordCount, lessThanOrEqualTo(12),
              reason: '$mood response "$text" has $wordCount words (max 12)');
        }
      }
    });

    test('all micro-response texts contain a transition indicator', () {
      for (final mood in ['joyful', 'grateful', 'weary', 'anxious', 'hurting', 'brave_courage', 'calm_peaceful', 'encouraging']) {
        for (var seed = 0; seed < 50; seed++) {
          final s = MoodService(random: Random(seed));
          final text = s.getMicroResponseText(mood);
          final lower = text.toLowerCase();
          expect(
            lower.contains('story') ||
                lower.contains('listen') ||
                lower.contains('play') ||
                lower.contains('share') ||
                lower.contains('hear') ||
                lower.contains('something') ||
                lower.contains("here's"),
            true,
            reason: '$mood response should contain a transition indicator: "$text"',
          );
        }
      }
    });
  });

  group('MoodService.detectMood', () {
    test('detects mood from keywords', () {
      final service = MoodService(random: Random(0));
      final result = service.detectMood('I am feeling very anxious today');
      expect(result.mood, isNotEmpty);
    });

    test('returns calm_peaceful for empty input', () {
      final service = MoodService(random: Random(0));
      final result = service.detectMood('');
      expect(result.mood, 'calm_peaceful');
    });

    // SPEC §3.1 (Emotional-Fit Selection Rule). Bug regression: short
    // positive replies like "Excellent" used to fall through every
    // keyword bucket and default to `weary`, which then routed users
    // to suffering content (e.g. "Job Loses Everything").
    test('classifies "Excellent" as joyful', () {
      final service = MoodService(random: Random(0));
      expect(service.detectMood('Excellent').mood, 'joyful');
      expect(service.detectMood('excellent!').mood, 'joyful');
      expect(service.detectMood("I'm doing excellent today").mood, 'joyful');
    });

    test('classifies common positive superlatives as joyful', () {
      final service = MoodService(random: Random(0));
      for (final word in const [
        'Excellent',
        'Perfect',
        'Splendid',
        'Incredible',
        'Terrific',
        'Lovely',
        'Fabulous',
        'Marvelous',
      ]) {
        expect(service.detectMood(word).mood, 'joyful',
            reason: '"$word" must classify as joyful, not fall through to weary');
      }
    });

    test('positive single-word inputs never default to weary or hurting', () {
      final service = MoodService(random: Random(0));
      const positives = [
        'Excellent', 'Perfect', 'Wonderful', 'Great', 'Amazing',
        'Fantastic', 'Awesome', 'Splendid', 'Incredible', 'Terrific',
        'Joyful', 'Happy', 'Blessed', 'Grateful',
      ];
      for (final word in positives) {
        final mood = service.detectMood(word).mood;
        expect(mood, isNot(equals('weary')),
            reason: '"$word" must not classify as weary (was the bug)');
        expect(mood, isNot(equals('hurting')),
            reason: '"$word" must not classify as hurting');
      }
    });

    test('unrecognized non-empty input falls back to calm_peaceful, not weary',
        () {
      // Per INVARIANTS.md "Mood System": the safe default is
      // calm_peaceful. Pre-fix this branch returned weary, which is
      // exactly the misroute that produced the Job Loses Everything bug.
      final service = MoodService(random: Random(0));
      // String with no mood keywords whatsoever.
      final result = service.detectMood('xyzzy plugh quux');
      expect(result.mood, 'calm_peaceful',
          reason: 'Unmatched non-empty input must default to calm_peaceful, '
              'never weary (INVARIANTS.md Mood System).');
    });
  });

  // ---------------------------------------------------------------------
  // Class B regression: word-boundary matching prevents substring
  // collisions ("painting" must not look like "pain", "already" must
  // not look like "ready", etc.). Pre-fix `String.contains` matched
  // any substring; the fix is `\bkeyword\b`-style regex matching in
  // `_containsAny`.
  // ---------------------------------------------------------------------
  group('MoodService.detectMood — substring-collision regressions', () {
    test('"unhappy" routes to hurting (not joyful, not calm)', () {
      // 'happy' is a joyful keyword; pre-fix substring match flipped a
      // negative reply into a positive mood, the worst class of bug.
      // Boundary fix alone sent it to calm_peaceful default, which
      // produced equally inappropriate calm/positive PAL responses.
      // The keyword `'unhappy'` in the hurting list pins it to a
      // negative mood for emotional fit.
      final service = MoodService(random: Random(0));
      expect(service.detectMood('unhappy').mood, 'hurting');
      expect(service.detectMood("I'm so unhappy today").mood, 'hurting');
      expect(service.detectMood('feeling unhappy').mood, 'hurting');
    });

    test('"painting" must not classify as hurting', () {
      // 'pain' is a hurting keyword; "painting today" should not look
      // like a sadness signal.
      final service = MoodService(random: Random(0));
      expect(service.detectMood('painting').mood, isNot('hurting'));
      expect(service.detectMood("I'm painting today").mood, isNot('hurting'));
    });

    test('"already" must not classify as encouraging', () {
      // 'ready' is an encouraging keyword; "I already finished" is not
      // a motivation signal.
      final service = MoodService(random: Random(0));
      expect(service.detectMood('already').mood, isNot('encouraging'));
      expect(service.detectMood('I already finished that').mood,
          isNot('encouraging'));
    });

    test('"freezing" must not classify as joyful', () {
      // 'free' is a joyful keyword; "I'm freezing" is a temperature
      // remark, not a celebration of liberty.
      final service = MoodService(random: Random(0));
      expect(service.detectMood('freezing').mood, isNot('joyful'));
      expect(service.detectMood("I'm freezing").mood, isNot('joyful'));
    });

    test('"software" does not engage the calm `soft` keyword', () {
      // 'soft' is a calm keyword; software talk should not engage it.
      // Pre-fix: substring matched → calm_peaceful with confidence 0.8.
      // Post-fix: no keyword matches → calm_peaceful via DEFAULT with
      // confidence 0.4. Same final mood (calm_peaceful is the safe
      // default), so we differentiate via confidence — the keyword path
      // would have returned 0.8.
      final service = MoodService(random: Random(0));
      final result = service.detectMood('software');
      expect(result.mood, 'calm_peaceful');
      expect(result.confidenceScore, lessThan(0.5),
          reason: 'Pre-fix matched the `soft` keyword (confidence 0.8). '
              'Post-fix should fall through to the default (0.4).');
    });

    test('"represent" does not engage the calm `present` keyword', () {
      // Same shape as "software" — the keyword `'present'` (calm) should
      // not match the substring inside "represent".
      final service = MoodService(random: Random(0));
      final result = service.detectMood('represent');
      expect(result.mood, 'calm_peaceful');
      expect(result.confidenceScore, lessThan(0.5),
          reason: 'Pre-fix matched the `present` keyword (confidence 0.8). '
              'Post-fix should fall through to the default (0.4).');
    });

    test('"fearless" routes to brave_courage, not anxious', () {
      // Pre-fix: 'fear' (anxious keyword) matched "fearless" via
      // substring, and anxious runs before brave_courage in the chain
      // — so the brave keyword `'fearless'` was effectively shadowed.
      // Boundary matching makes `\bfear\b` not match "fearless".
      final service = MoodService(random: Random(0));
      expect(service.detectMood('fearless').mood, 'brave_courage',
          reason: '"fearless" is a brave keyword and must win over the '
              'anxious substring match on "fear".');
      expect(service.detectMood("I'm fearless today").mood, 'brave_courage');
    });

    test('"calmed down" routes to calm_peaceful, not hurting', () {
      // Pre-fix: 'down' (hurting keyword) matched "calmed down". The
      // calm_peaceful keyword 'calm' didn't help because `\bcalm\b`
      // doesn't match "calmed". Fix is the explicit calm-resolution
      // pre-check that runs before the hurting branch.
      final service = MoodService(random: Random(0));
      expect(service.detectMood('calmed down').mood, 'calm_peaceful');
      expect(service.detectMood('finally calmed down').mood, 'calm_peaceful');
      expect(service.detectMood('settled down').mood, 'calm_peaceful');
    });
  });

  // ---------------------------------------------------------------------
  // Negation: "not <positive>" routes to hurting via the [_maskNegated-
  // Positives] substitution (the phrase is replaced with the marker
  // token "unhappy", which the hurting keyword list catches). Rich
  // negation handling ("don't feel", "wasn't really") remains out of
  // scope.
  // ---------------------------------------------------------------------
  group('MoodService.detectMood — negated positives route to hurting', () {
    test('"not happy" routes to hurting (not joyful, not calm)', () {
      final service = MoodService(random: Random(0));
      expect(service.detectMood('not happy').mood, 'hurting');
      expect(service.detectMood("I'm not happy today").mood, 'hurting');
    });

    test('"not great" routes to hurting', () {
      final service = MoodService(random: Random(0));
      expect(service.detectMood('not great').mood, 'hurting');
      expect(service.detectMood('today is not great').mood, 'hurting');
    });

    test('"not good" routes to hurting', () {
      final service = MoodService(random: Random(0));
      expect(service.detectMood('not good').mood, 'hurting');
      expect(service.detectMood('things are not good').mood, 'hurting');
    });

    test('other negated positives (not okay / not fine / not joyful) '
        'route to hurting', () {
      final service = MoodService(random: Random(0));
      for (final input in const [
        'not okay',
        "I'm not ok",
        'not fine',
        'not joyful',
        'not blessed',
      ]) {
        expect(service.detectMood(input).mood, 'hurting',
            reason: '"$input" should route to hurting via the negation '
                'substitution.');
      }
    });

    test('"not doing well" routes to hurting (optional `doing` bridge)', () {
      // Mask regex includes `(?:doing\s+)?` so "not doing well" / "not
      // doing great" both substitute to "unhappy" → hurting.
      final service = MoodService(random: Random(0));
      expect(service.detectMood('not doing well').mood, 'hurting');
      expect(service.detectMood("I'm not doing well today").mood, 'hurting');
      expect(service.detectMood('not doing great').mood, 'hurting');
    });

    test('"not alright" / "not well" route to hurting', () {
      final service = MoodService(random: Random(0));
      expect(service.detectMood('not alright').mood, 'hurting');
      expect(service.detectMood("I'm not alright").mood, 'hurting');
      expect(service.detectMood('not well').mood, 'hurting');
    });

    test('"not myself" routes to hurting (via the hurting keyword)', () {
      // Multi-word `'not myself'` keyword in the hurting list catches
      // this directly — no mask substitution needed.
      final service = MoodService(random: Random(0));
      expect(service.detectMood('not myself').mood, 'hurting');
      expect(service.detectMood("I'm not myself today").mood, 'hurting');
      expect(service.detectMood('been feeling not myself').mood, 'hurting');
    });

    test('"not lucky" routes to hurting (via the negation mask)', () {
      // `lucky` is in both the grateful keyword list (positive form)
      // and the negation mask token list. Bare "lucky" still routes to
      // grateful; "not lucky" substitutes to "unhappy" → hurting.
      final service = MoodService(random: Random(0));
      expect(service.detectMood('not lucky').mood, 'hurting');
      expect(service.detectMood("I'm not lucky").mood, 'hurting');
      // Sanity: bare "lucky" still routes to grateful (mask only fires
      // when preceded by "not").
      expect(service.detectMood('I feel lucky').mood, 'grateful',
          reason: 'Bare "lucky" must remain grateful — only "not lucky" '
              'should be re-routed.');
    });
  });

  // ---------------------------------------------------------------------
  // Conservative new keyword additions — confirms each one routes to
  // the intended mood. Catches any boundary-matching regression that
  // would silently lose these keywords.
  // ---------------------------------------------------------------------
  group('MoodService.detectMood — new keywords', () {
    test('thanks / thank you / blessing / appreciate route to grateful', () {
      final service = MoodService(random: Random(0));
      for (final input in const [
        'thanks',
        'Thanks!',
        'thank you',
        'Thank you so much',
        'what a blessing',
        'so many blessings',
        'I appreciate this',
        'feeling appreciative',
      ]) {
        expect(service.detectMood(input).mood, 'grateful',
            reason: '"$input" should route to grateful');
      }
    });

    test('fortunate / lucky / honored route to grateful', () {
      final service = MoodService(random: Random(0));
      for (final input in const [
        'I feel lucky',
        'so fortunate',
        'honored to be here',
        'truly fortunate',
      ]) {
        expect(service.detectMood(input).mood, 'grateful',
            reason: '"$input" should route to grateful');
      }
      // Boundary-collision sanity: 'unlucky' must not match `\blucky\b`.
      expect(service.detectMood('unlucky').mood, isNot('grateful'),
          reason: '`\\blucky\\b` must not match the word "unlucky".');
    });

    test('thrilled / delighted / elated / ecstatic / glad / pleased route to joyful',
        () {
      final service = MoodService(random: Random(0));
      for (final input in const [
        'thrilled',
        'I am delighted',
        'absolutely elated',
        'ecstatic about it',
        'glad to hear it',
        'pleased with the result',
      ]) {
        expect(service.detectMood(input).mood, 'joyful',
            reason: '"$input" should route to joyful');
      }
    });

    test('stoked / psyched / best day route to joyful', () {
      final service = MoodService(random: Random(0));
      for (final input in const [
        'I feel stoked',
        'so stoked about it',
        'I am psyched',
        'Best day ever',
        'best day of my life',
      ]) {
        expect(service.detectMood(input).mood, 'joyful',
            reason: '"$input" should route to joyful');
      }
    });

    test('sleepy / groggy / exhausting / pooped route to weary', () {
      final service = MoodService(random: Random(0));
      for (final input in const [
        'sleepy',
        'so groggy this morning',
        'today was exhausting',
        'pooped after that walk',
      ]) {
        expect(service.detectMood(input).mood, 'weary',
            reason: '"$input" should route to weary');
      }
    });

    test('busy / very busy / swamped route to weary', () {
      final service = MoodService(random: Random(0));
      for (final input in const [
        'busy',
        'very busy',
        'so busy today',
        'had a busy day',
        'swamped',
        "I'm swamped this week",
      ]) {
        expect(service.detectMood(input).mood, 'weary',
            reason: '"$input" should route to weary');
      }
      // Boundary-collision sanity: 'business' must not falsely match.
      // The detector ignoring it is fine; the assertion is just that
      // the keyword `'busy'` doesn't substring-match into 'business'.
      expect(service.detectMood('business').mood, isNot('weary'),
          reason: '`\\bbusy\\b` must not match the word "business".');
    });

    test('wiped / frazzled / dragging / can\'t sleep route to weary', () {
      final service = MoodService(random: Random(0));
      for (final input in const [
        "I'm wiped",
        'feeling frazzled',
        'just dragging today',
        "I can't sleep",
        "couldn't sleep last night",
      ]) {
        expect(service.detectMood(input).mood, 'weary',
            reason: '"$input" should route to weary');
      }
    });

    test('antsy / jittery / uptight route to anxious', () {
      final service = MoodService(random: Random(0));
      for (final input in const [
        'antsy',
        'feeling jittery',
        'a bit uptight today',
      ]) {
        expect(service.detectMood(input).mood, 'anxious',
            reason: '"$input" should route to anxious');
      }
    });

    test('wound up / wired / freaking route to anxious', () {
      final service = MoodService(random: Random(0));
      for (final input in const [
        "I'm wired",
        'totally wired tonight',
        'feeling wound up',
        "I'm freaking nervous",
      ]) {
        expect(service.detectMood(input).mood, 'anxious',
            reason: '"$input" should route to anxious');
      }
    });

    test('"freaking exhausted" is safe: anxious or weary, never joyful / '
        'grateful / calm_peaceful', () {
      // "freaking exhausted" matches both the new `freaking` keyword
      // (anxious) and the existing `exhausted` keyword (weary). Either
      // routing is acceptable — both moods produce comforting/settling
      // PAL responses. The hard guarantee is that it must NEVER route
      // to a positive or neutral mood.
      final service = MoodService(random: Random(0));
      final mood = service.detectMood('freaking exhausted').mood;
      expect({'anxious', 'weary'}, contains(mood),
          reason: '"freaking exhausted" should route to anxious or weary; '
              'got "$mood".');
      expect(mood, isNot('joyful'));
      expect(mood, isNot('grateful'));
      expect(mood, isNot('calm_peaceful'));
    });

    test('heartache / blue / low / mourning route to hurting', () {
      final service = MoodService(random: Random(0));
      for (final input in const [
        'heartache',
        'feeling blue',
        'I feel low',
        'still mourning',
      ]) {
        expect(service.detectMood(input).mood, 'hurting',
            reason: '"$input" should route to hurting');
      }
    });

    test('bummed / terrible / awful / horrible route to hurting', () {
      final service = MoodService(random: Random(0));
      for (final input in const [
        "I'm feeling bummed",
        'so bummed today',
        'This is awful',
        'horrible day',
        'terrible week',
      ]) {
        expect(service.detectMood(input).mood, 'hurting',
            reason: '"$input" should route to hurting');
      }
      // Boundary-collision sanity: 'terrible' (hurting) must not match
      // inside 'terrific' (joyful keyword) — different words entirely.
      expect(service.detectMood('terrific').mood, 'joyful',
          reason: '"terrific" must remain joyful, not be shadowed by '
              '"terrible".');
    });

    test("i got this / face it / won't back down route to brave_courage",
        () {
      final service = MoodService(random: Random(0));
      for (final input in const [
        'i got this',
        'I got this',
        'time to face it',
        "I won't back down",
      ]) {
        expect(service.detectMood(input).mood, 'brave_courage',
            reason: '"$input" should route to brave_courage');
      }
    });

    test("won't quit / no fear / i'll handle it route to brave_courage", () {
      final service = MoodService(random: Random(0));
      for (final input in const [
        "I won't quit",
        "won't quit on this",
        'I have no fear',
        'no fear of failure',
        "I'll handle it",
        "I'll handle it from here",
      ]) {
        expect(service.detectMood(input).mood, 'brave_courage',
            reason: '"$input" should route to brave_courage');
      }
    });

    test("go for it / got this / let's do this route to encouraging", () {
      final service = MoodService(random: Random(0));
      for (final input in const [
        'go for it',
        'you got this',
        "let's do this",
      ]) {
        expect(service.detectMood(input).mood, 'encouraging',
            reason: '"$input" should route to encouraging');
      }
    });

    test('chill / low key route to calm_peaceful', () {
      final service = MoodService(random: Random(0));
      for (final input in const [
        'Just a chill day',
        'feeling chill',
        'low key',
        'kind of low key today',
      ]) {
        expect(service.detectMood(input).mood, 'calm_peaceful',
            reason: '"$input" should route to calm_peaceful');
      }
    });
  });

  // ---------------------------------------------------------------------
  // Multi-word phrase regression: word-boundary matching must not
  // break legit phrase keywords like "thank you", "worn out",
  // "too much", "i got this". These are checked as part of the
  // groups above, but pinned explicitly here so a future regex tweak
  // can't silently degrade them.
  // ---------------------------------------------------------------------
  group('MoodService.detectMood — multi-word phrases preserved', () {
    test('"too much" still routes to weary', () {
      final service = MoodService(random: Random(0));
      expect(service.detectMood('too much going on').mood, 'weary');
    });

    test('"thank you" still routes to grateful', () {
      final service = MoodService(random: Random(0));
      expect(service.detectMood('thank you').mood, 'grateful');
    });

    test('"worn out" still routes to weary', () {
      final service = MoodService(random: Random(0));
      expect(service.detectMood('I am worn out').mood, 'weary');
    });

    test('"i got this" still routes to brave_courage', () {
      final service = MoodService(random: Random(0));
      expect(service.detectMood('i got this').mood, 'brave_courage');
    });
  });
}
