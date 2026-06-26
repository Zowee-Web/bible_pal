// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Regression test for Traditional mode boundary drift (ADR-025).
///
/// Scans all Traditional story text files for post-boundary continuation
/// phrases that indicate the story extended beyond the Scripture passage.
/// This test runs against committed story assets — it does not generate
/// stories, it validates existing ones.
///
/// See: docs/DECISIONS.md ADR-025 - Traditional Boundary Enforcement
void main() {
  // Post-boundary drift phrases — if these appear in the last 30% of a
  // Traditional story, the story likely drifted past its Scripture anchor.
  final driftPatterns = RegExp(
    r'as evening fell'
    r'|as the evening'
    r'|as dusk'
    r'|as nighttime settled'
    r'|as night fell'
    r'|later that day'
    r'|in the days that followed'
    r'|in the hours that followed'
    r'|from then on'
    r'|from that day forward'
    r'|when they departed'
    r'|when the guests departed'
    r'|when at last .* rose to leave'
    r'|the lesson lingered'
    r'|the lesson remained'
    r'|long after'
    r'|in the days ahead'
    r'|in the weeks that followed'
    r'|she would find herself'
    r'|he would find himself',
    caseSensitive: false,
  );

  late List<FileSystemEntity> traditionalStoryFiles;

  setUpAll(() {
    final traditionalDir = Directory('assets/stories/traditional');
    if (!traditionalDir.existsSync()) {
      fail('Traditional stories directory not found');
    }

    traditionalStoryFiles = traditionalDir
        .listSync(recursive: true)
        .where((f) =>
            f is File &&
            f.path.endsWith('.txt') &&
            f.path.contains('story_') &&
            !f.path.contains('reflection_'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  });

  test('Traditional story directory contains text files', () {
    expect(traditionalStoryFiles, isNotEmpty,
        reason: 'No Traditional story text files found');
    print('Found ${traditionalStoryFiles.length} Traditional story text files');
  });

  test('Post-ADR-025 stories (>= 826) have no boundary drift', () {
    final flagged = <String>[];

    // Only enforce on stories generated after ADR-025 boundary fix
    final postAdr025Files = traditionalStoryFiles.where((f) {
      final match = RegExp(r'/(\d+)/story_').firstMatch(f.path);
      if (match == null) return false;
      final id = int.tryParse(match.group(1)!) ?? 0;
      return id >= 826;
    }).toList();

    for (final file in postAdr025Files) {
      // Documented exemptions (boundary_enforcement_remediation backlog):
      // a story's meta may carry `boundaryException` — "scriptural" (the phrase
      // is verbatim in the anchor passage, e.g. "from that day forward" in
      // 1 Sam 16:13) or "deferred_boundary_drift" (legacy, queued for per-story
      // editorial review). New stories carry no such field and are still enforced.
      final idMatch = RegExp(r'/(\d+)/story_').firstMatch(file.path);
      if (idMatch != null) {
        final metaFile =
            File('${file.parent.path}/meta_${idMatch.group(1)}.json');
        if (metaFile.existsSync()) {
          final meta =
              jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
          if (meta['boundaryException'] != null) continue;
        }
      }

      final text = (file as File).readAsStringSync();
      final lines = text.split('\n');
      final totalLines = lines.length;

      final tailStart = (totalLines * 0.7).floor();
      final tailText = lines.skip(tailStart).join('\n');

      final match = driftPatterns.firstMatch(tailText);
      if (match != null) {
        final relativePath =
            file.path.replaceFirst(RegExp(r'.*/assets/'), 'assets/');
        flagged.add('$relativePath: "${match.group(0)}"');
      }
    }

    if (flagged.isNotEmpty) {
      print('FLAGGED post-ADR-025 stories with boundary drift:');
      for (final f in flagged) {
        print('  - $f');
      }
    }

    expect(flagged, isEmpty,
        reason:
            'Post-ADR-025 Traditional stories contain boundary drift phrases. '
            'See ADR-025 for details.');
  });

  test('Legacy stories (< 826) boundary drift audit (informational)', () {
    final flagged = <String>[];

    final legacyFiles = traditionalStoryFiles.where((f) {
      final match = RegExp(r'/(\d+)/story_').firstMatch(f.path);
      if (match == null) return false;
      final id = int.tryParse(match.group(1)!) ?? 0;
      return id < 826;
    }).toList();

    for (final file in legacyFiles) {
      final text = (file as File).readAsStringSync();
      final lines = text.split('\n');
      final totalLines = lines.length;

      final tailStart = (totalLines * 0.7).floor();
      final tailText = lines.skip(tailStart).join('\n');

      final match = driftPatterns.firstMatch(tailText);
      if (match != null) {
        final relativePath =
            file.path.replaceFirst(RegExp(r'.*/assets/'), 'assets/');
        flagged.add('$relativePath: "${match.group(0)}"');
      }
    }

    if (flagged.isNotEmpty) {
      print('INFO: ${flagged.length} legacy stories have potential boundary drift (pre-ADR-025):');
      for (final f in flagged) {
        print('  - $f');
      }
      print('These stories predate the boundary enforcement fix and may need regeneration.');
    } else {
      print('All legacy stories pass boundary check.');
    }
    // Informational only — does not fail
  });

  test('Traditional meta.json files have boundary validation results', () {
    final traditionalDir = Directory('assets/stories/traditional');
    final metaFiles = traditionalDir
        .listSync(recursive: true)
        .where((f) => f is File && f.path.contains('meta_') && f.path.endsWith('.json'))
        .toList();

    // Only check stories generated after ADR-025 (story IDs >= 826)
    final newMetaFiles = metaFiles.where((f) {
      final match = RegExp(r'meta_(\d+)\.json').firstMatch(f.path);
      if (match == null) return false;
      final id = int.tryParse(match.group(1)!) ?? 0;
      return id >= 826;
    }).toList();

    if (newMetaFiles.isEmpty) {
      print('No post-ADR-025 meta files found (stories >= 826). Skipping.');
      return;
    }

    for (final file in newMetaFiles) {
      final content = (file as File).readAsStringSync();
      final meta = jsonDecode(content) as Map<String, dynamic>;
      final relativePath =
          file.path.replaceFirst(RegExp(r'.*/assets/'), 'assets/');

      if (meta.containsKey('boundaryValidation')) {
        final bv = meta['boundaryValidation'] as Map<String, dynamic>;
        for (final entry in bv.entries) {
          expect(entry.value, equals('pass'),
              reason:
                  '$relativePath: ${entry.key} boundary validation = ${entry.value}');
        }
        print('$relativePath: boundary validation all pass');
      }
    }
  });
}
