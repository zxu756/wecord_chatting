import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Turns a PIN or a secret code into something that can be kept and checked
/// without keeping the PIN itself: PBKDF2 with HMAC-SHA-256 over a random
/// salt.
///
/// This is not encryption. A six digit PIN has a million possibilities, so
/// anyone who can read this device's storage can find it; the PIN only keeps
/// out the person who is handed an unlocked phone or a browser tab. The
/// settings say so.
abstract final class LockSecret {
  /// Few enough to stay quick when compiled to JavaScript for the web.
  static const iterations = 4000;

  /// A new random salt, as base64.
  static String newSalt([Random? random]) {
    final source = random ?? Random.secure();
    final bytes = Uint8List.fromList([
      for (var i = 0; i < 16; i++) source.nextInt(256),
    ]);
    return base64Encode(bytes);
  }

  /// PBKDF2-HMAC-SHA256 of [secret] over [salt] (base64), as hex.
  static String hash(String secret, String salt, {int rounds = iterations}) {
    final hmac = Hmac(sha256, utf8.encode(secret));
    // One output block (32 bytes) is all that is needed.
    final first = hmac.convert([...base64Decode(salt), 0, 0, 0, 1]).bytes;
    var u = first;
    final result = Uint8List.fromList(first);
    for (var i = 1; i < rounds; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return result.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Whether [secret] hashes to [expectedHash] over [salt]. Compares without
  /// stopping at the first difference.
  static bool matches(
    String secret, {
    required String salt,
    required String expectedHash,
    int rounds = iterations,
  }) {
    final actual = hash(secret, salt, rounds: rounds);
    if (actual.length != expectedHash.length) {
      return false;
    }
    var difference = 0;
    for (var i = 0; i < actual.length; i++) {
      difference |= actual.codeUnitAt(i) ^ expectedHash.codeUnitAt(i);
    }
    return difference == 0;
  }
}

/// A salted hash kept in place of a PIN or a secret code.
class StoredSecret {
  const StoredSecret({required this.salt, required this.hash});

  /// Hashes [secret] over a new salt.
  factory StoredSecret.of(String secret, {Random? random}) {
    final salt = LockSecret.newSalt(random);
    return StoredSecret(salt: salt, hash: LockSecret.hash(secret, salt));
  }

  final String salt;
  final String hash;

  bool accepts(String secret) =>
      LockSecret.matches(secret, salt: salt, expectedHash: hash);

  /// "salt:hash", the form kept on the device.
  String encode() => '$salt:$hash';

  static StoredSecret? decode(String? text) {
    if (text == null) {
      return null;
    }
    final parts = text.split(':');
    if (parts.length != 2 || parts.any((part) => part.isEmpty)) {
      return null;
    }
    return StoredSecret(salt: parts[0], hash: parts[1]);
  }
}
