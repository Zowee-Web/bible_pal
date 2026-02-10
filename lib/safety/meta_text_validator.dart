/// Meta-Text Validator - Prevents LLM meta-commentary in Scripture narration
///
/// Rejects generated output containing process language, introductions,
/// disclaimers, or explanations before Scripture content begins.
/// Violations trigger silent regeneration — never surfaced to users.
///
/// See: docs/INVARIANTS.md - Meta-Text Prevention Invariant
library;

/// Maximum regeneration attempts for meta-text failures
const int kMetaTextMaxRegenAttempts = 3;

/// Classification of verse types for narration rules
enum VerseType {
  /// Declarative verses: statement-level only, no narrative expansion.
  /// No scene, no people, no setting, no emotional atmosphere,
  /// no imagined listeners, no historical framing.
  declarativeOnly,

  /// Narrative-eligible verses: may include scene, setting, characters.
  narrativeEligible,
}

/// Registry of known verse classifications.
/// Verses not listed default to [VerseType.narrativeEligible].
class VerseClassification {
  static const Map<String, VerseType> _registry = {
    // Declarative verses — statement-level elevation only
    'Romans 8:28': VerseType.declarativeOnly,
    'Romans 8:38-39': VerseType.declarativeOnly,
    'Jeremiah 29:11': VerseType.declarativeOnly,
    'Proverbs 3:5-6': VerseType.declarativeOnly,
    'Philippians 4:13': VerseType.declarativeOnly,
    'Isaiah 40:31': VerseType.declarativeOnly,
    'Psalm 23:1': VerseType.declarativeOnly,
    'John 3:16': VerseType.declarativeOnly,
    '2 Corinthians 5:17': VerseType.declarativeOnly,
    'Romans 12:2': VerseType.declarativeOnly,
    'Philippians 4:6-7': VerseType.declarativeOnly,
    'Isaiah 41:10': VerseType.declarativeOnly,
    'Joshua 1:9': VerseType.declarativeOnly,
    'Psalm 46:1': VerseType.declarativeOnly,
    'Psalm 46:10': VerseType.declarativeOnly,
    'Matthew 11:28': VerseType.declarativeOnly,
    'Hebrews 11:1': VerseType.declarativeOnly,
    '1 John 4:18': VerseType.declarativeOnly,
    'Lamentations 3:22-23': VerseType.declarativeOnly,
    '2 Timothy 1:7': VerseType.declarativeOnly,
  };

  /// Get the verse type for a given reference.
  /// Returns [VerseType.narrativeEligible] for unclassified verses.
  static VerseType classify(String? bibleSourceRef) {
    if (bibleSourceRef == null) return VerseType.narrativeEligible;
    return _registry[bibleSourceRef.trim()] ?? VerseType.narrativeEligible;
  }
}

/// Result of meta-text validation
class MetaTextValidationResult {
  final bool isValid;
  final List<String> violations;

  const MetaTextValidationResult({
    required this.isValid,
    this.violations = const [],
  });

  /// Generate repair instruction for regeneration retry
  String get repairInstruction {
    if (isValid) return '';
    final buffer = StringBuffer();
    buffer.writeln('YOUR OUTPUT WAS REJECTED. FIX THESE ISSUES:');
    buffer.writeln();
    for (final v in violations) {
      buffer.writeln('- $v');
    }
    buffer.writeln();
    buffer.writeln('RULES:');
    buffer.writeln('- Begin DIRECTLY with story/Scripture prose.');
    buffer.writeln('- No introductions, disclaimers, or meta-commentary.');
    buffer.writeln('- No "Here is", "Certainly", "This version", etc.');
    buffer.writeln('- Write ONLY the story content.');
    return buffer.toString();
  }

  @override
  String toString() =>
      'MetaTextValidationResult(isValid: $isValid, violations: ${violations.length})';
}

/// Validates generated output for meta-text contamination.
class MetaTextValidator {
  /// Configurable blocklist of meta-text phrases.
  /// Matched case-insensitively against the opening of generated text.
  static const List<String> defaultBlocklist = [
    'here is',
    'here\'s',
    'this version',
    'certainly',
    'of course',
    'sure,',
    'sure!',
    'in this retelling',
    'expanded carefully',
    'staying true to',
    'the following',
    'this passage',
    'this story',
    'this verse',
    'this retelling',
    'this rendering',
    'this adaptation',
    'i\'ve',
    'i have',
    'let me',
    'below is',
    'as requested',
    'as you asked',
    'happy to',
    'glad to',
    'i\'d be',
    'i would be',
    'absolutely',
    'great question',
    'what a',
  ];

  /// Narrative markers forbidden in DECLARATIVE_ONLY verses.
  static final List<RegExp> _declarativeOnlyForbidden = [
    // Scene-setting
    RegExp(r'\b(the sun|the wind|the morning|the evening|as .* walked)\b',
        caseSensitive: false),
    // People/characters (imagined listeners)
    RegExp(r'\b(the (crowd|people|listeners|disciples) (gathered|stood|sat))\b',
        caseSensitive: false),
    // Setting/location descriptions
    RegExp(r'\b(in the (village|city|temple|field|garden|marketplace))\b',
        caseSensitive: false),
    // Emotional atmosphere
    RegExp(r'\b(a (hush|silence|stillness) fell)\b', caseSensitive: false),
    // Historical framing
    RegExp(r'\b(in (those|ancient|biblical) (days|times))\b',
        caseSensitive: false),
    RegExp(r'\b(long ago|centuries ago|in the time of)\b',
        caseSensitive: false),
  ];

