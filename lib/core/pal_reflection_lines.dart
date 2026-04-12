import 'dart:convert';

import 'package:flutter/services.dart';

/// Mood-scoped reflection lines for the typed-input PAL overlay.
///
/// These acknowledge the user's emotional state before the story-specific
/// framing line. One short sentence per selection. Keyed by mood.
class PalReflectionLines {
  PalReflectionLines._();

  static Map<String, List<String>>? _moods;

  /// Load reflection lines from bundled asset. Safe to call multiple times.
  static Future<void> ensureLoaded() async {
    if (_moods != null) return;
    final jsonStr =
        await rootBundle.loadString('assets/pal/pal_reflection_lines.json');
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final moodsData = data['moods'] as Map<String, dynamic>;
    _moods = moodsData.map((key, value) => MapEntry(
          key,
          (value as List<dynamic>).map((e) => e as String).toList(),
        ));
  }

  /// Get a reflection line for the given [mood] using deterministic rotation.
  ///
  /// Combines mood hash with the current day so the same mood on a different
  /// day rotates to a new line. Returns null if mood is unknown or not loaded.
  static String? getLine(String? mood) {
    if (mood == null || _moods == null) return null;
    final lines = _moods![mood];
    if (lines == null || lines.isEmpty) return null;
    final seed = mood.hashCode + DateTime.now().day;
    return lines[seed.abs() % lines.length];
  }

  /// All loaded mood keys. Returns empty list if not yet loaded.
  static List<String> get moods => _moods?.keys.toList() ?? const [];

  /// Get all lines for a mood. Returns empty list if not found.
  static List<String> linesForMood(String mood) =>
      _moods?[mood] ?? const [];

  /// Reset internal state (for testing only).
  static void resetForTesting() {
    _moods = null;
  }
}
