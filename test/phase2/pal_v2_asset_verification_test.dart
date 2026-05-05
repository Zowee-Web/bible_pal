import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Phase 2 verification tests for PAL V2 asset migration.
///
/// These tests verify:
/// - Old PAL audio directories have been deleted
/// - New PAL audio directories exist with correct file counts
/// - No legacy greeting/compassionate-reply MP3s remain
/// - All prompt and micro-response IDs in pal_lines.json have MP3s
void main() {
  final projectRoot = _findProjectRoot();
  final audioBase = Directory('$projectRoot/assets/pal/audio');
  final palLinesFile = File('$projectRoot/assets/pal/pal_lines.json');

  // --- Old directory deletion ---

  group('Old PAL audio directories deleted', () {
    const oldVoiceKeys = [
      'VOICE_SARAH_STORYTELLER',
      'VOICE_HANNAH_HOPE',
      'VOICE_JAMES_HUSKY',
      'VOICE_DAVID_SHEPHERD',
      // VOICE_GRACE retired 2026-04-23 — migrated to VOICE_RUTH_COMFORT
      'VOICE_GRACE',
    ];

    for (final key in oldVoiceKeys) {
      test('$key directory does not exist', () {
        final dir = Directory('${audioBase.path}/$key');
        expect(dir.existsSync(), false,
            reason: 'Old PAL directory $key should have been deleted');
      });
    }
  });

  // --- New directory presence ---

  group('New PAL audio directories present', () {
    const newVoiceKeys = [
      'VOICE_RUTH_COMFORT',
      'VOICE_SHEPHERD',
      'VOICE_HOPE',
      'VOICE_STILLWATER',
    ];

    for (final key in newVoiceKeys) {
      test('$key directory exists', () {
        final dir = Directory('${audioBase.path}/$key');
        expect(dir.existsSync(), true,
            reason: 'New PAL directory $key should exist');
      });
    }
  });

  // --- File counts ---

  group('New PAL directory file counts', () {
    // 96 prompts + 30 micro + 1 preview = 127 from pal_lines.json. Voice
    // directories may carry additional content (framing audio, opening lines
    // from a separate manifest, etc.), so this asserts a floor, not an exact
    // count.
    test('VOICE_RUTH_COMFORT has at least 128 MP3 files (default voice +'
        ' onboarding)', () {
      final dir = Directory('${audioBase.path}/VOICE_RUTH_COMFORT');
      if (!dir.existsSync()) {
        fail('VOICE_RUTH_COMFORT directory does not exist');
      }
      final mp3s = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.mp3'))
          .toList();
      expect(mp3s.length, greaterThanOrEqualTo(128),
          reason:
              'VOICE_RUTH_COMFORT (default): floor is 96 prompts + 30 micro + '
              '1 preview + 1 onboard = 128');
    });

    for (final key in ['VOICE_SHEPHERD', 'VOICE_HOPE', 'VOICE_STILLWATER']) {
      test('$key has at least 127 MP3 files (prompts + micro + preview)', () {
        final dir = Directory('${audioBase.path}/$key');
        if (!dir.existsSync()) {
          fail('$key directory does not exist');
        }
        final mp3s = dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.mp3'))
            .toList();
        expect(mp3s.length, greaterThanOrEqualTo(127),
            reason: '$key floor: 96 prompts + 30 micro + 1 preview = 127');
      });
    }
  });

  // --- No legacy files ---

  group('No legacy audio files remain', () {
    test('no greeting_*.mp3 files in any PAL audio directory', () {
      if (!audioBase.existsSync()) {
        fail('assets/pal/audio/ does not exist');
      }
      final greetingFiles = audioBase
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) {
        final name = f.uri.pathSegments.last;
        return name.startsWith('greeting_') && name.endsWith('.mp3');
      }).toList();

      expect(greetingFiles, isEmpty,
          reason:
              'No greeting_*.mp3 files should remain. Found: ${greetingFiles.map((f) => f.path).join(', ')}');
    });

    test('no comp_*.mp3 files in any PAL audio directory', () {
      if (!audioBase.existsSync()) {
        fail('assets/pal/audio/ does not exist');
      }
      final compFiles = audioBase
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) {
        final name = f.uri.pathSegments.last;
        return name.startsWith('comp_') && name.endsWith('.mp3');
      }).toList();

      expect(compFiles, isEmpty,
          reason:
              'No comp_*.mp3 files should remain. Found: ${compFiles.map((f) => f.path).join(', ')}');
    });
  });

  // --- All prompt IDs have MP3s ---

  group('All prompt IDs have corresponding MP3s', () {
    late Map<String, dynamic> palLines;

    setUpAll(() {
      if (!palLinesFile.existsSync()) {
        fail('pal_lines.json not found');
      }
      palLines = jsonDecode(palLinesFile.readAsStringSync()) as Map<String, dynamic>;
    });

    const voiceKeys = [
      'VOICE_RUTH_COMFORT',
      'VOICE_SHEPHERD',
      'VOICE_HOPE',
      'VOICE_STILLWATER',
    ];

    for (final voiceKey in voiceKeys) {
      test('$voiceKey has all prompt MP3s', () {
        final prompts = palLines['prompts'] as Map<String, dynamic>;
        final missingIds = <String>[];

        for (final bucket in prompts.entries) {
          final lines = bucket.value as List;
          for (final line in lines) {
            final id = (line as Map<String, dynamic>)['id'] as String;
            final file = File('${audioBase.path}/$voiceKey/$id.mp3');
            if (!file.existsSync() || file.lengthSync() == 0) {
              missingIds.add(id);
            }
          }
        }

        expect(missingIds, isEmpty,
            reason: '$voiceKey missing prompt MP3s: ${missingIds.join(', ')}');
      });

      test('$voiceKey has all micro-response MP3s', () {
        final microResponses = palLines['microResponses'] as Map<String, dynamic>;
        final missingIds = <String>[];

        for (final bucket in microResponses.entries) {
          final lines = bucket.value as List;
          for (final line in lines) {
            final id = (line as Map<String, dynamic>)['id'] as String;
            final file = File('${audioBase.path}/$voiceKey/$id.mp3');
            if (!file.existsSync() || file.lengthSync() == 0) {
              missingIds.add(id);
            }
          }
        }

        expect(missingIds, isEmpty,
            reason:
                '$voiceKey missing micro-response MP3s: ${missingIds.join(', ')}');
      });

      test('$voiceKey has preview MP3', () {
        final preview = palLines['preview'] as List;
        for (final line in preview) {
          final id = (line as Map<String, dynamic>)['id'] as String;
          final file = File('${audioBase.path}/$voiceKey/$id.mp3');
          expect(file.existsSync() && file.lengthSync() > 0, true,
              reason: '$voiceKey missing preview: $id.mp3');
        }
      });
    }

    test('VOICE_RUTH_COMFORT has onboarding MP3', () {
      final onboarding = palLines['onboarding'] as List;
      for (final line in onboarding) {
        final id = (line as Map<String, dynamic>)['id'] as String;
        final file = File('${audioBase.path}/VOICE_RUTH_COMFORT/$id.mp3');
        expect(file.existsSync() && file.lengthSync() > 0, true,
            reason: 'VOICE_RUTH_COMFORT missing onboarding: $id.mp3');
      }
    });
  });

  // --- Total file count ---

  group('Total file count', () {
    // Floor: 4 voices × 127 (pal_lines) + 1 onboarding (default voice) = 509.
    // Voice content has grown beyond the original migration baseline; assert
    // the floor not an exact snapshot.
    test('total PAL audio files >= 509', () {
      if (!audioBase.existsSync()) {
        fail('assets/pal/audio/ does not exist');
      }
      final allMp3s = audioBase
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.mp3'))
          .toList();

      expect(allMp3s.length, greaterThanOrEqualTo(509),
          reason:
              'Floor: 4 voices × 127 + 1 onboarding = 509. Found ${allMp3s.length}');
    });
  });
}

/// Walk up from the test file to find the project root (contains pubspec.yaml).
String _findProjectRoot() {
  var dir = Directory.current;
  while (dir.path != dir.parent.path) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) {
      return dir.path;
    }
    dir = dir.parent;
  }
  // Fallback: assume cwd is project root
  return Directory.current.path;
}
