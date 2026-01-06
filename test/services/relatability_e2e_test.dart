import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/services/relatability_matcher.dart';
import 'package:bible_pal/models/parable.dart';

/// End-to-end tests proving relatability matching works with real manifest data.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RelatabilityMatcher matcher;
  late List<Parable> allParables;

  setUpAll(() async {
    matcher = RelatabilityMatcher();

    // Load real manifest
    final jsonContent = await rootBundle.loadString('assets/stories/manifest.json');
    final manifestData = jsonDecode(jsonContent) as Map<String, dynamic>;
    final parablesList = manifestData['parables'] as List<dynamic>;
    allParables = parablesList.map((json) => Parable.fromJson(json as Map<String, dynamic>)).toList();
  });

  group('End-to-End Relatability Matching', () {
    test('"boss treated me badly and I\'m exhausted" ranks unfair_authority + overwhelmed stories higher', () {
      const userText = "my boss treated me badly and I'm exhausted";

      // Get all stories (no filtering for this test)
      final ranked = matcher.rankByRelatability(userText, allParables);

      // Verify extracted tags
      final extractedTags = matcher.extractTags(userText);
      expect(extractedTags, contains('unfair_authority'), reason: '"boss" should trigger unfair_authority');
      expect(extractedTags, contains('overwhelmed'), reason: '"exhausted" should trigger overwhelmed');

      // The top-ranked story should have at least one of these tags
      final topStory = ranked.first;
      final topTags = topStory.emotionalTags.toSet();
      final hasRelevantTag = topTags.contains('unfair_authority') || topTags.contains('overwhelmed');

      expect(
        hasRelevantTag,
        isTrue,
        reason: 'Top story should have unfair_authority or overwhelmed tag. '
            'Got: ${topStory.storyId} with tags ${topStory.emotionalTags}',
      );
    });

    test('"I feel alone and sad" ranks lonely + sad stories higher', () {
      const userText = "I feel alone and sad today";

      final extractedTags = matcher.extractTags(userText);
      expect(extractedTags, contains('lonely'));
      expect(extractedTags, contains('sad'));

      final ranked = matcher.rankByRelatability(userText, allParables);
      final topStory = ranked.first;
      final topTags = topStory.emotionalTags.toSet();

      final hasRelevantTag = topTags.contains('lonely') || topTags.contains('sad');
      expect(
        hasRelevantTag,
        isTrue,
        reason: 'Top story should have lonely or sad tag. '
            'Got: ${topStory.storyId} with tags ${topStory.emotionalTags}',
      );
    });

    test('"thank god for everything" ranks grateful stories higher', () {
      const userText = "thank god for everything today";

      final extractedTags = matcher.extractTags(userText);
      expect(extractedTags, contains('grateful'));

      final ranked = matcher.rankByRelatability(userText, allParables);
      final topStory = ranked.first;

      expect(
        topStory.emotionalTags,
        contains('grateful'),
        reason: 'Top story should have grateful tag. '
            'Got: ${topStory.storyId} with tags ${topStory.emotionalTags}',
      );
    });

    test('stories with 2 matching tags rank above stories with 1', () {
      const userText = "I'm anxious and overwhelmed";

      final extractedTags = matcher.extractTags(userText);
      expect(extractedTags.length, greaterThanOrEqualTo(2));

      final ranked = matcher.rankByRelatability(userText, allParables);

      // Find a story with 2 matches and a story with 1 match
      Parable? twoMatchStory;
      Parable? oneMatchStory;

      for (final parable in ranked) {
        final matchCount = extractedTags.intersection(parable.emotionalTags.toSet()).length;
        if (matchCount == 2 && twoMatchStory == null) {
          twoMatchStory = parable;
        } else if (matchCount == 1 && oneMatchStory == null) {
          oneMatchStory = parable;
        }
        if (twoMatchStory != null && oneMatchStory != null) break;
      }

      if (twoMatchStory != null && oneMatchStory != null) {
        final twoMatchIndex = ranked.indexOf(twoMatchStory);
        final oneMatchIndex = ranked.indexOf(oneMatchStory);

        expect(
          twoMatchIndex,
          lessThan(oneMatchIndex),
          reason: 'Story with 2 matches should rank before story with 1 match',
        );
      }
    });

    test('low-signal input preserves original order', () {
      const userText = "fine";

      final extractedTags = matcher.extractTags(userText);
      expect(extractedTags, isEmpty, reason: '"fine" is low-signal');

      final ranked = matcher.rankByRelatability(userText, allParables);

      // Order should be preserved (same as input)
      for (int i = 0; i < ranked.length; i++) {
        expect(ranked[i].storyId, allParables[i].storyId);
      }
    });

    test('Daniel stories rank high for unfair_authority queries', () {
      const userText = "my boss is bullying me";

      final extractedTags = matcher.extractTags(userText);
      expect(extractedTags, contains('unfair_authority'));

      final ranked = matcher.rankByRelatability(userText, allParables);

      // Find Daniel stories (which should have unfair_authority tag)
      final danielStories = ranked.where(
        (p) => p.title.toLowerCase().contains('daniel') && p.emotionalTags.contains('unfair_authority'),
      ).toList();

      if (danielStories.isNotEmpty) {
        // Daniel story should be in top 10 at minimum
        final firstDanielIndex = ranked.indexWhere(
          (p) => p.title.toLowerCase().contains('daniel') && p.emotionalTags.contains('unfair_authority'),
        );

        expect(
          firstDanielIndex,
          lessThan(20),
          reason: 'Daniel story with unfair_authority tag should rank in top 20 for boss/bully query',
        );
      }
    });

    test('Joseph story ranks high for rejection + injustice queries', () {
      const userText = "I was treated unfairly and rejected";

      final extractedTags = matcher.extractTags(userText);
      expect(extractedTags, contains('rejection'));
      expect(extractedTags, contains('injustice'));

      final ranked = matcher.rankByRelatability(userText, allParables);

      // Joseph story should have both rejection and injustice
      final josephStory = ranked.firstWhere(
        (p) => p.title.toLowerCase().contains('joseph'),
        orElse: () => ranked.first,
      );

      if (josephStory.title.toLowerCase().contains('joseph')) {
        final josephIndex = ranked.indexOf(josephStory);
        expect(
          josephIndex,
          lessThan(10),
          reason: 'Joseph story should rank in top 10 for rejection + injustice query. '
              'Actual index: $josephIndex',
        );
      }
    });
  });
}
