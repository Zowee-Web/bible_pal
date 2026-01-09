// CRITICAL VOICE CONSENT GATE BYPASS PREVENTION TEST
// This test scans the codebase to ensure all voice playback goes through
// VoiceConsentGate. Direct calls to audio/TTS APIs are forbidden outside
// the allowlisted files.
//
// DO NOT DISABLE OR WEAKEN THIS TEST.
// DO NOT ADD FILES TO THE ALLOWLIST WITHOUT ENSURING THEY USE VoiceConsentGate.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CRITICAL: VoiceConsentGate Bypass Prevention', () {
    late Directory libDir;

    setUpAll(() {
      // Find project root
      var projectRoot = Directory.current;
      while (!File('${projectRoot.path}/pubspec.yaml').existsSync()) {
        projectRoot = projectRoot.parent;
        if (projectRoot.path == projectRoot.parent.path) {
          throw Exception('Could not find project root (pubspec.yaml)');
        }
      }
      libDir = Directory('${projectRoot.path}/lib');
    });

    // Files allowed to call AudioService.play() directly
    // These files MUST use VoiceConsentGate before calling play()
    const audioPlayAllowlist = {
      'parable_player_notifier.dart', // Uses VoiceConsentGate.checkStoryNarration()
      'audio_service.dart', // The service itself (defines play())
      'voice_consent_gate.dart', // Contains usage example in doc comments
    };

    // Files allowed to call FlutterTts.speak() directly
    // These files MUST use VoiceConsentGate before calling speak()
    const ttsAllowlist = {
      'whisper_screen.dart', // Uses VoiceConsentGate.checkPalGreetings()
    };

    test('CRITICAL: No direct AudioService.play() calls outside allowlist', () {
      final violations = <String>[];

      for (final file in libDir.listSync(recursive: true)) {
        if (file is! File) continue;
        if (!file.path.endsWith('.dart')) continue;

        final fileName = file.uri.pathSegments.last;
        if (audioPlayAllowlist.contains(fileName)) continue;

        final content = file.readAsStringSync();

        // Check for _audioService.play() or audioService.play() patterns
        if (RegExp(r'_?audioService\.play\s*\(').hasMatch(content)) {
          violations.add(file.path);
        }

        // Check for AudioService().play() or similar direct instantiation
        if (RegExp(r'AudioService\s*\(\s*\).*\.play\s*\(').hasMatch(content)) {
          violations.add(file.path);
        }
      }

      expect(
        violations,
        isEmpty,
        reason: '''
🚨 VOICE CONSENT BYPASS DETECTED 🚨

The following files call AudioService.play() directly:
${violations.map((v) => '  - $v').join('\n')}

All voice playback MUST go through VoiceConsentGate.

To fix:
1. Import VoiceConsentGate
2. Call VoiceConsentGate.checkStoryNarration() before playing
3. Handle VoiceGateResult.needsConsent and .blocked cases

If this is a new legitimate audio path, add it to the allowlist in this test
AND ensure it properly uses VoiceConsentGate.
''',
      );
    });

    test('CRITICAL: No direct FlutterTts.speak() calls outside allowlist', () {
      final violations = <String>[];

      for (final file in libDir.listSync(recursive: true)) {
        if (file is! File) continue;
        if (!file.path.endsWith('.dart')) continue;

        final fileName = file.uri.pathSegments.last;
        if (ttsAllowlist.contains(fileName)) continue;

        final content = file.readAsStringSync();

        // Check for _tts.speak() or tts.speak() patterns
        if (RegExp(r'_?tts\.speak\s*\(').hasMatch(content)) {
          violations.add(file.path);
        }

        // Check for FlutterTts().speak() direct instantiation
        if (RegExp(r'FlutterTts\s*\(\s*\).*\.speak\s*\(').hasMatch(content)) {
          violations.add(file.path);
        }
      }

      expect(
        violations,
        isEmpty,
        reason: '''
🚨 VOICE CONSENT BYPASS DETECTED 🚨

The following files call FlutterTts.speak() directly:
${violations.map((v) => '  - $v').join('\n')}

All voice playback MUST go through VoiceConsentGate.

To fix:
1. Import VoiceConsentGate
2. Call VoiceConsentGate.checkPalGreetings() before speaking
3. Handle VoiceGateResult.needsConsent and .blocked cases

If this is a new legitimate TTS path, add it to the allowlist in this test
AND ensure it properly uses VoiceConsentGate.
''',
      );
    });

    test('Allowlisted files import VoiceConsentGate', () {
      final missingImports = <String>[];

      // Files that don't need to import VoiceConsentGate
      const exemptFromImport = {
        'audio_service.dart', // The service itself
        'voice_consent_gate.dart', // The gate itself
      };

      // Check audio allowlist files
      for (final fileName in audioPlayAllowlist) {
        if (exemptFromImport.contains(fileName)) continue;

        final file = _findFile(libDir, fileName);
        if (file == null) continue;

        final content = file.readAsStringSync();
        if (!content.contains("import 'package:bible_pal/services/voice_consent_gate.dart'") &&
            !content.contains('import "package:bible_pal/services/voice_consent_gate.dart"')) {
          missingImports.add(fileName);
        }
      }

      // Check TTS allowlist files
      for (final fileName in ttsAllowlist) {
        final file = _findFile(libDir, fileName);
        if (file == null) continue;

        final content = file.readAsStringSync();
        if (!content.contains("import 'package:bible_pal/services/voice_consent_gate.dart'") &&
            !content.contains('import "package:bible_pal/services/voice_consent_gate.dart"')) {
          missingImports.add(fileName);
        }
      }

      expect(
        missingImports,
        isEmpty,
        reason: '''
Files in the voice playback allowlist must import VoiceConsentGate:
${missingImports.map((f) => '  - $f').join('\n')}

This ensures the gate is actually being used, not just allowed.
''',
      );
    });

    test('Allowlisted files actually use VoiceConsentGate', () {
      final notUsingGate = <String>[];

      // Files that don't need to call VoiceConsentGate methods
      const exemptFromUsage = {
        'audio_service.dart', // The service itself
        'voice_consent_gate.dart', // The gate itself (defines the methods)
      };

      // Check audio allowlist files
      for (final fileName in audioPlayAllowlist) {
        if (exemptFromUsage.contains(fileName)) continue;

        final file = _findFile(libDir, fileName);
        if (file == null) continue;

        final content = file.readAsStringSync();
        if (!content.contains('VoiceConsentGate.checkStoryNarration')) {
          notUsingGate.add('$fileName (missing checkStoryNarration)');
        }
      }

      // Check TTS allowlist files
      for (final fileName in ttsAllowlist) {
        final file = _findFile(libDir, fileName);
        if (file == null) continue;

        final content = file.readAsStringSync();
        if (!content.contains('VoiceConsentGate.checkPalGreetings')) {
          notUsingGate.add('$fileName (missing checkPalGreetings)');
        }
      }

      expect(
        notUsingGate,
        isEmpty,
        reason: '''
Files in the voice playback allowlist must actually call VoiceConsentGate:
${notUsingGate.map((f) => '  - $f').join('\n')}

Being in the allowlist means you MUST use the gate, not that you're exempt from it.
''',
      );
    });
  });
}

/// Find a file by name in the directory tree
File? _findFile(Directory dir, String fileName) {
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File && entity.uri.pathSegments.last == fileName) {
      return entity;
    }
  }
  return null;
}
