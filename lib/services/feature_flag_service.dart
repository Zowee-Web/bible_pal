/// Feature Flag Service - controls feature availability via remote config
/// v1.0: Mock implementation with hardcoded values (local-only mode)
/// v1.1+: Will integrate Firebase Remote Config for dynamic kill switch
class FeatureFlagService {
  /// Transport Layer v1 kill switch
  /// Returns true if backend sharing is enabled, false for local-only mode
  ///
  /// v1.0: Hardcoded to false (local-only, no backend calls)
  /// v1.1+: Will fetch from Firebase Remote Config
  Future<bool> isTransportLayerEnabled() async {
    // v1.0: Always return false (local-only mode)
    // No backend calls occur when false
    return false;
  }
}
