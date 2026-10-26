import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/lock/pin_hasher.dart';

void main() {
  const salt = '00112233445566778899aabbccddeeff';
  final saltBytes = [
    for (var i = 0; i < salt.length; i += 2)
      int.parse(salt.substring(i, i + 2), radix: 16),
  ];

  group('isValidPin', () {
    test('accepts 4 to 8 digits', () {
      for (final pin in ['0000', '1234', '12345', '00000000', '98765432']) {
        expect(PinHasher.isValidPin(pin), isTrue, reason: pin);
      }
    });

    test('rejects other lengths and non-digits', () {
      for (final pin in [
        '',
        '123',
        '123456789',
        '12a4',
        '12 34',
        ' 1234',
        '-123',
        '١٢٣٤', // Arabic-Indic digits are not ASCII digits.
      ]) {
        expect(PinHasher.isValidPin(pin), isFalse, reason: pin);
      }
    });
  });

  group('newSalt', () {
    test('is 16 random bytes as 32 lowercase hex chars', () {
      final s = PinHasher.newSalt();
      expect(s, hasLength(PinHasher.saltBytes * 2));
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(s), isTrue);
    });

    test('differs between calls', () {
      final salts = {for (var i = 0; i < 20; i++) PinHasher.newSalt()};
      expect(salts, hasLength(20));
    });

    test('uses the given random source', () {
      expect(PinHasher.newSalt(Random(7)), PinHasher.newSalt(Random(7)));
    });
  });

  group('hash', () {
    test('one round is SHA-256(salt bytes ‖ pin)', () {
      final expected =
          sha256.convert([...saltBytes, ...utf8.encode('1234')]).toString();
      expect(PinHasher.hash('1234', salt, rounds: 1), expected);
    });

    test('each further round hashes previous digest ‖ salt ‖ pin', () {
      final pin = utf8.encode('1234');
      var digest = sha256.convert([...saltBytes, ...pin]).bytes;
      for (var i = 1; i < 3; i++) {
        digest = sha256.convert([...digest, ...saltBytes, ...pin]).bytes;
      }
      final expected =
          digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(PinHasher.hash('1234', salt, rounds: 3), expected);
    });

    test('defaults to 10,000 iterations', () {
      expect(PinHasher.iterations, 10000);
      expect(
        PinHasher.hash('1234', salt),
        PinHasher.hash('1234', salt, rounds: 10000),
      );
      expect(
        PinHasher.hash('1234', salt),
        isNot(PinHasher.hash('1234', salt, rounds: 9999)),
      );
    });

    test('is 64 lowercase hex chars and deterministic', () {
      final h = PinHasher.hash('5678', salt);
      expect(h, hasLength(64));
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(h), isTrue);
      expect(PinHasher.hash('5678', salt), h);
    });

    test('depends on the PIN and on the salt', () {
      final h = PinHasher.hash('1234', salt);
      expect(PinHasher.hash('1235', salt), isNot(h));
      expect(PinHasher.hash('01234', salt), isNot(h));
      expect(PinHasher.hash('1234', 'ffeeddccbbaa99887766554433221100'),
          isNot(h));
    });

    test('a malformed stored salt still hashes deterministically', () {
      expect(PinHasher.hash('1234', 'not hex!'),
          PinHasher.hash('1234', 'not hex!'));
      expect(PinHasher.hash('1234', 'abc'), hasLength(64));
    });

    test('rejects fewer than one round', () {
      expect(() => PinHasher.hash('1234', salt, rounds: 0),
          throwsArgumentError);
    });
  });

  group('verify', () {
    final stored = PinHasher.hash('2468', salt);

    test('accepts the right PIN', () {
      expect(PinHasher.verify('2468', salt: salt, expectedHash: stored),
          isTrue);
    });

    test('accepts an upper-case stored hash', () {
      expect(
        PinHasher.verify('2468',
            salt: salt, expectedHash: stored.toUpperCase()),
        isTrue,
      );
    });

    test('rejects a wrong PIN, salt or hash', () {
      expect(PinHasher.verify('2469', salt: salt, expectedHash: stored),
          isFalse);
      expect(
        PinHasher.verify('2468',
            salt: PinHasher.newSalt(), expectedHash: stored),
        isFalse,
      );
      expect(PinHasher.verify('2468', salt: salt, expectedHash: ''), isFalse);
      expect(
        PinHasher.verify('2468',
            salt: salt, expectedHash: stored.substring(0, 63)),
        isFalse,
      );
    });
  });

  group('constantTimeEquals', () {
    test('compares like ==', () {
      expect(PinHasher.constantTimeEquals('', ''), isTrue);
      expect(PinHasher.constantTimeEquals('abc', 'abc'), isTrue);
      expect(PinHasher.constantTimeEquals('abc', 'abd'), isFalse);
      expect(PinHasher.constantTimeEquals('abc', 'ab'), isFalse);
      expect(PinHasher.constantTimeEquals('ab', 'abc'), isFalse);
      expect(PinHasher.constantTimeEquals('a\u0000', 'a'), isFalse);
    });
  });
}
