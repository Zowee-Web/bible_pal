import 'parable.dart';

/// Favorite model - represents a user's favorited parable
/// Based on SPEC.md Feature #9: Favorites System
class Favorite {
  final String storyId;
  final String title; // User's edited title or AI title
  final String mood;
  final int length;
  final String faithTradition;
  final List<String> scriptureSources;
  final DateTime dateSaved;

  const Favorite({
    required this.storyId,
    required this.title,
    required this.mood,
    required this.length,
    required this.faithTradition,
    this.scriptureSources = const [],
    required this.dateSaved,
  });

  /// Create from Parable
  factory Favorite.fromParable(Parable parable) {
    return Favorite(
      storyId: parable.storyId,
      title: parable.title,
      mood: parable.mood,
      length: parable.length,
      faithTradition: parable.faithTradition,
      scriptureSources: parable.scriptureSources,
      dateSaved: DateTime.now(),
    );
  }

  /// Create from JSON
  factory Favorite.fromJson(Map<String, dynamic> json) {
    return Favorite(
      storyId: json['storyId'] as String,
      title: json['title'] as String,
      mood: json['mood'] as String,
      length: json['length'] as int,
      faithTradition: json['faithTradition'] as String,
      scriptureSources: (json['scriptureSources'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      dateSaved: DateTime.parse(json['dateSaved'] as String),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'storyId': storyId,
      'title': title,
      'mood': mood,
      'length': length,
      'faithTradition': faithTradition,
      'scriptureSources': scriptureSources,
      'dateSaved': dateSaved.toIso8601String(),
    };
  }

  /// Create a copy with modified fields (for title edits)
  Favorite copyWith({
    String? storyId,
    String? title,
    String? mood,
    int? length,
    String? faithTradition,
    List<String>? scriptureSources,
    DateTime? dateSaved,
  }) {
    return Favorite(
      storyId: storyId ?? this.storyId,
      title: title ?? this.title,
      mood: mood ?? this.mood,
      length: length ?? this.length,
      faithTradition: faithTradition ?? this.faithTradition,
      scriptureSources: scriptureSources ?? this.scriptureSources,
      dateSaved: dateSaved ?? this.dateSaved,
    );
  }
}
