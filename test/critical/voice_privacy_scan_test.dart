import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CRITICAL: Repo-wide scan for voice transcript leakage (Invariant 17).
///
/// Scans all lib/ Dart files for patterns that could leak voice transcript
/// data through logging, storage, or debug output.
///
/// Modeled after the existing repo_wide_compliance_scan_test.dart pattern.
void main() {
  /// Collect all Dart files under lib/
  List<File> getAllDartFiles() {
    final libDir = Directory('lib');
    if (!libDir.existsSync()) return [];
    return libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
  }

  group('CRITICAL: Voice privacy repo-wide scan (Invariant 17)', () {
    late List<File> dartFiles;

    setUpAll(() {
      dartFiles = getAllDartFiles();
      // Sanity check: lib/ should have Dart files
      expect(dartFiles, isNotEmpty,
          reason: 'lib/ directory must contain Dart files');
    });

    test('CRITICAL: no logEvent calls with transcript-like keys in lib/', () {
      // Scan for patterns like:
      //   logEvent('...', {'transcript': ...})
      //   logEvent('...', {'recognized_text': ...})
      //   logEvent('...', {'speech_result': ...})
      //   logEvent('...', {'voice_text': ...})
      final transcriptPatterns = [
        RegExp(r"logEvent\s*\([^)]*'transcript'", multiLine: true),
        RegExp(r'logEvent\s*\([^)]*"transcript"', multiLine: true),
        RegExp(r"logEvent\s*\([^)]*'recognized_text'", multiLine: true),
        RegExp(r'logEvent\s*\([^)]*"recognized_text"', multiLine: true),
        RegExp(r"logEvent\s*\([^)]*'speech_result'", multiLine: true),
        RegExp(r'logEvent\s*\([^)]*"speech_result"', multiLine: true),
        RegExp(r"logEvent\s*\([^)]*'voice_text'", multiLine: true),
        RegExp(r'logEvent\s*\([^)]*"voice_text"', multiLine: true),
      ];

      final violations = <String>[];

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        for (final pattern in transcriptPatterns) {
          if (pattern.hasMatch(content)) {
            violations.add('${file.path}: matches ${pattern.pattern}');
          }
        }
      }

      expect(violations, isEmpty,
          reason: '🚨 PRIVACY VIOLATION 🚨\n'
              'Found logEvent calls with transcript-like keys:\n'
              '${violations.join('\n')}\n\n'
              'Voice transcripts must NEVER be logged (Invariant 17).');
    });

    test('CRITICAL: no SharedPreferences transcript storage in lib/', () {
      final storagePatterns = [
        RegExp(r'setString\s*\([^)]*transcript', caseSensitive: false),
        RegExp(r'setString\s*\([^)]*recognized_text', caseSensitive: false),
        RegExp(r'setString\s*\([^)]*speech_result', caseSensitive: false),
        RegExp(r'setString\s*\([^)]*voice_text', caseSensitive: false),
        RegExp(r"SharedPreferences[^;]*transcript", caseSensitive: false),
      ];

      final violations = <String>[];

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        for (final pattern in storagePatterns) {
          if (pattern.hasMatch(content)) {
            violations.add('${file.path}: matches ${pattern.pattern}');
          }
        }
      }

      expect(violations, isEmpty,
          reason: '🚨 PRIVACY VIOLATION 🚨\n'
              'Found SharedPreferences writes with transcript data:\n'
              '${violations.join('\n')}\n\n'
              'Voice transcripts must NEVER be persisted (Invariant 17).');
    });

    test('CRITICAL: no debugPrint with transcript variables in lib/', () {
      // Scan for debugPrint calls that reference transcript-related variable names.
      // This catches: debugPrint('...$transcript'), debugPrint(transcript), etc.
      final debugPatterns = [
        RegExp(r'debugPrint\s*\([^)]*\btranscript\b', caseSensitive: false),
        RegExp(r'debugPrint\s*\([^)]*\brecognizedText\b', caseSensitive: false),
        RegExp(r'debugPrint\s*\([^)]*\brecognized_text\b', caseSensitive: false),
        RegExp(r'debugPrint\s*\([^)]*\bspeechResult\b', caseSensitive: false),
        RegExp(r'debugPrint\s*\([^)]*\bvoiceText\b', caseSensitive: false),
      ];

      final violations = <String>[];

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        for (final pattern in debugPatterns) {
          if (pattern.hasMatch(content)) {
            violations.add('${file.path}: matches ${pattern.pattern}');
          }
        }
      }

      expect(violations, isEmpty,
          reason: '🚨 PRIVACY VIOLATION 🚨\n'
              'Found debugPrint calls with transcript data:\n'
              '${violations.join('\n')}\n\n'
              'Voice transcripts must NEVER appear in debugPrint (Invariant 17).');
    });
  });
}