  /// Reflection/interpretation language forbidden in Scripture narration.
  /// These may ONLY appear in the post-story reflection system.
  static final List<RegExp> _reflectionFirewallPatterns = [
    // Emotional comfort
    RegExp(r'\b(take comfort|find comfort|be comforted)\b',
        caseSensitive: false),
    RegExp(r"\b(you are not alone|you're not alone)\b",
        caseSensitive: false),
    // Explanation
    RegExp(r'\b(this (means|shows|teaches|reminds) (us|you) that)\b',
        caseSensitive: false),
    RegExp(r'\b(what this (means|tells) us)\b', caseSensitive: false),
    // Application
    RegExp(r'\b(apply this to|in (your|our) (life|lives|daily))\b',
        caseSensitive: false),
    RegExp(r'\b(when (you|we) (face|feel|struggle))\b',
        caseSensitive: false),
    // Interpretation
    RegExp(r'\b(the (lesson|message|meaning) (here|of this) is)\b',
        caseSensitive: false),
    RegExp(r'\b(God is (telling|showing|teaching) (us|you))\b',
        caseSensitive: false),
  ];

  final List<String> _blocklist;

  /// Create a validator with default or custom blocklist.
  MetaTextValidator({List<String>? blocklist})
      : _blocklist = blocklist ?? defaultBlocklist;

  /// Validate generated text for meta-text contamination.
  ///
  /// Checks:
  /// 1. Opening text does not contain blocklisted meta-phrases
  /// 2. If [verseType] is DECLARATIVE_ONLY, no narrative markers allowed
  /// 3. Reflection/interpretation language is forbidden in narration
  MetaTextValidationResult validate(
    String text, {
    VerseType verseType = VerseType.narrativeEligible,
  }) {
    final violations = <String>[];
    final trimmed = text.trimLeft();
    if (trimmed.isEmpty) {
      return const MetaTextValidationResult(
        isValid: false,
        violations: ['Output is empty'],
      );
    }

    // Check first 200 chars for meta-text blocklist phrases
    final opening = trimmed.length > 200
        ? trimmed.substring(0, 200).toLowerCase()
        : trimmed.toLowerCase();

    for (final phrase in _blocklist) {
      if (opening.contains(phrase.toLowerCase())) {
        violations.add(
          'Meta-text detected in opening: "$phrase". '
          'Output must begin directly with story/Scripture prose.',
        );
        break; // One meta-text violation is enough
      }
    }

    // DECLARATIVE_ONLY enforcement
    if (verseType == VerseType.declarativeOnly) {
      for (final pattern in _declarativeOnlyForbidden) {
        if (pattern.hasMatch(text)) {
          violations.add(
            'DECLARATIVE_ONLY verse contains narrative expansion. '
            'Pattern: "${pattern.pattern}". '
            'Only statement-level elevation is allowed.',
          );
          break;
        }
      }
    }

    // Reflection firewall: these patterns belong in reflection, not narration
    for (final pattern in _reflectionFirewallPatterns) {
      if (pattern.hasMatch(text)) {
        violations.add(
          'Reflection/interpretation language in narration. '
          'Pattern: "${pattern.pattern}". '
          'Comfort, explanation, application, and interpretation '
          'belong in the post-story reflection system only.',
        );
        break;
      }
    }

    return MetaTextValidationResult(
      isValid: violations.isEmpty,
      violations: violations,
    );
  }
}

/// Harness that wraps generation with meta-text validation and regeneration.
///
/// Follows the same pattern as [KidBedtimeHarness].
class MetaTextHarness {
  final MetaTextValidator validator;
  final int maxAttempts;

  MetaTextHarness({
    MetaTextValidator? validator,
    this.maxAttempts = kMetaTextMaxRegenAttempts,
  }) : validator = validator ?? MetaTextValidator();

  /// Run validation with regeneration loop.
  ///
  /// [storyText] - initial generated text
  /// [regenerate] - callback to regenerate with optional repair instruction
  /// [verseType] - classification of the anchor verse
  MetaTextHarnessResult run({
    required String storyText,
    required String Function(String? repairInstruction) regenerate,
    VerseType verseType = VerseType.narrativeEligible,
  }) {
    var currentText = storyText;
    final attempts = <MetaTextValidationResult>[];

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final result = validator.validate(currentText, verseType: verseType);
      attempts.add(result);

      if (result.isValid) {
        return MetaTextHarnessResult(
          finalText: currentText,
          isClean: true,
          attempts: attempts,
        );
      }

      // Regenerate with stricter reminder if not last attempt
      if (attempt < maxAttempts) {
        currentText = regenerate(result.repairInstruction);
      }
    }

    // All attempts failed
    return MetaTextHarnessResult(
      finalText: currentText,
      isClean: false,
      attempts: attempts,
    );
  }
}

/// Result of running the meta-text harness.
class MetaTextHarnessResult {
  final String finalText;
  final bool isClean;
  final List<MetaTextValidationResult> attempts;

  const MetaTextHarnessResult({
    required this.finalText,
    required this.isClean,
    required this.attempts,
  });

  int get attemptCount => attempts.length;

  List<String> get finalViolations =>
      attempts.isNotEmpty ? attempts.last.violations : [];

  @override
  String toString() =>
      'MetaTextHarnessResult: ${isClean ? "CLEAN" : "CONTAMINATED"} '
      'after $attemptCount attempts';
}
