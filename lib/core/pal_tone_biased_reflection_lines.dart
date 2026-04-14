import 'dart:convert';

import 'package:flutter/services.dart';

import '../features/pal/opening/pal_opening_lines.dart';

/// Tone-biased first reflective sentence service (Feature 5.1).
///
/// Provides pre-written first-sentence variants keyed by (mood × openingTone).
/// Parallel to [PalReflectionLines] — used only when a session opening tone is
/// active. Falls back to null so the caller can fall through to the normal path.
///
/// Content lives in assets/pal/pal_tone_biased_reflection_lines.json.
/// No AI generation. No runtime string modification.
class PalToneBiasedReflectionLines {
  PalToneBiasedReflectionLines._();

  // mood → tone-name → List<String>
  static Map<String, Map<String, List<String>>>? _data;

  /// Load asset. Safe to call multiple times.
  static Future<void> ensureLoaded() async {
    if (_data != null) return;
    final jsonStr = await rootBundle
        .loadString('assets/pal/pal_tone_biased_reflection_lines.json');
    final root = jsonDecode(jsonStr) as Map<String, dynamic>;
    final moodsRaw = root['moods'] as Map<String, dynamic>;

    _data = moodsRaw.map((mood, toneMap) {
      final tones = (toneMap as Map<String, dynamic>).map((tone, variants) {
        return MapEntry(
          tone,
          (variants as List<dynamic>).map((e) => e as String).toList(),
        );
      });
      return MapEntry(mood, tones);
    });
  }

  /// Return a deterministic tone-biased first reflective sentence for the
  /// given [mood] and [tone], or `null` if the combination is not found.
  ///
  /// Uses the same rotation strategy as [PalReflectionLines]: mood hash + day.
  static String? getLine(String? mood, PalOpeningTone tone) {
    if (mood == null || _data == null) return null;
    final toneMap = _data![mood];
    if (toneMap == null) return null;
    final toneName = tone.name; // enum name matches JSON key
    final variants = toneMap[toneName];
    if (variants == null || variants.isEmpty) return null;
    final seed = mood.hashCode + DateTime.now().day;
    return variants[seed.abs() % variants.length];
  }

  /// Reset internal state (for testing only).
  static void resetForTesting() {
    _data = null;
  }

  /// All loaded mood keys. Returns empty list if not yet loaded.
  static List<String> get moods => _data?.keys.toList() ?? const [];
}
