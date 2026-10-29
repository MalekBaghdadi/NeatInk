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
import 'package:path/path.dart' as p;

import 'storage_test_support.dart';

NotebookMeta _nb(String id, List<String> pages) => NotebookMeta(
      id: id,
      title: 'Notes $id',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      pages: [for (final pg in pages) PageMeta(id: pg)],
    );

void main() {
  group('SearchData', () {
    test('handwriting text and its key go to JSON and back', () {
      final data = SearchData().withInkText('p0', 'Neurons fire', '3-abc').withPageText('p1', 'typed');
      final back = SearchData.fromJson(jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>);
      expect(back.pages['p0']!.ink, 'Neurons fire');
      expect(back.pages['p0']!.inkKey, '3-abc');
      expect(back.pages['p1']!.ink, '');
      expect(back.pages['p1']!.text, 'typed');
    });

    test('a page read as nothing keeps its key, and nothing at all is no entry', () {
      final read = SearchData().withInkText('p0', '', '2-ff');
      expect(read.pages['p0']!.inkKey, '2-ff', reason: 'a drawing is not read again');
      expect(read.withInkText('p0', '', '').pages, isEmpty);
    });

    test('old files without handwriting still load', () {
      final old = SearchData.fromJson({'version': 1, 'pages': {'p0': {'text': 'a'}}});
      expect(old.pages['p0']!.ink, '');
      expect(old.pages['p0']!.inkKey, '');
    });
  });

  group('searchNotebooks', () {
    test('finds handwriting, after typed text and before PDF text', () {
      final data = SearchData()
          .withInkText('p0', 'the hippocampus stores memories', 'k0')
          .withPageText('p1', 'hippocampus (typed)')
          .withPdfText({'p2': 'Hippocampus, PDF'});
      final hits = searchNotebooks('Hippocampus', [SearchableNotebook(_nb('a', ['p0', 'p1', 'p2']), data)],
          const LibraryIndex());
      expect([for (final h in hits) h.kind],
          [SearchMatchKind.text, SearchMatchKind.handwriting, SearchMatchKind.pdf]);
      final ink = hits[1];
      expect(ink.pageIndex, 0);
      expect(ink.snippet, contains('hippocampus'));
      expect(rankOf(SearchMatchKind.handwriting), greaterThan(rankOf(SearchMatchKind.text)));
      expect(rankOf(SearchMatchKind.handwriting), lessThan(rankOf(SearchMatchKind.pdf)));
    });
  });

  group('FileNotebookRepository', () {
    late Directory root;
    late FileNotebookRepository repo;
    setUp(() async {
      root = await createTempRoot();
      repo = FileNotebookRepository(root);
    });

    test('stores handwriting text, gives back the keys, and search finds it', () async {
      final meta = await repo.createNotebook(title: 'Bio', paper: const Paper(), pageCount: 2);
      final p0 = meta.pages[0].id, p1 = meta.pages[1].id;
      await repo.savePage(meta.id, p1, PageContent(texts: const [
        TextItem(id: 't', x: 0, y: 0, width: 100, height: 20, text: 'typed words'),
      ]));
      await repo.saveHandwritingText(meta.id, p0, text: 'Synapse and neurons', key: '5-1a');
      expect(await repo.handwritingKeys(meta.id), {p0: '5-1a'});

      final hits = await repo.search('neurons');
      expect(hits.single.kind, SearchMatchKind.handwriting);
      expect(hits.single.pageId, p0);

      // Saving the page again keeps the handwriting text, and a new launch
      // reads it from disk.
      await repo.savePage(meta.id, p1, PageContent());
      final again = FileNotebookRepository(root);
      expect(await again.handwritingKeys(meta.id), {p0: '5-1a'});
      expect((await again.search('synapse')).single.kind, SearchMatchKind.handwriting);
      final json = jsonDecode(File(p.join(root.path, 'notebooks', meta.id, 'search.json')).readAsStringSync()) as Map;
      expect(((json['pages'] as Map)[p0] as Map)['ink'], 'Synapse and neurons');
    });

    test('a deleted page takes its handwriting text with it', () async {
      final meta = await repo.createNotebook(title: 'Bio', paper: const Paper(), pageCount: 2);
      await repo.saveHandwritingText(meta.id, meta.pages[0].id, text: 'cortex', key: '1-1');
      await repo.saveMeta(meta.copyWith(pages: [meta.pages[1]]));
      expect(await repo.search('cortex'), isEmpty);
    });
  });
}
