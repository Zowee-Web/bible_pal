import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pal_line_ref.dart';
import 'pal_line_rotator.dart';

/// Mood-scoped reflection lines for the typed-input PAL overlay.
///
/// These acknowledge the user's emotional state before the story-specific
/// framing line. One short sentence per selection. Keyed by mood.
/// Each line carries a unique ID for audio asset lookup (Feature 5.1a).
class PalReflectionLines {
  PalReflectionLines._();

  static Map<String, List<PalLineRef>>? _moods;
  static final PalLineRotator _rotator = PalLineRotator();

  /// Load reflection lines from bundled asset. Safe to call multiple times.
  static Future<void> ensureLoaded() async {
    if (_moods != null) return;
    final jsonStr =
        await rootBundle.loadString('assets/pal/pal_reflection_lines.json');
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final moodsData = data['moods'] as Map<String, dynamic>;
    _moods = moodsData.map((key, value) => MapEntry(
          key,
          (value as List<dynamic>).map((e) {
            final obj = e as Map<String, dynamic>;
            return PalLineRef(obj['id'] as String, obj['text'] as String);
          }).toList(),
        ));
    final prefs = await SharedPreferences.getInstance();
    _rotator.enablePersistence(prefs, 'reflection');
  }

  /// Get a reflection line for the given [mood].
  static String? getLine(String? mood) {
    return getLineRef(mood)?.text;
  }

  /// Get a reflection line ref (id + text) for the given [mood].
  ///
  /// Uses persistent recency tracking so the same mood cycles through
  /// every available line before repeating, even across app restarts.
  static PalLineRef? getLineRef(String? mood) {
    if (mood == null || _moods == null) return null;
    final lines = _moods![mood];
    if (lines == null || lines.isEmpty) return null;
    return lines[_rotator.pick(mood, lines.length)];
  }

  /// All loaded mood keys. Returns empty list if not yet loaded.
  static List<String> get moods => _moods?.keys.toList() ?? const [];

  /// Get all lines for a mood. Returns empty list if not found.
  static List<String> linesForMood(String mood) =>
      _moods?[mood]?.map((r) => r.text).toList() ?? const [];

  /// Reset internal state (for testing only).
  static void resetForTesting() {
    _moods = null;
    _rotator.clearPersistedHistory();
  }
}
