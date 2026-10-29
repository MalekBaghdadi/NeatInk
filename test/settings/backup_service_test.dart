import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/features/settings/backup_service.dart';
import 'package:neatink/storage/backup/notebook_backup.dart';
import 'package:neatink/storage/file_notebook_repository.dart';

// The real service, with real isolates. Its progress callback is what the
// Settings screen passes: a closure that holds on to things that can't be
// sent to another isolate (the screen's state). In v1.6.0 that callback went
// along into the backup isolate, so every backup and restore on the tablet
// failed with "object is unsendable".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('backup_service');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tmp.path);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
    tmp.deleteSync(recursive: true);
  });

  test('progress reaches a callback that holds unsendable things', () async {
    final screenState = ReceivePort(); // can't cross isolates, like a BuildContext
    addTearDown(screenState.close);
    final seen = <(int, int)>[];
    final result = await runWithProgress((done, total) {
      seen.add((done, total));
      screenState.hashCode;
    }, (progress) async {
      progress(1, 2);
      progress(2, 2);
      return 42;
    });
    expect(result, 42);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(seen, [(1, 2), (2, 2)]);
  });

  test('a backup made and read back through the service, then restored elsewhere', () async {
    final root = Directory('${tmp.path}/notes')..createSync();
    final repo = FileNotebookRepository(root);
    final meta = await repo.createNotebook(title: 'Brain', paper: const Paper(), pageCount: 2);
    final service = DefaultBackupService(root.path);
    final screenState = ReceivePort();
    addTearDown(screenState.close);
    var reports = 0;
    final zip = await service.create({'settings': {'autocorrect': true}}, onProgress: (_, _) {
      reports++;
      screenState.hashCode;
    });
    expect(File(zip).existsSync(), isTrue);
    final info = await service.inspect(zip);
    expect([for (final n in info.notebooks) n.meta.title], ['Brain']);

    final other = Directory('${tmp.path}/other')..createSync();
    final target = DefaultBackupService(other.path);
    final plan = planRestore(info, const [], copyChanged: true, newId: () => 'unused');
    final result = await target.restore(zip, plan, onProgress: (_, _) => screenState.hashCode);
    expect(result.restored, [meta.id]);
    expect(await FileNotebookRepository(other).loadMeta(meta.id), isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(reports, greaterThan(0));
  });
}
