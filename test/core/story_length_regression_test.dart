import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests to prevent minute-based references from creeping back
/// into active code. The LOCKED SPEC uses bucket-based story lengths:
/// - short: 250-600 words
/// - full: 601-1200 words
/// - long: 1201-2000 words
///
/// Legacy minute references (5min, 10min, 15min, 20min) are allowed only in:
/// - server/legacy/ directory
/// - server/prompts/legacy/ directory
/// - docs/ directory (historical documentation)
/// - test/ directory (this test file and legacy compatibility tests)
void main() {
  group('Story Length Regression Tests', () {
    test('lib/ directory has no minute-era patterns in active code', () async {
      final violations = await _scanDirectoryForMinutePatterns('lib');

      if (violations.isNotEmpty) {
        final message = StringBuffer();
        message.writeln(
            'Found ${violations.length} minute-era pattern(s) in lib/:');
        message.writeln('');
        for (final v in violations) {
          message.writeln('  ${v.file}:${v.line}');
          message.writeln('    ${v.content.trim()}');
          message.writeln('');
        }
        message.writeln('ACTION REQUIRED:');
        message
            .writeln('  Replace minute references with bucket-based patterns.');
        message.writeln(
            '  LOCKED SPEC: short (250-600), full (601-1200), long (1201-2000)');
        fail(message.toString());
      }
    });

    test('active server scripts have no minute-era output filenames', () async {
      // Check active server scripts (not in legacy/)
      final activeScripts = [
        'server/generate_batch_parables.sh',
        'server/generate_adult_traditional_stories.sh',
        'server/tools/gen_one_story_api.sh',
        'server/tools/gen_one_audio.sh',
      ];

      final violations = <_Violation>[];

      for (final scriptPath in activeScripts) {
        final file = File(scriptPath);
        if (!await file.exists()) continue;

        final content = await file.readAsString();
        final lines = content.split('\n');

        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          // Look for output filename patterns with minutes
          if (_containsMinuteOutputPattern(line)) {
            violations.add(_Violation(
              file: scriptPath,
              line: i + 1,
              content: line,
            ));
          }
        }
      }

      if (violations.isNotEmpty) {
        final message = StringBuffer();
        message.writeln('Found minute-era output patterns in active scripts:');
        for (final v in violations) {
          message.writeln('  ${v.file}:${v.line}: ${v.content.trim()}');
        }
        message.writeln('');
        message
            .writeln('Expected patterns: *_short.txt, *_full.txt, *_long.txt');
        message.writeln('Not allowed: *_5min.txt, *_10min.txt, etc.');
        fail(message.toString());
      }
    });

    test('StoryLengthBucket has LOCKED SPEC word ranges', () {
      // Read the source file and verify LOCKED SPEC ranges
      final file = File('lib/core/story_length_bucket.dart');
      expect(file.existsSync(), isTrue,
          reason: 'story_length_bucket.dart must exist');

      final content = file.readAsStringSync();

      // Verify short bucket range
      expect(content, contains('(250, 600)'),
          reason: 'short bucket must have range (250, 600)');

      // Verify full bucket range
      expect(content, contains('(601, 1200)'),
          reason: 'full bucket must have range (601, 1200)');

      // Verify long bucket range
      expect(content, contains('(1201, 2000)'),
          reason: 'long bucket must have range (1201, 2000)');

      // Verify old ranges are NOT present
      expect(content, isNot(contains('(300, 700)')),
          reason: 'old short range (300, 700) must not be present');
      expect(content, isNot(contains('(900, 1400)')),
          reason: 'old full range (900, 1400) must not be present');
      expect(content, isNot(contains('(1700, 2600)')),
          reason: 'old long range (1700, 2600) must not be present');
    });

    test('kid_bedtime_validator uses LOCKED SPEC ranges', () {
      final file = File('lib/safety/kid_bedtime_validator.dart');
      expect(file.existsSync(), isTrue,
          reason: 'kid_bedtime_validator.dart must exist');

      final content = file.readAsStringSync();

      // Must have bucket-based validation (derives from StoryLengthBucket.wordCountRange)
      expect(content, contains('StoryLengthBucket'),
          reason: 'Must import StoryLengthBucket');
      expect(content, contains('getWordCountRangeForBucket'),
          reason: 'Must have getWordCountRangeForBucket function');
      expect(content, contains('bucket.wordCountRange'),
          reason: 'Must derive from bucket.wordCountRange (canonical source)');

      // Verify it uses lengthMinutesToBucket for legacy mappings
      expect(content, contains('lengthMinutesToBucket'),
          reason: 'Must use lengthMinutesToBucket for legacy minute mappings');
    });

    test('manifest.json entries have storyLength field', () async {
      final file = File('assets/stories/manifest.json');
      expect(await file.exists(), isTrue, reason: 'manifest.json must exist');

      final content = await file.readAsString();

      // Count entries and storyLength fields
      final entryMatches = RegExp(r'"storyId"\s*:').allMatches(content);
      final storyLengthMatches =
          RegExp(r'"storyLength"\s*:').allMatches(content);

      expect(storyLengthMatches.length, equals(entryMatches.length),
          reason: 'Every manifest entry must have a storyLength field');

      // Verify only valid bucket values
      final invalidBuckets =
          RegExp(r'"storyLength"\s*:\s*"(?!short|full|long)[^"]*"')
              .allMatches(content);
      expect(invalidBuckets.length, equals(0),
          reason: 'storyLength must be "short", "full", or "long"');
    });
  });
}

