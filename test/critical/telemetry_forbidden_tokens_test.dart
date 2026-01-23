// ignore_for_file: avoid_print
@Tags(['critical'])
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Telemetry Forbidden Tokens Invariant Enforcement Tests
///
/// These CRITICAL tests scan the entire codebase to ensure that minute-based
/// length fields are NEVER introduced in telemetry, allowlists, support bundles,
/// filter tracking, or analytics code.
///
/// See: docs/INVARIANTS.md - Telemetry: No minute-based length fields
///
/// FORBIDDEN TOKENS (must NEVER appear in telemetry context):
/// - length_min
/// - length_max
/// - duration_minutes
/// - story_length_minutes
/// - length_minutes
/// - minutes (as a telemetry field, not general usage)
/// - duration_min
///
/// Also forbidden (per Christian General Only invariant):
/// - tradition (as telemetry field)
/// - denomination (as telemetry field)
/// - faith_tradition (as telemetry field)
///
/// ALLOWED:
/// - This test file itself (exclusion)
/// - Comments explaining why these fields are banned
/// - docs/INVARIANTS.md documentation
/// - server/legacy/ folder (if exists and explicitly marked legacy)

void main() {
  group('CRITICAL: Telemetry Forbidden Tokens Scan', () {
    /// Minute-based length fields that must NEVER appear in telemetry code
    const forbiddenMinuteTokens = [
      'length_min',
      'length_max',
      'duration_minutes',
      'story_length_minutes',
      'length_minutes',
      'duration_min',
    ];

    /// Denomination fields that must NEVER appear in telemetry code
    /// (per Christian General Only invariant)
    const forbiddenDenominationTokens = [
      'tradition',
      'denomination',
      'faith_tradition',
    ];

    /// Files/patterns to exclude from scanning
    bool shouldExclude(String path) {
      // Exclude this test file
      if (path.contains('telemetry_forbidden_tokens_test.dart')) return true;
      // Exclude docs (allowed to document banned patterns)
      if (path.startsWith('docs/')) return true;
      // Exclude server/legacy if it exists
      if (path.contains('server/legacy/')) return true;
      // Exclude build artifacts
      if (path.contains('.dart_tool/')) return true;
      if (path.contains('build/')) return true;
      // Exclude test file that documents the constraint
      if (path.contains('support_bundle_test.dart')) return true;
      // Exclude any migration/legacy documentation
      if (path.contains('MIGRATION')) return true;
      return false;
    }

    /// Check if a line is a comment (allowed to document banned patterns)
    bool isCommentLine(String line) {
      final trimmed = line.trimLeft();
      return trimmed.startsWith('//') ||
          trimmed.startsWith('*') ||
          trimmed.startsWith('///') ||
          trimmed.startsWith('/*');
    }

    /// Telemetry-related file patterns where forbidden tokens matter most
    bool isTelemetryRelatedFile(String path) {
      final lowerPath = path.toLowerCase();
      return lowerPath.contains('telemetry') ||
          lowerPath.contains('analytics') ||
          lowerPath.contains('logger') ||
          lowerPath.contains('support_bundle') ||
          lowerPath.contains('breadcrumb') ||
          lowerPath.contains('allowlist') ||
          lowerPath.contains('allowedkeys') ||
          path.contains('app_logger.dart') ||
          path.contains('crash_reporter') ||
          path.contains('diagnostics');
    }

    test('CRITICAL: No minute-based length tokens in lib/ directory', () async {
      final violations = <String>[];
      final libDir = Directory('lib');

      if (!await libDir.exists()) {
        fail('lib/ directory not found');
      }

      await for (final entity in libDir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          final relativePath =
              entity.path.replaceFirst(Directory.current.path + '/', '');
          if (shouldExclude(relativePath)) continue;

          final content = await entity.readAsString();
          final lines = content.split('\n');

          for (int i = 0; i < lines.length; i++) {
            final line = lines[i];
            if (isCommentLine(line)) continue;

            for (final token in forbiddenMinuteTokens) {
              // Match token as a key in map/JSON or field name
              // Patterns: 'token': or "token": or .token or token: (as key)
              final patterns = [
                "'$token':",
                '"$token":',
                "'$token'",
                '"$token"',
                '.$token',
                'containsKey(\'$token\')',
                'containsKey("$token")',
                '[$token]',
              ];

              for (final pattern in patterns) {
                if (line.contains(pattern)) {
                  violations.add('${relativePath}:${i + 1}: Found "$token"\n'
                      '    Line: ${line.trim()}');
                }
              }
            }
          }
        }
      }

      if (violations.isNotEmpty) {
        print('');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print('🚨 TELEMETRY INVARIANT VIOLATION: Minute-Based Length Fields');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print('');
        print('Minute-based length fields are BANNED from telemetry.');
        print('Use StoryLengthBucket (short/full/long) via length_bucket only.');
        print('');
        print('Forbidden tokens: ${forbiddenMinuteTokens.join(", ")}');
        print('');
        print('Violations found:');
        for (final v in violations) {
          print('  ❌ $v');
        }
        print('');
        print('See: docs/INVARIANTS.md - Telemetry: No minute-based length fields');
        print('Test: test/critical/telemetry_forbidden_tokens_test.dart');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

        fail(
            'Telemetry Forbidden Tokens Invariant violated: ${violations.length} minute-based field(s) found in lib/');
      }
    });

    test('CRITICAL: No minute-based length tokens in telemetry allowlists',
        () async {
      final violations = <String>[];

      // Scan all Dart files for allowlist definitions containing forbidden tokens
      final libDir = Directory('lib');
      final testDir = Directory('test');

      for (final dir in [libDir, testDir]) {
        if (!await dir.exists()) continue;

        await for (final entity in dir.list(recursive: true)) {
          if (entity is File && entity.path.endsWith('.dart')) {
            final relativePath =
                entity.path.replaceFirst(Directory.current.path + '/', '');
            if (shouldExclude(relativePath)) continue;

            final content = await entity.readAsString();

            // Look for allowlist/allowed_keys definitions with forbidden tokens
            // Pattern: const Set<String> k...AllowedKeys = { ... 'length_min' ... }
            if (content.contains('AllowedKeys') ||
                content.contains('Allowlist') ||
                content.contains('allowlist')) {
              for (final token in forbiddenMinuteTokens) {
                if (content.contains("'$token'") ||
                    content.contains('"$token"')) {
                  // Find line number
                  final lines = content.split('\n');
                  for (int i = 0; i < lines.length; i++) {
                    final line = lines[i];
                    if (!isCommentLine(line) &&
                        (line.contains("'$token'") ||
                            line.contains('"$token"'))) {
                      violations.add(
                          '${relativePath}:${i + 1}: Forbidden token "$token" in allowlist\n'
                          '    Line: ${line.trim()}');
                    }
                  }
                }
              }
            }
          }
        }
      }

      if (violations.isNotEmpty) {
        print('');
        print('🚨 VIOLATION: Minute-based tokens found in telemetry allowlists');
        print('');
        for (final v in violations) {
          print('  ❌ $v');
        }
        print('');
        fail(
            'Telemetry allowlists contain ${violations.length} forbidden minute-based token(s)');
      }
    });

    test('CRITICAL: No denomination tokens in telemetry allowlists', () async {
      final violations = <String>[];

      final libDir = Directory('lib');
      final testDir = Directory('test');

      for (final dir in [libDir, testDir]) {
        if (!await dir.exists()) continue;

        await for (final entity in dir.list(recursive: true)) {
          if (entity is File && entity.path.endsWith('.dart')) {
            final relativePath =
                entity.path.replaceFirst(Directory.current.path + '/', '');
            if (shouldExclude(relativePath)) continue;

            final content = await entity.readAsString();

            // Look for allowlist definitions
            if (content.contains('AllowedKeys') ||
                content.contains('Allowlist') ||
                content.contains('allowlist')) {
              for (final token in forbiddenDenominationTokens) {
                // Only flag if it's a standalone token (not part of faith_tradition explanation)
                final patterns = [
                  "'$token'",
                  '"$token"',
                ];

                for (final pattern in patterns) {
                  if (content.contains(pattern)) {
                    final lines = content.split('\n');
                    for (int i = 0; i < lines.length; i++) {
                      final line = lines[i];
                      if (!isCommentLine(line) && line.contains(pattern)) {
                        // Skip if this is part of explaining a ban
                        if (line.contains('banned') ||
                            line.contains('BANNED') ||
                            line.contains('forbidden') ||
                            line.contains('FORBIDDEN') ||
                            line.contains('violates') ||
                            line.contains('violation')) {
                          continue;
                        }
                        violations.add(
                            '${relativePath}:${i + 1}: Forbidden token "$token" in allowlist\n'
                            '    Line: ${line.trim()}');
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      if (violations.isNotEmpty) {
        print('');
        print('🚨 VIOLATION: Denomination tokens found in telemetry allowlists');
        print('');
        for (final v in violations) {
          print('  ❌ $v');
        }
        print('');
        fail(
            'Telemetry allowlists contain ${violations.length} forbidden denomination token(s)');
      }
    });

    test(
        'CRITICAL: No backwards-compatibility comments for minute-based fields',
        () async {
      // This test catches misleading comments like "Keep length_min for backwards compatibility"
      final violations = <String>[];
      final forbiddenCommentPatterns = [
        'Keep length_min',
        'backwards compatibility.*length_min',
        'backward compatibility.*length_min',
        'legacy.*length_min',
        'deprecated.*length_min.*keep',
      ];

      final libDir = Directory('lib');

      if (!await libDir.exists()) {
        fail('lib/ directory not found');
      }

      await for (final entity in libDir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          final relativePath =
              entity.path.replaceFirst(Directory.current.path + '/', '');
          if (shouldExclude(relativePath)) continue;

          final content = await entity.readAsString();
          final lines = content.split('\n');

          for (int i = 0; i < lines.length; i++) {
            final line = lines[i].toLowerCase();
            for (final pattern in forbiddenCommentPatterns) {
              if (RegExp(pattern, caseSensitive: false).hasMatch(line)) {
                violations.add('${relativePath}:${i + 1}: Misleading comment\n'
                    '    Line: ${lines[i].trim()}');
              }
            }
          }
        }
      }

      if (violations.isNotEmpty) {
        print('');
        print('🚨 VIOLATION: Misleading backwards-compatibility comments found');
        print('');
        print('These comments suggest keeping minute-based fields, which is');
        print('prohibited. Remove the field AND the misleading comment.');
        print('');
        for (final v in violations) {
          print('  ❌ $v');
        }
        print('');
        fail(
            '${violations.length} misleading backwards-compatibility comment(s) found');
      }
    });

    test('CRITICAL: No minute tokens in support bundle serialization',
        () async {
      final violations = <String>[];

      // Check AppLogger and any support bundle related code
      final filesToCheck = [
        'lib/core/app_logger.dart',
        'lib/core/crash_reporter.dart',
        'lib/core/support_bundle.dart',
      ];

      for (final filePath in filesToCheck) {
        final file = File(filePath);
        if (!await file.exists()) continue;

        final content = await file.readAsString();
        final lines = content.split('\n');

        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (isCommentLine(line)) continue;

          for (final token in forbiddenMinuteTokens) {
            if (line.contains("'$token'") || line.contains('"$token"')) {
              violations.add('$filePath:${i + 1}: Found "$token"\n'
                  '    Line: ${line.trim()}');
            }
          }
        }
      }

      if (violations.isNotEmpty) {
        print('');
        print(
            '🚨 VIOLATION: Minute-based tokens in support bundle serialization');
        print('');
        for (final v in violations) {
          print('  ❌ $v');
        }
        print('');
        fail(
            '${violations.length} minute-based token(s) found in support bundle code');
      }
    });

    test('CRITICAL: No minute tokens in ParableService telemetry', () async {
      final parableServiceFile = File('lib/services/parable_service.dart');

      if (!await parableServiceFile.exists()) {
        // ParableService might not exist yet, skip
        return;
      }

      final content = await parableServiceFile.readAsString();
      final violations = <String>[];
      final lines = content.split('\n');

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (isCommentLine(line)) continue;

        // Check if this line is logging/telemetry related
        if (line.contains('logEvent') ||
            line.contains('logError') ||
            line.contains('breadcrumb') ||
            line.contains('analytics')) {
          for (final token in forbiddenMinuteTokens) {
            if (line.contains("'$token'") || line.contains('"$token"')) {
              violations.add(
                  'lib/services/parable_service.dart:${i + 1}: Found "$token" in telemetry\n'
                  '    Line: ${line.trim()}');
            }
          }
        }
      }

      if (violations.isNotEmpty) {
        print('');
        print('🚨 VIOLATION: Minute-based tokens in ParableService telemetry');
        print('');
        for (final v in violations) {
          print('  ❌ $v');
        }
        print('');
        fail(
            '${violations.length} minute-based token(s) found in ParableService telemetry');
      }
    });

    test('CRITICAL: Telemetry files use length_bucket not minutes', () async {
      // Verify that telemetry-related files that DO contain length tracking
      // use length_bucket (the canonical form)
      final libDir = Directory('lib');

      if (!await libDir.exists()) {
        fail('lib/ directory not found');
      }

      await for (final entity in libDir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          final relativePath =
              entity.path.replaceFirst(Directory.current.path + '/', '');

          if (!isTelemetryRelatedFile(relativePath)) continue;
          if (shouldExclude(relativePath)) continue;

          final content = await entity.readAsString();

          // If file contains length tracking, it should use length_bucket
          final hasLengthTracking = content.contains("'length") ||
              content.contains('"length') ||
              content.contains('length_');

          if (hasLengthTracking) {
            final lines = content.split('\n');
            var hasLengthBucket = false;
            var hasMinuteFields = false;

            for (final line in lines) {
              if (isCommentLine(line)) continue;
              if (line.contains('length_bucket')) hasLengthBucket = true;
              for (final token in forbiddenMinuteTokens) {
                if (line.contains("'$token'") || line.contains('"$token"')) {
                  hasMinuteFields = true;
                }
              }
            }

            if (hasMinuteFields && !hasLengthBucket) {
              fail(
                  '$relativePath has minute-based length fields but no length_bucket');
            }
          }
        }
      }
    });
  });

  group('Telemetry Forbidden Tokens - Example Failure Message', () {
    test('documents expected failure message format', () {
      // This test documents what the failure message looks like.
      // It always passes - it's here for documentation purposes only.
      //
      // If someone reintroduced length_min, they would see:
      //
      // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      // 🚨 TELEMETRY INVARIANT VIOLATION: Minute-Based Length Fields
      // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      //
      // Minute-based length fields are BANNED from telemetry.
      // Use StoryLengthBucket (short/full/long) via length_bucket only.
      //
      // Forbidden tokens: length_min, length_max, duration_minutes, ...
      //
      // Violations found:
      //   ❌ lib/services/parable_service.dart:142: Found "length_min"
      //       Line: 'length_min': bucket.minMinutes,
      //
      // See: docs/INVARIANTS.md - Telemetry: No minute-based length fields
      // Test: test/critical/telemetry_forbidden_tokens_test.dart
      // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

      expect(true, isTrue); // Always passes
    });
  });
}
