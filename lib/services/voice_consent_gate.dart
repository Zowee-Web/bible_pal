import 'package:bible_pal/models/user_preferences.dart';

/// Result of attempting to play voice audio through the consent gate.
/// Callers MUST handle `needsConsent` by showing VoiceConsentDialog.
enum VoiceGateResult {
  /// Consent granted - caller may proceed with audio playback
  allowed,

  /// User has not yet been asked for consent (value == null).
  /// Caller MUST show VoiceConsentDialog and retry after consent is given.
  needsConsent,

  /// User explicitly disabled this voice feature (value == false).
  /// Audio must NOT play. Caller may show text-only fallback.
  blocked,
}

/// Voice Consent Gate - the ONLY authorized path to voice playback.
///
/// This gate enforces the voice consent invariant:
/// - null = not asked yet → needsConsent (must show dialog)
/// - false = explicitly disabled → blocked (must not play)
/// - true = enabled → allowed (may proceed)
///
/// All voice playback (story narration, PAL greetings, future features)
/// MUST go through this gate. Direct calls to AudioService.play() or
/// FlutterTts.speak() are prohibited without first checking this gate.
///
/// Usage:
/// ```dart
/// final result = VoiceConsentGate.checkStoryNarration(userPrefs);
/// switch (result) {
///   case VoiceGateResult.allowed:
///     await audioService.play(); // Safe to play
///   case VoiceGateResult.needsConsent:
///     // Show VoiceConsentDialog, then retry
///   case VoiceGateResult.blocked:
///     // Show "disabled in Settings" message
/// }
/// ```
class VoiceConsentGate {
  // Private constructor - all methods are static
  VoiceConsentGate._();

  /// Check if story narration is allowed.
  /// Returns [VoiceGateResult] indicating whether playback may proceed.
  static VoiceGateResult checkStoryNarration(UserPreferences? prefs) {
    return _checkConsent(prefs?.storyNarrationEnabled);
  }

  /// Check if PAL greetings voice is allowed.
  /// Returns [VoiceGateResult] indicating whether TTS may proceed.
  static VoiceGateResult checkPalGreetings(UserPreferences? prefs) {
    return _checkConsent(prefs?.palGreetingsEnabled);
  }

  /// Internal: check tri-state consent value.
  static VoiceGateResult _checkConsent(bool? consentValue) {
    if (consentValue == null) {
      return VoiceGateResult.needsConsent;
    }
    if (consentValue == false) {
      return VoiceGateResult.blocked;
    }
    return VoiceGateResult.allowed;
  }
}
