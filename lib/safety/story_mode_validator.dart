// Story Mode Validator - ADR-010 Traditional-Only Enforcement
// Per docs/DECISIONS.md ADR-010 and docs/archive/CREATIVE_RETIREMENT_2026_05_13.md.
//
// Traditional mode is the only active lane after Creative retirement (2026-05-13).
// Stories must have bibleSourceRef and conform to third-person biblical narrative.
//
// ADR-010 Clarification: Traditional stories MUST be real Bible stories (e.g.,
// The Lost Sheep, David and Goliath), NOT devotional content or generic
// faith-themed stories.
//
// The validator is used at generation time to ensure stories meet the contract.

/// Validation result for story mode contract checks
class StoryModeValidationResult {
  final bool isValid;
  final String storytellingMode;
  final String? languageStyle;
  final List<String> violations;
  final List<String> warnings;

  const StoryModeValidationResult({
    required this.isValid,
    required this.storytellingMode,
    this.languageStyle,
    this.violations = const [],
    this.warnings = const [],
  });

  /// Get all issues (violations + warnings) as a single list
  List<String> get allIssues => [...violations, ...warnings];

  /// Get repair instruction for generation retry
  String get repairInstruction {
    if (violations.isEmpty) return '';
    final buffer = StringBuffer();
    buffer.writeln('STORY MODE CONTRACT VIOLATIONS - Please fix:');
    for (final v in violations) {
      buffer.writeln('- $v');
    }
    return buffer.toString();
  }

  @override
  String toString() {
    return 'StoryModeValidationResult(isValid: $isValid, mode: $storytellingMode, '
        'violations: ${violations.length}, warnings: ${warnings.length})';
  }
}

/// Story Mode Validator for Contracts v2 enforcement
class StoryModeValidator {
  // === Traditional Mode Forbidden Patterns ===
  // MoDC companionship voice patterns (forbidden in Traditional)
  static const _modcCompanionshipPatterns = [
    r'\bI sit with you\b',
    r'\bI am here with you\b',
    r'\bI am beside you\b',
    r'\blet me walk with you\b',
    r'\bwe journey together\b',
    r'\byou are not alone.*I\b',
    r'\bI hold space\b',
    r"\bI'm here for you\b",
  ];

  // First/second person spiritual guide posture (forbidden in Traditional)
  static const _spiritualGuidePatterns = [
    r'^Dear (friend|listener|child)',
    r'\blet me (tell|share|guide) you\b',
    r'\byou see,\b',
    r'\bremember, dear one\b',
    r'\bI want you to\b',
    r'\bI invite you to\b',
  ];

  // Devotional commentary patterns (forbidden in Traditional narrative)
  static const _devotionalCommentaryPatterns = [
    r'\bthis (shows|teaches|reminds) us that\b',
    r'\bwe can learn from this\b',
    r'\bwhat .* teaches us\b',
    r'\bthe lesson here is\b',
    r'\bapply this to (your|our) life\b',
  ];

  /// Validate a Traditional mode story
  ///
  /// Checks:
  /// - bibleSourceRef is present and non-empty
  /// - No MoDC companionship patterns
  /// - No spiritual guide posture
  /// - No devotional commentary (should be narrative)
  static StoryModeValidationResult validateTraditional({
    required String storyText,
    required String? bibleSourceRef,
    String? languageStyle,
  }) {
    final violations = <String>[];
    final warnings = <String>[];

    // CRITICAL: bibleSourceRef REQUIRED for Traditional
    if (bibleSourceRef == null || bibleSourceRef.trim().isEmpty) {
      violations.add(
        'Traditional story MUST have bibleSourceRef (scripture reference). '
        'Do NOT guess - mark for manual entry or exclude.',
      );
    }

    // Check for MoDC companionship patterns
    for (final pattern in _modcCompanionshipPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(storyText)) {
        violations.add(
          'Traditional story contains MoDC companionship voice. '
          'Pattern: "$pattern". Traditional should use third-person biblical narrative.',
        );
        break; // One violation per category is enough
      }
    }

    // Check for spiritual guide posture
    for (final pattern in _spiritualGuidePatterns) {
      if (RegExp(pattern, caseSensitive: false, multiLine: true)
          .hasMatch(storyText)) {
        violations.add(
          'Traditional story contains first/second-person spiritual guide posture. '
          'Pattern: "$pattern". Use third-person biblical narrative.',
        );
        break;
      }
    }

    // Check for devotional commentary (warning, not violation)
    final lowerText = storyText.toLowerCase();
    for (final pattern in _devotionalCommentaryPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(lowerText)) {
        warnings.add(
          'Traditional story may contain devotional commentary. '
          'Pattern: "$pattern". Prefer pure narrative without teaching asides.',
        );
        break;
      }
    }

    return StoryModeValidationResult(
      isValid: violations.isEmpty,
      storytellingMode: 'traditional',
      languageStyle: languageStyle,
      violations: violations,
      warnings: warnings,
    );
  }

  /// Validate a story based on its declared mode
  ///
  /// Post-Creative-retirement (2026-05-13): only 'traditional' is valid.
  static StoryModeValidationResult validate({
    required String storytellingMode,
    required String storyText,
    required String? bibleSourceRef,
    String? languageStyle,
  }) {
    if (storytellingMode == 'traditional') {
      return validateTraditional(
        storyText: storyText,
        bibleSourceRef: bibleSourceRef,
        languageStyle: languageStyle,
      );
    }
    return StoryModeValidationResult(
      isValid: false,
      storytellingMode: storytellingMode,
      languageStyle: languageStyle,
      violations: [
        'Unknown storytelling mode: "$storytellingMode". Must be "traditional".',
      ],
    );
  }

  /// Quick check if a story has valid mode metadata (no text analysis)
  ///
  /// This is faster than full validation and useful for manifest scanning.
  static StoryModeValidationResult validateMetadataOnly({
    required String storytellingMode,
    required String? bibleSourceRef,
    String? languageStyle,
  }) {
    final violations = <String>[];

    if (storytellingMode != 'traditional') {
      violations.add(
        'Invalid storytellingMode: "$storytellingMode". Must be "traditional".',
      );
    } else if (bibleSourceRef == null || bibleSourceRef.trim().isEmpty) {
      violations.add('Traditional story missing required bibleSourceRef.');
    }

    if (languageStyle != null &&
        languageStyle != 'WEB' &&
        languageStyle != 'KJV') {
      violations.add(
        'Invalid languageStyle: "$languageStyle". Must be "WEB" or "KJV".',
      );
    }

    return StoryModeValidationResult(
      isValid: violations.isEmpty,
      storytellingMode: storytellingMode,
      languageStyle: languageStyle,
      violations: violations,
    );
  }
}
