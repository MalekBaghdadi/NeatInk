import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/storage/atomic_file.dart';
import 'package:path/path.dart' as p;

import 'storage_test_support.dart';

void main() {
  late Directory root;

  setUp(() async => root = await createTempRoot());

  Future<List<String>> files() => listFilesRecursively(root);

  group('AtomicFile.writeBytes', () {
    test('creates parent folders and leaves no temp file', () async {
      final path = p.join(root.path, 'a', 'b', 'doc.json');
      await AtomicFile.writeBytes(path, [1, 2, 3]);
      expect(await File(path).readAsBytes(), [1, 2, 3]);
      expect(await files(), ['a/b/doc.json']);
    });

    test('replaces an existing file completely', () async {
      final path = p.join(root.path, 'doc.json');
      await AtomicFile.writeBytes(path, List.filled(100, 7));
      await AtomicFile.writeBytes(path, [9]);
      expect(await File(path).readAsBytes(), [9]);
      expect(await files(), ['doc.json']);
    });

    test('a failed rename leaves the target and no temp file', () async {
      // A folder where the file should go makes the final rename fail.
      final target = p.join(root.path, 'busy');
      await Directory(target).create();
      await File(p.join(target, 'inside.txt')).writeAsString('keep');

      await expectLater(
        AtomicFile.writeBytes(target, [1, 2, 3]),
        throwsA(isA<FileSystemException>()),
      );
      expect(await files(), ['busy/inside.txt']);
    });
  });

  group('AtomicFile.copy', () {
    test('copies the whole file and leaves no temp file', () async {
      final source = File(p.join(root.path, 'source.bin'));
      final bytes = List<int>.generate(300000, (i) => i % 251);
      await source.writeAsBytes(bytes);
      final target = p.join(root.path, 'out', 'copy.bin');

      await AtomicFile.copy(source.path, target);
      expect(await File(target).readAsBytes(), bytes);
      expect(await files(), ['out/copy.bin', 'source.bin']);
    });

    test('a missing source fails without creating the target', () async {
      final target = p.join(root.path, 'copy.bin');
      await File(target).writeAsString('old');
      await expectLater(
        AtomicFile.copy(p.join(root.path, 'missing.bin'), target),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File(target).readAsString(), 'old');
      expect(await files(), ['copy.bin']);
    });
  });

  group('StagedFile', () {
    test('discard keeps the target as it was', () async {
      final path = p.join(root.path, 'doc.json');
      await File(path).writeAsString('old');
      final staged = await AtomicFile.stageBytes(path, [1]);
      expect(File(staged.tempPath).existsSync(), isTrue);
      expect(AtomicFile.isTempName(staged.tempPath), isTrue);

      await staged.discard();
      expect(await File(path).readAsString(), 'old');
      expect(await files(), ['doc.json']);
    });

    test('commit twice is an error', () async {
      final staged =
          await AtomicFile.stageBytes(p.join(root.path, 'x.json'), [1]);
      await staged.commit();
      expect(staged.commit, throwsStateError);
    });
  });

  group('AtomicFile.removeStrayTemps', () {
    test('removes leftovers but never a write in progress', () async {
      await File(p.join(root.path, 'page.json.tmp-deadbeef'))
          .writeAsString('half');
      await File(p.join(root.path, 'page.json')).writeAsString('{}');
      final staged =
          await AtomicFile.stageBytes(p.join(root.path, 'other.json'), [1]);
      expect(AtomicFile.isInFlight(staged.tempPath), isTrue);

      final removed = await AtomicFile.removeStrayTemps(root);
      expect(removed, 1);
      expect(File(staged.tempPath).existsSync(), isTrue);
      expect(File(p.join(root.path, 'page.json')).existsSync(), isTrue);

      await staged.commit();
      expect(AtomicFile.isInFlight(staged.tempPath), isFalse);
      expect(await files(), ['other.json', 'page.json']);
    });

    test('a missing folder is not an error', () async {
      expect(
        await AtomicFile.removeStrayTemps(
            Directory(p.join(root.path, 'nope'))),
        0,
      );
    });
  });

  test('isTempName only matches temp files', () {
    expect(AtomicFile.isTempName('a.json.tmp-12ab'), isTrue);
    expect(AtomicFile.isTempName(p.join('x', 'a.json.tmp-1')), isTrue);
    expect(AtomicFile.isTempName('a.json'), isFalse);
    expect(AtomicFile.isTempName('a.json.bak'), isFalse);
  });
}
