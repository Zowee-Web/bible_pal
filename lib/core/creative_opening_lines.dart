import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pal_line_ref.dart';
import 'pal_line_rotator.dart';

/// Mood-based opening lines for Creative mode stories.
///
/// These provide a narrative opening spoken by PAL before the length picker,
/// equivalent to Traditional mode's BiblicalFigureRegistry framing lines.
/// Content is NOT Scripture-based — purely narrative and imaginative.
/// Each line carries a unique ID for audio asset lookup.
class CreativeOpeningLines {
  CreativeOpeningLines._();

  static Map<String, List<PalLineRef>>? _moods;
  static final PalLineRotator _rotator = PalLineRotator();

  /// Load from bundled asset. Safe to call multiple times.
  static Future<void> ensureLoaded() async {
    if (_moods != null) return;
    final jsonStr = await rootBundle
        .loadString('assets/pal/creative_opening_lines.json');
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
    _rotator.enablePersistence(prefs, 'creative');
  }

  /// Get an opening line for the given [mood].
  static String? getLine(String? mood) {
    return getLineRef(mood)?.text;
  }

  /// Get an opening line ref (id + text) for the given [mood].
  ///
  /// Uses persistent recency tracking so the same mood cycles through
  /// every available line before repeating, even across app restarts.
  static PalLineRef? getLineRef(String? mood) {
    if (mood == null || _moods == null) return null;
    final lines = _moods![mood];
    if (lines == null || lines.isEmpty) return null;
    return lines[_rotator.pick(mood, lines.length)];
  }

  /// All loaded mood keys.
  static List<String> get moods => _moods?.keys.toList() ?? const [];

  /// Reset internal state (for testing only).
  static void resetForTesting() {
    _moods = null;
    _rotator.clearPersistedHistory();
  }
}
