/// Kid Bedtime Safe Validator
///
/// Validates generated story content against the Kid Bedtime Contract.
/// Used for post-generation validation and regeneration decisions.
///
/// See: docs/prompts/kid_bedtime_contract.txt
/// See: server/kid_bedtime_forbidden.txt
library;

import 'dart:io';

/// Maximum regeneration attempts before giving up
const int kMaxRegenAttempts = 3;

/// Maximum average words per sentence for readability
const int kMaxAvgWordsPerSentence = 15;

/// Word count ranges for different story lengths (minutes)
/// Format: {minutes: (minWords, maxWords)}
const Map<int, (int, int)> kWordCountRanges = {
  3: (270, 400), // 3 min: ~90 wpm * 3 = 270, allow up to 400
  5: (540, 720), // 5 min: ~100-120 wpm * 5 = 500-600, allow 540-720
  10: (900, 1200), // 10 min: ~90-100 wpm * 10 = 900-1000
  15: (1350, 1800), // 15 min: ~90-100 wpm * 15
  20: (1800, 2400), // 20 min: ~90-100 wpm * 20
};

/// Get word count range for a given target length in minutes
/// Returns null if length not in predefined buckets (uses default 200 min)
(int, int)? getWordCountRange(int lengthMinutes) {
  return kWordCountRanges[lengthMinutes];
}

/// Result of validating a story against the Kid Bedtime Contract
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
    buffer.writeln('Remember: This is for children ages 5-9 at BEDTIME.');
    buffer.writeln('It must be calm, peaceful, and sleep-inducing.');

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

/// Validator for Kid Bedtime Safe stories
class KidBedtimeValidator {
  final List<String> _forbiddenPatterns;
  final List<RegExp> _forbiddenRegexes;

  /// Target length in minutes (used for word count validation)
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

  /// Validate story text against the Kid Bedtime Contract
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

    // Check bedtime closing
    final closingResult = _validateBedtimeClosing(storyText);
    if (closingResult != null) {
      otherViolations.add(closingResult);
    }

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

    // Check word count based on target length
    final wordCount = text.split(RegExp(r'\s+')).length;

    if (targetLengthMinutes != null) {
      final range = getWordCountRange(targetLengthMinutes!);
      if (range != null) {
        final (minWords, maxWords) = range;
        if (wordCount < minWords) {
          violations.add(
              'Story too short for ${targetLengthMinutes}min ($wordCount words, need $minWords-$maxWords). '
              'Expand sections 2-4 with more gentle, calm details.');
        } else if (wordCount > maxWords) {
          violations.add(
              'Story too long for ${targetLengthMinutes}min ($wordCount words, max $maxWords)');
        }
      } else {
        // Unknown length bucket, use default minimum
        if (wordCount < 200) {
          violations.add('Story too short ($wordCount words, minimum 200)');
        }
      }
    } else {
      // No target length specified, use default minimum
      if (wordCount < 200) {
        violations.add('Story too short ($wordCount words, minimum 200)');
      }
    }

    return violations;
  }

  /// Validate story has a calm bedtime closing
  String? _validateBedtimeClosing(String text) {
    // Get last ~200 characters for closing check
    final closingSection =
        text.length > 200 ? text.substring(text.length - 200) : text;
    final closingLower = closingSection.toLowerCase();

    // Check for bedtime/sleep-related closing signals
    final sleepSignals = [
      'sleep',
      'slept',
      'sleeping',
      'rest',
      'rested',
      'resting',
      'dream',
      'dreams',
      'dreaming',
      'peaceful',
      'peace',
      'calm',
      'quiet',
      'softly',
      'gently',
      'warm',
      'cozy',
      'safe',
      'eyes closed',
      'closed eyes',
      'night',
      'stars',
      'moon',
      'blanket',
      'pillow',
      'bed',
      'goodnight',
      'good night',
    ];

    final hasClosingSignal = sleepSignals.any((s) => closingLower.contains(s));

    if (!hasClosingSignal) {
      return 'Story ending lacks bedtime/sleep signals (should reference rest, sleep, peace, etc.)';
    }

    return null;
  }

  /// Calculate average words per sentence
  double _calculateAvgWordsPerSentence(String text) {
    // Split by sentence-ending punctuation
    final sentences = text.split(RegExp(r'[.!?]+'))
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
