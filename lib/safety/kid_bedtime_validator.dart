/// Kid Safe Validator
///
/// Validates generated story content against the Kid Story Contract.
/// Used for post-generation validation and regeneration decisions.
///
/// See: docs/prompts/kid_bedtime_contract.txt
/// See: server/kid_bedtime_forbidden.txt
library;

import 'dart:io';
import '../core/story_length_bucket.dart';

/// Maximum regeneration attempts before giving up
const int kMaxRegenAttempts = 3;

/// Maximum average words per sentence for readability
const int kMaxAvgWordsPerSentence = 15;

/// LEGACY: Special 3-minute kid story word count range
/// This is a KID-SPECIFIC range not in standard StoryLengthBucket enum
/// (kept for backwards compatibility with 3-minute kid stories)
const (int, int) k3MinuteKidStoryRange = (270, 400);

/// Get word count range for a storyLength bucket (PRIMARY method)
/// Derives from StoryLengthBucket.wordCountRange (canonical source of truth)
(int, int) getWordCountRangeForBucket(StoryLengthBucket bucket) {
  return bucket.wordCountRange;
}

/// LEGACY: Get word count range for a given target length in minutes
/// Maps minute-based lengths to bucket ranges via lengthMinutesToBucket()
/// Returns null only for truly unknown minute values
(int, int)? getWordCountRange(int lengthMinutes) {
  // Special case: 3-minute kid story (not in standard buckets)
  if (lengthMinutes == 3) {
    return k3MinuteKidStoryRange;
  }
  // Map minutes to bucket and get range from canonical source
  final bucket = lengthMinutesToBucket(lengthMinutes);
  return bucket.wordCountRange;
}

/// Result of validating a story against the Kid Story Contract
class KidBedtimeValidationResult {
  final bool isValid;
  final List<String> forbiddenWordsFound;
  final List<String> structureViolations;
  final List<String> otherViolations;
  final double avgWordsPerSentence;

  const KidBedtimeValidationResult({
    required this.isValid,
    this.forbiddenWordsFound = const [],
    this.structureViolations = const [],
    this.otherViolations = const [],
    this.avgWordsPerSentence = 0,
  });

  /// All violations combined for logging/repair instructions
  List<String> get allViolations => [
        ...forbiddenWordsFound.map((w) => 'Forbidden word: "$w"'),
        ...structureViolations,
        ...otherViolations,
      ];

  /// Generate repair instruction for Gemma regeneration
  String get repairInstruction {
    if (isValid) return '';

    final buffer = StringBuffer();
    buffer.writeln('YOUR PREVIOUS STORY FAILED VALIDATION. FIX THESE ISSUES:');
    buffer.writeln();

    if (forbiddenWordsFound.isNotEmpty) {
      buffer.writeln('FORBIDDEN WORDS DETECTED (remove or replace these):');
      for (final word in forbiddenWordsFound.take(10)) {
        buffer.writeln('  - "$word"');
      }
      if (forbiddenWordsFound.length > 10) {
        buffer.writeln('  - ...and ${forbiddenWordsFound.length - 10} more');
      }
      buffer.writeln();
    }

    if (structureViolations.isNotEmpty) {
      buffer.writeln('STRUCTURE PROBLEMS:');
      for (final v in structureViolations) {
        buffer.writeln('  - $v');
      }
      buffer.writeln();
    }

    if (otherViolations.isNotEmpty) {
      buffer.writeln('OTHER ISSUES:');
      for (final v in otherViolations) {
        buffer.writeln('  - $v');
      }
      buffer.writeln();
    }

    buffer.writeln('REWRITE THE STORY TO FIX ALL ISSUES ABOVE.');
    buffer.writeln('Remember: This is for children ages 5-9.');
    buffer.writeln('It must be calm, peaceful, and gentle.');

    return buffer.toString();
  }

  @override
  String toString() {
    if (isValid) return 'KidBedtimeValidationResult: VALID';
    return 'KidBedtimeValidationResult: INVALID\n'
        '  Forbidden words: ${forbiddenWordsFound.length}\n'
        '  Structure violations: ${structureViolations.length}\n'
        '  Other violations: ${otherViolations.length}\n'
        '  Avg words/sentence: ${avgWordsPerSentence.toStringAsFixed(1)}';
  }
}

/// Validator for Kid Safe stories
class KidBedtimeValidator {
  final List<String> _forbiddenPatterns;
  final List<RegExp> _forbiddenRegexes;

  /// Target storyLength bucket (PRIMARY - used for word count validation)
  StoryLengthBucket? targetLengthBucket;

