/// Bundled-asset path policy for PAL memory audio clips.
///
/// PAL Memory Doctrine, Slice 2c.2 (see docs/PAL_MEMORY_DOCTRINE.md): a
/// single source of truth for where memory clips live in the asset
/// bundle. Used by:
/// - [MemoryAudioResolver] to compose [MemoryAudioClipRef.assetPath].
/// - The Slice 2c.3 inventory validator to enumerate expected clip
///   paths and assert each one is bundled (or registered for R2).
///
/// Convention mirrors the existing PAL audio layout (`pal/audio/<VOICE>/`)
/// and adds a `memory/` subdirectory so memory clips don't collide with
/// the canonical PAL greeting / transition / reflection clips.
class PalMemoryAudioPaths {
  PalMemoryAudioPaths._();

  /// Returns the bundled asset path for a memory clip. Example:
  ///
  ///   assetPathFor(voiceKey: 'VOICE_HOPE', clipId: 'name_daniel')
  ///   → 'assets/pal/audio/VOICE_HOPE/memory/name_daniel.mp3'
  ///
  /// The literal path is also the rootBundle key — rootBundle is rooted
  /// at the package root, not at `assets/`.
  static String assetPathFor({
    required String voiceKey,
    required String clipId,
  }) {
    return 'assets/pal/audio/$voiceKey/memory/$clipId.mp3';
  }
}
