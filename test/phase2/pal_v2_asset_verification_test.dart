import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// PAL audio asset verification tests.
///
/// Originally written for Phase 2 PAL V2 migration. Updated 2026-05 after
/// Feature 2.0 (12-line time-bucketed library, PR #13 / commit ceb0d3a) which
/// retired VOICE_GRACE and VOICE_RUTH_COMFORT and grew per-voice asset counts
/// well beyond the original 127/128 file expectations.
///
/// Current invariants verified:
/// - Legacy V1 voice directories (Sarah/Hannah/James/David) remain deleted
/// - The 3 active PAL voices (Hope/Shepherd/Stillwater) have audio directories
/// - Retired voices (Grace/Ruth) are archived, not in audio/
/// - No legacy greeting_*.mp3 / comp_*.mp3 files remain
/// - All prompt and micro-response IDs in pal_lines.json have MP3s for active
///   voices
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
    ];

    for (final key in oldVoiceKeys) {
      test('$key directory does not exist', () {
        final dir = Directory('${audioBase.path}/$key');
        expect(dir.existsSync(), false,
            reason: 'Old PAL directory $key should have been deleted');
      });
    }
  });

  // --- Active voice directory presence ---

  group('Active PAL audio directories present', () {
    // 4 canonical PAL voices per `feedback_pal_canonical_system.md`.
    // Grace + Ruth retired; their audio is archived under audio_archive_*.
    // Miriam activated 2026-07-14 (ADR-029).
    const activeVoiceKeys = [
      'VOICE_HOPE',
      'VOICE_SHEPHERD',
      'VOICE_STILLWATER',
      'VOICE_MIRIAM',
    ];

    for (final key in activeVoiceKeys) {
      test('$key directory exists', () {
        final dir = Directory('${audioBase.path}/$key');
        expect(dir.existsSync(), true,
            reason: 'Active PAL voice $key must have an audio directory');
      });

      test('$key directory contains audio files', () {
        final dir = Directory('${audioBase.path}/$key');
        if (!dir.existsSync()) {
          fail('$key directory does not exist');
        }
        final mp3s = dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.mp3'))
            .toList();
        expect(mp3s.length, greaterThan(0),
            reason:
                '$key must have at least some audio (the per-voice count is not pinned because it grows as new lines are added)');
      });
    }
  });

  // --- Retired voices not in active audio dir ---

  group('Retired voices archived, not active', () {
    // Voice retirement does NOT delete the audio (per
    // `feedback_never_delete_audio.md`). Audio moves to audio_archive_*.
    const retiredVoiceKeys = ['VOICE_GRACE', 'VOICE_RUTH_COMFORT'];

    for (final key in retiredVoiceKeys) {
      test('$key directory does NOT exist in audio/ (audio archived)', () {
        final dir = Directory('${audioBase.path}/$key');
        expect(dir.existsSync(), false,
            reason:
                'Retired voice $key must not have an audio dir; audio moves to assets/pal/audio_archive_*');
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

    // Only the 4 active voices need full asset coverage. Retired voices'
    // audio is preserved under audio_archive_* and not referenced at runtime.
    // Miriam activated 2026-07-14 (ADR-029).
    const voiceKeys = [
      'VOICE_HOPE',
      'VOICE_SHEPHERD',
      'VOICE_STILLWATER',
      'VOICE_MIRIAM',
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

    // VOICE_GRACE onboarding MP3 test removed: Grace was retired 2026-04-23
    // and its audio is archived. The active default voice (VOICE_HOPE) is
    // covered by the prompt/micro/preview tests above.
  });

  // Total file count assertion removed: per-voice asset counts grow as new
  // lines are added (current state ~520+ per voice, far past the 127 baseline
  // this test originally pinned). Use per-ID coverage tests above instead;
  // they're robust to count drift.
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
