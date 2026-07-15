// PAL Voice Registry
// Defines the selectable voices for PAL's conversational audio.
// Keys match the canonical voice pool in server/voices.json.

class PalVoice {
  final String voiceKey;
  final String displayName;
  final String emoji;
  final String description;
  final String gender;
  final String elevenLabsId;

  const PalVoice({
    required this.voiceKey,
    required this.displayName,
    required this.emoji,
    required this.description,
    required this.gender,
    required this.elevenLabsId,
  });
}

class PalVoiceRegistry {
  PalVoiceRegistry._();

  /// Default PAL voice. Switched HOPE → STILLWATER 2026-06-27 to align
  /// with PAL Memory Slice 2d: Stillwater is the only voice with
  /// rendered memory clips (PRs #37–#40), so any new install on the
  /// prior default (HOPE) would silently never hear a memory line
  /// because the audio resolver gate would close on missing clips.
  /// Stillwater has equivalent PAL greeting/reflection coverage
  /// (~520 clips vs HOPE's 521), so the switch is acoustically
  /// transparent for cold-open greetings. Existing users with
  /// explicitly-persisted `palVoiceKey` (including HOPE) keep their
  /// choice — `migrateVoiceKey` only rewrites legacy/unknown keys.
  static const String defaultVoiceKey = 'VOICE_STILLWATER';

  /// Old voice keys that should be migrated to the default.
  /// - VOICE_GRACE was retired 2026-04-23 — audio archived to
  ///   `assets/pal/audio_archive_grace_2026_04_23/` (not bundled).
  /// - VOICE_RUTH_COMFORT was retired 2026-04-25 — audio archived to
  ///   `assets/pal/audio_archive_ruth_v1_2026_04_25/` (not bundled).
  ///   Will be rebuilt as Ruth v2 from the archived source audio.
  /// Existing users on any of these keys migrate to the current
  /// default ([defaultVoiceKey]) on next launch via `migrateVoiceKey`.
  static const List<String> _legacyVoiceKeys = [
    'VOICE_SARAH_STORYTELLER',
    'VOICE_HANNAH_HOPE',
    'VOICE_JAMES_HUSKY',
    'VOICE_DAVID_SHEPHERD',
    'VOICE_GRACE',
    'VOICE_RUTH_COMFORT',
  ];

  // Default voice declared above as [defaultVoiceKey]. Ruth v1 was
  // retired 2026-04-25; existing users on VOICE_RUTH_COMFORT migrate
  // to the current default on next launch via `migrateVoiceKey`
  // (Ruth is in `_legacyVoiceKeys`). Ruth's audio is preserved at
  // `assets/pal/audio_archive_ruth_v1_2026_04_25/` for future
  // rebuild as Ruth v2.
  static const List<PalVoice> voices = [
    PalVoice(
      voiceKey: 'VOICE_HOPE',
      displayName: 'Hope',
      emoji: '\u{2600}\u{FE0F}', // ☀️
      description: 'Bright encouragement',
      gender: 'female',
      elevenLabsId: 'qBDvhofpxp92JgXJxDjB',
    ),
    PalVoice(
      voiceKey: 'VOICE_SHEPHERD',
      displayName: 'Shepherd',
      emoji: '\u{1F4D6}', // 📖
      description: 'Wise storyteller',
      gender: 'male',
      elevenLabsId: 'EkK5I93UQWFDigLMpZcX',
    ),
    PalVoice(
      voiceKey: 'VOICE_STILLWATER',
      displayName: 'Stillwater',
      emoji: '\u{1F319}', // 🌙
      description: 'Calm companion',
      gender: 'male',
      elevenLabsId: 'uju3wxzG5OhpWcoi3SMy',
    ),
  ];

  /// Voices registered but not yet selectable. A staged voice has an
  /// approved persona and ElevenLabs source but no rendered PAL audio
  /// library; it is excluded from [voices], so it never appears in the
  /// Settings picker, never validates via [isValid], and a persisted
  /// key would migrate to the default like any unknown key. When its
  /// full live audio surface is rendered and passes the PAL_VOICE.md
  /// audit, the entry moves to [voices] (see SPEC 17b, ADR-029).
  ///
  /// - VOICE_MIRIAM (added 2026-07-14): balances the roster to
  ///   2 male / 2 female. Shares an ElevenLabs source voice with story
  ///   narrator VOICE_MIRIAM_JOYFUL — owner-approved exception to the
  ///   PAL/narrator separation; the two systems keep distinct keys.
  static const List<PalVoice> stagedVoices = [
    PalVoice(
      voiceKey: 'VOICE_MIRIAM',
      displayName: 'Miriam',
      emoji: '\u{1F33B}', // 🌻
      description: 'Joyful spirit',
      gender: 'female',
      elevenLabsId: 'XrExE9yKIg1WjnnlVkGX',
    ),
  ];

  /// Look up a voice by key. Returns the default voice when [key] is
  /// null or not found — explicitly resolved via [defaultVoiceKey]
  /// rather than `voices.first` so the display order in Settings can
  /// be reordered without changing default-voice behavior.
  static PalVoice getVoice(String? key) {
    final lookupKey = key ?? defaultVoiceKey;
    return voices.firstWhere(
      (v) => v.voiceKey == lookupKey,
      orElse: () => voices.firstWhere(
        (v) => v.voiceKey == defaultVoiceKey,
      ),
    );
  }

  /// Check if a voice key is valid.
  static bool isValid(String key) {
    return voices.any((v) => v.voiceKey == key);
  }

  /// Check if a voice key is a legacy key that needs migration.
  static bool isLegacyKey(String key) {
    return _legacyVoiceKeys.contains(key);
  }

  /// Migrate a voice key: if legacy, return default; otherwise return as-is.
  static String migrateVoiceKey(String key) {
    if (isLegacyKey(key)) return defaultVoiceKey;
    if (!isValid(key)) return defaultVoiceKey;
    return key;
  }
}
