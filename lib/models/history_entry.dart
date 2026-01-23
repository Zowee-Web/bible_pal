import 'parable.dart';
import '../core/story_length_bucket.dart';

/// History Entry model - represents a parable the user has listened to
/// Based on SPEC.md Feature #10: History System (Last 20 entries, FIFO)
class HistoryEntry {
  final String storyId;
  final String title;
  final String mood;
  final int length;
  final List<String> scriptureSources;
  final DateTime timestamp;

  const HistoryEntry({
    required this.storyId,
    required this.title,
    required this.mood,
    required this.length,
    this.scriptureSources = const [],
    required this.timestamp,
  });

  /// Create from Parable
  factory HistoryEntry.fromParable(Parable parable) {
    return HistoryEntry(
      storyId: parable.storyId,
      title: parable.title,
      mood: parable.mood,
      length: parable.length,
      scriptureSources: parable.scriptureSources,
      timestamp: DateTime.now(),
    );
  }

  /// Create from JSON
  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      storyId: json['storyId'] as String,
      title: json['title'] as String,
      mood: json['mood'] as String,
      length: json['length'] as int,
      scriptureSources: (json['scriptureSources'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'storyId': storyId,
      'title': title,
      'mood': mood,
      'length': length,
      'scriptureSources': scriptureSources,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Get length bucket for display (computed from legacy minute-based length)
  StoryLengthBucket get lengthBucket => lengthMinutesToBucket(length);
}