/// Patterns that indicate minute-era code in active lib/ files
final _minutePatterns = [
  // Output filename patterns
  RegExp(r'_5min\.(txt|mp3)'),
  RegExp(r'_10min\.(txt|mp3)'),
  RegExp(r'_15min\.(txt|mp3)'),
  RegExp(r'_20min\.(txt|mp3)'),
  // UI display patterns (should use bucket.displayLabel)
  RegExp(r'\$\{?\w*length\}?\s*(minutes?|min)'),
  RegExp(r'"\d+\s*(minutes?|min)"'),
  // Old word count ranges (superseded by LOCKED SPEC)
  RegExp(r'\(300,\s*700\)'),
  RegExp(r'\(900,\s*1400\)'),
  RegExp(r'\(1700,\s*2600\)'),
];

/// Patterns in script output filenames that indicate minute-era naming
bool _containsMinuteOutputPattern(String line) {
  // Skip comments
  if (line.trim().startsWith('#')) return false;

  // Look for output file assignments with minute patterns
  final outputPatterns = [
    RegExp(r'OUTPUT.*=.*_5min'),
    RegExp(r'OUTPUT.*=.*_10min'),
    RegExp(r'OUTPUT.*=.*_15min'),
    RegExp(r'OUTPUT.*=.*_20min'),
    RegExp(r'filename.*=.*_5min'),
    RegExp(r'filename.*=.*_10min'),
    RegExp(r'filename.*=.*_15min'),
    RegExp(r'filename.*=.*_20min'),
  ];

  return outputPatterns.any((p) => p.hasMatch(line));
}

Future<List<_Violation>> _scanDirectoryForMinutePatterns(String dirPath) async {
  final violations = <_Violation>[];
  final dir = Directory(dirPath);

  if (!await dir.exists()) return violations;

  await for (final entity in dir.list(recursive: true)) {
    if (entity is! File) continue;

    final path = entity.path;

    // Skip non-Dart files
    if (!path.endsWith('.dart')) continue;

    // Skip generated files
    if (path.contains('.g.dart') || path.contains('.freezed.dart')) continue;

    final content = await entity.readAsString();
    final lines = content.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Skip comments
      if (line.trim().startsWith('//')) continue;
      if (line.trim().startsWith('*')) continue;

      // Skip lines that are clearly about legacy compatibility
      if (line.contains('legacy') ||
          line.contains('Legacy') ||
          line.contains('LEGACY') ||
          line.contains('backwards compatibility')) {
        continue;
      }

      for (final pattern in _minutePatterns) {
        if (pattern.hasMatch(line)) {
          violations.add(_Violation(
            file: path,
            line: i + 1,
            content: line,
          ));
          break; // Only report once per line
        }
      }
    }
  }

  return violations;
}

class _Violation {
  final String file;
  final int line;
  final String content;

  _Violation({
    required this.file,
    required this.line,
    required this.content,
  });
}
