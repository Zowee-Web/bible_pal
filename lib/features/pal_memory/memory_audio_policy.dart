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
  ///
  /// Set editorially via the 2026-06-19 VOICE_STILLWATER audition
  /// (Adam Lipps) — the initial 250ms placeholder felt too long; 50ms
  /// reads as natural speech rhythm after the carrier-tail trim
  /// applied at render time (see [carrierTailTrimDuration]).
  static const Duration carrierToNameGap = Duration(milliseconds: 50);

  /// Duration to trim from the tail of every rendered carrier clip
  /// before shipping. ElevenLabs `eleven_turbo_v2_5` with the
  /// VOICE_STILLWATER profile leaves a trailing breath/exhale artifact
  /// at the end of every carrier (most audible as a hissy "s"-like
  /// trailing sound on phrases ending in "with"). 300ms is the
  /// editorial sweet spot determined by the 2026-06-19 audition —
  /// removes the artifact without clipping the final consonant.
  ///
  /// Applied at render time by `scripts/render_pal_memory_audio.py`
  /// (Slice 2d). Clips on disk are the final form; no runtime trim.
  /// VOICE-SPECIFIC: if additional voices ship later, each one needs
  /// its own editorial trim determination (TTS artifacts differ by
  /// voice).
  static const Duration carrierTailTrimDuration =
      Duration(milliseconds: 300);
}
