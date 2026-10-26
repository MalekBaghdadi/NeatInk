import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/library/search_results.dart';
import 'package:neatink/storage/notebook_repository.dart';

SearchHit hit(String id, SearchMatchKind kind,
        {int? page, String snippet = ''}) =>
    SearchHit(
      notebookId: id,
      notebookTitle: 'Title $id',
      kind: kind,
      pageIndex: page,
      pageId: page == null ? null : 'p$page',
      snippet: snippet,
    );

void main() {
  test('groupSearchHits keeps first-appearance order of notebooks and hits',
      () {
    final groups = groupSearchHits([
      hit('b', SearchMatchKind.title),
      hit('a', SearchMatchKind.tag, snippet: 'exam'),
      hit('b', SearchMatchKind.text, page: 2, snippet: 'x'),
      hit('a', SearchMatchKind.pdf, page: 0, snippet: 'y'),
    ]);
    expect(groups.map((g) => g.notebookId), ['b', 'a']);
    expect(groups[0].notebookTitle, 'Title b');
    expect(groups[0].hits.map((h) => h.kind),
        [SearchMatchKind.title, SearchMatchKind.text]);
    expect(groups[1].hits.map((h) => h.kind),
        [SearchMatchKind.tag, SearchMatchKind.pdf]);
    expect(groups[0].firstPageIndex, 2);
    expect(groups[1].firstPageIndex, 0);
    expect(groupSearchHits(const []), isEmpty);
  });

  test('firstPageIndex is null when no hit points at a page', () {
    final g = groupSearchHits([hit('a', SearchMatchKind.title)]).single;
    expect(g.firstPageIndex, isNull);
  });

  group('findMatches', () {
    test('finds every case-insensitive, non-overlapping occurrence', () {
      expect(findMatches('Exam prep: EXAM day', 'exam'), [
        (start: 0, end: 4),
        (start: 11, end: 15),
      ]);
      expect(findMatches('aaaa', 'aa'), [
        (start: 0, end: 2),
        (start: 2, end: 4),
      ]);
    });

    test('trims the query and handles empty input', () {
      expect(findMatches('Physics', '  phy '), [(start: 0, end: 3)]);
      expect(findMatches('Physics', '   '), isEmpty);
      expect(findMatches('', 'x'), isEmpty);
      expect(findMatches('abc', 'abcd'), isEmpty);
    });

    test('ranges always index into the original text', () {
      // 'İ' lower-cases to two code units; ranges must still be valid.
      const text = 'İstanbul notes';
      for (final m in findMatches(text, 'notes')) {
        expect(text.substring(m.start, m.end), 'notes');
      }
    });
  });

  test('display text falls back to the title for title matches', () {
    expect(searchHitDisplayText(hit('a', SearchMatchKind.title)), 'Title a');
    expect(
        searchHitDisplayText(
            hit('a', SearchMatchKind.text, page: 0, snippet: '…found…')),
        '…found…');
    expect(searchMatchKindLabel(SearchMatchKind.pdf), 'PDF text');
  });
}
