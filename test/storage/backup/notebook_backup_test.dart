import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/notebook_meta.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/storage/backup/notebook_backup.dart';
import 'package:neatink/storage/backup/zip_archive.dart';
import 'package:neatink/storage/file_notebook_repository.dart';
import 'package:neatink/storage/notebook_repository.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../storage_test_support.dart';

void main() {
  late Directory rootA;
  late FileNotebookRepository repoA;
  late NotebookMeta lecture;
  late NotebookMeta slides;
  late Directory scratch;
  final pdfBytes = Uint8List.fromList(utf8.encode('%PDF-1.4 not really a pdf\n' * 50));
  final pngBytes = Uint8List.fromList(List.generate(3000, (i) => (i * 7) % 256));
  final folder = Folder(id: 'f-bio', name: 'Biology', createdAt: DateTime.utc(2026, 10, 1));

  setUp(() async {
    rootA = await createTempRoot();
    scratch = await createTempRoot();
    repoA = FileNotebookRepository(rootA, clock: StepClock().call);
    lecture = await repoA.createNotebook(
        title: 'Neurons', paper: const Paper(type: PaperType.lined), pageCount: 2);
    final asset = await repoA.addAssetBytes(lecture.id, pngBytes, 'png');
    await repoA.savePage(
        lecture.id,
        lecture.pages.first.id,
        PageContent(strokes: [penStroke('s1'), penStroke('s2', y0: 140)], images: [
          ImageItem(id: 'i1', x: 10, y: 10, width: 100, height: 80, asset: asset),
        ]));
    final pdf = File(p.join(scratch.path, 'in.pdf'))..writeAsBytesSync(pdfBytes);
    slides = await repoA.createPdfNotebook(
        title: 'Slides',
        sourcePdfPath: pdf.path,
        pageSizes: const [PdfPageSize(600, 800), PdfPageSize(800, 600)]);
    await repoA.saveLibrary(LibraryIndex(folders: [folder]));
    lecture = lecture.copyWith(folderId: folder.id);
    await repoA.saveMeta(lecture);
    // A write that a crash interrupted: never part of a backup.
    File(p.join(rootA.path, 'notebooks', lecture.id, 'notebook.json.tmp-dead'))
        .writeAsStringSync('{');
  });

  Future<String> backUp({Map<String, Object?> appData = const {'words': ['Malek']}}) async {
    final out = p.join(scratch.path, 'backup.zip');
    await writeBackup(
        rootPath: rootA.path,
        outputPath: out,
        appData: appData,
        appVersion: '1.6.0',
        now: DateTime.utc(2026, 10, 28, 12));
    return out;
  }

  Future<List<String>> restoreInto(Directory root, String zip,
      {bool copyChanged = true, Iterable<NotebookMeta> local = const []}) async {
    final info = await readBackupInfo(zip);
    final plan = planRestore(info, local, copyChanged: copyChanged, newId: const Uuid().v4);
    final result = await restoreNotebooks(zipPath: zip, rootPath: root.path, items: plan);
    expect(result.failed, isEmpty);
    return result.restored;
  }

  test('the archive holds every notebook file, folders and app data, but no temp files',
      () async {
    final zip = await backUp();
    final r = await ZipReader.open(File(zip));
    addTearDown(r.close);
    final names = r.entries.map((e) => e.name).toSet();
    expect(names, containsAll([
      backupManifestName,
      backupAppDataName,
      'library.json',
      'notebooks/${lecture.id}/notebook.json',
      'notebooks/${lecture.id}/pages/${lecture.pages.first.id}.json',
      'notebooks/${slides.id}/source.pdf',
    ]));
    expect(names.where((n) => n.contains('.tmp-')), isEmpty);
    expect(names.where((n) => n.startsWith('notebooks/${lecture.id}/assets/')), hasLength(1));
    final manifest = jsonDecode(utf8.decode(await r.readBytes(r.entry(backupManifestName)!)));
    expect(manifest['format'], 'neatink-backup');
    expect(manifest['app'], '1.6.0');
    expect((manifest['notebooks'] as List).map((n) => n['title']), unorderedEquals(['Neurons', 'Slides']));
  });

  test('restoring on an empty device brings everything back', () async {
    final zip = await backUp();
    final info = await readBackupInfo(zip);
    expect(info.notebooks.map((n) => n.title), ['Neurons', 'Slides']);
    expect(info.unreadable, 0);
    expect(info.appData, {'words': ['Malek']});
    expect(info.createdAt, DateTime.utc(2026, 10, 28, 12));
    expect(info.library.folders.single.name, 'Biology');

    final rootB = await createTempRoot();
    final restored = await restoreInto(rootB, zip);
    expect(restored, unorderedEquals([lecture.id, slides.id]));

    final repoB = FileNotebookRepository(rootB);
    final merged = mergeRestoredFolders(
        await repoB.loadLibrary(), info.library, [for (final n in info.notebooks) n.meta]);
    await repoB.saveLibrary(merged!);

    final metas = {for (final m in await repoB.listNotebooks()) m.id: m};
    expect(metas.keys, unorderedEquals([lecture.id, slides.id]));
    expect(metas[lecture.id]!.folderId, folder.id);
    expect((await repoB.loadLibrary()).folders.single.id, folder.id);
    final page = await repoB.loadPage(lecture.id, lecture.pages.first.id);
    expect(page.strokes.map((s) => s.id), ['s1', 's2']);
    expect(jsonEncode(page.strokes.first.toJson()), jsonEncode(penStroke('s1').toJson()));
    final asset = page.images.single.asset;
    expect(File(repoB.assetPath(lecture.id, asset)).readAsBytesSync(), pngBytes);
    expect(File(repoB.sourcePdfPath(slides.id)).readAsBytesSync(), pdfBytes);
    expect(Directory(rootB.path).listSync().map((e) => p.basename(e.path)),
        isNot(contains(startsWith('.restore-'))));
  });

  test('on the same device unchanged notebooks are skipped and changed ones copied',
      () async {
    final zip = await backUp();
    var info = await readBackupInfo(zip);
    var plan = planRestore(info, await repoA.listNotebooks(),
        copyChanged: true, newId: const Uuid().v4);
    expect(plan.map((i) => i.reason), everyElement(RestoreReason.unchanged));
    expect(plan.map((i) => i.action), everyElement(RestoreAction.skip));

    await repoA.renameNotebook(lecture.id, 'Neurons (edited)');
    final local = await repoA.listNotebooks();
    plan = planRestore(info, local, copyChanged: false, newId: const Uuid().v4);
    expect(plan.firstWhere((i) => i.notebook.id == lecture.id).action, RestoreAction.skip);

    final restored = await restoreInto(rootA, zip, local: local);
    expect(restored, hasLength(1));
    final copyId = restored.single;
    expect(copyId, isNot(lecture.id));

    final fresh = FileNotebookRepository(rootA);
    final metas = {for (final m in await fresh.listNotebooks()) m.id: m};
    expect(metas, hasLength(3));
    expect(metas[lecture.id]!.title, 'Neurons (edited)'); // never replaced
    expect(metas[copyId]!.title, 'Neurons (from backup)');
    expect(metas[copyId]!.pages.map((p) => p.id), lecture.pages.map((p) => p.id));
    final page = await fresh.loadPage(copyId, lecture.pages.first.id);
    expect(page.strokes, hasLength(2));
  });

  test('an existing notebook folder is never overwritten', () async {
    final zip = await backUp();
    final info = await readBackupInfo(zip);
    // Planned as missing, but the notebook appears before the restore runs.
    final plan = planRestore(info, const [], copyChanged: true, newId: const Uuid().v4);
    final result = await restoreNotebooks(zipPath: zip, rootPath: rootA.path, items: plan);
    expect(result.restored, isEmpty);
    expect(result.failed, unorderedEquals(['Neurons', 'Slides']));
    final metas = await FileNotebookRepository(rootA).listNotebooks();
    expect(metas, hasLength(2));
  });

  test('a notebook whose metadata cannot be read is reported, the rest restore', () async {
    File(p.join(rootA.path, 'notebooks', slides.id, 'notebook.json')).writeAsStringSync('{oops');
    final zip = await backUp();
    final info = await readBackupInfo(zip);
    expect(info.notebooks.map((n) => n.title), ['Neurons']);
    expect(info.unreadable, 1);
  });

  test('files that are not backups are refused with a readable message', () async {
    final notZip = File(p.join(scratch.path, 'x.zip'))..writeAsStringSync('nope');
    await expectLater(readBackupInfo(notZip.path),
        throwsA(isA<BackupException>().having((e) => e.message, 'message', contains('not a notebook backup'))));

    Future<String> zipWith(Map<String, Object?> manifest) async {
      final f = File(p.join(scratch.path, 'other.zip'));
      final w = await ZipWriter.create(f);
      await w.addBytes(backupManifestName, utf8.encode(jsonEncode(manifest)));
      await w.close();
      return f.path;
    }

    await expectLater(readBackupInfo(await zipWith({'format': 'something-else', 'version': 1})),
        throwsA(isA<BackupException>()));
    await expectLater(readBackupInfo(await zipWith({'format': 'neatink-backup', 'version': 99})),
        throwsA(isA<BackupException>().having((e) => e.message, 'message', contains('newer version'))));
  });

  test('runs in a background isolate', () async {
    final out = p.join(scratch.path, 'iso.zip');
    final root = rootA.path;
    final result = await Isolate.run(() => writeBackup(
        rootPath: root, outputPath: out, appData: const {}, appVersion: 'x'));
    expect(result.notebooks, 2);
    expect(result.bytes, File(out).lengthSync());
    final info = await Isolate.run(() => readBackupInfo(out));
    expect(info.notebooks, hasLength(2));
  });

  test('folders: only the ones restored notebooks need, with their parents', () {
    final t = DateTime.utc(2026);
    final backup = LibraryIndex(folders: [
      Folder(id: 'a', name: 'A', createdAt: t),
      Folder(id: 'b', name: 'B', parentId: 'a', createdAt: t),
      Folder(id: 'c', name: 'C', createdAt: t),
    ]);
    NotebookMeta inFolder(String? id) => NotebookMeta(
        id: 'n', title: 'n', createdAt: t, updatedAt: t, kind: NotebookKind.blank,
        defaultPaper: const Paper(), pages: const [], folderId: id);
    final merged = mergeRestoredFolders(const LibraryIndex(), backup, [inFolder('b')])!;
    expect(merged.folders.map((f) => f.id), ['a', 'b']);
    expect(mergeRestoredFolders(merged, backup, [inFolder('b')]), isNull);
    expect(mergeRestoredFolders(const LibraryIndex(), backup, [inFolder(null)]), isNull);
    expect(mergeRestoredFolders(const LibraryIndex(), backup, [inFolder('gone')]), isNull);
  });
}
