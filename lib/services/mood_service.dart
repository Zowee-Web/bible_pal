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
    final lowered = text.toLowerCase().trim();

    if (lowered.isEmpty) {
      return const MoodResult(
        mood: 'calm_peaceful',
        emotionalTags: [],
        confidenceScore: 0.5,
      );
    }

    // Mask "not <positive>" so "not happy" / "not great" don't classify
    // as joyful via raw keyword presence. See [_maskNegatedPositives].
    final normalizedText = _maskNegatedPositives(lowered);

    // Check for grateful/thankful indicators (before joyful — more specific)
    if (_containsAny(normalizedText, [
      'grateful', 'thankful', 'blessed', 'appreciated', 'thankfulness',
      'gratitude', 'thank god', 'thank the lord', 'counting blessings',
      'so blessed', 'truly blessed',
      // Common bare verb/noun forms that boundary-matching otherwise misses
      // (e.g. `\bblessed\b` won't match "blessing"; `\bappreciated\b` won't
      // match "appreciate").
      'thanks', 'thank you', 'blessing', 'blessings',
      'appreciate', 'appreciative',
      // Direct gratitude synonyms missing from the original list.
      'fortunate', 'lucky', 'honored',
    ])) {
      return MoodResult(
        mood: 'grateful',
        emotionalTags: _extractTags(normalizedText, [
          'grateful', 'thankful', 'blessed', 'appreciated', 'gratitude',
        ]),
        confidenceScore: 0.85,
      );
    }

    // Calm-resolution phrases must beat the bare `down` / `low`
    // keywords in the hurting list later in the chain. "calmed down" /
    // "settled down" express resolution, not hurting; "low key"
    // expresses an unhurried day.
    if (_containsAny(normalizedText, [
      'calmed down', 'calming down', 'settled down', 'winding down',
      'low key',
    ])) {
      return const MoodResult(
        mood: 'calm_peaceful',
        emotionalTags: [],
        confidenceScore: 0.7,
      );
    }

    // Brave-resolution phrases — same shape as the calm pre-check above.
    // "won't back down" / "never back down" contain `down`, which would
    // otherwise match the hurting list before the brave_courage list
    // gets its turn. "no fear" contains `fear`, which would otherwise
    // match the anxious list (which runs before brave_courage).
    if (_containsAny(normalizedText, [
      'won\'t back down', 'never back down', 'no fear',
    ])) {
      return const MoodResult(
        mood: 'brave_courage',
        emotionalTags: ['determined'],
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
      // Positive superlatives — short replies like "Excellent" or "Perfect"
      // must route to joyful, never the weary fallback.
      'excellent', 'perfect', 'splendid', 'incredible', 'terrific',
      'lovely', 'fabulous', 'marvelous',
      // Common positive synonyms that miss the keyword list above and
      // would otherwise default to calm_peaceful.
      'thrilled', 'delighted', 'elated', 'ecstatic', 'glad', 'pleased',
      // Excited-slang + strong positive markers.
      'stoked', 'psyched', 'best day',
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
      'heavy', 'hard week', 'hard day', 'long week', 'long day',
      'rough week', 'rough day', 'difficult', 'too much',
      'tough day', 'tough week',
      // Common tired-state synonyms missed by the list above.
      // 'exhausted' and 'drained' are already present.
      'sleepy', 'groggy', 'exhausting', 'pooped',
      // Workload/overwhelm shorthand. `\bbusy\b` won't match "business"
      // (different letters); covers "busy day", "very busy", "so busy".
      'busy', 'swamped',
      // Bare slang + sleep-deprivation phrases.
      'wiped', 'frazzled', 'dragging',
      'can\'t sleep', 'couldn\'t sleep',
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
      'stressed', 'stress', 'stressing', 'anxious', 'worried', 'worrying',
      'nervous', 'afraid', 'scared',
      'tense', 'pressure', 'overwhelmed', 'panic', 'fear', 'fearful',
      'uneasy', 'on edge', 'can\'t relax', 'racing thoughts', 'racing',
      'overthinking', 'restless', 'apprehensive', 'dreading', 'dread',
      'uncertain', 'unsettled', 'shaking', 'frantic', 'freaking out',
      'losing my mind', 'spiraling', 'what if', 'terrified',
      'keep thinking about', 'can\'t stop thinking',
      'can\'t stop worrying', 'won\'t stop',
      // Short anxious synonyms that miss the list above.
      'antsy', 'jittery', 'uptight',
      // Physical-tension markers + adverbial form of "freaking out".
      'wound up', 'wired', 'freaking',
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
      'hard time', 'rough time', 'going through',
      // Short sadness synonyms that miss the list above.
      // 'aching' is already present.
      'heartache', 'blue', 'low', 'mourning',
      // Negated-positive shorthand that boundary matching otherwise
      // sends to the calm_peaceful default. 'unhappy' is the most
      // common form; it must route to a sad mood, not to calm.
      'unhappy',
      // Strong-negative markers + "off / unwell" phrasing.
      'bummed', 'terrible', 'awful', 'horrible', 'not myself',
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
      // Short brave declarations that miss the list above.
      // 'fearless' is already present (and word-boundary matching means
      // it now correctly routes to brave instead of being shadowed by
      // the substring 'fear' in the anxious list).
      'i got this', 'won\'t back down', 'face it',
      // Confident-self statements. 'no fear' also lives in the
      // brave-resolution pre-check above so it wins over anxious 'fear'.
      'won\'t quit', 'no fear', 'i\'ll handle it',
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
      // Calm-day shorthand. `\bchill\b` does not match "chilly" or
      // "chilling" (no boundary after `chill` when followed by `y`/`i`).
      'chill', 'low key',
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
      // Short can-do declarations missed by the list above. 'i can' was
      // intentionally NOT added — `\bi can\b` matches "i can't" (the
      // apostrophe is a word boundary), recreating the exact false-positive
      // class this fix exists to remove. 'can do' already covers the
      // legitimate "I can do this" usage.
      'go for it', 'got this', 'let\'s do this',
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

    // Default to calm_peaceful for unrecognized non-empty input.
    // INVARIANTS.md (Mood System) requires the safe default to be
    // calm_peaceful, never weary — otherwise short positive replies
    // ("Excellent", "Perfect") that miss the keyword list misroute
    // straight into suffering content like "Job Loses Everything".
    return const MoodResult(
      mood: 'calm_peaceful',
      emotionalTags: [],
      confidenceScore: 0.4,
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

  /// Word-boundary keyword match. Prevents substring collisions like
  /// "painting" matching the keyword `pain` or "already" matching `ready`.
  /// Multi-word phrases (`thank you`, `worn out`, `i got this`) work
  /// unchanged — only the outer edges need boundaries; the spaces inside
  /// the literal are still required to appear.
  bool _containsAny(String text, List<String> keywords) {
    return keywords.any((keyword) {
      return RegExp(r'\b' + _escapeRegex(keyword) + r'\b').hasMatch(text);
    });
  }

  /// Extract emotional tags that are present in the text. Same
  /// word-boundary semantics as [_containsAny] — keeps tag extraction in
  /// lockstep with classification so a tag never appears for a phrase
  /// that didn't actually trigger its mood.
  List<String> _extractTags(String text, List<String> possibleTags) {
    return possibleTags.where((tag) {
      return RegExp(r'\b' + _escapeRegex(tag) + r'\b').hasMatch(text);
    }).toList();
  }

  /// Escape regex metacharacters so a keyword is matched as a literal.
  /// Current keyword set has none, but this guards future additions.
  String _escapeRegex(String s) {
    return s.replaceAllMapped(
      RegExp(r'[\\^$.|?*+()\[\]{}]'),
      (m) => '\\${m[0]}',
    );
  }

  /// Substitute "not <positive>" patterns with the marker token
  /// "unhappy" before keyword matching. This routes phrases like
  /// "not happy" / "not great" / "not good" into the hurting mood
  /// (where 'unhappy' is a keyword), instead of dropping the phrase
  /// to the calm_peaceful default — which produced inappropriate
  /// calm/positive PAL responses to negative input.
  ///
  /// Optional `(?:doing\s+)?` bridge catches the common "not doing
  /// well" / "not doing great" form. Token list also includes
  /// `well` / `alright` so plain "not well" / "not alright" route
  /// to hurting too.
  ///
  /// Narrow scope: only the bare "not <positive>" form. Richer
  /// negation handling (e.g. "I don't feel great", "wasn't really
  /// happy") is a separate, harder problem and remains out of scope.
  String _maskNegatedPositives(String text) {
    return text.replaceAll(
      RegExp(
        r'\bnot\s+(?:doing\s+)?(?:happy|good|great|okay|ok|fine|joyful|'
        r'blessed|excited|amazing|wonderful|fantastic|awesome|excellent|'
        r'perfect|grateful|thrilled|delighted|elated|ecstatic|glad|'
        r'pleased|well|alright|lucky)\b',
      ),
      'unhappy',
    );
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
