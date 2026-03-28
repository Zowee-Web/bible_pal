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
        mood: 'calm_peaceful',
        emotionalTags: [],
        confidenceScore: 0.5,
      );
    }

    // Check for grateful/thankful indicators (before joyful — more specific)
    if (_containsAny(normalizedText, [
      'grateful', 'thankful', 'blessed', 'appreciated', 'thankfulness',
      'gratitude', 'thank god', 'thank the lord', 'counting blessings',
      'so blessed', 'truly blessed',
    ])) {
      return MoodResult(
        mood: 'grateful',
        emotionalTags: _extractTags(normalizedText, [
          'grateful', 'thankful', 'blessed', 'appreciated', 'gratitude',
        ]),
        confidenceScore: 0.85,
      );
    }

    // Check for joyful/positive indicators
    // Note: 'peaceful', 'encouraged', 'inspired' removed — they belong to calm_peaceful/encouraging
    if (_containsAny(normalizedText, [
      'good', 'great', 'wonderful',
      'amazing', 'joyful', 'happy', 'excited',
      'hopeful', 'praise', 'joy', 'content', 'fulfilled', 'cheerful',
      'uplifted', 'optimistic', 'relieved', 'celebration',
      'celebrate', 'thriving', 'fantastic', 'awesome', 'loving',
      'confident', 'proud', 'victorious', 'free',
    ])) {
      return MoodResult(
        mood: 'joyful',
        emotionalTags: _extractTags(normalizedText, [
          'joyful',
          'happy', 'hopeful', 'relieved',
          'confident', 'proud', 'fulfilled',
        ]),
        confidenceScore: 0.8,
      );
    }

    // Check for weary/tired indicators
    if (_containsAny(normalizedText, [
      'tired', 'exhausted', 'weary', 'drained', 'worn', 'fatigued',
      'overwhelmed', 'burnt out', 'burnout', 'running on empty',
      'no energy', 'wiped out', 'beat', 'spent', 'run down',
      'stretched thin', 'can barely', 'so much going on',
      'nonstop', 'never ends', 'carrying a lot', 'heavy load',
      'worn out', 'burned out', 'sleepless', 'restless',
    ])) {
      return MoodResult(
        mood: 'weary',
        emotionalTags: _extractTags(normalizedText, [
          'tired', 'exhausted', 'weary', 'drained', 'overwhelmed',
          'fatigued', 'restless',
        ]),
        confidenceScore: 0.75,
      );
    }

    // Check for anxious/stressed indicators
    if (_containsAny(normalizedText, [
      'stressed', 'anxious', 'worried', 'nervous', 'afraid', 'scared',
      'tense', 'pressure', 'overwhelmed', 'panic', 'fear', 'fearful',
      'uneasy', 'on edge', 'can\'t relax', 'racing thoughts',
      'overthinking', 'restless', 'apprehensive', 'dreading', 'dread',
      'uncertain', 'unsettled', 'shaking', 'frantic', 'freaking out',
      'losing my mind', 'spiraling', 'what if', 'terrified',
      'keep thinking about', 'can\'t stop thinking',
    ])) {
      return MoodResult(
        mood: 'anxious',
        emotionalTags: _extractTags(normalizedText, [
          'stressed', 'anxious', 'worried', 'nervous', 'afraid',
          'tense', 'fearful', 'overwhelmed', 'overthinking',
        ]),
        confidenceScore: 0.8,
      );
    }

    // Check for hurting/sad indicators
    if (_containsAny(normalizedText, [
      'sad', 'hurt', 'hurting', 'pain', 'lonely', 'alone',
      'discouraged', 'down', 'upset', 'heartbroken', 'broken',
      'depressed', 'grieving', 'loss', 'lost', 'cry', 'crying',
      'tears', 'empty', 'numb', 'hopeless', 'worthless', 'rejected',
      'abandoned', 'betrayed', 'miserable', 'suffering', 'aching',
      'devastated', 'crushed', 'let down', 'disappointed',
      'miss them', 'miss him', 'miss her', 'passed away', 'died',
      'struggling', 'falling apart', 'giving up',
    ])) {
      return MoodResult(
        mood: 'hurting',
        emotionalTags: _extractTags(normalizedText, [
          'sad', 'hurt', 'lonely', 'discouraged', 'heartbroken',
          'grieving', 'hopeless', 'rejected', 'empty', 'betrayed',
        ]),
        confidenceScore: 0.85,
      );
    }

    // Check for brave/courageous indicators
    if (_containsAny(normalizedText, [
      'brave', 'courage', 'courageous', 'strong', 'strength', 'bold',
      'determined', 'facing', 'stand up', 'standing firm', 'fight',
      'fighting', 'warrior', 'fearless', 'overcoming', 'overcome',
      'conquer', 'resilient', 'tough', 'persevere', 'endure',
      'never give up', 'push through', 'stepping out', 'taking a stand',
    ])) {
      return MoodResult(
        mood: 'brave_courage',
        emotionalTags: _extractTags(normalizedText, [
          'brave', 'courage', 'strong', 'determined', 'bold',
          'fearless', 'resilient', 'persevere',
        ]),
        confidenceScore: 0.8,
      );
    }

    // Check for calm/peaceful indicators
    if (_containsAny(normalizedText, [
      'calm', 'peaceful', 'peace', 'serene', 'quiet', 'still',
      'at ease', 'relaxed', 'resting', 'tranquil', 'centered',
      'grounded', 'settled', 'steady', 'balanced', 'present',
      'mindful', 'unhurried', 'gentle', 'soft',
    ])) {
      return MoodResult(
        mood: 'calm_peaceful',
        emotionalTags: _extractTags(normalizedText, [
          'calm', 'peaceful', 'serene', 'quiet', 'relaxed',
          'tranquil', 'centered', 'grounded',
        ]),
        confidenceScore: 0.8,
      );
    }

    // Check for encouraging/motivated indicators
    if (_containsAny(normalizedText, [
      'encouraged', 'motivated', 'ready', 'pumped', 'energized',
      'fired up', 'inspired', 'driven', 'eager', 'looking forward',
      'can do', 'let\'s go', 'bring it on', 'feeling good about',
      'on track', 'making progress', 'getting better', 'growing',
    ])) {
      return MoodResult(
        mood: 'encouraging',
        emotionalTags: _extractTags(normalizedText, [
          'encouraged', 'motivated', 'ready', 'inspired',
          'energized', 'driven', 'eager',
        ]),
        confidenceScore: 0.75,
      );
    }

    // Default to calm_peaceful (gentler default than "neutral")
    return const MoodResult(
      mood: 'calm_peaceful',
      emotionalTags: [],
      confidenceScore: 0.5,
    );
  }

  /// Get a micro-response text for the given mood (text-only fallback).
  /// Used when PAL audio is disabled (palGreetingsEnabled == false).
  String getMicroResponseText(String mood) {
    final responses = _microResponses[mood] ?? _microResponses['calm_peaceful']!;
    return responses[_random.nextInt(responses.length)];
  }

  /// Micro-response fallback text (≤ 12 words each).
  /// These match the content in pal_lines.json microResponses.
  static const Map<String, List<String>> _microResponses = {
    'joyful': [
      "That's beautiful. I'll share a story that matches it.",
      "Your joy matters. Let's listen to something uplifting.",
      "Praise God. Here's a story to strengthen that light.",
      "I'm glad for you. Let's hear something hopeful.",
      "That's a gift. I'll play a joyful story.",
    ],
    'grateful': [
      "What a beautiful heart. I'll share something thankful.",
      "Gratitude is a gift. Let's hear something beautiful.",
      "That thankfulness shines. Here's a story to hold it.",
      "I love hearing that. Let's listen to something warm.",
      "A grateful heart sees clearly. I have a story for you.",
    ],
    'weary': [
      "That sounds tiring. I'll share something steady for you.",
      "You've carried a lot. Let's rest in a story.",
      "I hear that. I'll play something strengthening now.",
      "It's okay to be weary. Here's something gentle.",
      "You're not alone in this. Let's listen together.",
    ],
    'anxious': [
      "I hear the worry. Let's settle with something grounding.",
      "That's a lot to carry. Let's listen to something steady.",
      "It's okay. Let's slow down with a steady story.",
      "I'm here with you. Let's listen and breathe.",
      "Let's quiet the noise. I'll share something peaceful.",
    ],
    'hurting': [
      "I'm so sorry. You're not alone\u2014listen with me.",
      "That pain matters. I'll play something gentle now.",
      "I'm here. Let's hold this quietly with a story.",
      "God sees you. I'll share comfort through a story.",
      "You don't have to carry this alone. Let's listen.",
    ],
    'brave_courage': [
      "That takes real strength. I have a story for you.",
      "Courage like that matters. Let's hear something bold.",
      "Stand firm. I'll share a story of strength.",
      "I see your courage. Here's something to fuel it.",
      "You're braver than you know. Let's listen together.",
    ],
    'calm_peaceful': [
      "What a good place to be. I'll share something gentle.",
      "Peace is a gift. I'll play something quiet for you.",
      "I'm with you. Let's listen to something peaceful.",
      "Let's take a moment. I'll play a calm story.",
      "That stillness matters. Here's a story to rest in.",
    ],
    'encouraging': [
      "I love that energy. Let's hear something uplifting.",
      "That's the spirit. I have something uplifting for you.",
      "Keep going. I'll share a story to fuel that fire.",
      "You're on the right path. Let's hear something strong.",
      "That determination shines. Here's a story to match it.",
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
  final String mood; // 'joyful', 'grateful', 'weary', 'anxious', 'hurting', 'brave_courage', 'calm_peaceful', 'encouraging'
  final List<String> emotionalTags;
  final double confidenceScore; // 0.0 to 1.0

  const MoodResult({
    required this.mood,
    required this.emotionalTags,
    required this.confidenceScore,
  });
}
