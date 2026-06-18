import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/core/parent_lock.dart';
import 'package:bible_pal/models/user_preferences.dart';

void main() {
  group('ParentLock hashing (SPEC 51.6)', () {
    test('isValidPinFormat accepts exactly 4 digits', () {
      expect(ParentLock.isValidPinFormat('1234'), isTrue);
      expect(ParentLock.isValidPinFormat('0000'), isTrue);
      expect(ParentLock.isValidPinFormat('123'), isFalse);
      expect(ParentLock.isValidPinFormat('12345'), isFalse);
      expect(ParentLock.isValidPinFormat('12a4'), isFalse);
      expect(ParentLock.isValidPinFormat(''), isFalse);
    });

    test('hashPin is deterministic for the same pin+salt', () {
      final salt = ParentLock.generateSalt(Random(1));
      expect(ParentLock.hashPin('1234', salt), ParentLock.hashPin('1234', salt));
    });

    test('hash never equals the plaintext pin', () {
      final salt = ParentLock.generateSalt(Random(1));
      expect(ParentLock.hashPin('1234', salt), isNot('1234'));
    });

    test('verify accepts the correct pin and rejects wrong ones', () {
      final salt = ParentLock.generateSalt(Random(2));
      final hash = ParentLock.hashPin('4729', salt);
      expect(ParentLock.verify('4729', hash: hash, salt: salt), isTrue);
      expect(ParentLock.verify('0000', hash: hash, salt: salt), isFalse);
    });

    test('different salts produce different hashes for the same pin', () {
      final h1 = ParentLock.hashPin('1234', ParentLock.generateSalt(Random(3)));
      final h2 = ParentLock.hashPin('1234', ParentLock.generateSalt(Random(4)));
      expect(h1, isNot(h2));
    });
  });

  group('UserPreferences parent-lock fields (SPEC 51.6)', () {
    test('default has no parent lock', () {
      final p = UserPreferences.defaults();
      expect(p.hasParentLock, isFalse);
      expect(p.parentLockPinHash, isNull);
      expect(p.parentLockBiometricEnabled, isFalse);
    });

    test('round-trips through toJson/fromJson', () {
      final p = UserPreferences.defaults().copyWith(
        parentLockPinHash: 'hash',
        parentLockSalt: 'salt',
        parentLockBiometricEnabled: true,
      );
      final restored = UserPreferences.fromJson(p.toJson());
      expect(restored.parentLockPinHash, 'hash');
      expect(restored.parentLockSalt, 'salt');
      expect(restored.parentLockBiometricEnabled, isTrue);
      expect(restored.hasParentLock, isTrue);
    });

    test('copyWith sets the lock; resetParentLock clears it', () {
      final locked = UserPreferences.defaults().copyWith(
        parentLockPinHash: 'h',
        parentLockSalt: 's',
        parentLockBiometricEnabled: true,
      );
      expect(locked.hasParentLock, isTrue);

      final cleared = locked.copyWith(resetParentLock: true);
      expect(cleared.hasParentLock, isFalse);
      expect(cleared.parentLockPinHash, isNull);
      expect(cleared.parentLockSalt, isNull);
      expect(cleared.parentLockBiometricEnabled, isFalse);
    });

    test('copyWith without lock args preserves an existing lock', () {
      final locked = UserPreferences.defaults()
          .copyWith(parentLockPinHash: 'h', parentLockSalt: 's');
      final unrelated = locked.copyWith(kidFriendlyOnly: true);
      expect(unrelated.hasParentLock, isTrue);
      expect(unrelated.parentLockPinHash, 'h');
    });
  });
}
