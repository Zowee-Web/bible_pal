/// Asset-path composition for PAL journey audio clips — Journey
/// Doctrine Slice 2 Phase 6.
///
/// Path policy:
///   assets/pal/audio/<VOICE_KEY>/journey/<clipId>.mp3
///
/// Parallel to [PalMemoryAudioPaths] (Slice 2c.3): same root, sibling
/// `journey/` subdirectory next to `memory/`. Keeps journey clips
/// distinct from recognition clips so each inventory validator can
/// scope cleanly to its own asset family.
///
/// Clip ID conventions for first-ship Slice 2 (VOICE_STILLWATER):
///   - `offer_narrative_adult`        — generic adult carrier (single clip
///     covers every adult journey type; no per-journey customization)
///   - `decline_adult`      — generic adult decline
///   - `carrier_narrative_kid`        — generic kid carrier (precedes name)
///   - `invitation_narrative_kid`     — generic kid invitation (follows name)
///   - `decline_kid`        — generic kid decline
///   - `name_<character_snake>_journey` — per-kid-journey character clip
///     (e.g. `name_david_journey`). Derived from the journey's
///     [Journey.characterName] via [PalJourneyAudioPaths.nameClipIdFor].
///     Distinct from Slice 2d's `name_<x>` recognition clips so each
///     family can evolve independently.
class PalJourneyAudioPaths {
  PalJourneyAudioPaths._();

  /// Compose the bundled-asset path for a journey clip.
  static String assetPathFor({
    required String voiceKey,
    required String clipId,
  }) {
    return 'assets/pal/audio/$voiceKey/journey/$clipId.mp3';
  }

  /// Derive the per-kid-journey character name clip ID from the
  /// editorial [characterName] on the journey. Convention: lowercase,
  /// spaces and punctuation collapsed to underscores, trailing
  /// `_journey` suffix so the clip is distinct from Slice 2d
  /// recognition clips.
  ///
  /// Examples:
  ///   - "David"              → "name_david_journey"
  ///   - "Mary Magdalene"     → "name_mary_magdalene_journey"
  ///   - "the Good Samaritan" → "name_the_good_samaritan_journey"
  ///
  /// Throws [ArgumentError] if [characterName] is empty or
  /// becomes empty after normalization (defensive — schema validator
  /// should catch upstream, but this is the last line of defense
  /// before the convention becomes runtime-load-bearing).
  static String nameClipIdFor(String characterName) {
    if (characterName.trim().isEmpty) {
      throw ArgumentError(
          'characterName must not be empty for journey name clip ID derivation');
    }
    final lower = characterName.toLowerCase();
    final normalized = lower
        .replaceAll(RegExp(r"[^a-z0-9]+"), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (normalized.isEmpty) {
      throw ArgumentError(
          'characterName "$characterName" normalized to empty — must contain '
          'at least one [a-z0-9] character');
    }
    return 'name_${normalized}_journey';
  }
}