  /// LEGACY: Target length in minutes (used for word count validation)
  /// If both targetLengthBucket and targetLengthMinutes are set, bucket takes priority
  /// If null, only enforces minimum 200 words
  int? targetLengthMinutes;

  KidBedtimeValidator._(this._forbiddenPatterns, this._forbiddenRegexes);

  /// Create validator with forbidden patterns from the source-of-truth file
  static Future<KidBedtimeValidator> create({String? forbiddenFilePath}) async {
    final patterns = <String>[];

    // Try to load from file
    final path = forbiddenFilePath ?? _findForbiddenFile();
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        final lines = await file.readAsLines();
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
          patterns.add(trimmed.toLowerCase());
        }
      }
    }

    // Fallback to hardcoded critical patterns if file not found
    if (patterns.isEmpty) {
      patterns.addAll(_fallbackForbiddenPatterns);
    }

    // Compile regexes for word boundary matching
    final regexes = patterns.map((p) {
      // Escape special regex chars, then wrap with word boundaries
      final escaped = RegExp.escape(p);
      return RegExp(r'\b' + escaped + r'\b', caseSensitive: false);
    }).toList();

    return KidBedtimeValidator._(patterns, regexes);
  }

  /// Create validator synchronously with provided patterns (for testing)
  factory KidBedtimeValidator.withPatterns(List<String> patterns) {
    final lowerPatterns = patterns.map((p) => p.toLowerCase()).toList();
    final regexes = lowerPatterns.map((p) {
      final escaped = RegExp.escape(p);
      return RegExp(r'\b' + escaped + r'\b', caseSensitive: false);
    }).toList();
    return KidBedtimeValidator._(lowerPatterns, regexes);
  }

  /// Validate story text against the Kid Story Contract
  KidBedtimeValidationResult validate(String storyText) {
    final forbiddenFound = <String>[];
    final structureViolations = <String>[];
    final otherViolations = <String>[];

    // Check forbidden words
    for (var i = 0; i < _forbiddenRegexes.length; i++) {
      if (_forbiddenRegexes[i].hasMatch(storyText)) {
        forbiddenFound.add(_forbiddenPatterns[i]);
      }
    }

    // Check structure (5 parts)
    final structureResult = _validateStructure(storyText);
    structureViolations.addAll(structureResult);

    // Check sentence length
    final avgWords = _calculateAvgWordsPerSentence(storyText);
    if (avgWords > kMaxAvgWordsPerSentence) {
      otherViolations.add(
          'Sentences too long (avg ${avgWords.toStringAsFixed(1)} words, max $kMaxAvgWordsPerSentence)');
    }

    final isValid = forbiddenFound.isEmpty &&
        structureViolations.isEmpty &&
        otherViolations.isEmpty;

    return KidBedtimeValidationResult(
      isValid: isValid,
      forbiddenWordsFound: forbiddenFound,
      structureViolations: structureViolations,
      otherViolations: otherViolations,
      avgWordsPerSentence: avgWords,
    );
  }

  /// Validate the story has appropriate structure (5 distinct sections)
  List<String> _validateStructure(String text) {
    final violations = <String>[];

    // Count paragraphs (sections separated by double newlines or significant breaks)
    final paragraphs = text
        .split(RegExp(r'\n\s*\n'))
        .where((p) => p.trim().length > 50)
        .toList();

    if (paragraphs.length < 3) {
      violations.add(
          'Story needs at least 3 distinct sections (found ${paragraphs.length})');
    }

    // Check word count based on target length (bucket takes priority)
    final wordCount = text.split(RegExp(r'\s+')).length;

    if (targetLengthBucket != null) {
      // PRIMARY: Use bucket-based validation (LOCKED SPEC)
      final (minWords, maxWords) =
          getWordCountRangeForBucket(targetLengthBucket!);
      final bucketLabel = targetLengthBucket!.displayLabel;
      if (wordCount < minWords) {
        violations.add(
            'Story too short for $bucketLabel ($wordCount words, need $minWords-$maxWords). '
            'Expand sections 2-4 with more gentle, calm details.');
      } else if (wordCount > maxWords) {
        violations.add(
            'Story too long for $bucketLabel ($wordCount words, max $maxWords)');
      }
    } else if (targetLengthMinutes != null) {
      // LEGACY: Fallback to minute-based validation
      final range = getWordCountRange(targetLengthMinutes!);
      // getWordCountRange always returns a value now (maps to bucket)
      final (minWords, maxWords) = range!;
      if (wordCount < minWords) {
        violations.add(
            'Story too short ($wordCount words, need $minWords-$maxWords). '
            'Expand sections 2-4 with more gentle, calm details.');
      } else if (wordCount > maxWords) {
        violations.add('Story too long ($wordCount words, max $maxWords)');
      }
    } else {
      // No target length specified, use short bucket minimum (canonical source)
      final minWords = StoryLengthBucket.short.wordCountRange.$1;
      if (wordCount < minWords) {
        violations.add('Story too short ($wordCount words, minimum $minWords)');
      }
    }

    return violations;
  }

  /// Calculate average words per sentence
  double _calculateAvgWordsPerSentence(String text) {
    // Split by sentence-ending punctuation
    final sentences = text
        .split(RegExp(r'[.!?]+'))
        .where((s) => s.trim().isNotEmpty)
        .toList();

    if (sentences.isEmpty) return 0;

    var totalWords = 0;
    for (final sentence in sentences) {
      totalWords += sentence.trim().split(RegExp(r'\s+')).length;
    }

    return totalWords / sentences.length;
  }

  /// Find the forbidden file in common locations
  static String? _findForbiddenFile() {
    final candidates = [
      'server/kid_bedtime_forbidden.txt',
      '../server/kid_bedtime_forbidden.txt',
      '/Volumes/T9-AI/bible_pal/server/kid_bedtime_forbidden.txt',
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) {
        return path;
      }
    }
    return null;
  }

  /// Fallback forbidden patterns if file can't be loaded
  static const _fallbackForbiddenPatterns = [
    // Violence & peril
    'roar', 'roared', 'roaring', 'jaws', 'teeth', 'claws', 'fangs',
    'devour', 'devoured', 'attack', 'attacked', 'kill', 'killed',
    'slay', 'slew', 'slain', 'destroy', 'destroyed', 'battle', 'war',
    'fight', 'fought', 'sword', 'weapon', 'army', 'warrior',
    // Death
    'death', 'dead', 'died', 'dying', 'perish', 'perished',
    // Fear & terror
    'terror', 'terrified', 'horror', 'scream', 'nightmare', 'frightened',
    // Punishment
    'punish', 'punishment', 'vengeance', 'wrath', 'doom', 'condemned',
    // Power rewards
    'crown', 'crowned', 'throne', 'king', 'kingdom', 'ruler', 'reign',
    'conquer', 'conquered', 'victory', 'triumphant',
    // Predator imagery
    'beast', 'monster', 'predator', 'hunt', 'chase', 'flee', 'escape', 'trap',
    // Loud/startling
    'thunder', 'crash', 'boom', 'explode', 'explosion',
    // Threatening darkness
    'darkness', 'ominous', 'menacing', 'evil', 'wicked', 'demon', 'devil',
    // Suffering
    'suffer', 'agony', 'torment', 'torture', 'blood', 'wound',
  ];
}

