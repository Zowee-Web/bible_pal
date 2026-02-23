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
  Future<DailyBread> getDailyVerse(UserPreferences userPrefs) async {
    final now = DateTime.now();
    return getVerseForDate(now, userPrefs);
  }

  /// Get verse for a specific date using deterministic selection
  Future<DailyBread> getVerseForDate(
    DateTime date,
    UserPreferences userPrefs,
  ) async {
    final verses = await _loadVerses();

    if (verses.isEmpty) {
      // Fallback if no verses available
      return _fallbackVerse(date, userPrefs);
    }

    // Deterministic selection: (dayOfYear - 1) % verses.length
    // Jan 1 (day 1) → index 0 (first verse)
    final dayOfYear = _dayOfYear(date);
    final index = (dayOfYear - 1) % verses.length;
    final entry = verses[index];

    // Get text for requested translation, fallback to WEB if missing
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
