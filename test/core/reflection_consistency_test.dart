import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CRITICAL: Validates that reflection assets are consistent across all stories.
///
/// meta_*.json.reflectionText is the single source of truth. This test ensures:
/// 1. Every meta JSON has a reflectionText field (non-null, non-empty string)
/// 2. A corresponding reflection .txt file exists
/// 3. The .txt content exactly matches meta.reflectionText
/// 4. No active reflectionAudioStale flags are left in committed meta
///
/// Line ending normalization: both sides are .trim()'d before comparison.
/// This handles trailing newlines that git or editors may introduce. No other
/// normalization is applied — content must match exactly.
///
/// See: docs/INVARIANTS.md — Reflection System Invariant
void main() {
  group('CRITICAL: Reflection Consistency', () {
    late List<_StoryUnit> storyUnits;

    setUpAll(() {
      storyUnits = _discoverStoryUnits();
    });

    test('all meta JSON files have reflectionText (non-null, non-empty string)',
        () {
      final violations = <String>[];

      for (final unit in storyUnits) {
        final meta = unit.meta;
        if (!meta.containsKey('reflectionText')) {
          violations.add('${unit.id}: reflectionText field missing from meta');
        } else if (meta['reflectionText'] == null) {
          violations.add('${unit.id}: reflectionText is null');
        } else if (meta['reflectionText'] is! String) {
          violations.add(
              '${unit.id}: reflectionText is ${meta['reflectionText'].runtimeType}, expected String');
        } else if ((meta['reflectionText'] as String).trim().isEmpty) {
          violations.add('${unit.id}: reflectionText is empty string');
        }
      }

      expect(violations, isEmpty,
          reason:
              'Every story meta must have a non-empty reflectionText string.\n\n'
              'Violations:\n${violations.join('\n')}');
    });

    test('every story has a reflection .txt file', () {
      final missing = <String>[];

      for (final unit in storyUnits) {
        if (unit.reflectionTxtFile == null) {
          missing.add('${unit.id}: no reflection_*.txt in ${unit.dir}');
        } else if (!unit.reflectionTxtFile!.existsSync()) {
          missing.add(
              '${unit.id}: ${unit.reflectionTxtFile!.path} does not exist');
        }
      }

      expect(missing, isEmpty,
          reason: 'Every story must have a reflection .txt file.\n\n'
              'Missing:\n${missing.join('\n')}');
    });

    test('reflection .txt content exactly matches meta.reflectionText', () {
      final mismatches = <String>[];

      for (final unit in storyUnits) {
        final metaText = unit.meta['reflectionText'];
        if (metaText == null || metaText is! String) continue;
        if (unit.reflectionTxtFile == null ||
            !unit.reflectionTxtFile!.existsSync()) {
          continue;
        }

        final fileText = unit.reflectionTxtFile!.readAsStringSync().trim();
        final metaTrimmed = metaText.trim();

        if (fileText != metaTrimmed) {
          mismatches.add(
            '${unit.id}:\n'
            '  META: "${metaTrimmed.length > 80 ? '${metaTrimmed.substring(0, 80)}...' : metaTrimmed}"\n'
            '  FILE: "${fileText.length > 80 ? '${fileText.substring(0, 80)}...' : fileText}"',
          );
        }
      }

      expect(mismatches, isEmpty,
          reason:
              'Reflection .txt must exactly match meta.reflectionText (after trim).\n'
              'meta JSON is canonical — sync .txt from meta to fix.\n\n'
              'Mismatches:\n${mismatches.join('\n\n')}');
    });

    test('reflection .txt files are not empty', () {
      final empty = <String>[];

      for (final unit in storyUnits) {
        if (unit.reflectionTxtFile == null ||
            !unit.reflectionTxtFile!.existsSync()) {
          continue;
        }

        final content = unit.reflectionTxtFile!.readAsStringSync().trim();
        if (content.isEmpty) {
          empty.add('${unit.id}: ${unit.reflectionTxtFile!.path}');
        }
      }

      expect(empty, isEmpty,
          reason: 'Reflection .txt files must not be empty.\n\n'
              'Empty files:\n${empty.join('\n')}');
    });

    test('no active reflectionAudioStale flags in committed meta', () {
      final stale = <String>[];

      for (final unit in storyUnits) {
        final isStale = unit.meta['reflectionAudioStale'];
        if (isStale == true) {
          final reason =
              unit.meta['reflectionAudioStaleReason'] ?? '(no reason given)';
          stale.add('${unit.id}: reflectionAudioStale=true — $reason');
        }
      }

      expect(stale, isEmpty,
          reason:
              'Active reflectionAudioStale flags must be resolved before commit.\n'
              'Regenerate the audio, then remove the stale flag.\n\n'
              'Stale:\n${stale.join('\n')}');
    });
  });
}

/// Discovers all story units by scanning for meta_*.json files.
List<_StoryUnit> _discoverStoryUnits() {
  final units = <_StoryUnit>[];

  for (final modeDir in ['assets/stories/traditional', 'assets/stories/creative']) {
    final dir = Directory(modeDir);
    if (!dir.existsSync()) continue;

    for (final entity in dir.listSync()) {
      if (entity is! Directory) continue;

      final metaFiles = entity
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('meta_') && f.path.endsWith('.json'))
          .toList();

      if (metaFiles.isEmpty) continue;

      final metaFile = metaFiles.first;
      final meta =
          jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;

      final reflectionTxt = entity
          .listSync()
          .whereType<File>()
          .where(
              (f) => f.path.contains('reflection_') && f.path.endsWith('.txt'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      units.add(_StoryUnit(
        id: meta['storyId']?.toString() ?? entity.path.split('/').last,
        dir: entity.path,
        metaFile: metaFile,
        meta: meta,
        reflectionTxtFile: reflectionTxt.isNotEmpty ? reflectionTxt.first : null,
      ));
    }
  }

  units.sort((a, b) => a.id.compareTo(b.id));
  return units;
}

class _StoryUnit {
  final String id;
  final String dir;
  final File metaFile;
  final Map<String, dynamic> meta;
  final File? reflectionTxtFile;

  const _StoryUnit({
    required this.id,
    required this.dir,
    required this.metaFile,
    required this.meta,
    this.reflectionTxtFile,
  });
}
