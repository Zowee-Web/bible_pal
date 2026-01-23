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
    late String libPath;

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
      libPath = libDir.path;
    });

    /// Convert absolute file path to lib-relative path (e.g., "providers/parable_player_notifier.dart")
    String toLibRelative(String absolutePath) {
      if (absolutePath.startsWith(libPath)) {
        var relative = absolutePath.substring(libPath.length);
        if (relative.startsWith('/')) relative = relative.substring(1);
        return relative;
      }
      return absolutePath;
    }

    // Files allowed to call AudioService.play() directly (lib-relative paths)
    // These files MUST use VoiceConsentGate before calling play()
    const audioPlayAllowlist = {
      'providers/parable_player_notifier.dart', // Uses VoiceConsentGate.checkStoryNarration()
      'services/audio_service.dart', // The service itself (defines play())
      'services/voice_consent_gate.dart', // Contains usage example in doc comments
    };

    // Files allowed to call FlutterTts.speak() directly (lib-relative paths)
    // These files MUST use VoiceConsentGate before calling speak()
    const ttsAllowlist = {
      'features/whisper/whisper_screen.dart', // Uses VoiceConsentGate.checkPalGreetings()
    };

    // Files exempt from "must import gate" and "must use gate" checks
    const exemptFromGateUsage = {
      'services/audio_service.dart', // The service itself
      'services/voice_consent_gate.dart', // The gate itself
    };

    test('CRITICAL: No direct AudioService.play() calls outside allowlist', () {
      final violations = <String>[];

      for (final file in libDir.listSync(recursive: true)) {
        if (file is! File) continue;
        if (!file.path.endsWith('.dart')) continue;

        final relativePath = toLibRelative(file.path);
        if (audioPlayAllowlist.contains(relativePath)) continue;

        final content = file.readAsStringSync();

        // Check for _audioService.play() or audioService.play() patterns
        if (RegExp(r'_?audioService\.play\s*\(').hasMatch(content)) {
          violations.add(relativePath);
        }

        // Check for AudioService().play() or similar direct instantiation
        if (RegExp(r'AudioService\s*\(\s*\).*\.play\s*\(').hasMatch(content)) {
          violations.add(relativePath);
        }
      }

      expect(
        violations,
        isEmpty,
        reason: '''
🚨 VOICE CONSENT BYPASS DETECTED 🚨

The following files call AudioService.play() directly:
${violations.map((v) => '  - lib/$v').join('\n')}

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

        final relativePath = toLibRelative(file.path);
        if (ttsAllowlist.contains(relativePath)) continue;

        final content = file.readAsStringSync();

        // Check for _tts.speak() or tts.speak() patterns
        if (RegExp(r'_?tts\.speak\s*\(').hasMatch(content)) {
          violations.add(relativePath);
        }

        // Check for FlutterTts().speak() direct instantiation
        if (RegExp(r'FlutterTts\s*\(\s*\).*\.speak\s*\(').hasMatch(content)) {
          violations.add(relativePath);
        }
      }

      expect(
        violations,
        isEmpty,
        reason: '''
🚨 VOICE CONSENT BYPASS DETECTED 🚨

The following files call FlutterTts.speak() directly:
${violations.map((v) => '  - lib/$v').join('\n')}

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

      // Check audio allowlist files
      for (final relativePath in audioPlayAllowlist) {
        if (exemptFromGateUsage.contains(relativePath)) continue;

        final file = File('$libPath/$relativePath');
        if (!file.existsSync()) continue;

        final content = file.readAsStringSync();
        if (!content.contains(
                "import 'package:bible_pal/services/voice_consent_gate.dart'") &&
            !content.contains(
                'import "package:bible_pal/services/voice_consent_gate.dart"')) {
          missingImports.add(relativePath);
        }
      }

      // Check TTS allowlist files
      for (final relativePath in ttsAllowlist) {
        if (exemptFromGateUsage.contains(relativePath)) continue;

        final file = File('$libPath/$relativePath');
        if (!file.existsSync()) continue;

        final content = file.readAsStringSync();
        if (!content.contains(
                "import 'package:bible_pal/services/voice_consent_gate.dart'") &&
            !content.contains(
                'import "package:bible_pal/services/voice_consent_gate.dart"')) {
          missingImports.add(relativePath);
        }
      }

      expect(
        missingImports,
        isEmpty,
        reason: '''
Files in the voice playback allowlist must import VoiceConsentGate:
${missingImports.map((f) => '  - lib/$f').join('\n')}

This ensures the gate is actually being used, not just allowed.
''',
      );
    });

    test('Allowlisted files actually use VoiceConsentGate', () {
      final notUsingGate = <String>[];

      // Check audio allowlist files
      for (final relativePath in audioPlayAllowlist) {
        if (exemptFromGateUsage.contains(relativePath)) continue;

        final file = File('$libPath/$relativePath');
        if (!file.existsSync()) continue;

        final content = file.readAsStringSync();
        if (!content.contains('VoiceConsentGate.checkStoryNarration')) {
          notUsingGate.add('$relativePath (missing checkStoryNarration)');
        }
      }

      // Check TTS allowlist files
      for (final relativePath in ttsAllowlist) {
        if (exemptFromGateUsage.contains(relativePath)) continue;

        final file = File('$libPath/$relativePath');
        if (!file.existsSync()) continue;

        final content = file.readAsStringSync();
        if (!content.contains('VoiceConsentGate.checkPalGreetings')) {
          notUsingGate.add('$relativePath (missing checkPalGreetings)');
        }
      }

      expect(
        notUsingGate,
        isEmpty,
        reason: '''
Files in the voice playback allowlist must actually call VoiceConsentGate:
${notUsingGate.map((f) => '  - lib/$f').join('\n')}

Being in the allowlist means you MUST use the gate, not that you're exempt from it.
''',
      );
    });
  });
}
