/// Abstract interface for typewriter click fallback pool.
/// Used to isolate just_audio from web builds via conditional import.
abstract class TypewriterFallbackPool {
  /// Initialize the audio pool with the given asset paths.
  Future<void> init(List<String> assetPaths);

  /// Play a click sound (fire-and-forget, round-robin through pool).
  void playClick();

  /// Dispose all resources.
  Future<void> dispose();

  /// Whether the pool has any players available.
  bool get isReady;
}
