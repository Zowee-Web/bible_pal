import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/services/relatability_matcher.dart';
import 'package:bible_pal/models/parable.dart';

void main() {
  late RelatabilityMatcher matcher;

  setUp(() {
    matcher = RelatabilityMatcher();
  });

  group('normalizeInput', () {
    test('lowercases input', () {
      expect(matcher.normalizeInput('HELLO WORLD'), 'hello world');
    });

    test('trims whitespace', () {
      expect(matcher.normalizeInput('  hello  '), 'hello');
    });

    test('collapses multiple spaces', () {
      expect(matcher.normalizeInput('hello   world'), 'hello world');
    });

    test('normalizes smart apostrophes', () {
      expect(matcher.normalizeInput("can't"), "can't");
      expect(matcher.normalizeInput("can't"), "can't");
    });

    test('normalizes smart quotes', () {
      expect(matcher.normalizeInput('"hello"'), '"hello"');
    });
  });

  group('isLowSignal', () {
    test('returns true for short input', () {
      expect(matcher.isLowSignal('hi'), true);
      expect(matcher.isLowSignal('ok'), true);
    });

    test('returns true for low-signal words', () {
      expect(matcher.isLowSignal('fine'), true);
      expect(matcher.isLowSignal('good'), true);
      expect(matcher.isLowSignal('okay'), true);
      expect(matcher.isLowSignal('meh'), true);
      expect(matcher.isLowSignal('idk'), true);
    });

    test('returns false for meaningful input', () {
      expect(matcher.isLowSignal('i am stressed'), false);
      expect(matcher.isLowSignal('feeling overwhelmed'), false);
    });
  });

  group('extractTags', () {
    test('returns empty set for low-signal input', () {
      expect(matcher.extractTags('ok'), isEmpty);
      expect(matcher.extractTags('fine'), isEmpty);
      expect(matcher.extractTags('hi'), isEmpty);
    });

    test('returns empty set for too-short input', () {
      expect(matcher.extractTags('sad'), isEmpty); // 3 chars < 5
    });

    test('extracts single tag', () {
      final tags = matcher.extractTags('I am feeling overwhelmed today');
      expect(tags, contains('overwhelmed'));
    });

    test('extracts multiple tags', () {
      final tags = matcher.extractTags('My boss yelled at me and I feel exhausted');
      expect(tags, contains('overwhelmed')); // 'exhausted' keyword
      expect(tags, contains('unfair_authority')); // 'boss' keyword
    });

    test('caps at 3 tags maximum', () {
      final tags = matcher.extractTags(
        'I am overwhelmed anxious sad angry lonely hopeless and grateful',
      );
      expect(tags.length, lessThanOrEqualTo(3));
    });

    test('is case-insensitive', () {
      expect(matcher.extractTags('I am OVERWHELMED'), contains('overwhelmed'));
      expect(matcher.extractTags('STRESSED out'), contains('anxious'));
    });

    test('matches keywords with punctuation', () {
      expect(matcher.extractTags('my boss!'), contains('unfair_authority'));
      expect(matcher.extractTags('feeling stressed.'), contains('anxious'));
    });

    test('duplicate keywords do not inflate results', () {
      // "boss boss boss" should only match unfair_authority once
      final tags = matcher.extractTags('boss boss boss boss');
      expect(tags.where((t) => t == 'unfair_authority').length, 1);
    });

    test('extracts unfair_authority for "boss treated me badly"', () {
      final tags = matcher.extractTags('my boss treated me badly');
      expect(tags, contains('unfair_authority'));
    });

    test('does not extract workplace_conflict for just "boss"', () {
      // "boss" should trigger unfair_authority, not workplace_conflict
      // because "work" was removed from workplace_conflict keywords
      final tags = matcher.extractTags('my boss is mean');
      expect(tags, contains('unfair_authority'));
      expect(tags, isNot(contains('workplace_conflict')));
    });

    test('extracts workplace_conflict for job-related keywords', () {
      final tags = matcher.extractTags('problems at the office');
      expect(tags, contains('workplace_conflict'));
    });

    test('extracts lonely with softened keywords', () {
      // Should work with "feel alone" but not just "alone"
      expect(matcher.extractTags('I feel alone'), contains('lonely'));
      expect(matcher.extractTags('feeling isolated'), contains('lonely'));
      expect(matcher.extractTags('I am lonely'), contains('lonely'));
    });

    test('extracts grateful with "thank god"', () {
      final tags = matcher.extractTags('thank god for this day');
      expect(tags, contains('grateful'));
    });
  });

  group('scoreParable', () {
    test('returns 0 for empty extracted tags', () {
      final parable = _createParable(emotionalTags: ['overwhelmed', 'anxious']);
      expect(matcher.scoreParable({}, parable), 0);
    });

    test('returns 0 for parable with no matching tags', () {
      final parable = _createParable(emotionalTags: ['grateful']);
      expect(matcher.scoreParable({'overwhelmed', 'anxious'}, parable), 0);
    });

    test('returns 0 for parable with empty emotionalTags', () {
      final parable = _createParable(emotionalTags: []);
      expect(matcher.scoreParable({'overwhelmed'}, parable), 0);
    });

    test('counts matching tags correctly', () {
      final parable = _createParable(emotionalTags: ['overwhelmed', 'anxious', 'sad']);
      expect(matcher.scoreParable({'overwhelmed'}, parable), 1);
      expect(matcher.scoreParable({'overwhelmed', 'anxious'}, parable), 2);
      expect(matcher.scoreParable({'overwhelmed', 'anxious', 'sad'}, parable), 3);
    });

    test('does not count non-matching story tags negatively', () {
      final parable = _createParable(
        emotionalTags: ['overwhelmed', 'workplace_conflict', 'unfair_authority'],
      );
      // User only expressed 'overwhelmed', story has 3 tags
      // Score should be 1, not penalized for extra tags
      expect(matcher.scoreParable({'overwhelmed'}, parable), 1);
    });
  });

  group('rankByRelatability', () {
    test('returns empty list for empty candidates', () {
      final ranked = matcher.rankByRelatability('overwhelmed', []);
      expect(ranked, isEmpty);
    });

    test('returns original order for low-signal input', () {
      final p1 = _createParable(storyId: 'a', emotionalTags: ['overwhelmed']);
      final p2 = _createParable(storyId: 'b', emotionalTags: ['anxious']);
      final p3 = _createParable(storyId: 'c', emotionalTags: ['sad']);

      final ranked = matcher.rankByRelatability('fine', [p1, p2, p3]);
      expect(ranked.map((p) => p.storyId).toList(), ['a', 'b', 'c']);
    });

    test('ranks by score descending', () {
      final p1 = _createParable(storyId: 'a', emotionalTags: ['grateful']); // 0 match
      final p2 = _createParable(storyId: 'b', emotionalTags: ['overwhelmed']); // 1 match
      final p3 = _createParable(storyId: 'c', emotionalTags: ['overwhelmed', 'anxious']); // 2 matches

      final ranked = matcher.rankByRelatability(
        'I am overwhelmed and anxious',
        [p1, p2, p3],
      );
      expect(ranked.first.storyId, 'c'); // highest score
      expect(ranked[1].storyId, 'b'); // second highest
      expect(ranked.last.storyId, 'a'); // lowest score
    });

    test('tie-breaks by least-recently-played', () {
      final p1 = _createParable(storyId: 'a', emotionalTags: ['overwhelmed']);
      final p2 = _createParable(storyId: 'b', emotionalTags: ['overwhelmed']);

      final now = DateTime.now();
      final playHistory = {
        'a': now, // played now (more recent)
        'b': now.subtract(const Duration(hours: 1)), // played 1 hour ago (older)
      };

      final ranked = matcher.rankByRelatability(
        'I am overwhelmed',
        [p1, p2],
        playHistory: playHistory,
      );
      // p2 was played earlier, so it should come first
      expect(ranked.first.storyId, 'b');
    });

    test('never-played comes before recently-played in tie-break', () {
      final p1 = _createParable(storyId: 'a', emotionalTags: ['overwhelmed']);
      final p2 = _createParable(storyId: 'b', emotionalTags: ['overwhelmed']);

      final playHistory = {
        'a': DateTime.now(), // played
        // 'b' not in history (never played)
      };

      final ranked = matcher.rankByRelatability(
        'I am overwhelmed',
        [p1, p2],
        playHistory: playHistory,
      );
      // p2 was never played, should come first
      expect(ranked.first.storyId, 'b');
    });

    test('tie-breaks by storyId ascending when play history is equal', () {
      final p1 = _createParable(storyId: 'c', emotionalTags: ['overwhelmed']);
      final p2 = _createParable(storyId: 'a', emotionalTags: ['overwhelmed']);
      final p3 = _createParable(storyId: 'b', emotionalTags: ['overwhelmed']);

      // No play history, all scores equal
      final ranked = matcher.rankByRelatability(
        'I am overwhelmed',
        [p1, p2, p3],
      );
      // Should be sorted by storyId: a, b, c
      expect(ranked.map((p) => p.storyId).toList(), ['a', 'b', 'c']);
    });

    test('single candidate returns that candidate', () {
      final p1 = _createParable(storyId: 'only');

      final ranked = matcher.rankByRelatability('overwhelmed', [p1]);
      expect(ranked.length, 1);
      expect(ranked.first.storyId, 'only');
    });

    test('deterministic tie-breaking produces same result on repeated calls', () {
      final p1 = _createParable(storyId: 'a', emotionalTags: ['overwhelmed']);
      final p2 = _createParable(storyId: 'b', emotionalTags: ['overwhelmed']);
      final p3 = _createParable(storyId: 'c', emotionalTags: ['overwhelmed']);

      final candidates = [p1, p2, p3];
      const userText = 'I am overwhelmed';

      // Call multiple times
      final result1 = matcher.rankByRelatability(userText, candidates);
      final result2 = matcher.rankByRelatability(userText, candidates);
      final result3 = matcher.rankByRelatability(userText, candidates);

      // All should produce the same order
      expect(result1.map((p) => p.storyId).toList(), result2.map((p) => p.storyId).toList());
      expect(result2.map((p) => p.storyId).toList(), result3.map((p) => p.storyId).toList());
    });

    test('multi-tag input outranks single-tag (boss + overwhelmed > overwhelmed)', () {
      final p1 = _createParable(storyId: 'single', emotionalTags: ['overwhelmed']);
      final p2 = _createParable(storyId: 'multi', emotionalTags: ['overwhelmed', 'unfair_authority']);

      final ranked = matcher.rankByRelatability(
        'my boss is overwhelming me',
        [p1, p2],
      );
      expect(ranked.first.storyId, 'multi');
    });

    test('selects unfair_authority story over workplace_conflict for "boss treated me badly"', () {
      final workplaceStory = _createParable(
        storyId: 'workplace',
        emotionalTags: ['workplace_conflict'],
      );
      final authorityStory = _createParable(
        storyId: 'authority',
        emotionalTags: ['unfair_authority'],
      );

      final ranked = matcher.rankByRelatability(
        'my boss treated me badly',
        [workplaceStory, authorityStory],
      );
      expect(ranked.first.storyId, 'authority');
    });
  });
}

/// Helper to create a test Parable with minimal required fields.
Parable _createParable({
  String storyId = 'test_story',
  List<String> emotionalTags = const [],
}) {
  return Parable(
    storyId: storyId,
    title: 'Test Story',
    mood: 'neutral',
    emotionalTags: emotionalTags,
    length: 5,
    faithTradition: 'Unspecified',
    storytellingMode: 'creative',
    kidFriendly: false,
  );
}
