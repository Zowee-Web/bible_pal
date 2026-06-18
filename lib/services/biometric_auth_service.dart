import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

/// Thin, defensive wrapper around [LocalAuthentication] for the Kids-mode
/// parent lock (SPEC Feature 51.6). All failures (no hardware, not enrolled,
/// user cancel, platform error) resolve to `false` so callers can simply fall
/// back to the PIN pad.
class BiometricAuthService {
  BiometricAuthService([LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  /// True when the device supports biometrics AND the user has enrolled one
  /// (Face ID / Touch ID). Never throws.
  Future<bool> isAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  /// Prompt the system biometric sheet. Returns `true` only on a confirmed
  /// success; any failure/cancel/error returns `false`. Never throws.
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}

/// Provider for [BiometricAuthService] — override in tests to stub biometrics.
final biometricAuthServiceProvider =
    Provider<BiometricAuthService>((ref) => BiometricAuthService());
