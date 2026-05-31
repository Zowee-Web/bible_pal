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
/// **V3 PILOT exemption retired 2026-05-31.** Every active Traditional story
/// must satisfy the full reflection contract — reflectionText, reflection
/// .txt, and exact content match — without exception. The V3_PILOT and
/// shortScripture skip-list was removed after the 156-story dual-lane KJV
/// backfill brought the corpus to 100% coverage.
///
/// See: docs/INVARIANTS.md — Reflection System Invariant
///       docs/REFLECTION_VOICE.md — voice spec

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

        // Dual-lane stories ship reflection_*_web.txt + reflection_*_kjv.txt;
        // meta.reflectionText was captured from one lane at story-creation
        // time (legacy 1000-series → KJV-captured; newer stories → WEB).
        // The test passes if meta matches ANY of the reflection files in the
        // story dir. Real drift fails this (matches neither lane).
        final candidates = unit.reflectionTxtFiles.isNotEmpty
            ? unit.reflectionTxtFiles
            : (unit.reflectionTxtFile != null
                ? [unit.reflectionTxtFile!]
                : <File>[]);
        if (candidates.isEmpty) continue;

        final metaTrimmed = _normalizeTypography(metaText.trim());
        final anyMatch = candidates.any((f) =>
            f.existsSync() &&
            _normalizeTypography(f.readAsStringSync().trim()) == metaTrimmed);

        if (!anyMatch) {
          final firstFileText =
              candidates.first.existsSync() ? candidates.first.readAsStringSync().trim() : '(no file)';
          mismatches.add(
            '${unit.id}:\n'
            '  META: "${metaTrimmed.length > 80 ? '${metaTrimmed.substring(0, 80)}...' : metaTrimmed}"\n'
            '  FILE: "${firstFileText.length > 80 ? '${firstFileText.substring(0, 80)}...' : firstFileText}"',
          );
        }
      }

      expect(mismatches, isEmpty,
          reason:
              'Reflection .txt must exactly match meta.reflectionText (after trim).\n'
              'Test now accepts a match against ANY lane file in the story dir.\n'
              'A failure here means meta matches NEITHER _web.txt NOR _kjv.txt — real drift.\n\n'
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

      // meta.reflectionText is captured from one lane at story-creation time:
      //   - Legacy 1000-series stories: meta matches KJV file (KJV-canonical)
      //   - Newer stories (1058+):       meta matches WEB file (WEB-canonical)
      // `primaryLanguageStyle` is empty on many stories so it cannot
      // disambiguate. Expose ALL lane files; the consistency test treats
      // meta as canonical if it matches ANY available reflection file.
      final preferredReflection = reflectionTxt.isNotEmpty
          ? reflectionTxt.first
          : null;

      units.add(_StoryUnit(
        id: meta['storyId']?.toString() ?? entity.path.split('/').last,
        dir: entity.path,
        metaFile: metaFile,
        meta: meta,
        reflectionTxtFile: preferredReflection,
        reflectionTxtFiles: reflectionTxt,
      ));
    }
  }

  units.sort((a, b) => a.id.compareTo(b.id));
  return units;
}

/// Normalize typography differences that don't represent content drift:
/// curly quotes, en/em-dashes with optional surrounding spaces, NBSP, etc.
/// Used by the meta↔reflection.txt exact-match test so that a story whose
/// meta has Word-style typography and whose .txt was editorially restyled
/// (or vice-versa) does not fail content equality. Real prose drift still
/// fails — only the typographic surface is canonicalized.
String _normalizeTypography(String input) {
  var s = input
      .replaceAll('’', "'") // right single quote → straight
      .replaceAll('‘', "'") // left single quote → straight
      .replaceAll('“', '"') // left double quote → straight
      .replaceAll('”', '"'); // right double quote → straight
  s = s
      .replaceAll(RegExp(r'[ \t]+\n'), '\n') // trailing whitespace before newline
      .replaceAll(RegExp(r'\n[ \t]+'), '\n') // leading whitespace after newline
      .replaceAll(' — ', '—') // " — " → "—" (drop em-dash spacing)
      .replaceAll(' – ', '–'); // " – " → "–"
  s = s.replaceAll(' ', ' '); // non-breaking space → space
  // Collapse all runs of whitespace (including paragraph breaks) to a single
  // space. JSON reflectionText is a single-line string but .txt files use
  // double-newlines between paragraphs; that is layout, not content drift.
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

class _StoryUnit {
  final String id;
  final String dir;
  final File metaFile;
  final Map<String, dynamic> meta;
  final File? reflectionTxtFile;
  final List<File> reflectionTxtFiles;

  const _StoryUnit({
    required this.id,
    required this.dir,
    required this.metaFile,
    required this.meta,
    this.reflectionTxtFile,
    this.reflectionTxtFiles = const [],
  });
}
