/// Audio prosody policy constants for PAL memory delivery.
///
/// PAL Memory Doctrine, Slice 2c.3 (see docs/PAL_MEMORY_DOCTRINE.md):
/// the durations live in a single named place so the resolver, the
/// inventory validator, and the eventual audio player all agree on the
/// cadence. Editorial decision — measured against the rendered clips,
/// not derived from a model.
class PalMemoryAudioPolicy {
  PalMemoryAudioPolicy._();

  /// Silence between the carrier ("Yesterday you sat with") and the
  /// display name ("Daniel"). Short natural breath; the audio should
  /// feel like one sentence, not a concatenation. Tune against rendered
  /// clips when audio ships — adjust the constant, never invent
  /// per-call values.
  static const Duration carrierToNameGap = Duration(milliseconds: 250);
}
