import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/notebook_meta.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/storage/file_notebook_repository.dart';
import 'package:neatink/storage/notebook_repository.dart';
import 'package:neatink/storage/search_data.dart';
import 'package:neatink/storage/search_engine.dart';
import 'package:neatink/storage/text_fold.dart';
import 'package:path/path.dart' as p;

import 'storage_test_support.dart';

NotebookMeta _nb(
  String id,
  String title, {
  List<String> pages = const ['p0'],
  List<String> tags = const [],
  String? folderId,
  DateTime? updatedAt,
}) =>
    NotebookMeta(
      id: id,
      title: title,
      createdAt: DateTime.utc(2026),
      updatedAt: updatedAt ?? DateTime.utc(2026),
      pages: [for (final pg in pages) PageMeta(id: pg)],
      tags: tags,
      folderId: folderId,
    );

/// Snippet for [query] in [text], found the way the search engine does.
String snippetFor(String text, String query) {
  final q = foldForSearch(query);
  final at = foldForSearch(text).indexOf(q);
  expect(at, greaterThanOrEqualTo(0), reason: 'test text must match');
  return buildSnippet(text, at, q.length);
}

String _strip(String snippet) {
  var s = snippet;
  if (s.startsWith('…')) s = s.substring(1);
  if (s.endsWith('…')) s = s.substring(0, s.length - 1);
  return s;
}

TextItem _text(String id, String text) =>
    TextItem(id: id, x: 0, y: 0, width: 100, height: 20, text: text);

