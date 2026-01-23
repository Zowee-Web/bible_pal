import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Strict manifest integrity tests per Story Mode Contracts v2.
///
/// These tests FAIL FAST if the manifest is inconsistent:
/// 1. Traditional mode entries MUST have bibleSourceRef present and non-empty
/// 2. Creative mode entries MUST NOT have bibleSourceRef
/// 3. All textFilePath values must point to files that exist
/// 4. All audioFilePath values must point to existing files (if specified)
void main() {
  group('Manifest Integrity - Story Mode Contracts v2', () {
    late List<Map<String, dynamic>> parables;

    setUpAll(() async {
      final file = File('assets/stories/manifest.json');
      expect(file.existsSync(), isTrue,
          reason: 'manifest.json must exist at assets/stories/manifest.json');

      final content = await file.readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      expect(decoded.containsKey('parables'), isTrue,
          reason: 'manifest.json must contain a "parables" array');

      parables = (decoded['parables'] as List).cast<Map<String, dynamic>>();
    });

    test('Traditional mode entries MUST have bibleSourceRef', () {
      final violations = <String>[];

      for (final entry in parables) {
        final id = entry['storyId'] as String? ?? 'UNKNOWN';
        final mode = entry['storytellingMode'] as String?;
        final bibleRef = entry['bibleSourceRef'] as String?;

        if (mode == 'traditional') {
          if (bibleRef == null || bibleRef.trim().isEmpty) {
            violations.add(
                '$id: storytellingMode=traditional but bibleSourceRef is missing/empty');
          }
        }
      }

      expect(violations, isEmpty,
          reason:
              'Story Mode Contracts v2 requires bibleSourceRef for traditional mode.\n'
              'Violations found:\n${violations.join('\n')}');
    });

    test('Creative mode entries MUST NOT have bibleSourceRef', () {
      final violations = <String>[];

      for (final entry in parables) {
        final id = entry['storyId'] as String? ?? 'UNKNOWN';
        final mode = entry['storytellingMode'] as String?;
        final bibleRef = entry['bibleSourceRef'] as String?;

        if (mode == 'creative') {
          if (bibleRef != null && bibleRef.trim().isNotEmpty) {
            violations.add(
                '$id: storytellingMode=creative but has bibleSourceRef="$bibleRef"');
          }
        }
      }

      expect(violations, isEmpty,
          reason:
              'Story Mode Contracts v2 forbids bibleSourceRef for creative mode.\n'
              'Violations found:\n${violations.join('\n')}');
    });

    test('All textFilePath values must point to existing files', () {
      final violations = <String>[];

      for (final entry in parables) {
        final id = entry['storyId'] as String? ?? 'UNKNOWN';
        final textPath = entry['textFilePath'] as String?;

        if (textPath != null && textPath.isNotEmpty) {
          final file = File('assets/stories/$textPath');
          if (!file.existsSync()) {
            violations
                .add('$id: textFilePath="$textPath" but file does not exist');
          }
        }
      }

      expect(violations, isEmpty,
          reason: 'All textFilePath entries must point to existing files.\n'
              'Violations found:\n${violations.join('\n')}');
    });

    test('All audioFilePath values must point to existing files (if specified)',
        () {
      final violations = <String>[];

      for (final entry in parables) {
        final id = entry['storyId'] as String? ?? 'UNKNOWN';
        final audioPath = entry['audioFilePath'] as String?;

        if (audioPath != null && audioPath.isNotEmpty) {
          final file = File('assets/stories/$audioPath');
          if (!file.existsSync()) {
            violations
                .add('$id: audioFilePath="$audioPath" but file does not exist');
          }
        }
      }

      expect(violations, isEmpty,
          reason: 'All audioFilePath entries must point to existing files.\n'
              'Violations found:\n${violations.join('\n')}');
    });

    test('All entries must have required fields', () {
      final violations = <String>[];
      const requiredFields = ['storyId', 'title', 'mood', 'storytellingMode'];

      for (final entry in parables) {
        final id = entry['storyId'] as String? ?? 'UNKNOWN';

        for (final field in requiredFields) {
          final value = entry[field];
          if (value == null || (value is String && value.trim().isEmpty)) {
            violations.add('$id: missing required field "$field"');
          }
        }
      }

      expect(violations, isEmpty,
          reason: 'All manifest entries must have required fields.\n'
              'Violations found:\n${violations.join('\n')}');
    });

    test('storytellingMode must be either "traditional" or "creative"', () {
      final violations = <String>[];

      for (final entry in parables) {
        final id = entry['storyId'] as String? ?? 'UNKNOWN';
        final mode = entry['storytellingMode'] as String?;

        if (mode != null && mode != 'traditional' && mode != 'creative') {
          violations.add(
              '$id: invalid storytellingMode="$mode" (must be traditional or creative)');
        }
      }

      expect(violations, isEmpty,
          reason: 'storytellingMode must be "traditional" or "creative".\n'
              'Violations found:\n${violations.join('\n')}');
    });

    test('kidFriendly must be a boolean', () {
      final violations = <String>[];

      for (final entry in parables) {
        final id = entry['storyId'] as String? ?? 'UNKNOWN';
        final kidFriendly = entry['kidFriendly'];

        if (kidFriendly != null && kidFriendly is! bool) {
          violations.add('$id: kidFriendly="$kidFriendly" is not a boolean');
        }
      }

      expect(violations, isEmpty,
          reason: 'kidFriendly must be a boolean.\n'
              'Violations found:\n${violations.join('\n')}');
    });
  });
}
