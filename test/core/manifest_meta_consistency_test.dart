import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every Traditional manifest variant must agree with its meta_<id>.json
/// on title, bibleStoryKey, and scripture reference. A drift here means a
/// story was edited in one place but not the other and users will see
/// inconsistent data.
///
/// Field mapping:
///   manifest.title             == meta.title
///   manifest.bibleStoryKey     == meta.bibleStoryKey
///   manifest.bibleSourceRef    == meta.scriptureAnchor (raw "Book Ch:Vv")
///
/// Comparisons are skipped when either side is missing the field — this
/// test enforces agreement, not field presence (other tests cover presence).
void main() {
  test('Manifest entries match their meta_<id>.json on title / key / anchor',
      () async {
    final manifest = jsonDecode(
            await File('assets/stories/manifest.json').readAsString())
        as Map<String, dynamic>;
    final parables = (manifest['parables'] as List).cast<Map<String, dynamic>>();

    final storyIdPattern = RegExp(r'^story_(\d+)_');
    final mismatches = <String>[];

    for (final entry in parables) {
      if (entry['storytellingMode'] != 'traditional') continue;
      final storyId = entry['storyId'] as String? ?? '';
      final match = storyIdPattern.firstMatch(storyId);
      if (match == null) continue;
      final id = int.parse(match.group(1)!);

      final metaFile = File('assets/stories/traditional/$id/meta_$id.json');
      if (!metaFile.existsSync()) continue;
      final meta =
          jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;

      final entryTitle = entry['title'] as String?;
      final metaTitle = meta['title'] as String?;
      if (entryTitle != null && metaTitle != null && entryTitle != metaTitle) {
        mismatches.add(
            '$storyId  title: meta="$metaTitle" manifest="$entryTitle"');
      }

      final entryKey = entry['bibleStoryKey'] as String?;
      final metaKey = meta['bibleStoryKey'] as String?;
      if (entryKey != null && metaKey != null && entryKey != metaKey) {
        mismatches.add(
            '$storyId  bibleStoryKey: meta="$metaKey" manifest="$entryKey"');
      }

      final entryAnchor = entry['bibleSourceRef'] as String?;
      final metaAnchor = meta['scriptureAnchor'] as String?;
      if (entryAnchor != null &&
          metaAnchor != null &&
          entryAnchor != metaAnchor) {
        mismatches.add(
            '$storyId  scriptureAnchor: meta="$metaAnchor" manifest="$entryAnchor"');
      }
    }

    expect(mismatches, isEmpty,
        reason: 'Manifest ↔ meta drift detected. Fix the divergent field in '
            'whichever file is wrong:\n  ${mismatches.join('\n  ')}');
  });
}
