import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CRITICAL: Validates that all audio assets referenced by story metadata
/// exist as non-empty files in the repo.
///
/// This test enforces two relationships:
/// 1. meta.files.{length}.storyAudio → file exists and is non-empty
/// 2. Reflection audio → file exists and is non-empty
///    - Standard (50/51 stories): meta.files.reflection.reflectionAudio
///    - Legacy (story 801): meta.files.{length}.reflectionAudio (per-length)
///
/// Also validates that no active stale-audio flags remain in committed meta.
///
/// See: docs/INVARIANTS.md — Audio Asset Consistency
void main() {
  group('CRITICAL: Audio Asset Consistency', () {
    late List<_StoryUnit> storyUnits;

    setUpAll(() {
      storyUnits = _discoverStoryUnits();
    });

    test('story units discovered', () {
      expect(storyUnits, isNotEmpty,
          reason: 'Expected to find story units in assets/stories/');
    });

    // ---------------------------------------------------------------
    // 1. Story audio files referenced in meta exist and are non-empty
    // ---------------------------------------------------------------
    test('CRITICAL: all meta.files.*.storyAudio references resolve to non-empty files',
        () {
      final violations = <String>[];

      for (final unit in storyUnits) {
        final files = unit.meta['files'];
        if (files is! Map) continue;

        for (final entry in files.entries) {
          if (entry.key == 'reflection') continue;
          if (entry.value is! Map) continue;

          final audioRef = entry.value['storyAudio'];
          if (audioRef == null || audioRef is! String || audioRef.isEmpty) {
            continue;
          }

          final audioFile = File('${unit.dir}/$audioRef');
          if (!audioFile.existsSync()) {
            violations.add(
                '${unit.id} [${entry.key}]: MISSING — ${unit.dir}/$audioRef');
          } else if (audioFile.lengthSync() == 0) {
            violations.add(
                '${unit.id} [${entry.key}]: EMPTY (0 bytes) — ${unit.dir}/$audioRef');
          }
        }
      }

      expect(violations, isEmpty,
          reason:
              'All story audio files referenced in meta.files must exist and be non-empty.\n\n'
              'Violations:\n${violations.join('\n')}');
    });

    // ---------------------------------------------------------------
    // 2. Reflection audio references resolve to non-empty files
    //    Handles both standard and legacy (per-length) patterns
    // ---------------------------------------------------------------
    test('CRITICAL: all reflection audio references resolve to non-empty files',
        () {
      final violations = <String>[];

      for (final unit in storyUnits) {
        final files = unit.meta['files'];
        if (files is! Map) continue;

        // Standard pattern: meta.files.reflection.reflectionAudio
        if (files.containsKey('reflection') && files['reflection'] is Map) {
          final reflAudio = files['reflection']['reflectionAudio'];
          if (reflAudio is String && reflAudio.isNotEmpty) {
            final audioFile = File('${unit.dir}/$reflAudio');
            if (!audioFile.existsSync()) {
              violations.add(
                  '${unit.id} [reflection]: MISSING — ${unit.dir}/$reflAudio');
            } else if (audioFile.lengthSync() == 0) {
              violations.add(
                  '${unit.id} [reflection]: EMPTY (0 bytes) — ${unit.dir}/$reflAudio');
            }
          }
        }

        // Legacy pattern: meta.files.{length}.reflectionAudio (per-length)
        for (final entry in files.entries) {
          if (entry.key == 'reflection') continue;
          if (entry.value is! Map) continue;

          final reflAudio = entry.value['reflectionAudio'];
          if (reflAudio is String && reflAudio.isNotEmpty) {
            final audioFile = File('${unit.dir}/$reflAudio');
            if (!audioFile.existsSync()) {
              violations.add(
                  '${unit.id} [${entry.key}/reflectionAudio]: MISSING — ${unit.dir}/$reflAudio');
            } else if (audioFile.lengthSync() == 0) {
              violations.add(
                  '${unit.id} [${entry.key}/reflectionAudio]: EMPTY (0 bytes) — ${unit.dir}/$reflAudio');
            }
          }
        }
      }

      expect(violations, isEmpty,
          reason:
              'All reflection audio files referenced in meta must exist and be non-empty.\n\n'
              'Violations:\n${violations.join('\n')}');
    });

    // ---------------------------------------------------------------
    // 3. No active stale-audio flags in committed meta
    // ---------------------------------------------------------------
    test('no active reflectionAudioStale flags in committed meta', () {
      final stale = <String>[];

      for (final unit in storyUnits) {
        if (unit.meta['reflectionAudioStale'] == true) {
          final reason =
              unit.meta['reflectionAudioStaleReason'] ?? '(no reason)';
          stale.add('${unit.id}: reflectionAudioStale=true — $reason');
        }
      }

      expect(stale, isEmpty,
          reason:
              'Active stale-audio flags must be resolved before commit.\n'
              'Regenerate the audio, then remove the flag.\n\n'
              'Stale:\n${stale.join('\n')}');
    });

    // ---------------------------------------------------------------
    // 4. Audio path strings are well-formed
    // ---------------------------------------------------------------
    test('audio path references are well-formed strings', () {
      final malformed = <String>[];

      for (final unit in storyUnits) {
        final files = unit.meta['files'];
        if (files is! Map) continue;

        for (final entry in files.entries) {
          if (entry.value is! Map) continue;

          for (final audioField in ['storyAudio', 'reflectionAudio']) {
            final ref = entry.value[audioField];
            if (ref == null) continue;

            if (ref is! String) {
              malformed.add(
                  '${unit.id} [${entry.key}.$audioField]: expected String, got ${ref.runtimeType}');
            } else if (ref.contains('..') || ref.startsWith('/')) {
              malformed.add(
                  '${unit.id} [${entry.key}.$audioField]: path traversal or absolute path — "$ref"');
            }
          }
        }
      }

      expect(malformed, isEmpty,
          reason:
              'Audio path references must be well-formed relative paths.\n\n'
              'Malformed:\n${malformed.join('\n')}');
    });
  });
}

