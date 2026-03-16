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
      'grateful', 'thankful', 'blessed', 'good', 'great', 'wonderful',
      'amazing', 'encouraged', 'joyful', 'happy', 'excited', 'peaceful',
      'hopeful', 'praise', 'joy', 'content', 'fulfilled', 'cheerful',
      'uplifted', 'inspired', 'optimistic', 'relieved', 'celebration',
      'celebrate', 'thriving', 'fantastic', 'awesome', 'loving',
      'appreciated', 'confident', 'proud', 'victorious', 'free',
    ])) {
      return MoodResult(
        mood: 'joyful',
        emotionalTags: _extractTags(normalizedText, [
          'grateful', 'thankful', 'blessed', 'encouraged', 'joyful',
          'happy', 'peaceful', 'hopeful', 'inspired', 'relieved',
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

    // Default to neutral
    return const MoodResult(
      mood: 'neutral',
      emotionalTags: [],
      confidenceScore: 0.6,
    );
  }

  /// Get a micro-response text for the given mood (text-only fallback).
  /// Used when PAL audio is disabled (palGreetingsEnabled == false).
  String getMicroResponseText(String mood) {
    final responses = _microResponses[mood] ?? _microResponses['neutral']!;
    return responses[_random.nextInt(responses.length)];
  }

  /// Micro-response fallback text (≤ 12 words each).
  /// These match the content in pal_lines.json microResponses.
  static const Map<String, List<String>> _microResponses = {
    'joyful': [
      "I'm grateful to hear that. Let's lean into that joy.",
      "That's beautiful. I'll share a story that matches it.",
      "Your joy matters. Let's listen to something uplifting.",
      "Praise God. Here's a story to strengthen that light.",
      "I'm glad for you. Let's hear something hopeful.",
      "That's a gift. I'll play a joyful story.",
    ],
    'weary': [
      "That sounds tiring. I'll share something steady for you.",
      "You've carried a lot. Let's rest in a story.",
      "I hear that. I'll play something strengthening now.",
      "It's okay to be weary. Here's something gentle.",
      "You're not alone in this. Let's listen together.",
      "Let's breathe. I'll play a steady story.",
    ],
    'anxious': [
      "I hear the worry. Let's settle with something grounding.",
      "That's a lot to carry. Let's listen to something steady.",
      "It's okay. Let's slow down with a steady story.",
      "I'm here with you. Let's listen and breathe.",
      "Let's quiet the noise. I'll share something peaceful.",
      "We'll take this moment gently. Here's a calm story.",
    ],
    'hurting': [
      "I'm so sorry. You're not alone\u2014listen with me.",
      "That pain matters. I'll play something gentle now.",
      "I'm here. Let's hold this quietly with a story.",
      "God sees you. I'll share comfort through a story.",
      "You don't have to carry this alone. Let's listen.",
      "I hear you. I'll play a tender story now.",
    ],
    'neutral': [
      "Thank you for sharing. I'll play a fitting story.",
      "I'm with you. Let's listen to something steady.",
      "I hear you. I'll choose something wise for you.",
      "Let's take a moment\u2026 I'll play a calm story.",
      "Thanks for saying that. I'll share something steady.",
      "Alright. I'll play a story that meets you here.",
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
