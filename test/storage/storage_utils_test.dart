import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/notebook_meta.dart';
import 'package:neatink/storage/keyed_mutex.dart';
import 'package:neatink/storage/library_json.dart';
import 'package:neatink/storage/storage_ids.dart';

void main() {
  group('storage ids', () {
    test('accepts uuids and simple ids', () {
      expect(isValidStorageId('3f2a9c1e-0b7d-4c55-9e1a-1234567890ab'), isTrue);
      expect(isValidStorageId('page_1'), isTrue);
      expect(isValidStorageId('A'), isTrue);
      expect(isValidStorageId('a' * 64), isTrue);
    });

    test('rejects anything that could escape a folder', () {
      for (final bad in [
        '',
        '.',
        '..',
        '../x',
        r'..\x',
        'a/b',
        r'a\b',
        'C:',
        'a b',
        '-leading-dash',
        '_leading',
        'x.json',
        'a' * 65,
        'é',
      ]) {
        expect(isValidStorageId(bad), isFalse, reason: bad);
        expect(() => checkStorageId(bad), throwsArgumentError, reason: bad);
      }
      expect(checkStorageId('ok-1'), 'ok-1');
    });

    test('asset names are an id plus a short lowercase extension', () {
      expect(isValidAssetName('3f2a9c1e-0b7d-4c55-9e1a-1234567890ab.png'),
          isTrue);
      expect(isValidAssetName('pic'), isTrue);
      expect(isValidAssetName('pic.webp'), isTrue);
      for (final bad in ['pic.PNG', '.png', 'a.b.c', '../a.png', 'a.png/', 'a.toolongext']) {
        expect(isValidAssetName(bad), isFalse, reason: bad);
        expect(() => checkAssetName(bad), throwsArgumentError, reason: bad);
      }
    });

    test('sanitizeExtension', () {
      expect(sanitizeExtension('.JPG'), 'jpg');
      expect(sanitizeExtension('png'), 'png');
      expect(sanitizeExtension('tar.gz'), 'gz');
      expect(sanitizeExtension(''), 'bin');
      expect(sanitizeExtension('.'), 'bin');
      expect(sanitizeExtension(' .We bP '), 'webp');
      expect(sanitizeExtension('abcdefghijk'), 'abcdefgh');
      expect(sanitizeExtension('../../png'), 'png');
    });
  });

  group('KeyedMutex', () {
    test('runs actions for one key in order, never overlapping', () async {
      final mutex = KeyedMutex();
      final log = <String>[];
      var active = 0;
      Future<int> job(int i, int delayMs) => mutex.run('k', () async {
            active++;
            expect(active, 1);
            log.add('start $i');
            await Future<void>.delayed(Duration(milliseconds: delayMs));
            log.add('end $i');
            active--;
            return i;
          });
      final results = await Future.wait([job(1, 30), job(2, 1), job(3, 10)]);
      expect(results, [1, 2, 3]);
      expect(log, [
        'start 1', 'end 1', 'start 2', 'end 2', 'start 3', 'end 3', //
      ]);
      expect(mutex.isLocked('k'), isFalse);
    });

    test('different keys run concurrently', () async {
      final mutex = KeyedMutex();
      final gate = Completer<void>();
      final slow = mutex.run('a', () => gate.future);
      var otherRan = false;
      await mutex.run('b', () async => otherRan = true);
      expect(otherRan, isTrue);
      expect(mutex.isLocked('a'), isTrue);
      gate.complete();
      await slow;
      expect(mutex.isLocked('a'), isFalse);
    });

    test('a failing action does not block the next one', () async {
      final mutex = KeyedMutex();
      final failing = mutex.run<void>('k', () async => throw StateError('x'));
      final next = mutex.run('k', () async => 'ok');
      await expectLater(failing, throwsStateError);
      expect(await next, 'ok');
    });
  });

  group('library.json migration', () {
    test('accepts v1 and a missing version', () {
      final lib = libraryFromJson({
        'folders': [
          {'id': 'f', 'name': 'F', 'createdAt': '2026-01-01T00:00:00.000Z'},
        ],
      });
      expect(lib.folders.single.name, 'F');
      expect(migrateLibraryJson({'version': 1}), {'version': 1});
    });

    test('rejects a file from a newer app version', () {
      expect(() => libraryFromJson({'version': LibraryIndex.currentVersion + 1}),
          throwsFormatException);
    });
  });
}
