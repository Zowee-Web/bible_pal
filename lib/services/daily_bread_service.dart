import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../core/bible_translation_registry.dart';
import '../models/daily_bread.dart';
import '../models/user_preferences.dart';

/// Daily Bread Service - manages daily verse display
/// Based on SPEC.md Features #20, #21: Daily Bread Verse Display and Thematic Alignment
///
/// Loads verses from assets/daily_bread/daily_bread_verses.json
/// Selects verse deterministically by date: index = dayOfYear % verses.length
/// Falls back to WEB translation if requested translation is missing for a verse
class DailyBreadService {
  /// Cached verses loaded from JSON asset (null until first load)
  List<DailyBreadEntry>? _cachedVerses;

  /// Asset path for daily bread verses
  static const String _assetPath = 'assets/daily_bread/daily_bread_verses.json';

  /// Get daily bread verse for today
  /// Uses deterministic selection: index = dayOfYear % verses.length
  /// If [mood] is provided and valid, biases selection toward theme-matching verses.
  Future<DailyBread> getDailyVerse(
    UserPreferences userPrefs, {
    String? mood,
  }) async {
    final now = DateTime.now();
    return getVerseForDate(now, userPrefs, mood: mood);
  }

  /// Get verse for a specific date using deterministic selection.
  /// If [mood] is provided, filters to theme-compatible verses first;
  /// falls back to full pool if no matches.
  Future<DailyBread> getVerseForDate(
    DateTime date,
    UserPreferences userPrefs, {
    String? mood,
  }) async {
    final allVerses = await _loadVerses();

    if (allVerses.isEmpty) {
      return _fallbackVerse(date, userPrefs);
    }

    final dayOfYear = _dayOfYear(date);

    // Mood-biased selection: filter to compatible themes if mood is valid
    List<DailyBreadEntry> pool = allVerses;
    if (mood != null) {
      final compatibleThemes = getCompatibleThemes(mood);
      if (compatibleThemes.isNotEmpty) {
        final filtered = allVerses
            .where((v) => v.theme != null && compatibleThemes.contains(v.theme))
            .toList();
        if (filtered.isNotEmpty) {
          pool = filtered;
        }
        // If filtered is empty, fall back to full pool (existing behavior)
      }
    }

    // Deterministic selection: (dayOfYear - 1) % pool.length
    final index = (dayOfYear - 1) % pool.length;
    final entry = pool[index];

    final translation = userPrefs.bibleTranslation;
    final verseText = entry.getText(translation);

    return DailyBread(
      verse: verseText,
      reference: entry.reference,
      translation: entry.hasTranslation(translation)
          ? translation
          : BibleTranslationRegistry.defaultTranslationId,
      date: DateTime(date.year, date.month, date.day),
      theme: entry.theme,
    );
  }

  /// Returns the set of Daily Bread themes compatible with a detected mood.
  /// Returns empty set for unknown moods (caller should fall back to full pool).
  static Set<String> getCompatibleThemes(String mood) {
    switch (mood) {
      case 'joyful':
        return const {'joyful', 'encouraging'};
      case 'weary':
        return const {'weary', 'encouraging', 'calm_peaceful'};
      case 'anxious':
        return const {'anxious', 'calm_peaceful', 'brave_courage'};
      case 'hurting':
        return const {'hurting', 'encouraging', 'calm_peaceful'};
      case 'neutral':
        return const {'neutral', 'calm_peaceful'};
      default:
        return const {};
    }
  }

  /// Load and cache verses from JSON asset
  Future<List<DailyBreadEntry>> _loadVerses() async {
    if (_cachedVerses != null) {
      return _cachedVerses!;
    }

    try {
      final jsonString = await rootBundle.loadString(_assetPath);
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      final versesList = data['verses'] as List<dynamic>? ?? [];

      _cachedVerses = versesList
          .map((json) => DailyBreadEntry.fromJson(json as Map<String, dynamic>))
          .toList();

      return _cachedVerses!;
    } catch (e) {
      // Asset loading failed - return empty list (fallback will be used)
      return [];
    }
  }

  /// Calculate day of year (1-366)
  int _dayOfYear(DateTime date) {
    final startOfYear = DateTime(date.year, 1, 1);
    final difference = date.difference(startOfYear).inDays;
    return difference + 1; // 1-indexed (Jan 1 = day 1)
  }

  /// Fallback verse when JSON asset is unavailable
  DailyBread _fallbackVerse(DateTime date, UserPreferences userPrefs) {
    // Belt-and-suspenders: ensure translation is always valid
    final translation = BibleTranslationRegistry.validateAndSanitize(
      userPrefs.bibleTranslation,
    );
    return DailyBread(
      verse: 'In Your presence is fullness of joy',
      reference: 'Psalm 16:11',
      translation: translation,
      date: DateTime(date.year, date.month, date.day),
      theme: null,
    );
  }

  /// Clear cached verses (for testing)
  void clearCache() {
    _cachedVerses = null;
  }
}

/// Internal model for a verse entry with multiple translations
class DailyBreadEntry {
  final String id;
  final String reference;
  final Map<String, String> text;
  final String? theme;

  const DailyBreadEntry({
    required this.id,
    required this.reference,
    required this.text,
    this.theme,
  });

  factory DailyBreadEntry.fromJson(Map<String, dynamic> json) {
    final textMap = json['text'] as Map<String, dynamic>;
    return DailyBreadEntry(
      id: json['id'] as String,
      reference: json['reference'] as String,
      text: textMap.map((k, v) => MapEntry(k, v as String)),
      theme: json['theme'] as String?,
    );
  }

  /// Check if this entry has a specific translation
  bool hasTranslation(String translationId) {
    return text.containsKey(translationId);
  }

  /// Get verse text for a translation, falling back to WEB if missing
  String getText(String translationId) {
    if (text.containsKey(translationId)) {
      return text[translationId]!;
    }
    // Fallback to WEB (default translation per INVARIANTS.md)
    return text[BibleTranslationRegistry.defaultTranslationId] ??
        text.values.first;
  }
}
