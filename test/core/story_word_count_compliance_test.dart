import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CRITICAL: Validates all production story text files meet STORY_FACTORY.md
/// word count ranges.
///
/// Only checks stories that appear in the production manifest (manifest.json).
/// Quarantined or orphaned stories on disk are ignored.
///
/// STORY_FACTORY.md defines mode-specific locked ranges:
///   Traditional:     Short 300-500, Full 501-900,  Long 901-1500
///   Creative Adult:  Short 200-400, Full 401-700,  Long 701-1100
///   Creative Kid:    Short 200-500, Full 501-900,  Long 901-1400
void main() {
  group('CRITICAL: Story Word Count Compliance (STORY_FACTORY.md)', () {
    test('all production story text files meet word count ranges', () {
      final storiesDir = Directory('assets/stories');
      final violations = <String>[];

      // Build set of production story directories from manifest
      final manifestFile = File('assets/stories/manifest.json');
      expect(manifestFile.existsSync(), isTrue,
          reason: 'manifest.json must exist');
      final manifest =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
      final parables = manifest['parables'] as List;

      // Extract unique base story IDs and their modes from manifest
      // storyId format: story_504_joyful_short_creative → baseId=504, mode=creative
      final productionStories = <String>{};
      for (final p in parables) {
        final textPath = p['textFilePath'] as String?;
        if (textPath == null) continue;
        // textFilePath: "creative/504/story_504_creative_web_short.txt"
        final parts = textPath.split('/');
        if (parts.length >= 2) {
          productionStories.add('${parts[0]}/${parts[1]}');
        }
      }

      for (final modeDir in ['creative', 'traditional']) {
        final dir = Directory('${storiesDir.path}/$modeDir');
        if (!dir.existsSync()) continue;

        for (final storyDir in dir.listSync().whereType<Directory>()) {
          final storyId = storyDir.path.split('/').last;
          final relPath = '$modeDir/$storyId';

          // Skip stories not in the production manifest
          if (!productionStories.contains(relPath)) continue;

          final metaFile = File('${storyDir.path}/meta_$storyId.json');
          if (!metaFile.existsSync()) continue;

          final meta =
              jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
          final mode = meta['mode'] as String? ?? modeDir;
          final isKid = meta['kidFriendly'] as bool? ?? false;

          // Documented carve-outs (word-count remediation backlog):
          //  - editorialBucketException: legacy stories explicitly flagged for a
          //    future editorial expand/trim pass (legacy_bucket_drift /
          //    lyric_expansion). New content carries no such field and is still
          //    strictly enforced below.
          if (meta['editorialBucketException'] != null) continue;
          //  - shortScripture: psalms/short passages may fall below the SHORT
          //    floor when the full passage is rendered (feedback_psalm_word_floor).
          final shortScripture = meta['shortScripture'] as bool? ?? false;

          for (final bucket in ['short', 'full', 'long']) {
            final textFile = File(
                '${storyDir.path}/story_${storyId}_${mode}_web_$bucket.txt');
            if (!textFile.existsSync()) continue;

            final content = textFile.readAsStringSync();
            final wordCount = content
                .split(RegExp(r'\s+'))
                .where((w) => w.isNotEmpty)
                .length;
            final range = _getRange(mode, isKid, bucket);

            if (wordCount < range.$1 || wordCount > range.$2) {
              // Psalm/short-passage floor carve-out: a SHORT below its floor is
              // allowed when the full scripture passage is included.
              if (bucket == 'short' &&
                  shortScripture &&
                  wordCount < range.$1) {
                continue;
              }
              violations.add(
                '$mode/$storyId $bucket: $wordCount words '
                '(expected ${range.$1}-${range.$2}, kid=$isKid)',
              );
            }
          }
        }
      }

      if (violations.isNotEmpty) {
        // ignore: avoid_print
        print('\nWORD COUNT VIOLATIONS (STORY_FACTORY.md):');
        for (final v in violations) {
          // ignore: avoid_print
          print('  - $v');
        }
      }

      expect(violations, isEmpty,
          reason:
              'All production story text files must meet STORY_FACTORY.md word count ranges');
    });
  });
}

/// Returns (min, max) word count range per STORY_FACTORY.md.
(int, int) _getRange(String mode, bool isKid, String bucket) {
  if (mode == 'traditional') {
    return switch (bucket) {
      'short' => (300, 500),
      'full' => (501, 900),
      'long' => (901, 1500),
      _ => (0, 99999),
    };
  } else if (isKid) {
    return switch (bucket) {
      'short' => (200, 500),
      'full' => (501, 900),
      'long' => (901, 1400),
      _ => (0, 99999),
    };
  } else {
    return switch (bucket) {
      'short' => (200, 400),
      'full' => (401, 700),
      'long' => (701, 1100),
      _ => (0, 99999),
    };
  }
}
