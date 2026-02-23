// Content Filter Service
// Enforces SPEC.md Feature #24: Content Filtering / Moderation Controls
// Scans story text for inappropriate content before it reaches the user.
//
// This is the general-audience filter (distinct from kid-safe filtering).
// Adult Biblical content (war, death, blood) is allowed — only genuinely
// inappropriate content (profanity, explicit sexual content, graphic gore,
// hate speech) is blocked.

import 'dart:developer' as developer;
import 'package:flutter/services.dart' show rootBundle;
import 'kid_safety_service.dart' show ScanResult, ScanViolation;

class ContentFilterService {
  List<RegExp>? _cachedPatterns;
  bool _initialized = false;

  static const String _assetPath = 'assets/safety/content_filter_blocklist.txt';

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final patterns = await _loadBlocklistPatterns();
      _cachedPatterns = patterns;
      _initialized = true;

      developer.log(
        '[ContentFilter] Loaded ${patterns.length} blocklist patterns',
        name: 'bible_pal.content_filter',
      );
    } catch (e) {
      developer.log(
        '[ContentFilter] ERROR: Failed to initialize: $e',
        name: 'bible_pal.content_filter',
        level: 1000,
      );
      rethrow;
    }
  }

  Future<ScanResult> scanText(String text) async {
    if (!_initialized) {
      await initialize();
    }

    if (_cachedPatterns == null || _cachedPatterns!.isEmpty) {
      return ScanResult.pass();
    }

    final violations = <ScanViolation>[];
    final lines = text.split('\n');

    for (final pattern in _cachedPatterns!) {
      for (int lineIdx = 0; lineIdx < lines.length; lineIdx++) {
        final line = lines[lineIdx];
        final matches = pattern.allMatches(line);

        for (final match in matches) {
          violations.add(
            ScanViolation(
              pattern: pattern.pattern,
              matchedText: match.group(0) ?? '',
              lineNumber: lineIdx + 1,
              columnNumber: match.start + 1,
            ),
          );
        }
      }
    }

    if (violations.isEmpty) {
      return ScanResult.pass();
    }

    developer.log(
      '[ContentFilter] FAIL: Found ${violations.length} violations',
      name: 'bible_pal.content_filter',
      level: 1000,
    );

    return ScanResult.fail(violations);
  }

  Future<List<RegExp>> _loadBlocklistPatterns() async {
    try {
      final content = await rootBundle.loadString(_assetPath);
      final patterns = <RegExp>[];
      final lines = content.split('\n');

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

        try {
          patterns.add(RegExp(trimmed, caseSensitive: false));
        } catch (e) {
          developer.log(
            '[ContentFilter] WARNING: Invalid pattern "$trimmed": $e',
            name: 'bible_pal.content_filter',
            level: 900,
          );
        }
      }

      if (patterns.isEmpty) {
        return _getCriticalFallbackPatterns();
      }

      return patterns;
    } catch (e) {
      developer.log(
        '[ContentFilter] ERROR: Failed to load blocklist: $e',
        name: 'bible_pal.content_filter',
        level: 1000,
      );
      return _getCriticalFallbackPatterns();
    }
  }

  List<RegExp> _getCriticalFallbackPatterns() {
    return [
      RegExp(r'\bfuck\b', caseSensitive: false),
      RegExp(r'\bshit\b', caseSensitive: false),
      RegExp(r'\bcunt\b', caseSensitive: false),
      RegExp(r'\bmotherfucker\b', caseSensitive: false),
      RegExp(r'\bnigger', caseSensitive: false),
      RegExp(r'\bfaggot', caseSensitive: false),
      RegExp(r'\btortur(?:ed|ing|e)\b', caseSensitive: false),
      RegExp(r'\bdismember', caseSensitive: false),
    ];
  }
}