/// Harness that wraps story generation with validation and regeneration
class KidBedtimeHarness {
  final KidBedtimeValidator validator;
  final int maxAttempts;

  KidBedtimeHarness({
    required this.validator,
    this.maxAttempts = kMaxRegenAttempts,
  });

  /// Result of running the harness
  KidBedtimeHarnessResult run({
    required String storyText,
    required String Function(String? repairInstruction) regenerate,
  }) {
    var currentText = storyText;
    final attempts = <KidBedtimeValidationResult>[];

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final result = validator.validate(currentText);
      attempts.add(result);

      if (result.isValid) {
        return KidBedtimeHarnessResult(
          finalText: currentText,
          isKidSafe: true,
          attempts: attempts,
        );
      }

      // If not last attempt, regenerate with repair instruction
      if (attempt < maxAttempts) {
        currentText = regenerate(result.repairInstruction);
      }
    }

    // All attempts failed - return best attempt marked as unsafe
    return KidBedtimeHarnessResult(
      finalText: currentText,
      isKidSafe: false,
      attempts: attempts,
    );
  }
}

/// Result of running the Kid Bedtime Harness
class KidBedtimeHarnessResult {
  final String finalText;
  final bool isKidSafe;
  final List<KidBedtimeValidationResult> attempts;

  const KidBedtimeHarnessResult({
    required this.finalText,
    required this.isKidSafe,
    required this.attempts,
  });

  int get attemptCount => attempts.length;

  /// Get all violations from the final attempt
  List<String> get finalViolations =>
      attempts.isNotEmpty ? attempts.last.allViolations : [];

  @override
  String toString() {
    return 'KidBedtimeHarnessResult: '
        '${isKidSafe ? "SAFE" : "UNSAFE"} after $attemptCount attempts';
  }
}
