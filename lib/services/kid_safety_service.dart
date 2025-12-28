// Kid Safety Service
// Enforces Layer 3 of Kid Safety Contract Invariant
// See docs/INVARIANTS.md for complete specification

import 'dart:developer' as developer;
import 'package:flutter/services.dart' show rootBundle;

/// Result of a kid safety content scan
class ScanResult {
  final bool passed;
  final List<ScanViolation> violations;

  const ScanResult({
    required this.passed,
    required this.violations,
  });

  /// Create a passing result with no violations
  factory ScanResult.pass() => const ScanResult(
        passed: true,
        violations: [],
      );

  /// Create a failing result with violations
  factory ScanResult.fail(List<ScanViolation> violations) => ScanResult(
        passed: false,
        violations: violations,
      );

  @override
  String toString() =>
      'ScanResult(passed: $passed, violations: ${violations.length})';
}

/// Individual content violation detected during scan
class ScanViolation {
  final String pattern;
  final String matchedText;
  final int lineNumber;
  final int columnNumber;

  const ScanViolation({
    required this.pattern,
    required this.matchedText,
    required this.lineNumber,
    required this.columnNumber,
  });

  @override
  String toString() =>
      'Violation at $lineNumber:$columnNumber - pattern "$pattern" matched "$matchedText"';
}

/// Service for enforcing kid-friendly content safety
///
/// INVARIANT ENFORCEMENT (Layer 3):
/// This service provides runtime content scanning to ensure that stories
/// served in kid-friendly mode contain no inappropriate content.
///
/// See docs/INVARIANTS.md - Kid Safety Contract Invariant
class KidSafetyService {
  // Cached blocklist patterns loaded from assets
  List<RegExp>? _cachedPatterns;
  bool _initialized = false;

  /// Known-safe fallback story ID (David & Goliath)
  /// Used when a story fails safety scan in kid mode
  static const String fallbackStoryId = '101';

  /// Initialize the service by loading blocklist patterns
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      developer.log(
        '[KidSafety] Initializing kid safety service',
        name: 'bible_pal.kid_safety',
      );

      final patterns = await _loadBlocklistPatterns();
      _cachedPatterns = patterns;
      _initialized = true;

      developer.log(
        '[KidSafety] Loaded ${patterns.length} blocklist patterns',
        name: 'bible_pal.kid_safety',
      );
    } catch (e) {
      developer.log(
        '[KidSafety] ERROR: Failed to initialize: $e',
        name: 'bible_pal.kid_safety',
        level: 1000, // ERROR level
      );
      rethrow;
    }
  }

  /// Scan story text for inappropriate content
  ///
  /// Returns [ScanResult] indicating whether the content passed.
  /// If failed, result contains list of violations with locations.
  ///
  /// This method enforces Layer 3 of the Kid Safety Contract invariant.
  Future<ScanResult> scanStoryText(String text) async {
    // Ensure initialized
    if (!_initialized) {
      await initialize();
    }

    if (_cachedPatterns == null || _cachedPatterns!.isEmpty) {
      developer.log(
        '[KidSafety] WARNING: No patterns loaded, defaulting to PASS',
        name: 'bible_pal.kid_safety',
        level: 900, // WARNING level
      );
      return ScanResult.pass();
    }

    developer.log(
      '[KidSafety] Scanning text (${text.length} characters) with ${_cachedPatterns!.length} patterns',
      name: 'bible_pal.kid_safety',
    );

    final violations = <ScanViolation>[];

    // Split text into lines for line-number reporting
    final lines = text.split('\n');

    // Check each pattern against each line
    for (final pattern in _cachedPatterns!) {
      for (int lineIdx = 0; lineIdx < lines.length; lineIdx++) {
        final line = lines[lineIdx];
        final matches = pattern.allMatches(line);

        for (final match in matches) {
          violations.add(
            ScanViolation(
              pattern: pattern.pattern,
              matchedText: match.group(0) ?? '',
              lineNumber: lineIdx + 1, // 1-indexed for user display
              columnNumber: match.start + 1, // 1-indexed
            ),
          );
        }
      }
    }

    if (violations.isEmpty) {
      developer.log(
        '[KidSafety] ✓ PASS: No violations detected',
        name: 'bible_pal.kid_safety',
      );
      return ScanResult.pass();
    } else {
      developer.log(
        '[KidSafety] ✗ FAIL: Found ${violations.length} violations',
        name: 'bible_pal.kid_safety',
        level: 1000, // ERROR level
      );

      // Log first few violations for debugging
      for (int i = 0; i < violations.length && i < 5; i++) {
        developer.log(
          '[KidSafety]   ${violations[i]}',
          name: 'bible_pal.kid_safety',
          level: 1000,
        );
      }

      if (violations.length > 5) {
        developer.log(
          '[KidSafety]   ... and ${violations.length - 5} more violations',
          name: 'bible_pal.kid_safety',
          level: 1000,
        );
      }

      return ScanResult.fail(violations);
    }
  }

  /// Load blocklist patterns from assets
  ///
  /// Returns list of compiled RegExp objects ready for matching.
  /// Patterns are loaded from server/kid_safety_blocklist.txt and
  /// compiled as case-insensitive regex patterns.
  Future<List<RegExp>> _loadBlocklistPatterns() async {
    try {
      // Load blocklist file from assets
      final content =
          await rootBundle.loadString('assets/kid_safety_blocklist.txt');

      final patterns = <RegExp>[];
      final lines = content.split('\n');

      for (final line in lines) {
        final trimmed = line.trim();

        // Skip empty lines and comments
        if (trimmed.isEmpty || trimmed.startsWith('#')) {
          continue;
        }

        try {
          // Compile as case-insensitive regex
          final pattern = RegExp(trimmed, caseSensitive: false);
          patterns.add(pattern);
        } catch (e) {
          developer.log(
            '[KidSafety] WARNING: Invalid pattern "$trimmed": $e',
            name: 'bible_pal.kid_safety',
            level: 900,
          );
          // Continue loading other patterns
        }
      }

      return patterns;
    } catch (e) {
      developer.log(
        '[KidSafety] ERROR: Failed to load blocklist: $e',
        name: 'bible_pal.kid_safety',
        level: 1000,
      );
      // Return empty list to fail-open (better than crashing)
      // Build-time gates are the primary defense anyway
      return [];
    }
  }

  /// Optional: ML-based content classifier hook (future enhancement)
  ///
  /// This hook exists to allow plugging in an ML-based content classifier
  /// in the future without changing the service interface.
  ///
  /// Currently returns PASS (feature-flagged off by default).
  Future<ScanResult> classifyContent(String text,
      {bool enabled = false}) async {
    if (!enabled) {
      return ScanResult.pass();
    }

    // Future implementation:
    // - Call ML model API
    // - Get content classification scores
    // - Return FAIL if inappropriate content detected

    developer.log(
      '[KidSafety] ML classifier called but not yet implemented',
      name: 'bible_pal.kid_safety',
    );

    return ScanResult.pass();
  }
}
