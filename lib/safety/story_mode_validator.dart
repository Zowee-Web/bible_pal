// Story Mode Validator - Contracts v2 and ADR-010 Enforcement
// Per SPEC.md Story Mode Contracts v2, INVARIANTS.md, and docs/DECISIONS.md ADR-010
//
// This validator enforces the separation between Traditional and Creative modes:
// - Traditional: ACTUAL Bible stories faithfully retold, bibleSourceRef REQUIRED
// - Creative: Original stories, bibleSourceRef FORBIDDEN, MoDC rules apply
//
// ADR-010 Clarification: Traditional stories MUST be real Bible stories (e.g., The Lost Sheep,
// David and Goliath), NOT devotional content or generic faith-themed stories.
//
// The validator is used at generation time to ensure stories meet their mode contract.

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

  // === Creative Mode Forbidden Patterns ===
  // Scripture authority claims (forbidden in Creative)
  static const _scriptureAuthorityPatterns = [
    r'\bas (the Bible|scripture|the Word) (says|tells us|teaches)\b',
    r'\bscripture (says|tells us|teaches)\b',
    r'\bit is written\b',
    r'\bthe (Lord|God) (said|spoke|commanded)\b',
    r'\baccording to (scripture|the Bible)\b',
    r'\bbiblical truth\b',
    r"\bGod's Word (says|tells)\b",
  ];

  // Advice/prescription patterns (forbidden in Creative - MoDC violation)
  static const _advicePrescriptionPatterns = [
    r'\byou should\b',
    r'\byou must\b',
    r'\byou need to\b',
    r'\btry to\b',
    r'\bmake sure (you|to)\b',
    r'\bremember to\b',
    r"\bdon't forget to\b",
    r'\balways (do|be|remember)\b',
    r'\bnever (do|be|forget)\b',
  ];

  // Dependency language (forbidden in Creative - MoDC violation)
  static const _dependencyPatterns = [
    r'\byou need (this|me|us)\b',
    r'\bcome back (tomorrow|again|soon)\b',
    r'\bwithout (this|me|us) you\b',
    r"\byou can't (do|live|survive) without\b",
    r'\bkeep coming back\b',
  ];

  // === Creative + KJV Extra Restrictions ===
  // Scripture-claim markers (forbidden in Creative+KJV)
  static const _scriptureClaimMarkersKjv = [
    r'\bthus saith\b',
    r'\bverily\b.*\bsaith\b',
    r'\bchapter\s+\d+\b',
    r'\bverse\s+\d+\b',
    r'\b\d+:\d+\b',
    r'\bthis is the Word\b',
    r'\bhear the Word\b',
    r'\bthe Word of (the Lord|God)\b',
    r'\bsaith the Lord\b',
    r'\bspake unto\b',
  ];

  // === Bible Story Retelling Signals (forbidden in Creative) ===
  // Strong signals that a creative story is actually retelling a Bible story
  static const _bibleRetellingSignals = [
    r'\b(Noah|Noach).*ark\b',
    r'\b(Moses|Moshe).*Red Sea\b',
    r'\b(Moses|Moshe).*burning bush\b',
    r'\b(David).*Goliath\b',
    r"\b(Daniel).*lion('s)? den\b",
    r'\b(Jonah).*whale\b',
    r'\b(Jonah).*fish\b',
    r'\b(Jonah).*Nineveh\b',
    r'\b(Abraham|Abram).*Isaac.*sacrifice\b',
    r'\b(Joseph).*coat of many colors\b',
    r'\b(Samson).*Delilah\b',
    r'\b(Elijah).*prophets of Baal\b',
    r'\bthe (Bible|scripture) (tells|records|says) (of|that|how)\b',
    r'\bin the (book of|gospel of)\b',
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

  /// Validate a Creative mode story
  ///
  /// Checks:
  /// - bibleSourceRef is absent or empty
  /// - No scripture authority claims
  /// - No advice/prescription language (MoDC)
  /// - No dependency language (MoDC)
  /// - No Bible story retelling signals
  /// - If languageStyle=KJV, no scripture-claim markers
  static StoryModeValidationResult validateCreative({
    required String storyText,
    required String? bibleSourceRef,
    String? languageStyle,
  }) {
    final violations = <String>[];
    final warnings = <String>[];

    // CRITICAL: bibleSourceRef FORBIDDEN for Creative
    if (bibleSourceRef != null && bibleSourceRef.trim().isNotEmpty) {
      violations.add(
        'Creative story MUST NOT have bibleSourceRef. '
        'Creative stories are original, not scripture retellings.',
      );
    }

    final lowerText = storyText.toLowerCase();

    // Check for scripture authority claims
    for (final pattern in _scriptureAuthorityPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(lowerText)) {
        violations.add(
          'Creative story contains scripture authority claim. '
          'Pattern: "$pattern". Creative stories should not claim scriptural authority.',
        );
        break;
      }
    }

    // Check for advice/prescription patterns (MoDC violation)
    for (final pattern in _advicePrescriptionPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(lowerText)) {
        violations.add(
          'Creative story contains advice/prescription language (MoDC violation). '
          'Pattern: "$pattern". Use descriptive, not prescriptive language.',
        );
        break;
      }
    }

    // Check for dependency patterns (MoDC violation)
    for (final pattern in _dependencyPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(lowerText)) {
        violations.add(
          'Creative story contains dependency language (MoDC violation). '
          'Pattern: "$pattern". Stories should not create dependency.',
        );
        break;
      }
    }

    // Check for Bible story retelling signals
    for (final pattern in _bibleRetellingSignals) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(storyText)) {
        warnings.add(
          'Creative story may be retelling a specific Bible story. '
          'Signal: "$pattern". Creative should be original, not retellings.',
        );
        break;
      }
    }

    // EXTRA: Creative + KJV restrictions
    if (languageStyle == 'KJV') {
      for (final pattern in _scriptureClaimMarkersKjv) {
        if (RegExp(pattern, caseSensitive: false).hasMatch(storyText)) {
          violations.add(
            'Creative+KJV story contains scripture-claim marker. '
            'Pattern: "$pattern". KJV in Creative is poetic diction only, not scripture.',
          );
          break;
        }
      }
    }

    return StoryModeValidationResult(
      isValid: violations.isEmpty,
      storytellingMode: 'creative',
      languageStyle: languageStyle,
      violations: violations,
      warnings: warnings,
    );
  }

  /// Validate a story based on its declared mode
  ///
  /// Dispatches to validateTraditional or validateCreative based on mode.
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
    } else if (storytellingMode == 'creative') {
      return validateCreative(
        storyText: storyText,
        bibleSourceRef: bibleSourceRef,
        languageStyle: languageStyle,
      );
    } else {
      // Unknown mode - fail validation
      return StoryModeValidationResult(
        isValid: false,
        storytellingMode: storytellingMode,
        languageStyle: languageStyle,
        violations: [
          'Unknown storytelling mode: "$storytellingMode". '
              'Must be "traditional" or "creative".',
        ],
      );
    }
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

    if (storytellingMode != 'traditional' && storytellingMode != 'creative') {
      violations.add(
        'Invalid storytellingMode: "$storytellingMode". Must be "traditional" or "creative".',
      );
    }

    if (storytellingMode == 'traditional') {
      if (bibleSourceRef == null || bibleSourceRef.trim().isEmpty) {
        violations.add(
          'Traditional story missing required bibleSourceRef.',
        );
      }
    }

    if (storytellingMode == 'creative') {
      if (bibleSourceRef != null && bibleSourceRef.trim().isNotEmpty) {
        violations.add(
          'Creative story has forbidden bibleSourceRef: "$bibleSourceRef".',
        );
      }
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
