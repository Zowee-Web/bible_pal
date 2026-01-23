// CRITICAL NARRATOR VOICE VALIDATION TEST
// This test ensures that:
// 1. All narrator voice keys used in the codebase are in the voices.json allowlist
// 2. Manifest entries with audio files MUST have narratorVoiceKey set
// 3. Scripts only use VOICE_* keys from the allowlist
//
// See ADR-002 in docs/DECISIONS.md for rationale.
//
// DO NOT DISABLE OR WEAKEN THIS TEST.

@Tags(['critical'])
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Forbidden voice names that must NEVER appear
const List<String> forbiddenVoiceNames = ['Grace', 'Abilene', 'Grant'];

void main() {
  late Set<String> allowedVoiceKeys;
  late Map<String, dynamic> voicesJson;

  setUpAll(() async {
    // Load voices.json to get the allowlist
    final voicesFile = File('server/voices.json');
    expect(
      voicesFile.existsSync(),
      true,
      reason: 'server/voices.json must exist',
    );

    final content = await voicesFile.readAsString();
    voicesJson = jsonDecode(content) as Map<String, dynamic>;

    // Extract allowed voice keys
    final voices = voicesJson['voices'] as List<dynamic>;
    allowedVoiceKeys = voices
        .map((v) => (v as Map<String, dynamic>)['voiceKey'] as String)
        .toSet();
  });

  group('CRITICAL: Voice Key Allowlist Enforcement', () {
    test('CRITICAL: voices.json must have at least 1 voice in the pool',
        () async {
      expect(
        allowedVoiceKeys.isNotEmpty,
        true,
        reason: 'Voice pool cannot be empty',
      );
      expect(
        allowedVoiceKeys.length,
        greaterThanOrEqualTo(5),
        reason: 'Voice pool should have at least 5 voices for variety',
      );
    });

    test('CRITICAL: All voice keys must follow VOICE_ naming convention',
        () async {
      for (final key in allowedVoiceKeys) {
        expect(
          key.startsWith('VOICE_'),
          true,
          reason: 'Voice key "$key" must start with VOICE_',
        );
        expect(
          key.toUpperCase(),
          key,
          reason: 'Voice key "$key" must be uppercase',
        );
      }
    });

    test('CRITICAL: Kid-compatible voices must exist in pool', () async {
      final voices = voicesJson['voices'] as List<dynamic>;
      final kidVoices = voices.where((v) {
        final audience =
            (v as Map<String, dynamic>)['audience'] as List<dynamic>;
        return audience.contains('kid');
      }).toList();

      expect(
        kidVoices.isNotEmpty,
        true,
        reason: 'At least one kid-compatible voice must exist',
      );
      expect(
        kidVoices.length,
        greaterThanOrEqualTo(3),
        reason: 'At least 3 kid-compatible voices should exist for variety',
      );
    });

    test('CRITICAL: Fallback voice must be in the allowlist', () async {
      final algorithm =
          voicesJson['selectionAlgorithm'] as Map<String, dynamic>?;
      expect(algorithm, isNotNull, reason: 'selectionAlgorithm must exist');

      final fallback = algorithm!['fallback'] as String?;
      expect(fallback, isNotNull, reason: 'Fallback voice must be specified');

      expect(
        allowedVoiceKeys.contains(fallback),
        true,
        reason: 'Fallback voice "$fallback" must be in the voice pool',
      );
    });

    test('CRITICAL: Server scripts using voice_selector must exist', () async {
      final voiceSelectorFile = File('server/voice_selector.sh');
      expect(
        voiceSelectorFile.existsSync(),
        true,
        reason: 'server/voice_selector.sh must exist for voice selection',
      );
    });
  });

  group('CRITICAL: Script VOICE_* Key Allowlist Scan', () {
    test(
        'CRITICAL: All VOICE_* keys in server scripts must be in voices.json allowlist',
        () async {
      // Regex to find VOICE_[A-Z0-9_]+ tokens
      final voiceKeyPattern = RegExp(r'VOICE_[A-Z0-9_]+');

      // Files to scan
      final scanPaths = <String>[
        'server',
        'server/tools',
      ];

      // Files to exclude (documentation, tests, voices.json itself)
      final excludePatterns = [
        'voices.json', // The source of truth itself
        '_test.dart', // Test files
        'DECISIONS.md', // Documentation
        '.DISABLED', // Disabled scripts
        '.env', // Config files define voices, not use them
        'voice_selector.sh', // The selector itself uses variables like VOICE_SELECTOR_DIR
      ];

      // Legacy scripts not yet migrated to voice_selector.sh
      // TODO: Migrate these scripts and remove from exclusion list
      final legacyScripts = <String>{
        'generate_one_kid_audio.sh', // Uses hardcoded VOICE_ARABELLA
        'generate_audio_from_text.sh', // Uses env var VOICE_ID
        'generate_kidfriendly_batch.sh', // Uses env var VOICE_ID
        'generate_cinematic_story.sh', // Uses env var VOICE_ID
        'generate_traditional_story.sh', // Uses env var VOICE_ID
        'generate_single_kidfriendly.sh', // Uses env var VOICE_ID
        'generate_reflection_audio.sh', // Uses local VOICE_KEY variable
        'gen_one_audio.sh', // Uses VOICE_VAR/VOICE_ID pattern
      };

      // Variable name patterns that are NOT actual voice keys
      // These are generic variable names used in scripts, not voice references
      final variableNamePatterns = <String>{
        'VOICE_ID', // Generic variable for ElevenLabs ID
        'VOICE_KEY', // Generic variable for voice key
        'VOICE_VAR', // Generic variable name
        'VOICE_SELECTOR_DIR', // Directory path variable
        'VOICE_NAME', // Generic variable for voice name
        'VOICE_FILE', // Generic variable for voice file
        'VOICE_PATH', // Generic variable for voice path
        'VOICE_COUNT', // Generic variable for count
        'VOICE_INDEX', // Generic variable for index
        'VOICE_LIST', // Generic variable for list
        'VOICE_POOL', // Generic variable for pool
        'VOICE_SELECTED', // Generic variable for selected voice
        'VOICE_DEFAULT', // Generic variable for default
        'VOICE_FALLBACK', // Generic variable for fallback
      };

      final violations = <String, Set<String>>{};
      final forbiddenViolations = <String, Set<String>>{};

      for (final scanPath in scanPaths) {
        final dir = Directory(scanPath);
        if (!dir.existsSync()) continue;

        await for (final entity in dir.list(recursive: false)) {
          if (entity is! File) continue;

          final path = entity.path;

          // Only scan .sh and .env files
          if (!path.endsWith('.sh') && !path.contains('.env')) continue;

          // Skip excluded files
          if (excludePatterns.any((p) => path.contains(p))) continue;

          // Skip legacy scripts (not yet migrated to voice_selector.sh)
          final filename = path.split('/').last;
          if (legacyScripts.contains(filename)) continue;

          final content = await entity.readAsString();
          final lines = content.split('\n');

          for (int i = 0; i < lines.length; i++) {
            final line = lines[i];

            // Skip comments
            if (line.trim().startsWith('#')) continue;

            // Find all VOICE_* matches
            final matches = voiceKeyPattern.allMatches(line);

            for (final match in matches) {
              final voiceKey = match.group(0)!;

              // Check if it's a forbidden voice
              for (final forbidden in forbiddenVoiceNames) {
                if (voiceKey.toUpperCase().contains(forbidden.toUpperCase())) {
                  forbiddenViolations
                      .putIfAbsent(path, () => <String>{})
                      .add('Line ${i + 1}: $voiceKey (FORBIDDEN: $forbidden)');
                }
              }

              // Skip generic variable names (not actual voice keys)
              if (variableNamePatterns.contains(voiceKey)) {
                continue;
              }

              // Check if it's in the allowlist
              if (!allowedVoiceKeys.contains(voiceKey)) {
                // Special case: allow fallback patterns like VOICE_JAMES_HUSKY
                // which may appear as default values
                final fallback = (voicesJson['selectionAlgorithm']
                    as Map<String, dynamic>?)?['fallback'] as String?;
                if (fallback != null && voiceKey == fallback) {
                  continue; // Fallback is always allowed
                }

                violations
                    .putIfAbsent(path, () => <String>{})
                    .add('Line ${i + 1}: $voiceKey');
              }
            }
          }
        }
      }

      // First check forbidden voices - this is a hard failure
      expect(
        forbiddenViolations,
        isEmpty,
        reason: '🚨 FORBIDDEN VOICE KEYS FOUND IN SCRIPTS 🚨\n'
            'The following scripts contain forbidden voice references:\n'
            '${forbiddenViolations.entries.map((e) => '\n${e.key}:\n${e.value.map((v) => '  $v').join('\n')}').join('\n')}\n\n'
            'These voices are banned per ADR-002. Remove them immediately.',
      );

      // Then check allowlist violations
      expect(
        violations,
        isEmpty,
        reason: '🚨 VOICE KEY ALLOWLIST VIOLATION 🚨\n'
            'The following scripts use VOICE_* keys not in voices.json:\n'
            '${violations.entries.map((e) => '\n${e.key}:\n${e.value.map((v) => '  $v').join('\n')}').join('\n')}\n\n'
            'Allowed voice keys:\n${allowedVoiceKeys.map((k) => '  $k').join('\n')}\n\n'
            'Either add the voice to voices.json or use an existing voice key.',
      );
    });

    test('CRITICAL: .env files must not contain forbidden voice keys',
        () async {
      final envFiles = [
        File('.env'),
        File('server/.env'),
      ];

      final forbiddenPattern =
          RegExp(r'VOICE_(GRACE|ABILENE|GRANT)', caseSensitive: false);
      final violations = <String>[];

      for (final envFile in envFiles) {
        if (!envFile.existsSync()) continue;

        final content = await envFile.readAsString();
        final lines = content.split('\n');

        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];

          // Skip comments
          if (line.trim().startsWith('#')) continue;

          if (forbiddenPattern.hasMatch(line)) {
            violations.add('${envFile.path}:${i + 1}: $line');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: '🚨 FORBIDDEN VOICE KEYS IN .env FILES 🚨\n'
            '${violations.join('\n')}\n\n'
            'Grace, Abilene, and Grant are forbidden voices per ADR-002.',
      );
    });
  });

  group('CRITICAL: Manifest Narrator Voice Requirements', () {
    test(
        'CRITICAL: Manifest entries with audio MUST have narratorVoiceKey (STRICT)',
        () async {
      final manifestFile = File('assets/stories/manifest.json');
      if (!manifestFile.existsSync()) {
        fail('assets/stories/manifest.json must exist');
      }

      final content = await manifestFile.readAsString();
      final manifest = jsonDecode(content) as Map<String, dynamic>;
      final parables = manifest['parables'] as List<dynamic>? ?? [];

      // Track entries that need narratorVoiceKey but don't have it
      final missingVoiceKey = <String>[];

      for (final parable in parables) {
        final entry = parable as Map<String, dynamic>;
        final storyId = entry['storyId'] as String;
        final audioFilePath = entry['audioFilePath'] as String?;
        final narratorVoiceKey = entry['narratorVoiceKey'] as String?;

        // If audio exists, narratorVoiceKey MUST exist
        if (audioFilePath != null && audioFilePath.isNotEmpty) {
          if (narratorVoiceKey == null || narratorVoiceKey.isEmpty) {
            missingVoiceKey.add(storyId);
          }
        }
      }

      // STRICT: This must now fail if any are missing
      expect(
        missingVoiceKey,
        isEmpty,
        reason: '🚨 MISSING narratorVoiceKey VIOLATION 🚨\n'
            '${missingVoiceKey.length} manifest entries have audio but no narratorVoiceKey:\n'
            '${missingVoiceKey.take(10).map((id) => '  - $id').join('\n')}'
            '${missingVoiceKey.length > 10 ? '\n  ... and ${missingVoiceKey.length - 10} more' : ''}\n\n'
            'Run server/tools/backfill_narrator_voice_key.sh to fix this.',
      );
    });

    test(
        'CRITICAL: narratorVoiceKey in manifest must be in voices.json allowlist',
        () async {
      final manifestFile = File('assets/stories/manifest.json');
      if (!manifestFile.existsSync()) {
        return;
      }

      final content = await manifestFile.readAsString();
      final manifest = jsonDecode(content) as Map<String, dynamic>;
      final parables = manifest['parables'] as List<dynamic>? ?? [];

      final invalidVoiceKeys = <String, String>{};

      for (final parable in parables) {
        final entry = parable as Map<String, dynamic>;
        final storyId = entry['storyId'] as String;
        final narratorVoiceKey = entry['narratorVoiceKey'] as String?;

        if (narratorVoiceKey != null && narratorVoiceKey.isNotEmpty) {
          if (!allowedVoiceKeys.contains(narratorVoiceKey)) {
            invalidVoiceKeys[storyId] = narratorVoiceKey;
          }
        }
      }

      expect(
        invalidVoiceKeys,
        isEmpty,
        reason: '🚨 INVALID VOICE KEY VIOLATION 🚨\n'
            'The following manifest entries have narratorVoiceKey not in voices.json:\n'
            '${invalidVoiceKeys.entries.map((e) => '  ${e.key}: ${e.value}').join('\n')}\n\n'
            'Allowed voice keys: ${allowedVoiceKeys.join(', ')}',
      );
    });

    test('CRITICAL: Parable model must support narratorVoiceKey field',
        () async {
      final parableFile = File('lib/models/parable.dart');
      expect(parableFile.existsSync(), true);

      final content = await parableFile.readAsString();

      // Check for field declaration
      expect(
        content.contains('narratorVoiceKey'),
        true,
        reason: 'Parable model must have narratorVoiceKey field',
      );

      // Check for fromJson support
      expect(
        content.contains("json['narratorVoiceKey']"),
        true,
        reason: 'Parable.fromJson must handle narratorVoiceKey',
      );

      // Check for toJson support
      expect(
        content.contains("'narratorVoiceKey': narratorVoiceKey"),
        true,
        reason: 'Parable.toJson must include narratorVoiceKey',
      );

      // Check for copyWith support
      expect(
        content.contains('String? narratorVoiceKey'),
        true,
        reason: 'Parable.copyWith must support narratorVoiceKey',
      );
    });
  });
}
