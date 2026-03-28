/// A single reflection journal entry tied to a story listen.
class JournalEntry {
  final String id;
  final String storyId;
  final String storyTitle;
  final String mood;
  final String note; // User's one-line reflection
  final DateTime createdAt;

  const JournalEntry({
    required this.id,
    required this.storyId,
    required this.storyTitle,
    required this.mood,
    required this.note,
    required this.createdAt,
  });

  factory JournalEntry.fromJson(Map<String, dynamic> json) {
    return JournalEntry(
      id: json['id'] as String,
      storyId: json['storyId'] as String,
      storyTitle: json['storyTitle'] as String? ?? '',
      mood: json['mood'] as String? ?? '',
      note: json['note'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'storyId': storyId,
        'storyTitle': storyTitle,
        'mood': mood,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
      };
}
