import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/parent_lock.dart';
import '../../providers/app_state_notifier.dart';
import '../../services/biometric_auth_service.dart';
import '../../widgets/pin_pad_sheet.dart';

/// Authenticate the grown-up against the parent lock (SPEC Feature 51.6).
///
/// Returns `true` if there is no lock (nothing to check) or the parent passes
/// Face ID / Touch ID or the correct PIN. Biometric is tried first when
/// enabled + available; any biometric failure falls back to the PIN pad, which
/// retries until the correct PIN is entered or the parent cancels (→ `false`).
Future<bool> authenticateParent(
  BuildContext context,
  WidgetRef ref, {
  String reason = 'Exit Kids mode',
}) async {
  final prefs = ref.read(appStateProvider).valueOrNull?.userPreferences;
  if (prefs == null || !prefs.hasParentLock) return true;

  if (prefs.parentLockBiometricEnabled) {
    final bio = ref.read(biometricAuthServiceProvider);
    if (await bio.isAvailable()) {
      if (await bio.authenticate(reason: reason)) return true;
      // Biometric failed/cancelled → fall through to PIN.
    }
  }

  String? error;
  while (true) {
    if (!context.mounted) return false;
    final pin = await showPinPad(
      context,
      title: 'Enter Parent PIN',
      subtitle: reason,
      errorText: error,
    );
    if (pin == null) return false; // cancelled
    if (ref.read(appStateProvider.notifier).verifyParentPin(pin)) return true;
    error = 'Incorrect PIN. Try again.';
  }
}

/// Set or change the parent PIN: enter a 4-digit PIN, then confirm it.
/// Persists on success and returns `true`. Cancelling at any step → `false`.
Future<bool> setupParentPin(BuildContext context, WidgetRef ref) async {
  String? error;
  while (true) {
    if (!context.mounted) return false;
    final first = await showPinPad(
      context,
      title: 'Set a 4-digit PIN',
      subtitle: 'A grown-up uses this to exit Kids mode',
      errorText: error,
    );
    if (first == null) return false;
    if (!ParentLock.isValidPinFormat(first)) {
      error = 'PIN must be 4 digits';
      continue;
    }
    if (!context.mounted) return false;

    final confirm = await showPinPad(context, title: 'Confirm your PIN');
    if (confirm == null) return false;
    if (first != confirm) {
      error = "PINs didn't match. Try again.";
      continue;
    }

    await ref.read(appStateProvider.notifier).setParentLockPin(first);
    return true;
  }
}
