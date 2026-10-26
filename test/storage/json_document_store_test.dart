import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/storage/json_document_store.dart';
import 'package:neatink/storage/storage_errors.dart';
import 'package:path/path.dart' as p;

import 'storage_test_support.dart';

/// Parser used by these tests: a document must have an integer `value`.
/// Top-level so it can run in a background isolate.
int parseValue(Map<String, dynamic> json) => json['value'] as int;

List<int> doc(int value, {String padding = ''}) =>
    encodeJsonBytes({'value': value, 'padding': padding});

void main() {
  late Directory root;
  late String path;
  late List<String> logs;
  late JsonDocumentStore store;

  setUp(() async {
    root = await createTempRoot();
    path = p.join(root.path, 'doc.json');
    logs = [];
    store = JsonDocumentStore(log: logs.add);
  });

  Future<List<String>> files() => listFilesRecursively(root);

  test('reading a missing document returns null', () async {
    expect(await store.read(path, parseValue), isNull);
    expect(await store.exists(path), isFalse);
  });

  test('first write has no backup; later writes keep the previous copy',
      () async {
    await store.write(path, doc(1));
    expect(await files(), ['doc.json']);
    expect(await store.read(path, parseValue), 1);

    await store.write(path, doc(2));
    expect(await files(), ['doc.json', 'doc.json.bak']);
    expect(await store.read(path, parseValue), 2);
    final backup = jsonDecode(await File(backupPathFor(path)).readAsString())
        as Map<String, dynamic>;
    expect(backup['value'], 1);

    await store.write(path, doc(3));
    expect(parseValue(_readJson(backupPathFor(path))), 2);
  });

  test('a valid file written by someone else is promoted to .bak', () async {
    await File(path).writeAsBytes(doc(5));
    await store.write(path, doc(6));
    expect(parseValue(_readJson(backupPathFor(path))), 5);
  });

  test('falls back to .bak when the main file is corrupt, touching nothing',
      () async {
    await store.write(path, doc(1));
    await store.write(path, doc(2));
    await File(path).writeAsString('{"value": 2, "trunc');

    final fresh = JsonDocumentStore(log: logs.add);
    final result = await fresh.readWithSource(path, parseValue);
    expect(result!.value, 1);
    expect(result.fromBackup, isTrue);
    expect(logs.single, contains('backup'));
    // Nothing was repaired or deleted by the read.
    expect(await File(path).readAsString(), '{"value": 2, "trunc');
    expect(await files(), ['doc.json', 'doc.json.bak']);
  });

  test('a document the parser rejects also falls back to .bak', () async {
    await store.write(path, doc(1));
    await store.write(path, encodeJsonBytes({'value': 'not an int'}));
    expect(await JsonDocumentStore().read(path, parseValue), 1);
  });

  test('falls back to .bak when the main file is missing', () async {
    await store.write(path, doc(1));
    await store.write(path, doc(2));
    // A crash between "main → .bak" and "temp → main" looks like this.
    await File(path).delete();
    expect(await JsonDocumentStore().read(path, parseValue), 1);
    expect(await store.exists(path), isTrue);
  });

  test('both copies unreadable: throws and keeps both files', () async {
    await File(path).writeAsString('garbage');
    await File(backupPathFor(path)).writeAsString('[1, 2]');
    await expectLater(
      store.read(path, parseValue),
      throwsA(isA<CorruptFileException>()
          .having((e) => e.path, 'path', path)),
    );
    expect(await files(), ['doc.json', 'doc.json.bak']);
  });

  test('writing over a corrupt main keeps it as .corrupt and the good .bak',
      () async {
    await store.write(path, doc(1));
    await store.write(path, doc(2));
    await File(path).writeAsString('garbage');

    final fresh = JsonDocumentStore(log: logs.add);
    await fresh.write(path, doc(3));
    expect(await files(), ['doc.json', 'doc.json.bak', 'doc.json.corrupt']);
    expect(await fresh.read(path, parseValue), 3);
    expect(parseValue(_readJson(backupPathFor(path))), 1);
    expect(await File(corruptPathFor(path)).readAsString(), 'garbage');
    expect(logs, contains(contains('.corrupt')));
  });

  test('no temp files are left after many writes', () async {
    for (var i = 0; i < 20; i++) {
      await store.write(path, doc(i));
    }
    expect(await files(), ['doc.json', 'doc.json.bak']);
  });

  group('large documents (background isolate)', () {
    late JsonDocumentStore small;

    setUp(() => small = JsonDocumentStore(backgroundThresholdBytes: 64));

    test('read and write through the background path', () async {
      final big = doc(42, padding: 'x' * 1000);
      expect(big.length, greaterThan(64));
      await small.write(path, big);
      await small.write(path, doc(43, padding: 'y' * 1000));
      expect(await JsonDocumentStore(backgroundThresholdBytes: 64)
          .read(path, parseValue), 43);
    });

    test('backup fallback also works in the background', () async {
      await small.write(path, doc(1, padding: 'x' * 1000));
      await small.write(path, doc(2, padding: 'x' * 1000));
      await File(path).writeAsString('x' * 2000);
      final result = await JsonDocumentStore(backgroundThresholdBytes: 64)
          .readWithSource(path, parseValue);
      expect(result!.value, 1);
      expect(result.fromBackup, isTrue);
    });

    test('a corrupt large main is detected in the background on write',
        () async {
      await small.write(path, doc(1, padding: 'x' * 1000));
      await small.write(path, doc(2, padding: 'x' * 1000));
      await File(path).writeAsString('x' * 2000);
      await JsonDocumentStore(backgroundThresholdBytes: 64)
          .write(path, doc(3));
      expect(await File(corruptPathFor(path)).readAsString(), 'x' * 2000);
      expect(parseValue(_readJson(backupPathFor(path))), 1);
    });

    test('readJsonDocumentSync matches the async reader', () async {
      await small.write(path, doc(7));
      final result = readJsonDocumentSync(path, parseValue);
      expect(result!.value, 7);
      expect(result.source, JsonSource.main);
    });
  });

  test('encodeJsonBytes pretty prints on request', () {
    final pretty = utf8.decode(encodeJsonBytes({'a': 1}, pretty: true));
    expect(pretty, '{\n  "a": 1\n}');
    expect(utf8.decode(encodeJsonBytes({'a': 1})), '{"a":1}');
  });
}

Map<String, dynamic> _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
