import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/notebook_meta.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/storage/file_notebook_repository.dart';
import 'package:neatink/storage/notebook_repository.dart';
import 'package:neatink/storage/page_codec.dart';
import 'package:neatink/storage/storage_errors.dart';
import 'package:path/path.dart' as p;

import 'storage_test_support.dart';

final RegExp _uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

const _lined = Paper(type: PaperType.lined, spacingPt: 24);

String _json(Object? o) => jsonEncode(o);

void main() {
  late Directory root;
  late StepClock clock;
  late FileNotebookRepository repo;

  setUp(() async {
    root = await createTempRoot();
    clock = StepClock();
    repo = FileNotebookRepository(root, clock: clock.call);
  });

  /// A repository over the same folder with empty caches, like the next
  /// app launch.
  FileNotebookRepository relaunch() =>
      FileNotebookRepository(root, clock: clock.call);

  String nbDir(String id) => p.join(root.path, 'notebooks', id);

  Future<List<String>> filesOf(String id) =>
      listFilesRecursively(Directory(nbDir(id)));

  group('createNotebook', () {
    test('writes notebook.json with clock timestamps and pages', () async {
      final meta = await repo.createNotebook(
        title: 'Physics',
        paper: _lined,
        pageCount: 3,
        folderId: 'folder-1',
        coverColor: 0xFF00897B,
      );
      expect(meta.id, matches(_uuidV4));
      expect(meta.title, 'Physics');
      expect(meta.kind, NotebookKind.blank);
      expect(meta.createdAt, clock.issued.single);
      expect(meta.updatedAt, clock.issued.single);
      expect(meta.defaultPaper, _lined);
      expect(meta.pages, hasLength(3));
      expect(meta.pages.map((pg) => pg.id).toSet(), hasLength(3));
      for (final page in meta.pages) {
        expect(page.id, matches(_uuidV4));
        expect(page.paper, _lined);
        expect(page.width, a4WidthPt);
        expect(page.height, a4HeightPt);
        expect(page.pdfPageIndex, isNull);
      }
      expect(meta.folderId, 'folder-1');
      expect(meta.coverColor, 0xFF00897B);

      expect(await filesOf(meta.id), ['notebook.json']);
      expect(Directory(p.join(nbDir(meta.id), 'pages')).existsSync(), isTrue);
      final onDisk = jsonDecode(
              File(p.join(nbDir(meta.id), 'notebook.json')).readAsStringSync())
          as Map<String, dynamic>;
      expect(onDisk['version'], NotebookMeta.currentVersion);

      final loaded = await relaunch().loadMeta(meta.id);
      expect(_json(loaded!.toJson()), _json(meta.toJson()));
    });

    test('always has at least one page and the default cover', () async {
      final meta = await repo.createNotebook(
          title: 'Empty', paper: const Paper(), pageCount: 0);
      expect(meta.pages, hasLength(1));
      expect(meta.coverColor, NotebookMeta.defaultCoverColor);
      expect(meta.folderId, isNull);
    });

    test('pages that were never saved load as empty pages', () async {
      final meta = await repo.createNotebook(title: 'A', paper: _lined);
      final page = await repo.loadPage(meta.id, meta.pages.single.id);
      expect(page.isEmpty, isTrue);
    });
  });

  group('createPdfNotebook', () {
    late File pdf;

    setUp(() async {
      pdf = File(p.join(root.path, 'import', 'lecture.pdf'));
      await pdf.create(recursive: true);
      await pdf.writeAsBytes(utf8.encode('%PDF-1.4\n% tiny test file\n%%EOF'));
    });

    test('copies the PDF and makes one page per PDF page', () async {
      final meta = await repo.createPdfNotebook(
        title: 'Lecture',
        sourcePdfPath: pdf.path,
        pageSizes: const [
          PdfPageSize(612, 792),
          PdfPageSize(842, 595),
          PdfPageSize(double.nan, 0),
        ],
        folderId: 'f',
      );
      expect(meta.kind, NotebookKind.pdf);
      expect(meta.isPdf, isTrue);
      expect(meta.createdAt, clock.issued.single);
      expect(meta.folderId, 'f');
      expect([for (final pg in meta.pages) pg.pdfPageIndex], [0, 1, 2]);
      expect([for (final pg in meta.pages) pg.width], [612, 842, a4WidthPt]);
      expect([for (final pg in meta.pages) pg.height], [792, 595, a4HeightPt]);
      expect(meta.pages.every((pg) => pg.paper.type == PaperType.blank),
          isTrue);

      final copy = File(repo.sourcePdfPath(meta.id));
      expect(copy.path, p.join(nbDir(meta.id), 'source.pdf'));
      expect(await copy.readAsBytes(), await pdf.readAsBytes());
      expect(await pdf.exists(), isTrue, reason: 'original left alone');
      expect(await filesOf(meta.id), ['notebook.json', 'source.pdf']);
    });

    test('needs at least one page', () async {
      await expectLater(
        repo.createPdfNotebook(
            title: 'x', sourcePdfPath: pdf.path, pageSizes: const []),
        throwsArgumentError,
      );
      expect(await repo.listNotebooks(), isEmpty);
    });

    test('a missing source PDF leaves no half-made notebook', () async {
      await expectLater(
        repo.createPdfNotebook(
          title: 'x',
          sourcePdfPath: p.join(root.path, 'missing.pdf'),
          pageSizes: const [PdfPageSize(100, 100)],
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await repo.listNotebooks(), isEmpty);
      final notebooks = Directory(p.join(root.path, 'notebooks'));
      expect(await notebooks.list().toList(), isEmpty);
    });
  });

  group('metadata', () {
    test('saveMeta writes the meta exactly as given', () async {
      final meta = await repo.createNotebook(title: 'A', paper: _lined);
      final edited = meta.copyWith(
        title: 'B',
        updatedAt: DateTime.utc(2030, 1, 2, 3, 4, 5),
        tags: ['physics', 'exam'],
        favorite: true,
        coverColor: 0xFFE53935,
        lastPageIndex: 0,
        pages: [
          ...meta.pages,
          const PageMeta(id: 'second-page', paper: Paper(type: PaperType.grid)),
        ],
      );
      final issued = clock.issued.length;
      await repo.saveMeta(edited);
      expect(clock.issued.length, issued, reason: 'saveMeta adds no time');

      final loaded = await relaunch().loadMeta(meta.id);
      expect(_json(loaded!.toJson()), _json(edited.toJson()));
      expect((await relaunch().listNotebooks()).single.title, 'B');
    });

    test('saveMeta of an unknown notebook throws', () async {
      final ghost = NotebookMeta(
        id: 'ghost',
        title: 'x',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      await expectLater(
          repo.saveMeta(ghost), throwsA(isA<NotebookNotFoundException>()));
      expect(Directory(nbDir('ghost')).existsSync(), isFalse);
    });

    test('loadMeta of an unknown notebook is null', () async {
      expect(await repo.loadMeta('nope'), isNull);
    });

    test('renameNotebook sets the title and bumps updatedAt', () async {
      final meta = await repo.createNotebook(title: 'Old', paper: _lined);
      await repo.renameNotebook(meta.id, 'New');
      final loaded = await relaunch().loadMeta(meta.id);
      expect(loaded!.title, 'New');
      expect(loaded.createdAt, meta.createdAt);
      expect(loaded.updatedAt, clock.issued.last);
      expect(loaded.updatedAt.isAfter(meta.updatedAt), isTrue);
      expect(loaded.pages.single.id, meta.pages.single.id);
    });

    test('renameNotebook of an unknown notebook throws', () async {
      await expectLater(repo.renameNotebook('nope', 'x'),
          throwsA(isA<NotebookNotFoundException>()));
    });

    test('the folder name wins over a mismatched id in the file', () async {
      final meta = await repo.createNotebook(title: 'A', paper: _lined);
      final file = File(p.join(nbDir(meta.id), 'notebook.json'));
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>
        ..['id'] = 'something-else';
      await file.writeAsString(jsonEncode(json));
      expect((await relaunch().loadMeta(meta.id))!.id, meta.id);
    });
  });

  group('listNotebooks', () {
    test('lists every notebook', () async {
      final a = await repo.createNotebook(title: 'A', paper: _lined);
      final b = await repo.createNotebook(title: 'B', paper: _lined);
      final listed = await relaunch().listNotebooks();
      expect(listed.map((m) => m.id).toSet(), {a.id, b.id});
    });

    test('an empty library lists nothing', () async {
      expect(await repo.listNotebooks(), isEmpty);
    });

    test('skips corrupt notebooks and never deletes them', () async {
      final good = await repo.createNotebook(title: 'Good', paper: _lined);
      final bad = await repo.createNotebook(title: 'Bad', paper: _lined);
      final badMeta = File(p.join(nbDir(bad.id), 'notebook.json'));
      await badMeta.writeAsString('{"title": "Bad", "pa');
      // A folder without notebook.json (e.g. a crash during create).
      final bare = Directory(nbDir('bare-folder'));
      await Directory(p.join(bare.path, 'pages')).create(recursive: true);
      // Not notebook folders at all.
      await Directory(p.join(root.path, 'notebooks', 'not valid!'))
          .create(recursive: true);
      await File(p.join(root.path, 'notebooks', 'stray.txt'))
          .writeAsString('x');

      final listed = await relaunch().listNotebooks();
      expect(listed.map((m) => m.id), [good.id]);
      expect(await badMeta.readAsString(), '{"title": "Bad", "pa');
      expect(bare.existsSync(), isTrue);
    });

    test('uses notebook.json.bak when notebook.json is corrupt', () async {
      final meta = await repo.createNotebook(title: 'First', paper: _lined);
      await repo.renameNotebook(meta.id, 'Second');
      await File(p.join(nbDir(meta.id), 'notebook.json'))
          .writeAsString('corrupt');
      final listed = await relaunch().listNotebooks();
      expect(listed.single.title, 'First');
    });

    test('a notebook.json with a path-like page id is rejected', () async {
      final meta = await repo.createNotebook(title: 'A', paper: _lined);
      final file = File(p.join(nbDir(meta.id), 'notebook.json'));
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      ((json['pages'] as List<dynamic>).first as Map<String, dynamic>)['id'] =
          '../../escape';
      await file.writeAsString(jsonEncode(json));
      expect(await relaunch().listNotebooks(), isEmpty);
      expect(await file.exists(), isTrue);
    });

    test('finishes a delete that was interrupted', () async {
      final trash = Directory(
          p.join(root.path, 'notebooks', '.deleted-abc-1234', 'pages'));
      await trash.create(recursive: true);
      await File(p.join(trash.path, 'x.json')).writeAsString('{}');
      expect(await repo.listNotebooks(), isEmpty);
      expect(trash.parent.existsSync(), isFalse);
    });
  });

  group('pages', () {
    late NotebookMeta meta;
    late String pageId;

    setUp(() async {
      meta = await repo.createNotebook(title: 'Ink', paper: _lined);
      pageId = meta.pages.single.id;
    });

    test('strokes round trip exactly (raw and points)', () async {
      final shapeRaw = wavePoints(8, y0: 300);
      final content = PageContent(strokes: [
        penStroke('plain', points: 40),
        tidiedStroke('tidied'),
        Stroke(
          id: 'hl',
          tool: StrokeTool.highlighter,
          color: 0x80FFEB3B,
          size: 12,
          raw: wavePoints(5, y0: 200),
        ),
        Stroke(
          id: 'shape',
          tool: StrokeTool.pen,
          penStyle: PenStyle.pencil,
          color: 0xFF000000,
          size: 1,
          raw: shapeRaw,
          points: [shapeRaw.first, shapeRaw.last],
          shape: ShapeKind.line,
        ),
        Stroke(
          id: 'locked',
          tool: StrokeTool.pen,
          color: 0xFF123456,
          size: 3,
          raw: wavePoints(3),
          tidy: const TidyInfo(applied: false, version: 1, locked: true),
        ),
      ]);
      await repo.savePage(meta.id, pageId, content);
      final loaded = await relaunch().loadPage(meta.id, pageId);

      expect(loaded.strokes, hasLength(5));
      for (var i = 0; i < 5; i++) {
        final a = content.strokes[i], b = loaded.strokes[i];
        expect(b.id, a.id);
        expect(b.raw, a.raw, reason: '${a.id}: raw must survive exactly');
        expect(b.points, a.points, reason: '${a.id}: points exactly');
        expect(b.pointsAreRaw, a.pointsAreRaw, reason: a.id);
        expect(_json(b.toJson()), _json(a.toJson()));
      }
      final plain = loaded.strokeById('plain')!;
      expect(plain.pointsAreRaw, isTrue);
      expect(plain.penStyle, PenStyle.fountain);
      expect(plain.wordId, 'w-plain');

      final tidied = loaded.strokeById('tidied')!;
      expect(tidied.pointsAreRaw, isFalse);
      expect(tidied.tidy, const TidyInfo(applied: true, version: 1));
      expect(tidied.raw, isNot(equals(tidied.points)));

      expect(loaded.strokeById('hl')!.tool, StrokeTool.highlighter);
      expect(loaded.strokeById('hl')!.color, 0x80FFEB3B);
      expect(loaded.strokeById('shape')!.shape, ShapeKind.line);
      expect(loaded.strokeById('shape')!.raw, shapeRaw);
      expect(loaded.strokeById('shape')!.points, hasLength(2));
      expect(loaded.strokeById('locked')!.tidy.locked, isTrue);
    });

    test('unquantized points are stored at the documented precision',
        () async {
      final stroke = Stroke(
        id: 's',
        tool: StrokeTool.pen,
        color: 0xFF000000,
        size: 2,
        raw: const [InkPoint(10.123456, 20.987654, 0.33333, 5)],
      );
      await repo.savePage(meta.id, pageId, PageContent(strokes: [stroke]));
      final loaded = await relaunch().loadPage(meta.id, pageId);
      expect(loaded.strokes.single.raw.single,
          const InkPoint(10.12, 20.99, 0.333, 5));
      expect(loaded.strokes.single.pointsAreRaw, isTrue);
    });

    test('text and image items round trip with every field', () async {
      const text = TextItem(
        id: 't1',
        x: 12.5,
        y: 40,
        width: 200,
        height: 48,
        text: 'Hello\nwörld',
        fontSize: 18,
        color: 0xFFD81B60,
        bold: true,
        italic: true,
        underline: true,
        align: TextAlignKind.center,
        font: FontKind.serif,
        background: 0x33FFEB3B,
      );
      const image = ImageItem(
        id: 'i1',
        x: 100,
        y: 150,
        width: 240,
        height: 180,
        asset: 'pic.png',
        pixelWidth: 1024,
        pixelHeight: 768,
      );
      await repo.savePage(meta.id, pageId,
          PageContent(texts: [text], images: [image]));
      final loaded = await relaunch().loadPage(meta.id, pageId);
      expect(_json(loaded.texts.single.toJson()), _json(text.toJson()));
      expect(_json(loaded.images.single.toJson()), _json(image.toJson()));
      expect(loaded.texts.single.text, 'Hello\nwörld');
      expect(loaded.texts.single.align, TextAlignKind.center);
      expect(loaded.images.single.asset, 'pic.png');
    });

    test('the page is snapshotted when savePage is called', () async {
      final content = PageContent(strokes: [penStroke('a')]);
      final saving = repo.savePage(meta.id, pageId, content);
      content.strokes.add(penStroke('b'));
      await saving;
      final loaded = await relaunch().loadPage(meta.id, pageId);
      expect(loaded.strokes.map((s) => s.id), ['a']);
    });

    test('writes are atomic: no temp files remain', () async {
      for (var i = 0; i < 5; i++) {
        await repo.savePage(meta.id, pageId,
            PageContent(strokes: [for (var j = 0; j <= i; j++) penStroke('s$j')]));
      }
      final files = await filesOf(meta.id);
      expect(files.where((f) => f.contains('.tmp-')), isEmpty);
      expect(files, containsAll(['pages/$pageId.json', 'pages/$pageId.json.bak']));
    });

    test('falls back to the .bak copy when the page file is corrupt',
        () async {
      await repo.savePage(meta.id, pageId, PageContent(strokes: [penStroke('v1')]));
      await repo.savePage(meta.id, pageId,
          PageContent(strokes: [penStroke('v1'), penStroke('v2')]));
      final file = File(p.join(nbDir(meta.id), 'pages', '$pageId.json'));
      await file.writeAsString('{"strokes": [{"id": "v1", "ra');

      final reopened = relaunch();
      final loaded = await reopened.loadPage(meta.id, pageId);
      expect(loaded.strokes.map((s) => s.id), ['v1']);
      expect(await file.readAsString(), startsWith('{"strokes"'),
          reason: 'reading never repairs or deletes');

      // The next save keeps the unreadable file instead of destroying it.
      loaded.strokes.add(penStroke('v3'));
      await reopened.savePage(meta.id, pageId, loaded);
      expect(await filesOf(meta.id),
          containsAll(['pages/$pageId.json', 'pages/$pageId.json.corrupt']));
      expect((await relaunch().loadPage(meta.id, pageId)).strokes.length, 2);
    });

    test('a page whose copies are all unreadable throws, files kept',
        () async {
      final file = File(p.join(nbDir(meta.id), 'pages', '$pageId.json'));
      await file.writeAsString('nope');
      await expectLater(relaunch().loadPage(meta.id, pageId),
          throwsA(isA<CorruptFileException>()));
      expect(await file.readAsString(), 'nope');
    });

    test('concurrent saves to one notebook never lose an update', () async {
      final ids = [for (var i = 0; i < 12; i++) 'page-$i'];
      await repo.saveMeta(
          meta.copyWith(pages: [for (final id in ids) PageMeta(id: id)]));
      await Future.wait([
        for (final id in ids)
          repo.savePage(
            meta.id,
            id,
            PageContent(strokes: [penStroke(id)], texts: [
              TextItem(id: 't', x: 0, y: 0, width: 9, height: 9, text: 'w $id'),
            ]),
          ),
        repo.savePdfText(meta.id, {ids.first: 'pdf text'}),
        repo.saveThumbnail(meta.id, Uint8List.fromList([1])),
      ]);
      final next = relaunch();
      for (final id in ids) {
        expect((await next.loadPage(meta.id, id)).strokes.single.id, id);
      }
      final search = jsonDecode(File(p.join(nbDir(meta.id), 'search.json'))
          .readAsStringSync()) as Map<String, dynamic>;
      final pages = search['pages'] as Map<String, dynamic>;
      expect(pages.keys.toSet(), ids.toSet());
      expect((pages[ids.first] as Map<String, dynamic>)['pdf'], 'pdf text');
      expect(
          (await filesOf(meta.id)).where((f) => f.contains('.tmp-')), isEmpty);
    });

    test('savePage to an unknown notebook throws', () async {
      await expectLater(repo.savePage('missing', 'page', PageContent()),
          throwsA(isA<NotebookNotFoundException>()));
    });

    test('saveMeta deletes orphan page files only', () async {
      final three = meta.copyWith(pages: [
        ...meta.pages,
        const PageMeta(id: 'page-two'),
        const PageMeta(id: 'page-three'),
      ]);
      await repo.saveMeta(three);
      for (final page in three.pages) {
        await repo.savePage(meta.id, page.id, PageContent(strokes: [penStroke(page.id)]));
        await repo.savePage(meta.id, page.id, PageContent(strokes: [penStroke(page.id)]));
      }
      final pagesDir = p.join(nbDir(meta.id), 'pages');
      await File(p.join(pagesDir, 'page-two.json.corrupt')).writeAsString('x');
      await File(p.join(pagesDir, 'readme.txt')).writeAsString('not ours');
      await File(p.join(pagesDir, 'page-one.json.tmp-0badf00d'))
          .writeAsString('half');

      await repo.saveMeta(three.copyWith(
          pages: [three.pages[0], three.pages[2]]));

      final files = await filesOf(meta.id);
      expect(files.where((f) => f.contains('page-two')), isEmpty);
      expect(files.where((f) => f.contains('.tmp-')), isEmpty);
      expect(files, containsAll([
        'pages/$pageId.json',
        'pages/$pageId.json.bak',
        'pages/page-three.json',
        'pages/page-three.json.bak',
        'pages/readme.txt',
      ]));
      expect((await relaunch().loadPage(meta.id, 'page-three')).strokes,
          hasLength(1));
    });

    test('large pages are encoded and decoded off the UI isolate', () async {
      final big = PageContent(strokes: [
        for (var i = 0; i < 2100; i++) penStroke('s$i', points: 12, y0: (i % 800).toDouble()),
      ]);
      expect(big.strokes.length, greaterThan(PageCodec.backgroundStrokeThreshold));
      expect(PageCodec.encodesInBackground(big), isTrue);
      expect(PageCodec.encodesInBackground(PageContent(strokes: [penStroke('x')])),
          isFalse);

      final bytes = await PageCodec.encode(big);
      expect(bytes, PageCodec.encodeSync(big));

      await repo.savePage(meta.id, pageId, big);
      final file = File(p.join(nbDir(meta.id), 'pages', '$pageId.json'));
      expect(await file.length(),
          greaterThanOrEqualTo(PageCodec.backgroundByteThreshold),
          reason: 'big enough to take the background decode path');

      final loaded = await relaunch().loadPage(meta.id, pageId);
      expect(loaded.strokes, hasLength(2100));
      expect(_json(loaded.toJson()), _json(big.toJson()));
      expect(loaded.strokes.every((s) => s.pointsAreRaw), isTrue);
    });

    test('estimateJsonBytes is in the right ballpark', () {
      final page = PageContent(strokes: [
        for (var i = 0; i < 50; i++) penStroke('s$i', points: 30),
      ]);
      final actual = PageCodec.encodeSync(page).length;
      final estimate = PageCodec.estimateJsonBytes(page);
      expect(estimate, greaterThan(actual * 0.5));
      expect(estimate, lessThan(actual * 2));
    });
  });

  group('ids are validated before they become paths', () {
    test('notebook and page ids', () async {
      final meta = await repo.createNotebook(title: 'A', paper: _lined);
      for (final bad in ['../x', r'..\x', 'a/b', '', '.', 'C:', 'a b']) {
        expect(() => repo.loadPage(bad, 'page'), throwsArgumentError,
            reason: bad);
        expect(() => repo.loadPage(meta.id, bad), throwsArgumentError,
            reason: bad);
        expect(() => repo.savePage(meta.id, bad, PageContent()),
            throwsArgumentError,
            reason: bad);
        expect(() => repo.sourcePdfPath(bad), throwsArgumentError);
        expect(() => repo.thumbnailPath(bad), throwsArgumentError);
        expect(() => repo.deleteNotebook(bad), throwsArgumentError);
      }
      expect(
        () => repo.saveMeta(meta.copyWith(pages: [const PageMeta(id: '../p')])),
        throwsArgumentError,
      );
      expect(() => repo.assetPath(meta.id, '../evil.png'), throwsArgumentError);
      expect(() => repo.assetPath(meta.id, 'a.png/..'), throwsArgumentError);
      expect(() => repo.savePdfText(meta.id, {'../p': 'x'}), throwsArgumentError);
      expect(repo.assetPath(meta.id, 'ok-1.png'),
          p.join(nbDir(meta.id), 'assets', 'ok-1.png'));
    });
  });

  group('deleteNotebook', () {
    test('removes the folder and the notebook from listings and search',
        () async {
      final keep = await repo.createNotebook(title: 'Keep', paper: _lined);
      final gone = await repo.createNotebook(title: 'Gone', paper: _lined);
      await repo.savePage(gone.id, gone.pages.single.id,
          PageContent(strokes: [penStroke('s')]));
      expect(await repo.search('gone'), isNotEmpty);

      await repo.deleteNotebook(gone.id);
      expect(Directory(nbDir(gone.id)).existsSync(), isFalse);
      expect((await repo.listNotebooks()).map((m) => m.id), [keep.id]);
      expect(await repo.loadMeta(gone.id), isNull);
      expect(await repo.search('gone'), isEmpty);
      final leftovers = await Directory(p.join(root.path, 'notebooks'))
          .list()
          .map((e) => p.basename(e.path))
          .toList();
      expect(leftovers, [keep.id]);
    });

    test('deleting an unknown notebook is a no-op', () async {
      await repo.deleteNotebook('never-existed');
    });
  });

  group('assets & thumbnails', () {
    late NotebookMeta meta;

    setUp(() async {
      meta = await repo.createNotebook(title: 'Pics', paper: _lined);
    });

    Future<File> sourceImage(String name, List<int> bytes) async {
      final f = File(p.join(root.path, 'gallery', name));
      await f.create(recursive: true);
      await f.writeAsBytes(bytes);
      return f;
    }

    Future<List<String>> assetFiles() async =>
        [for (final f in await filesOf(meta.id)) if (f.startsWith('assets/')) f];

    test('addAsset copies the file under a new safe name', () async {
      final src = await sourceImage('Holiday Photo.JPG', [1, 2, 3, 4]);
      final name = await repo.addAsset(meta.id, src.path);
      expect(name, matches(RegExp(r'^[0-9a-f-]{36}\.jpg$')));
      final copy = File(repo.assetPath(meta.id, name));
      expect(await copy.readAsBytes(), [1, 2, 3, 4]);
      expect(await src.exists(), isTrue);
      expect(await assetFiles(), ['assets/$name']);
    });

    test('addAssetBytes sanitizes the extension', () async {
      final a = await repo.addAssetBytes(meta.id, Uint8List.fromList([1]), '.PNG');
      final b = await repo.addAssetBytes(meta.id, Uint8List.fromList([2]), 'tar.gz');
      final c = await repo.addAssetBytes(meta.id, Uint8List.fromList([3]), '');
      final d = await repo.addAssetBytes(
          meta.id, Uint8List.fromList([4]), '../../x/../png');
      expect(a, endsWith('.png'));
      expect(b, endsWith('.gz'));
      expect(c, endsWith('.bin'));
      expect(d, endsWith('.png'));
      expect(await File(repo.assetPath(meta.id, b)).readAsBytes(), [2]);
    });

    test('adding an asset to an unknown notebook throws', () async {
      await expectLater(
          repo.addAssetBytes('missing', Uint8List.fromList([1]), 'png'),
          throwsA(isA<NotebookNotFoundException>()));
    });

    test('unreferenced assets are cleaned up, but only when safe', () async {
      final pageId = meta.pages.single.id;
      final used = await repo.addAssetBytes(meta.id, Uint8List.fromList([1]), 'png');
      final unused =
          await repo.addAssetBytes(meta.id, Uint8List.fromList([2]), 'png');
      await repo.savePage(
          meta.id,
          pageId,
          PageContent(images: [
            ImageItem(id: 'i', x: 0, y: 0, width: 10, height: 10, asset: used),
          ]));

      // Same session: an asset added now may come back with undo, so it
      // stays even though no page uses it.
      await repo.saveMeta(meta);
      expect(await assetFiles(), unorderedEquals(['assets/$used', 'assets/$unused']));

      // Next launch: nothing references `unused` any more.
      final next = relaunch();
      await next.saveMeta(meta);
      expect(await assetFiles(), ['assets/$used']);
      expect(await File(next.assetPath(meta.id, used)).readAsBytes(), [1]);
    });

    test('assets are kept when any page cannot be read', () async {
      final pageId = meta.pages.single.id;
      final withTwo = meta.copyWith(
          pages: [...meta.pages, const PageMeta(id: 'second')]);
      await repo.saveMeta(withTwo);
      final asset = await repo.addAssetBytes(meta.id, Uint8List.fromList([1]), 'png');
      await repo.savePage(
          meta.id,
          'second',
          PageContent(images: [
            ImageItem(id: 'i', x: 0, y: 0, width: 1, height: 1, asset: asset),
          ]));
      await repo.savePage(meta.id, pageId, PageContent());
      // The page that references the asset becomes unreadable.
      await File(p.join(nbDir(meta.id), 'pages', 'second.json'))
          .writeAsString('broken');
      await File(p.join(nbDir(meta.id), 'pages', 'second.json.bak'))
          .writeAsString('broken');

      await relaunch().saveMeta(withTwo);
      expect(await assetFiles(), ['assets/$asset']);
    });

    test('assets of a deleted page are removed on a later launch', () async {
      final withTwo = meta.copyWith(
          pages: [...meta.pages, const PageMeta(id: 'second')]);
      await repo.saveMeta(withTwo);
      final asset = await repo.addAssetBytes(meta.id, Uint8List.fromList([1]), 'webp');
      await repo.savePage(
          meta.id,
          'second',
          PageContent(images: [
            ImageItem(id: 'i', x: 0, y: 0, width: 1, height: 1, asset: asset),
          ]));
      // Delete the page in this session: the asset is kept for undo.
      await repo.saveMeta(meta);
      expect(await assetFiles(), ['assets/$asset']);
      // Next launch: the page is gone for good, so is its picture.
      await relaunch().saveMeta(meta);
      expect(await assetFiles(), isEmpty);
    });

    test('saveThumbnail writes thumb.png atomically', () async {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
      await repo.saveThumbnail(meta.id, png);
      await repo.saveThumbnail(meta.id, png);
      expect(repo.thumbnailPath(meta.id), p.join(nbDir(meta.id), 'thumb.png'));
      expect(await File(repo.thumbnailPath(meta.id)).readAsBytes(), png);
      expect(await filesOf(meta.id), ['notebook.json', 'thumb.png']);
    });
  });

  group('duplicateNotebook', () {
    test('deep copies pages, assets, PDF, thumbnail and search text',
        () async {
      final pdf = File(p.join(root.path, 'doc.pdf'));
      await pdf.writeAsBytes(utf8.encode('%PDF-1.4 dup test'));
      final source = await repo.createPdfNotebook(
        title: 'Notes',
        sourcePdfPath: pdf.path,
        pageSizes: const [PdfPageSize(600, 800), PdfPageSize(600, 800)],
      );
      final tagged = source.copyWith(tags: ['t1'], favorite: true);
      await repo.saveMeta(tagged);
      final p0 = source.pages[0].id, p1 = source.pages[1].id;
      final asset =
          await repo.addAssetBytes(source.id, Uint8List.fromList([7, 7]), 'png');
      await repo.savePage(
          source.id,
          p0,
          PageContent(
            strokes: [penStroke('a'), tidiedStroke('b')],
            texts: [
              const TextItem(
                  id: 't', x: 1, y: 2, width: 50, height: 20, text: 'kinematics'),
            ],
            images: [
              ImageItem(id: 'i', x: 0, y: 0, width: 5, height: 5, asset: asset),
            ],
          ));
      await repo.savePdfText(source.id, {p1: 'Newton laws of motion'});
      await repo.saveThumbnail(source.id, Uint8List.fromList([1, 2, 3]));

      final copy = await repo.duplicateNotebook(source.id);
      expect(copy.id, isNot(source.id));
      expect(copy.id, matches(_uuidV4));
      expect(copy.title, 'Notes (copy)');
      expect(copy.kind, NotebookKind.pdf);
      expect(copy.tags, ['t1']);
      expect(copy.favorite, isTrue);
      expect(copy.createdAt, clock.issued.last);
      expect(copy.updatedAt, clock.issued.last);
      expect(copy.pages, hasLength(2));
      final copyIds = copy.pages.map((pg) => pg.id).toSet();
      expect(copyIds.intersection({p0, p1}), isEmpty);
      expect([for (final pg in copy.pages) pg.pdfPageIndex], [0, 1]);

      final fresh = relaunch();
      final original = await fresh.loadPage(source.id, p0);
      final copied = await fresh.loadPage(copy.id, copy.pages[0].id);
      expect(_json(copied.toJson()), _json(original.toJson()));
      expect((await fresh.loadPage(copy.id, copy.pages[1].id)).isEmpty, isTrue);

      expect(await File(fresh.assetPath(copy.id, asset)).readAsBytes(), [7, 7]);
      expect(await File(fresh.sourcePdfPath(copy.id)).readAsBytes(),
          await pdf.readAsBytes());
      expect(await File(fresh.thumbnailPath(copy.id)).readAsBytes(), [1, 2, 3]);

      final textHits = await fresh.search('kinematics');
      expect(textHits.map((h) => h.notebookId).toSet(), {source.id, copy.id});
      final copyText = textHits.firstWhere((h) => h.notebookId == copy.id);
      expect(copyText.pageId, copy.pages[0].id);
      final pdfHits = await fresh.search('newton');
      final copyPdf = pdfHits.firstWhere((h) => h.notebookId == copy.id);
      expect(copyPdf.kind, SearchMatchKind.pdf);
      expect(copyPdf.pageId, copy.pages[1].id);
      expect(copyPdf.pageIndex, 1);

      // The source is unchanged.
      final reloaded = await fresh.loadMeta(source.id);
      expect(_json(reloaded!.toJson()), _json(tagged.toJson()));
      expect((await fresh.listNotebooks()).length, 2);
    });

    test('duplicating an unknown notebook throws', () async {
      await expectLater(repo.duplicateNotebook('missing'),
          throwsA(isA<NotebookNotFoundException>()));
    });

    test('a failed copy leaves no partial notebook', () async {
      final source = await repo.createNotebook(title: 'S', paper: _lined);
      // An unreadable page makes the copy fail midway.
      final pageFile = File(
          p.join(nbDir(source.id), 'pages', '${source.pages.single.id}.json'));
      await pageFile.writeAsString('broken');
      await expectLater(repo.duplicateNotebook(source.id),
          throwsA(isA<CorruptFileException>()));
      expect((await relaunch().listNotebooks()).map((m) => m.id), [source.id]);
      final folders = await Directory(p.join(root.path, 'notebooks'))
          .list()
          .toList();
      expect(folders, hasLength(1));
      expect(await pageFile.readAsString(), 'broken');
    });
  });

  group('library.json', () {
    test('a missing library is empty', () async {
      expect((await repo.loadLibrary()).folders, isEmpty);
    });

    test('nested folders round trip', () async {
      final library = LibraryIndex(folders: [
        Folder(id: 'school', name: 'School', createdAt: DateTime.utc(2026, 1)),
        Folder(
          id: 'physics',
          name: 'Physics',
          parentId: 'school',
          color: 0xFF1E88E5,
          createdAt: DateTime.utc(2026, 2),
        ),
      ]);
      await repo.saveLibrary(library);
      final loaded = await relaunch().loadLibrary();
      expect(_json(loaded.toJson()), _json(library.toJson()));
      expect(loaded.childrenOf('school').single.name, 'Physics');
      final onDisk = jsonDecode(
              File(p.join(root.path, 'library.json')).readAsStringSync())
          as Map<String, dynamic>;
      expect(onDisk['version'], LibraryIndex.currentVersion);
    });

    test('a corrupt library shows no folders and is never destroyed',
        () async {
      final file = File(p.join(root.path, 'library.json'));
      await file.writeAsString('{"folders": [');
      expect((await repo.loadLibrary()).folders, isEmpty);
      expect(await file.readAsString(), '{"folders": [');

      await repo.saveLibrary(LibraryIndex(folders: [
        Folder(id: 'f', name: 'F', createdAt: DateTime.utc(2026)),
      ]));
      expect(File(p.join(root.path, 'library.json.corrupt')).readAsStringSync(),
          '{"folders": [');
      expect((await relaunch().loadLibrary()).folders.single.id, 'f');
    });

    test('loadLibrary cleans up stray temp files in the root', () async {
      final stray = File(p.join(root.path, 'library.json.tmp-12345678'));
      await stray.writeAsString('half');
      await repo.loadLibrary();
      expect(stray.existsSync(), isFalse);
    });
  });
}
