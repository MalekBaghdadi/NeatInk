import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/notebook_meta.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/storage/file_notebook_repository.dart';
import 'package:neatink/storage/storage_errors.dart';
import 'package:path/path.dart' as p;

import 'storage_test_support.dart';

void main() {
  late Directory root;
  late StepClock clock;
  late FileNotebookRepository repo;

  setUp(() async {
    root = await createTempRoot();
    clock = StepClock();
    repo = FileNotebookRepository(root, clock: clock.call);
  });

  Future<NotebookMeta> notebook(String title, {String? folderId, String text = 'brain cells'}) async {
    final meta = await repo.createNotebook(title: title, paper: const Paper(), folderId: folderId);
    await repo.savePage(meta.id, meta.pages.first.id,
        PageContent(texts: [TextItem(id: 't', x: 0, y: 0, width: 100, height: 20, text: text)]));
    return meta;
  }

  test('a trashed notebook leaves the library and search, with its files', () async {
    final a = await notebook('Anatomy');
    await repo.saveThumbnail(a.id, Uint8List.fromList([1, 2, 3]));
    await repo.trashNotebook(a.id);

    expect(await repo.listNotebooks(), isEmpty);
    expect(await repo.search('brain'), isEmpty);
    expect(Directory(p.join(root.path, 'notebooks', a.id)).existsSync(), isFalse);
    final trash = await repo.listTrash();
    expect(trash.single.meta.title, 'Anatomy');
    expect(trash.single.thumbnailPath, isNotNull);
    expect(File(trash.single.thumbnailPath!).readAsBytesSync(), [1, 2, 3]);
    // The date comes from the clock, and survives the next launch.
    final when = trash.single.deletedAt;
    final again = await FileNotebookRepository(root, clock: clock.call).listTrash();
    expect(again.single.deletedAt, when);
  });

  test('restoring brings back the pages, search and its folder', () async {
    final library = await repo.loadLibrary();
    final folder = Folder(id: 'f1', name: 'Uni', createdAt: DateTime.utc(2026));
    await repo.saveLibrary(library.copyWith(folders: [folder]));
    final a = await notebook('Anatomy', folderId: 'f1');
    await repo.trashNotebook(a.id);
    final back = await repo.restoreFromTrash(a.id);

    expect(back.id, a.id);
    expect(back.folderId, 'f1');
    expect((await repo.listNotebooks()).single.title, 'Anatomy');
    expect((await repo.loadPage(a.id, a.pages.first.id)).texts.single.text, 'brain cells');
    expect(await repo.search('brain'), isNotEmpty);
    expect(await repo.listTrash(), isEmpty);
    expect(File(p.join(root.path, 'notebooks', a.id, 'trashed.json')).existsSync(), isFalse);
  });

  test('a notebook whose folder is gone comes back at the top level', () async {
    await repo.saveLibrary(LibraryIndex(folders: [Folder(id: 'f1', name: 'Uni', createdAt: DateTime.utc(2026))]));
    final a = await notebook('Anatomy', folderId: 'f1');
    await repo.trashNotebook(a.id);
    await repo.saveLibrary(const LibraryIndex());
    final back = await repo.restoreFromTrash(a.id);
    expect(back.folderId, isNull);
    expect((await repo.loadMeta(a.id))!.folderId, isNull);
  });

  test('a notebook whose id came back meanwhile is restored with a new id', () async {
    final a = await notebook('Anatomy');
    await repo.trashNotebook(a.id);
    // The same notebook restored from a backup in the meantime.
    final from = Directory(p.join(root.path, 'trash', a.id));
    await copyDirectory(from, Directory(p.join(root.path, 'notebooks', a.id)));
    final back = await repo.restoreFromTrash(a.id);
    expect(back.id, isNot(a.id));
    expect((await repo.listNotebooks()).map((m) => m.title), ['Anatomy', 'Anatomy']);
  });

  test('delete for good, and emptying old ones', () async {
    final a = await notebook('Old');
    await repo.trashNotebook(a.id);
    final cut = clock.call();
    final b = await notebook('New');
    await repo.trashNotebook(b.id);

    expect(await repo.emptyTrash(before: cut), 1);
    expect((await repo.listTrash()).map((t) => t.meta.title), ['New']);
    expect(Directory(p.join(root.path, 'trash', a.id)).existsSync(), isFalse);

    await repo.deleteFromTrash(b.id);
    expect(await repo.listTrash(), isEmpty);
    expect(Directory(p.join(root.path, 'trash')).listSync(), isEmpty);
  });

  test('trashing a notebook that does not exist fails, and so does restoring one', () async {
    await expectLater(repo.trashNotebook('missing'), throwsA(isA<NotebookNotFoundException>()));
    await expectLater(repo.restoreFromTrash('missing'), throwsA(isA<NotebookNotFoundException>()));
  });
}

Future<void> copyDirectory(Directory from, Directory to) async {
  await to.create(recursive: true);
  await for (final e in from.list(recursive: true)) {
    final rel = p.relative(e.path, from: from.path);
    if (e is Directory) {
      await Directory(p.join(to.path, rel)).create(recursive: true);
    } else if (e is File) {
      await File(p.join(to.path, rel)).parent.create(recursive: true);
      await e.copy(p.join(to.path, rel));
    }
  }
}
