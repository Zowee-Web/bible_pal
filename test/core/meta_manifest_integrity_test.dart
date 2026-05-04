import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every meta_<id>.json on disk must be either:
///   (a) referenced by an active manifest entry, OR
///   (b) listed in assets/stories/traditional/_ARCHIVED_IDS.json
///
/// Anything else is an unresolved orphan: a story that exists on disk
/// but is neither shipped nor explicitly archived. To intentionally retire
/// a shipped story, remove it from manifest.json and add its ID to
/// _ARCHIVED_IDS.json.
void main() {
  test(
      'Every meta_<id>.json is either active in manifest or allowlisted in '
      '_ARCHIVED_IDS.json', () async {
    final manifestFile = File('assets/stories/manifest.json');
    expect(manifestFile.existsSync(), isTrue);
    final manifest =
        jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
    final parables = (manifest['parables'] as List).cast<Map<String, dynamic>>();

    final storyIdPattern = RegExp(r'^story_(\d+)_');
    final manifestIds = <int>{};
    for (final entry in parables) {
      if (entry['storytellingMode'] != 'traditional') continue;
      final match = storyIdPattern.firstMatch(entry['storyId'] as String? ?? '');
      if (match != null) {
        manifestIds.add(int.parse(match.group(1)!));
      }
    }

    final archivedFile =
        File('assets/stories/traditional/_ARCHIVED_IDS.json');
    expect(archivedFile.existsSync(), isTrue,
        reason: '_ARCHIVED_IDS.json must exist as the orphan allowlist');
    final archivedJson =
        jsonDecode(await archivedFile.readAsString()) as Map<String, dynamic>;
    final archivedIds =
        (archivedJson['archivedIds'] as List).cast<int>().toSet();

    final tradDir = Directory('assets/stories/traditional');
    final orphans = <int>[];
    for (final entity in tradDir.listSync()) {
      if (entity is! Directory) continue;
      final name = entity.path.split('/').last;
      final id = int.tryParse(name);
      if (id == null) continue;
      final metaPath = '${entity.path}/meta_$id.json';
      if (!File(metaPath).existsSync()) continue;
      if (manifestIds.contains(id)) continue;
      if (archivedIds.contains(id)) continue;
      orphans.add(id);
    }

    expect(orphans, isEmpty,
        reason: 'These story IDs have meta_<id>.json on disk but are neither '
            'in manifest.json nor allowlisted in _ARCHIVED_IDS.json: '
            '${orphans..sort()}. Either add them to the manifest or to '
            '_ARCHIVED_IDS.json (do not delete files).');
  });
}
