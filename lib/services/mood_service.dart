import 'dart:math';

/// Mood Detection Service
/// Based on SPEC.md Feature #2: Mood Detection Flow
/// Analyzes user input text to detect emotional state
class MoodService {
  final Random _random;

  MoodService({Random? random}) : _random = random ?? Random();
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
    final replies = _compassionateReplies[moodResult.mood] ??
        _compassionateReplies['neutral']!;
    return replies[_random.nextInt(replies.length)];
  }

  static const Map<String, List<String>> _compassionateReplies = {
    'joyful': [
      "That's wonderful to hear! Your joy is a gift. Let's explore a story that celebrates this moment.",
      "I love that! Joy like yours is contagious. I have a story that matches your spirit.",
      "What a blessing! Let's carry that joy into a story of gratitude together.",
      "That makes me so glad to hear. Let's celebrate with a story that lifts the heart.",
      "Your happiness shines through! I know just the story for a moment like this.",
      "How beautiful! Let's hold onto that feeling with a story of thankfulness.",
    ],
    'weary': [
      "I hear that you're feeling weary. Rest is sacred. Let's find a story that offers you comfort and renewal.",
      "It sounds like you've been carrying a lot. Let me share a story about finding rest.",
      "Weariness is real, and it's okay to feel it. I have a gentle story for you tonight.",
      "You've been giving so much of yourself. Let's slow down together with a story of renewal.",
      "I understand that tiredness. Let me bring you a story that feels like a deep breath.",
      "Being weary doesn't mean you're weak. Let's rest together in a story of comfort.",
    ],
    'anxious': [
      "I understand that things feel overwhelming right now. You're not alone. Let's journey together through a story of peace.",
      "Worry can feel so heavy. Let me share a story that reminds us where peace comes from.",
      "I hear you. Those anxious feelings are real. I have a story that brings calm.",
      "You don't have to carry that worry alone. Let's breathe together through a story of trust.",
      "It's okay to feel unsettled. Let me bring you a story about finding stillness.",
      "I'm right here with you. Let's quiet those worries with a story of hope and peace.",
    ],
    'hurting': [
      "I'm so sorry you're going through this pain. Your feelings are valid. Let me share a story that holds space for healing.",
      "My heart goes out to you. Let me bring you a story that speaks to that tender place.",
      "Pain like that deserves to be heard. I have a story about finding light in the darkness.",
      "I wish I could take that hurt away. Let's sit together with a story of healing and hope.",
      "You don't have to face this alone. Let me share a story that wraps around you like a comfort.",
      "That sounds really hard. I'm here, and I have a story that gently holds space for what you're feeling.",
    ],
    'neutral': [
      "Thank you for sharing. Let's spend this time together with a meaningful story.",
      "I'm glad you're here. Let me find a story that speaks to where you are right now.",
      "Good to have you. I have a story I think you'll really enjoy.",
      "Thanks for checking in. Let's make this moment count with a great story.",
      "I'm happy you stopped by. Let me share something meaningful with you.",
      "Welcome! I've got a story ready that I think will really resonate.",
    ],
  };

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
