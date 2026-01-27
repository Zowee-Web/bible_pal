import 'typewriter_click_fallback.dart';

/// No-op fallback pool for web builds.
/// Web does not use just_audio for typewriter clicks.
class TypewriterFallbackPoolImpl implements TypewriterFallbackPool {
  @override
  Future<void> init(List<String> assetPaths) async {
    // No-op on web
  }

  @override
  void playClick() {
    // No-op on web
  }

  @override
  Future<void> dispose() async {
    // No-op on web
  }

  @override
  bool get isReady => false;
}

/// Factory function for conditional import.
TypewriterFallbackPool createFallbackPool() => TypewriterFallbackPoolImpl();
