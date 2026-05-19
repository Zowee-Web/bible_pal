import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Compliance tests for Life Situation Tags v1.
///
/// Loads `assets/stories/life_situation_tags_registry.json` and walks
/// every `assets/stories/traditional/{id}/meta_{id}.json` directly via
/// dart:io (not the bundled manifest, which v1 leaves untouched).
///
/// Asserts:
///   - Every tag on every story is in the registry allowlist
///   - Cardinality caps: ≤2 primary, ≤3 secondary per story
///   - No tag appears in both primary and secondary on the same story
///   - No duplicates within either array
///   - snake_case format
///   - Primary tags are not in the banned-generics list (defensive)
///   - Anti-bloat: every tag declared in the registry appears (as primary
///     or secondary) on ≥2 stories across the corpus
void main() {
  late Set<String> allowedTags;
  late List<String> bannedGenerics;
  late int minStoriesPerTag;
  late int maxPrimary;
  late int maxSecondary;
  late List<_StoryMeta> stories;

  final snakeCase = RegExp(r'^[a-z][a-z0-9_]*[a-z0-9]$');

  setUpAll(() {
    final registryFile = File('assets/stories/life_situation_tags_registry.json');
    final registry = jsonDecode(registryFile.readAsStringSync()) as Map<String, dynamic>;
    allowedTags = {
      for (final t in (registry['tags'] as List<dynamic>))
        (t as Map<String, dynamic>)['tagId'] as String,
    };
    final rules = registry['rules'] as Map<String, dynamic>;
    bannedGenerics = (rules['bannedGenerics'] as List<dynamic>).cast<String>();
    minStoriesPerTag = rules['minStoriesPerTag'] as int;
    maxPrimary = rules['maxPrimaryPerStory'] as int;
    maxSecondary = rules['maxSecondaryPerStory'] as int;

    stories = [];
    final dir = Directory('assets/stories/traditional');
    for (final entry in dir.listSync()) {
      if (entry is! Directory) continue;
      final id = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final meta = File('${entry.path}/meta_$id.json');
      if (!meta.existsSync()) continue;
      final data = jsonDecode(meta.readAsStringSync()) as Map<String, dynamic>;
      final primary = (data['primaryLifeSituationTags'] as List<dynamic>?)
              ?.cast<String>() ??
          const <String>[];
      final secondary = (data['secondaryLifeSituationTags'] as List<dynamic>?)
              ?.cast<String>() ??
          const <String>[];
      stories.add(_StoryMeta(id: id, primary: primary, secondary: secondary));
    }
  });

  group('Life Situation Tags Compliance', () {
    test('every tag on every story is in the registry', () {
      final violations = <String>[];
      for (final s in stories) {
        for (final tag in [...s.primary, ...s.secondary]) {
          if (!allowedTags.contains(tag)) {
            violations.add('${s.id}: tag "$tag" not in registry');
          }
        }
      }
      if (violations.isNotEmpty) {
        fail(
          'Found ${violations.length} unknown tags:\n${violations.join('\n')}\n\n'
          'Registry contains ${allowedTags.length} tags.',
        );
      }
    });

    test('cardinality caps: ≤2 primary, ≤3 secondary', () {
      final violations = <String>[];
      for (final s in stories) {
        if (s.primary.length > maxPrimary) {
          violations
              .add('${s.id}: ${s.primary.length} primary tags (max $maxPrimary)');
        }
        if (s.secondary.length > maxSecondary) {
          violations.add(
              '${s.id}: ${s.secondary.length} secondary tags (max $maxSecondary)');
        }
      }
      if (violations.isNotEmpty) {
        fail('Cardinality violations:\n${violations.join('\n')}');
      }
    });

    test('no tag appears in both primary and secondary on same story', () {
      final violations = <String>[];
      for (final s in stories) {
        final overlap = s.primary.toSet().intersection(s.secondary.toSet());
        if (overlap.isNotEmpty) {
          violations.add('${s.id}: overlap = $overlap');
        }
      }
      if (violations.isNotEmpty) {
        fail('Primary/secondary overlap:\n${violations.join('\n')}');
      }
    });

    test('no duplicates within either array', () {
      final violations = <String>[];
      for (final s in stories) {
        if (s.primary.length != s.primary.toSet().length) {
          violations.add('${s.id}: duplicate in primary = ${s.primary}');
        }
        if (s.secondary.length != s.secondary.toSet().length) {
          violations.add('${s.id}: duplicate in secondary = ${s.secondary}');
        }
      }
      if (violations.isNotEmpty) {
        fail('Duplicate tags:\n${violations.join('\n')}');
      }
    });

    test('all tag IDs are snake_case', () {
      final violations = <String>[];
      for (final s in stories) {
        for (final tag in [...s.primary, ...s.secondary]) {
          if (!snakeCase.hasMatch(tag)) {
            violations.add('${s.id}: tag "$tag" is not snake_case');
          }
        }
      }
      if (violations.isNotEmpty) {
        fail('snake_case violations:\n${violations.join('\n')}');
      }
    });

    test('primary tags are never in the banned-generics list', () {
      final violations = <String>[];
      for (final s in stories) {
        for (final tag in s.primary) {
          if (bannedGenerics.contains(tag)) {
            violations.add('${s.id}: primary tag "$tag" is in banned-generics');
          }
        }
      }
      if (violations.isNotEmpty) {
        fail(
          'Banned-generic primary tags:\n${violations.join('\n')}\n\n'
          'Banned generics: ${bannedGenerics.join(', ')}',
        );
      }
    });

    test('anti-bloat: every registry tag appears on ≥2 stories', () {
      final usage = <String, int>{};
      for (final tag in allowedTags) {
        usage[tag] = 0;
      }
      for (final s in stories) {
        for (final tag in [...s.primary, ...s.secondary]) {
          if (usage.containsKey(tag)) {
            usage[tag] = usage[tag]! + 1;
          }
        }
      }

      final underused = usage.entries
          .where((e) => e.value < minStoriesPerTag)
          .map((e) => '${e.key} (${e.value} stories)')
          .toList()
        ..sort();

      if (underused.isNotEmpty) {
        fail(
          'Found ${underused.length} registry tags below the '
          'minimum of $minStoriesPerTag stories:\n  ${underused.join('\n  ')}\n\n'
          'Fix: tag a second story OR move the tag to '
          'scripts/life_situation_tags_drafts.json. Do not lower the threshold.',
        );
      }
    });
  });

  group('Life Situation Tags Distribution Report', () {
    test('print tag usage statistics', () {
      final usage = <String, int>{};
      var primaryHits = 0;
      var secondaryHits = 0;
      var taggedStories = 0;

      for (final s in stories) {
        if (s.primary.isNotEmpty || s.secondary.isNotEmpty) taggedStories++;
        primaryHits += s.primary.length;
        secondaryHits += s.secondary.length;
        for (final tag in [...s.primary, ...s.secondary]) {
          usage[tag] = (usage[tag] ?? 0) + 1;
        }
      }

      final sorted = usage.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      // ignore: avoid_print
      print('\n=== Life Situation Tag Distribution ===');
      // ignore: avoid_print
      print(
          'Stories tagged: $taggedStories / ${stories.length} (${(100 * taggedStories / stories.length).toStringAsFixed(1)}%)');
      // ignore: avoid_print
      print('Primary hits: $primaryHits, Secondary hits: $secondaryHits');
      for (final e in sorted) {
        // ignore: avoid_print
        print('  ${e.key}: ${e.value}');
      }

      expect(true, isTrue);
    });
  });
}

class _StoryMeta {
  _StoryMeta({required this.id, required this.primary, required this.secondary});
  final String id;
  final List<String> primary;
  final List<String> secondary;
}
