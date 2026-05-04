import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every Traditional manifest entry must have a corresponding
/// assets/stories/traditional/<id>/meta_<id>.json on disk.
///
/// Pairs with meta_manifest_integrity_test.dart (the reverse direction)
/// and manifest_meta_consistency_test.dart (field-level agreement).
void main() {
  test('Every Traditional manifest ID has a meta_<id>.json on disk', () async {
    final manifestFile = File('assets/stories/manifest.json');
    expect(manifestFile.existsSync(), isTrue,
        reason: 'manifest.json must exist');
    final manifest =
        jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
    final parables = (manifest['parables'] as List).cast<Map<String, dynamic>>();

    final storyIdPattern = RegExp(r'^story_(\d+)_');
    final manifestIds = <int>{};
    final unparseable = <String>[];

    for (final entry in parables) {
      if (entry['storytellingMode'] != 'traditional') continue;
      final storyId = entry['storyId'] as String? ?? '';
      final match = storyIdPattern.firstMatch(storyId);
      if (match == null) {
        unparseable.add(storyId);
        continue;
      }
      manifestIds.add(int.parse(match.group(1)!));
    }

    expect(unparseable, isEmpty,
        reason: 'All Traditional manifest storyIds must match '
            'story_<digits>_ pattern. Offending: $unparseable');

    final missing = <int>[];
    for (final id in manifestIds) {
      final metaPath = 'assets/stories/traditional/$id/meta_$id.json';
      if (!File(metaPath).existsSync()) {
        missing.add(id);
      }
    }

    expect(missing, isEmpty,
        reason: 'Manifest references stories with no meta_<id>.json '
            'on disk: ${missing.toList()..sort()}');
  });
}
