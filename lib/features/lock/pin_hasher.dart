import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Hashing for the app-lock PIN: salted SHA-256, iterated, hex encoded.
///
/// `h₁ = SHA-256(salt ‖ pin)`, then `hᵢ = SHA-256(hᵢ₋₁ ‖ salt ‖ pin)` up to
/// [iterations]. The iteration count makes each guess against a copied
/// settings file cost ~10,000 hashes. This is a privacy lock for casual
/// access, not encryption: notebooks themselves are stored unencrypted.
abstract final class PinHasher {
  static const int iterations = 10000;
  static const int saltBytes = 16;
  static const int minLength = 4;
  static const int maxLength = 8;

  static final RegExp _pinPattern = RegExp(r'^[0-9]{4,8}$');

  /// A PIN is 4 to 8 ASCII digits.
  static bool isValidPin(String pin) => _pinPattern.hasMatch(pin);

  /// A new random salt ([saltBytes] bytes from a cryptographically secure
  /// generator), hex encoded.
  static String newSalt([Random? random]) {
    final rng = random ?? Random.secure();
    final bytes = Uint8List(saltBytes);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return _hex(bytes);
  }

  /// Hash of [pin] with the hex-encoded [salt], as 64 lowercase hex chars.
  static String hash(String pin, String salt, {int rounds = iterations}) {
    if (rounds < 1) throw ArgumentError.value(rounds, 'rounds', 'must be ≥ 1');
    final saltAndPin = [..._unhex(salt), ...utf8.encode(pin)];
    var digest = sha256.convert(saltAndPin).bytes;
    // One reusable buffer: [previous digest (32 bytes) | salt | pin].
    final buffer = Uint8List(32 + saltAndPin.length)
      ..setRange(32, 32 + saltAndPin.length, saltAndPin);
    for (var i = 1; i < rounds; i++) {
      buffer.setRange(0, 32, digest);
      digest = sha256.convert(buffer).bytes;
    }
    return _hex(digest);
  }

  /// Whether [pin] hashes to [expectedHash] under [salt]. The final
  /// comparison runs in constant time.
  static bool verify(
    String pin, {
    required String salt,
    required String expectedHash,
  }) =>
      constantTimeEquals(hash(pin, salt), expectedHash.toLowerCase());

  /// Compares two strings without returning early on the first difference,
  /// so the time taken doesn't reveal how many leading characters match.
  static bool constantTimeEquals(String a, String b) {
    var diff = a.length ^ b.length;
    final n = max(a.length, b.length);
    for (var i = 0; i < n; i++) {
      final ca = i < a.length ? a.codeUnitAt(i) : 0;
      final cb = i < b.length ? b.codeUnitAt(i) : 0;
      diff |= ca ^ cb;
    }
    return diff == 0;
  }

  static String _hex(List<int> bytes) {
    final out = StringBuffer();
    for (final b in bytes) {
      out.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return out.toString();
  }

  /// Hex → bytes. Invalid input is treated as raw text so a malformed stored
  /// salt still hashes deterministically instead of throwing.
  static List<int> _unhex(String hex) {
    if (hex.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(hex)) {
      return utf8.encode(hex);
    }
    return [
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
  }
}
