import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Pure helpers for the Kids-mode Parent Lock (SPEC Feature 51.6).
///
/// The 4-digit PIN is never stored in plaintext. We store a random per-setup
/// salt and the SHA-256 hash of `salt:pin`. The threat model is a young child,
/// so a salted hash in preferences is sufficient (no keychain dependency).
class ParentLock {
  ParentLock._();

  /// A 4-digit PIN is exactly four ASCII digits.
  static bool isValidPinFormat(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);

  /// Generate a fresh random salt (base64url, 16 bytes). Pass [rng] in tests
  /// for determinism; production uses a cryptographically secure source.
  static String generateSalt([Random? rng]) {
    final r = rng ?? Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// Salted SHA-256 hash of [pin] under [salt].
  static String hashPin(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  /// True when [pin] matches the stored [hash] under [salt].
  static bool verify(String pin, {required String hash, required String salt}) =>
      hashPin(pin, salt) == hash;
}