void main() {
  group('foldForSearch', () {
    test('lowercases and removes Latin accents', () {
      expect(foldForSearch('Résumé CAFÉ Ångström'), 'resume cafe angstrom');
      expect(foldForSearch('Straße Œuvre Æther'), 'strasse oeuvre aether');
      expect(foldForSearch('ŁÓDŹ Ñandú Čeština'), 'lodz nandu cestina');
    });

    test('drops combining accents (decomposed text)', () {
      expect(foldForSearch('Résumé'), 'resume');
    });

    test('collapses every whitespace run to one space', () {
      expect(foldForSearch('a \t\n b  c'), 'a b c');
    });

    test('keeps other scripts, lowercased', () {
      expect(foldForSearch('ΑΒΓ Привет'), 'αβγ привет');
      expect(foldForSearch('😀 ok'), '😀 ok');
    });
  });

  group('buildSnippet', () {
    const filler = 'The quick brown fox jumps over the lazy dog. ';

    test('short text is returned whole, without ellipses', () {
      expect(snippetFor('Hello world', 'world'), 'Hello world');
    });

    test('long text: ~60 chars around the match with ellipses', () {
      final text = '${filler * 4}Momentum is conserved in elastic '
          'collisions. ${filler * 4}';
      final s = snippetFor(text, 'momentum');
      expect(s, startsWith('…'));
      expect(s, endsWith('…'));
      expect(s, contains('Momentum'));
      final body = _strip(s);
      expect(body.length, inInclusiveRange(40, 60));
      // Snapped to whole words.
      final at = text.indexOf(body);
      expect(at, greaterThan(0));
      expect(text[at - 1], ' ');
      expect(text[at + body.length], ' ');
    });

    test('a match at the start has no leading ellipsis', () {
      final s = snippetFor('Momentum ${filler * 3}', 'momentum');
      expect(s, startsWith('Momentum'));
      expect(s, endsWith('…'));
    });

    test('a match at the end has no trailing ellipsis', () {
      final s = snippetFor('${filler * 3}the end', 'end');
      expect(s, startsWith('…'));
      expect(s, endsWith('the end'));
    });

    test('maps folded matches back to the original text', () {
      expect(snippetFor('Le café de la gare', 'CAFE'), 'Le café de la gare');
      expect(snippetFor('Straße', 'strasse'), 'Straße');
      expect(snippetFor('line one\n\n   line   two', 'one line'),
          'line one line two');
      final decomposed = '${filler * 3}Résumé ${filler * 3}';
      expect(snippetFor(decomposed, 'resume'), contains('Résumé'));
    });

    test('a match longer than the budget is still shown whole', () {
      final long = 'x' * 80;
      expect(snippetFor('aa $long bb', long), contains(long));
    });

    test('degenerate inputs give an empty snippet', () {
      expect(buildSnippet('', 0, 3), '');
      expect(buildSnippet('abc', 0, 0), '');
      expect(buildSnippet('abc', 10, 2), '');
    });
  });

  group('searchNotebooks (ranking)', () {
    final library = LibraryIndex(folders: [
      Folder(id: 'uni', name: 'University', createdAt: DateTime.utc(2026)),
      Folder(
          id: 'phys',
          name: 'Physics',
          parentId: 'uni',
          createdAt: DateTime.utc(2026)),
    ]);

    test('title > tag/folder > text > pdf, then most recent first', () {
      final hits = searchNotebooks('PHYSICS', [
        SearchableNotebook(_nb('pdf', 'Art'),
            SearchData({'p0': PageSearchText(pdf: 'intro to physics')})),
        SearchableNotebook(_nb('text', 'History'),
            SearchData({'p0': PageSearchText(text: 'physics of war')})),
        SearchableNotebook(
            _nb('folder', 'Math',
                folderId: 'phys', updatedAt: DateTime.utc(2026, 2)),
            SearchData.empty),
        SearchableNotebook(
            _nb('tag', 'Chemistry',
                tags: ['physics'], updatedAt: DateTime.utc(2026, 3)),
            SearchData.empty),
        SearchableNotebook(_nb('title', 'Physics notes'),
            SearchData({'p0': PageSearchText(text: 'more physics')})),
        SearchableNotebook(_nb('none', 'Biology'), SearchData.empty),
      ], library);

      expect([for (final h in hits) '${h.notebookId}:${h.kind.name}'], [
        'title:title',
        'title:text',
        'tag:tag',
        'folder:folder',
        'text:text',
        'pdf:pdf',
      ]);
      expect(hits[0].snippet, '');
      expect(hits[0].notebookTitle, 'Physics notes');
      expect(hits[2].snippet, 'physics');
      expect(hits[3].snippet, 'Physics');
      expect(hits[4].snippet, 'physics of war');
      expect(hits[4].pageId, 'p0');
      expect(hits[4].pageIndex, 0);
    });

    test('ancestor folders match too', () {
      final hits = searchNotebooks('univ', [
        SearchableNotebook(_nb('n', 'Math', folderId: 'phys'), SearchData.empty),
      ], library);
      expect(hits.single.kind, SearchMatchKind.folder);
      expect(hits.single.snippet, 'University');
    });

    test('a folder cycle in library.json does not hang', () {
      final cyclic = LibraryIndex(folders: [
        Folder(id: 'a', name: 'A', parentId: 'b', createdAt: DateTime.utc(2026)),
        Folder(id: 'b', name: 'B', parentId: 'a', createdAt: DateTime.utc(2026)),
      ]);
      final hits = searchNotebooks('zzz', [
        SearchableNotebook(_nb('n', 'N', folderId: 'a'), SearchData.empty),
      ], cyclic);
      expect(hits, isEmpty);
    });

    test('at most 5 page hits per notebook, text first, in page order', () {
      final pageIds = [for (var i = 0; i < 8; i++) 'pg$i'];
      // Insertion order differs from the page order on purpose.
      final data = SearchData({
        for (final id in pageIds.reversed)
          id: PageSearchText(text: 'force $id', pdf: 'force pdf $id'),
      });
      final hits = searchNotebooks('force', [
        SearchableNotebook(_nb('n', 'Notes', pages: pageIds), data),
      ], const LibraryIndex());
      expect(hits, hasLength(defaultMaxSnippetHits));
      expect(hits.every((h) => h.kind == SearchMatchKind.text), isTrue);
      expect([for (final h in hits) h.pageIndex], [0, 1, 2, 3, 4]);
      expect([for (final h in hits) h.pageId], pageIds.take(5));

      final pdfFirst = searchNotebooks('pdf', [
        SearchableNotebook(_nb('n', 'Notes', pages: pageIds), data),
      ], const LibraryIndex(), maxSnippetHits: 2);
      expect([for (final h in pdfFirst) h.kind], [SearchMatchKind.pdf, SearchMatchKind.pdf]);
    });

    test('pages missing from the metadata are not reported', () {
      final hits = searchNotebooks('ghost', [
        SearchableNotebook(_nb('n', 'N'),
            SearchData({'deleted': PageSearchText(text: 'ghost')})),
      ], const LibraryIndex());
      expect(hits, isEmpty);
    });

    test('equal rank and date fall back to title, then id', () {
      final hits = searchNotebooks('note', [
        SearchableNotebook(_nb('b', 'Note'), SearchData.empty),
        SearchableNotebook(_nb('c', 'A note'), SearchData.empty),
        SearchableNotebook(_nb('a', 'Note'), SearchData.empty),
      ], const LibraryIndex());
      expect(hits.map((h) => h.notebookId), ['c', 'a', 'b']);
    });

    test('empty or whitespace queries find nothing', () {
      final notebooks = [SearchableNotebook(_nb('n', 'Anything'), SearchData.empty)];
      expect(searchNotebooks('', notebooks, const LibraryIndex()), isEmpty);
      expect(searchNotebooks('  \n\t', notebooks, const LibraryIndex()), isEmpty);
    });

    test('accent- and case-insensitive both ways', () {
      final notebooks = [
        SearchableNotebook(_nb('a', 'Résumé'), SearchData.empty),
        SearchableNotebook(_nb('b', 'resume'), SearchData.empty),
      ];
      expect(searchNotebooks('RESUME', notebooks, const LibraryIndex()),
          hasLength(2));
      expect(searchNotebooks('résumé', notebooks, const LibraryIndex()),
          hasLength(2));
    });

    test('stays fast for 200 notebooks', () {
      final words = 'alpha beta gamma delta epsilon zeta eta theta iota kappa '
          'lambda mu nu xi omicron pi rho sigma tau upsilon ';
      final notebooks = [
        for (var n = 0; n < 200; n++)
          SearchableNotebook(
            _nb('n$n', 'Notebook $n',
                pages: [for (var i = 0; i < 10; i++) 'n$n-p$i'],
                tags: ['tag$n']),
            SearchData({
              for (var i = 0; i < 10; i++)
                'n$n-p$i': PageSearchText(
                    text: words * 4, pdf: '${words * 4} page $n.$i'),
            }),
          ),
      ];
      // First search folds and caches every page's text.
      searchNotebooks('warm up', notebooks, const LibraryIndex());
      final watch = Stopwatch()..start();
      final hits = searchNotebooks('page 199.9', notebooks, const LibraryIndex());
      watch.stop();
      expect(hits.single.notebookId, 'n199');
      expect(hits.single.kind, SearchMatchKind.pdf);
      expect(watch.elapsedMilliseconds, lessThan(500));
    });
  });

  group('SearchData', () {
    test('json round trip and version', () {
      final data = SearchData()
          .withPageText('a', 'typed')
          .withPdfText({'a': 'pdf a', 'b': 'pdf b'});
      final json = data.toJson();
      expect(json['version'], SearchData.currentVersion);
      final back = SearchData.fromJson(
          jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
      expect(back.pages['a']!.text, 'typed');
      expect(back.pages['a']!.pdf, 'pdf a');
      expect(back.pages['b']!.text, '');
      expect(back.pages['b']!.pdf, 'pdf b');
    });

    test('empty text removes a page; updates return new copies', () {
      final one = SearchData().withPageText('a', 'x');
      final none = one.withPageText('a', '');
      expect(one.pages, contains('a'));
      expect(none.isEmpty, isTrue);
      expect(() => one.pages['z'] = PageSearchText(), throwsUnsupportedError);
    });

    test('retainPages and remapPages', () {
      final data = SearchData({
        'a': PageSearchText(text: 'A'),
        'b': PageSearchText(pdf: 'B'),
      });
      expect(data.retainPages({'b'}).pages.keys, ['b']);
      final remapped = data.remapPages({'a': 'a2'});
      expect(remapped.pages.keys, ['a2']);
      expect(remapped.pages['a2']!.text, 'A');
    });

    test('migration accepts v1 and no version, rejects newer files', () {
      expect(migrateSearchJson({'pages': <String, dynamic>{}}), isNotNull);
      expect(migrateSearchJson({'version': 1}), isNotNull);
      expect(() => migrateSearchJson({'version': 99}), throwsFormatException);
    });
  });

  group('FileNotebookRepository.search', () {
    late Directory root;
    late FileNotebookRepository repo;

    setUp(() async {
      root = await createTempRoot();
      repo = FileNotebookRepository(root, clock: StepClock().call);
    });

    String searchFile(String id) =>
        p.join(root.path, 'notebooks', id, 'search.json');

    test('finds text boxes with page index and snippet', () async {
      final meta = await repo.createNotebook(
          title: 'Lab', paper: const Paper(), pageCount: 2);
      final second = meta.pages[1].id;
      await repo.savePage(meta.id, second, PageContent(texts: [
        _text('a', 'Measured the pendulum period twice.'),
        _text('b', '   '),
      ]));
      final hits = await repo.search('PENDULUM');
      expect(hits.single.kind, SearchMatchKind.text);
      expect(hits.single.notebookId, meta.id);
      expect(hits.single.notebookTitle, 'Lab');
      expect(hits.single.pageId, second);
      expect(hits.single.pageIndex, 1);
      expect(hits.single.snippet, 'Measured the pendulum period twice.');

      final file = jsonDecode(File(searchFile(meta.id)).readAsStringSync())
          as Map<String, dynamic>;
      expect(file['version'], SearchData.currentVersion);
      expect((file['pages'] as Map<String, dynamic>).keys, [second]);
    });

    test('edits replace the old text (cache invalidated on write)', () async {
      final meta = await repo.createNotebook(title: 'N', paper: const Paper());
      final pg = meta.pages.single.id;
      await repo.savePage(meta.id, pg, PageContent(texts: [_text('a', 'apple')]));
      expect(await repo.search('apple'), hasLength(1));
      await repo.savePage(meta.id, pg, PageContent(texts: [_text('a', 'banana')]));
      expect(await repo.search('apple'), isEmpty);
      expect(await repo.search('banana'), hasLength(1));
      await repo.savePage(meta.id, pg, PageContent());
      expect(await repo.search('banana'), isEmpty);
    });

    test('PDF text, titles, tags and folders', () async {
      final meta = await repo.createNotebook(title: 'Résumé', paper: const Paper());
      final pg = meta.pages.single.id;
      await repo.saveMeta(meta.copyWith(tags: ['career'], folderId: 'jobs'));
      await repo.saveLibrary(LibraryIndex(folders: [
        Folder(id: 'jobs', name: 'Applications', createdAt: DateTime.utc(2026)),
      ]));
      await repo.savePdfText(meta.id, {pg: 'Curriculum vitae of A. Student'});

      expect((await repo.search('resume')).single.kind, SearchMatchKind.title);
      expect((await repo.search('CAREER')).single.kind, SearchMatchKind.tag);
      expect((await repo.search('applic')).single.kind, SearchMatchKind.folder);
      final pdf = (await repo.search('vitae')).single;
      expect(pdf.kind, SearchMatchKind.pdf);
      expect(pdf.pageIndex, 0);
      expect(pdf.snippet, 'Curriculum vitae of A. Student');

      // Renaming the folder is picked up without a relaunch.
      await repo.saveLibrary(LibraryIndex(folders: [
        Folder(id: 'jobs', name: 'Interviews', createdAt: DateTime.utc(2026)),
      ]));
      expect(await repo.search('applic'), isEmpty);
      expect((await repo.search('interv')).single.kind, SearchMatchKind.folder);

      // Empty PDF text removes it.
      await repo.savePdfText(meta.id, {pg: ''});
      expect(await repo.search('vitae'), isEmpty);
    });

    test('text of deleted pages is dropped from search', () async {
      final meta = await repo.createNotebook(
          title: 'N', paper: const Paper(), pageCount: 2);
      final keep = meta.pages[0].id, drop = meta.pages[1].id;
      await repo.savePage(meta.id, keep, PageContent(texts: [_text('a', 'kept words')]));
      await repo.savePage(meta.id, drop, PageContent(texts: [_text('a', 'gone words')]));
      await repo.saveMeta(meta.copyWith(pages: [meta.pages[0]]));
      expect((await repo.search('words')).single.pageId, keep);

      final onDisk = SearchData.fromJson(jsonDecode(
          File(searchFile(meta.id)).readAsStringSync()) as Map<String, dynamic>);
      expect(onDisk.pages.keys, [keep]);
    });

    test('search data survives a relaunch and is cached in memory', () async {
      final meta = await repo.createNotebook(title: 'N', paper: const Paper());
      await repo.savePage(meta.id, meta.pages.single.id,
          PageContent(texts: [_text('a', 'entropy')]));

      final next = FileNotebookRepository(root);
      expect((await next.search('entropy')).single.kind, SearchMatchKind.text);
      // Served from the cache now, without touching the disk.
      for (final f in [
        File(searchFile(meta.id)),
        File('${searchFile(meta.id)}.bak'),
      ]) {
        if (f.existsSync()) f.deleteSync();
      }
      expect((await next.search('entropy')).single.kind, SearchMatchKind.text);
    });

    test('an unreadable search.json is rebuilt from the text boxes',
        () async {
      final meta = await repo.createNotebook(title: 'N', paper: const Paper());
      final pg = meta.pages.single.id;
      await repo.savePage(meta.id, pg, PageContent(texts: [_text('a', 'typed note')]));
      await repo.savePdfText(meta.id, {pg: 'pdf words'});
      await File(searchFile(meta.id)).writeAsString('broken');
      await File('${searchFile(meta.id)}.bak').writeAsString('broken');

      final next = FileNotebookRepository(root);
      expect((await next.search('typed')).single.kind, SearchMatchKind.text);
      expect(await next.search('pdf words'), isEmpty,
          reason: 'PDF text cannot be rebuilt here');
      expect(File(searchFile(meta.id)).readAsStringSync(), 'broken',
          reason: 'reads never overwrite files');
    });

    test('pages without text boxes do not create search.json', () async {
      final meta = await repo.createNotebook(title: 'N', paper: const Paper());
      await repo.savePage(meta.id, meta.pages.single.id, PageContent());
      expect(File(searchFile(meta.id)).existsSync(), isFalse);
    });

    test('empty queries return nothing', () async {
      await repo.createNotebook(title: 'Anything', paper: const Paper());
      expect(await repo.search(''), isEmpty);
      expect(await repo.search('   '), isEmpty);
    });

    test('new notebooks show up in search after the first listing',
        () async {
      await repo.createNotebook(title: 'First', paper: const Paper());
      expect(await repo.search('first'), hasLength(1));
      await repo.createNotebook(title: 'Second', paper: const Paper());
      expect(await repo.search('second'), hasLength(1));
      final copy = await repo.duplicateNotebook(
          (await repo.search('first')).single.notebookId);
      expect((await repo.search('first')).map((h) => h.notebookId),
          contains(copy.id));
    });
  });
}