/// Discovers story units that are in the production manifest.
/// Only validates audio for stories that are actually served to users.
List<_StoryUnit> _discoverStoryUnits() {
  // Build set of production story directories from manifest
  final manifestFile = File('assets/stories/manifest.json');
  final productionDirs = <String>{};
  if (manifestFile.existsSync()) {
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    final parables = manifest['parables'] as List;
    for (final p in parables) {
      final textPath = p['textFilePath'] as String?;
      if (textPath == null) continue;
      final parts = textPath.split('/');
      if (parts.length >= 2) {
        productionDirs.add('${parts[0]}/${parts[1]}');
      }
    }
  }

  final units = <_StoryUnit>[];

  for (final modeDir in [
    'assets/stories/traditional',
    'assets/stories/creative',
  ]) {
    final dir = Directory(modeDir);
    if (!dir.existsSync()) continue;
    final modeName = modeDir.split('/').last;

    for (final entity in dir.listSync()) {
      if (entity is! Directory) continue;
      final storyId = entity.path.split('/').last;

      // Skip stories not in the production manifest
      if (!productionDirs.contains('$modeName/$storyId')) continue;

      final metaFiles = entity
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('meta_') && f.path.endsWith('.json'))
          .toList();

      if (metaFiles.isEmpty) continue;

      final metaFile = metaFiles.first;
      final meta =
          jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;

      units.add(_StoryUnit(
        id: meta['storyId']?.toString() ?? entity.path.split('/').last,
        dir: entity.path,
        metaFile: metaFile,
        meta: meta,
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

  const _StoryUnit({
    required this.id,
    required this.dir,
    required this.metaFile,
    required this.meta,
  });
}
