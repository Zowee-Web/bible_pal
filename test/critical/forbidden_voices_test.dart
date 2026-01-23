// CRITICAL FORBIDDEN VOICE TEST
// This test ensures that banned ElevenLabs voices (Grace, Abilene, Grant)
// are never used in Bible PAL.
//
// See ADR-002 in docs/DECISIONS.md for rationale.
//
// DO NOT DISABLE OR WEAKEN THIS TEST.

@Tags(['critical'])
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Forbidden voice names that must NEVER appear in Bible PAL.
/// These are banned per project policy (ADR-002).
const List<String> forbiddenVoices = ['Grace', 'Abilene', 'Grant'];

/// Patterns to detect forbidden voices in code/config files.
/// Case-insensitive matching for voice references.
final List<RegExp> forbiddenPatterns = [
  // Direct voice name references (case insensitive)
  RegExp(r'VOICE_GRACE', caseSensitive: false),
  RegExp(r'VOICE_ABILENE', caseSensitive: false),
  RegExp(r'VOICE_GRANT', caseSensitive: false),
  // Display names in JSON/config
  RegExp(r'"Grace"', caseSensitive: true), // Exact match for voice name
  RegExp(r'"Abilene"', caseSensitive: true),
  RegExp(r'"Grant"', caseSensitive: true),
  // Voice key patterns
  RegExp(r'voiceKey.*[Gg]race', caseSensitive: false),
  RegExp(r'voiceKey.*[Aa]bilene', caseSensitive: false),
  RegExp(r'voiceKey.*[Gg]rant', caseSensitive: false),
];

/// File extensions to scan for forbidden voice references.
const List<String> scanExtensions = [
  '.dart',
  '.sh',
  '.json',
  '.yaml',
  '.yml',
  '.env',
];

/// Directories to exclude from scanning.
const List<String> excludeDirs = [
  '.git',
  '.dart_tool',
  'build',
  '.idea',
  '.vscode',
  // Documentation files are allowed to reference forbidden voices
  // (for explaining WHY they're forbidden)
];

/// Files that are allowed to mention forbidden voices for documentation purposes.
const List<String> allowedDocumentationFiles = [
  'DECISIONS.md',
  'forbidden_voices_test.dart', // This test file
  'voices.json', // Contains _forbiddenVoices section for documentation
];

