// PAL Voice Registry
// Defines the 4 selectable voices for PAL's conversational audio.
// Keys match the canonical voice pool in server/voices.json.

class PalVoice {
  final String voiceKey;
  final String displayName;
  final String description;
  final String gender;

  const PalVoice({
    required this.voiceKey,
    required this.displayName,
    required this.description,
    required this.gender,
  });
}

class PalVoiceRegistry {
  PalVoiceRegistry._();

  static const String defaultVoiceKey = 'VOICE_SARAH_STORYTELLER';

  static const List<PalVoice> voices = [
    PalVoice(
      voiceKey: 'VOICE_SARAH_STORYTELLER',
      displayName: 'Sarah',
      description: 'Warm and nurturing',
      gender: 'female',
    ),
    PalVoice(
      voiceKey: 'VOICE_HANNAH_HOPE',
      displayName: 'Hannah',
      description: 'Bright and encouraging',
      gender: 'female',
    ),
    PalVoice(
      voiceKey: 'VOICE_JAMES_HUSKY',
      displayName: 'James',
      description: 'Calm and reflective',
      gender: 'male',
    ),
    PalVoice(
      voiceKey: 'VOICE_DAVID_SHEPHERD',
      displayName: 'David',
      description: 'Warm and protective',
      gender: 'male',
    ),
  ];

  /// Look up a voice by key. Returns default if not found.
  static PalVoice getVoice(String? key) {
    if (key == null) return voices.first;
    return voices.firstWhere(
      (v) => v.voiceKey == key,
      orElse: () => voices.first,
    );
  }

  /// Check if a voice key is valid.
  static bool isValid(String key) {
    return voices.any((v) => v.voiceKey == key);
  }
}
