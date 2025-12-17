/// Mood Detection Service
/// Based on SPEC.md Feature #2: Mood Detection Flow
/// Analyzes user input text to detect emotional state
class MoodService {
  /// Detect mood from user's text input
  /// Returns mood category and emotional tags
  MoodResult detectMood(String text) {
    final normalizedText = text.toLowerCase().trim();

    if (normalizedText.isEmpty) {
      return const MoodResult(
        mood: 'neutral',
        emotionalTags: [],
        confidenceScore: 0.5,
      );
    }

    // Check for joyful/positive indicators
    if (_containsAny(normalizedText, [
      'grateful',
      'thankful',
      'blessed',
      'good',
      'great',
      'wonderful',
      'amazing',
      'encouraged',
      'joyful',
      'happy',
      'excited',
      'peaceful',
      'hopeful',
    ])) {
      return MoodResult(
        mood: 'joyful',
        emotionalTags: _extractTags(normalizedText, [
          'grateful',
          'thankful',
          'blessed',
          'encouraged',
          'joyful',
          'happy',
          'peaceful',
          'hopeful',
        ]),
        confidenceScore: 0.8,
      );
    }

    // Check for weary/tired indicators
    if (_containsAny(normalizedText, [
      'tired',
      'exhausted',
      'weary',
      'drained',
      'worn',
      'fatigued',
      'overwhelmed',
      'burnt out',
      'burnout',
    ])) {
      return MoodResult(
        mood: 'weary',
        emotionalTags: _extractTags(normalizedText, [
          'tired',
          'exhausted',
          'weary',
          'drained',
          'overwhelmed',
        ]),
        confidenceScore: 0.75,
      );
    }

    // Check for anxious/stressed indicators
    if (_containsAny(normalizedText, [
      'stressed',
      'anxious',
      'worried',
      'nervous',
      'afraid',
      'scared',
      'tense',
      'pressure',
      'overwhelmed',
      'panic',
    ])) {
      return MoodResult(
        mood: 'anxious',
        emotionalTags: _extractTags(normalizedText, [
          'stressed',
          'anxious',
          'worried',
          'nervous',
          'afraid',
          'tense',
        ]),
        confidenceScore: 0.8,
      );
    }

    // Check for hurting/sad indicators
    if (_containsAny(normalizedText, [
      'sad',
      'hurt',
      'hurting',
      'pain',
      'lonely',
      'alone',
      'discouraged',
      'down',
      'upset',
      'heartbroken',
      'broken',
      'depressed',
      'grieving',
      'loss',
    ])) {
      return MoodResult(
        mood: 'hurting',
        emotionalTags: _extractTags(normalizedText, [
          'sad',
          'hurt',
          'lonely',
          'discouraged',
          'heartbroken',
          'grieving',
        ]),
        confidenceScore: 0.85,
      );
    }

    // Default to neutral
    return const MoodResult(
      mood: 'neutral',
      emotionalTags: [],
      confidenceScore: 0.6,
    );
  }

  /// Generate a compassionate reply based on detected mood
  /// Per SPEC.md Feature #3: Compassionate Reply System
  String generateCompassionateReply(MoodResult moodResult) {
    switch (moodResult.mood) {
      case 'joyful':
        return "That's wonderful to hear! Your joy is a gift. Let's explore a story that celebrates this moment.";

      case 'weary':
        return "I hear that you're feeling weary. Rest is sacred. Let's find a story that offers you comfort and renewal.";

      case 'anxious':
        return "I understand that things feel overwhelming right now. You're not alone. Let's journey together through a story of peace.";

      case 'hurting':
        return "I'm so sorry you're going through this pain. Your feelings are valid. Let me share a story that holds space for healing.";

      case 'neutral':
      default:
        return "Thank you for sharing. Let's spend this time together with a meaningful story.";
    }
  }

  /// Check if text contains any of the given keywords
  bool _containsAny(String text, List<String> keywords) {
    return keywords.any((keyword) => text.contains(keyword));
  }

  /// Extract emotional tags that are present in the text
  List<String> _extractTags(String text, List<String> possibleTags) {
    return possibleTags.where((tag) => text.contains(tag)).toList();
  }
}

/// Result of mood detection
class MoodResult {
  final String mood; // 'joyful', 'weary', 'anxious', 'hurting', 'neutral'
  final List<String> emotionalTags;
  final double confidenceScore; // 0.0 to 1.0

  const MoodResult({
    required this.mood,
    required this.emotionalTags,
    required this.confidenceScore,
  });
}