void main() {
  group('CRITICAL: Forbidden Voices Enforcement', () {
    test(
        'CRITICAL: voices.json must NOT contain forbidden voices in the active pool',
        () async {
      final voicesFile = File('server/voices.json');
      expect(
        voicesFile.existsSync(),
        true,
        reason: 'server/voices.json must exist',
      );

      final content = await voicesFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      // Check that _forbiddenVoices section exists
      expect(
        json.containsKey('_forbiddenVoices'),
        true,
        reason:
            'voices.json must contain _forbiddenVoices documentation section',
      );

      // Check that no forbidden voice is in the active voices array
      final voices = json['voices'] as List<dynamic>;
      for (final voice in voices) {
        final voiceMap = voice as Map<String, dynamic>;
        final voiceKey = voiceMap['voiceKey'] as String;
        final displayName = voiceMap['displayName'] as String;

        for (final forbidden in forbiddenVoices) {
          expect(
            voiceKey.toLowerCase().contains(forbidden.toLowerCase()),
            false,
            reason: '🚨 FORBIDDEN VOICE VIOLATION 🚨\n'
                'Voice key "$voiceKey" contains forbidden name "$forbidden".\n'
                'This voice must be removed from the voice pool.\n'
                'See ADR-002 in docs/DECISIONS.md.',
          );

          expect(
            displayName.toLowerCase().contains(forbidden.toLowerCase()),
            false,
            reason: '🚨 FORBIDDEN VOICE VIOLATION 🚨\n'
                'Display name "$displayName" contains forbidden name "$forbidden".\n'
                'This voice must be removed from the voice pool.\n'
                'See ADR-002 in docs/DECISIONS.md.',
          );
        }
      }
    });

    test('CRITICAL: .env must NOT define forbidden voice variables', () async {
      final envFile = File('.env');
      if (!envFile.existsSync()) {
        // .env may not exist in CI, skip this test
        return;
      }

      final content = await envFile.readAsString();
      final lines = content.split('\n');

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        final lineNum = i + 1;

        // Skip comments (lines starting with #)
        if (line.trim().startsWith('#')) continue;
        // Skip empty lines
        if (line.trim().isEmpty) continue;

        for (final forbidden in forbiddenVoices) {
          final pattern = RegExp('VOICE_$forbidden', caseSensitive: false);
          expect(
            pattern.hasMatch(line),
            false,
            reason: '🚨 FORBIDDEN VOICE VIOLATION 🚨\n'
                '.env line $lineNum contains forbidden voice "$forbidden":\n'
                '  $line\n'
                'Remove this line. See ADR-002 in docs/DECISIONS.md.',
          );
        }
      }
    });

    test('CRITICAL: Server scripts must NOT use forbidden voices as defaults',
        () async {
      final serverDir = Directory('server');
      if (!serverDir.existsSync()) {
        fail('server/ directory must exist');
      }

      final violations = <String>[];

      await for (final entity in serverDir.list(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.sh')) continue;

        final content = await entity.readAsString();
        final lines = content.split('\n');

        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          final lineNum = i + 1;

          // Look for default voice assignments using forbidden voices
          for (final forbidden in forbiddenVoices) {
            // Pattern: default value like ${VAR:-VOICE_GRACE}
            final defaultPattern =
                RegExp(':-VOICE_$forbidden', caseSensitive: false);
            // Pattern: direct assignment like VOICE=VOICE_GRACE
            final assignPattern =
                RegExp('=VOICE_$forbidden', caseSensitive: false);

            if (defaultPattern.hasMatch(line) || assignPattern.hasMatch(line)) {
              violations.add(
                  '${entity.path}:$lineNum - Uses forbidden voice "$forbidden":\n  $line');
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: '🚨 FORBIDDEN VOICE VIOLATIONS IN SERVER SCRIPTS 🚨\n'
            '${violations.join('\n\n')}\n\n'
            'Replace with allowed voices (e.g., VOICE_JAMES_HUSKY).\n'
            'See ADR-002 in docs/DECISIONS.md.',
      );
    });

    test(
        'CRITICAL: Fallback voice in voices.json must NOT be a forbidden voice',
        () async {
      final voicesFile = File('server/voices.json');
      expect(voicesFile.existsSync(), true);

      final content = await voicesFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      final algorithm = json['selectionAlgorithm'] as Map<String, dynamic>?;
      if (algorithm == null) return;

      final fallback = algorithm['fallback'] as String?;
      if (fallback == null) return;

      for (final forbidden in forbiddenVoices) {
        expect(
          fallback.toLowerCase().contains(forbidden.toLowerCase()),
          false,
          reason: '🚨 FORBIDDEN VOICE VIOLATION 🚨\n'
              'Fallback voice "$fallback" contains forbidden name "$forbidden".\n'
              'Use an allowed voice like VOICE_JAMES_HUSKY.\n'
              'See ADR-002 in docs/DECISIONS.md.',
        );
      }
    });

    test('CRITICAL: _forbiddenVoices section lists all banned voices',
        () async {
      final voicesFile = File('server/voices.json');
      expect(voicesFile.existsSync(), true);

      final content = await voicesFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      final forbiddenSection =
          json['_forbiddenVoices'] as Map<String, dynamic>?;
      expect(
        forbiddenSection,
        isNotNull,
        reason: 'voices.json must have _forbiddenVoices section',
      );

      final listedForbidden = (forbiddenSection!['voices'] as List<dynamic>)
          .map((e) => e.toString().toLowerCase())
          .toSet();

      for (final voice in forbiddenVoices) {
        expect(
          listedForbidden.contains(voice.toLowerCase()),
          true,
          reason: '_forbiddenVoices section must list "$voice" as forbidden',
        );
      }
    });
  });
}
