import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/notebook_meta.dart';
import 'package:neatink/features/library/library_state.dart';
import 'package:neatink/features/settings/app_settings.dart';

NotebookMeta nb(
  String id, {
  String? title,
  int created = 0,
  int edited = 0,
  String? folderId,
  bool favorite = false,
  List<String> tags = const [],
  NotebookKind kind = NotebookKind.blank,
}) =>
    NotebookMeta(
      id: id,
      title: title ?? id,
      createdAt: DateTime.utc(2026, 1, 1).add(Duration(days: created)),
      updatedAt: DateTime.utc(2026, 1, 1).add(Duration(days: edited)),
      folderId: folderId,
      favorite: favorite,
      tags: tags,
      kind: kind,
    );

Folder folder(String id, {String? parent, int created = 0}) => Folder(
      id: id,
      name: id,
      parentId: parent,
      createdAt: DateTime.utc(2026, 1, 1).add(Duration(days: created)),
    );

void main() {
  group('sortNotebooks', () {
    final list = [
      nb('a', title: 'Notebook 10', created: 3, edited: 1),
      nb('b', title: 'notebook 9', created: 1, edited: 5),
      nb('c', title: 'Algebra', created: 2, edited: 5),
    ];

    test('last edited: newest first, ties by title', () {
      expect(sortNotebooks(list, LibrarySort.edited).map((n) => n.id),
          ['c', 'b', 'a']);
    });

    test('created: newest first', () {
      expect(sortNotebooks(list, LibrarySort.created).map((n) => n.id),
          ['a', 'c', 'b']);
    });

    test('title: case-insensitive and number-aware', () {
      expect(sortNotebooks(list, LibrarySort.title).map((n) => n.id),
          ['c', 'b', 'a']);
    });
  });

  test('sortFolders sorts by name, or newest first for "created"', () {
    final folders = [
      folder('b', created: 1),
      folder('a', created: 0),
      folder('c', created: 2),
    ];
    expect(sortFolders(folders, LibrarySort.title).map((f) => f.id),
        ['a', 'b', 'c']);
    expect(sortFolders(folders, LibrarySort.edited).map((f) => f.id),
        ['a', 'b', 'c']);
    expect(sortFolders(folders, LibrarySort.created).map((f) => f.id),
        ['c', 'b', 'a']);
  });

  group('LibraryState', () {
    final state = LibraryState(
      notebooks: [
        nb('root1', edited: 2),
        nb('inSchool', folderId: 'school', favorite: true, tags: ['Exam']),
        nb('inPhysics', folderId: 'physics', tags: ['exam', 'Lab']),
        nb('orphan', folderId: 'deleted-folder'),
        nb('pdf', kind: NotebookKind.pdf, edited: 1),
      ],
      library: LibraryIndex(folders: [
        folder('school'),
        folder('physics', parent: 'school'),
      ]),
    );

    test('root view shows top-level folders and notebooks, including '
        'notebooks whose folder no longer exists', () {
      expect(state.isAtRoot, isTrue);
      expect(state.visibleFolders.map((f) => f.id), ['school']);
      expect(state.visibleNotebooks.map((n) => n.id),
          unorderedEquals(['root1', 'orphan', 'pdf']));
    });

    test('folder view shows that folder only, with a breadcrumb', () {
      final s = state.copyWith(folderId: 'school');
      expect(s.visibleFolders.map((f) => f.id), ['physics']);
      expect(s.visibleNotebooks.map((n) => n.id), ['inSchool']);
      expect(s.breadcrumb.map((f) => f.id), ['school']);
      expect(s.copyWith(folderId: 'physics').breadcrumb.map((f) => f.id),
          ['school', 'physics']);
      expect(s.isAtRoot, isFalse);
    });

    test('filters are flat lists across folders and hide folders', () {
      final fav = state.copyWith(filter: LibraryFilter.favorites);
      expect(fav.visibleNotebooks.map((n) => n.id), ['inSchool']);
      expect(fav.visibleFolders, isEmpty);
      expect(fav.isAtRoot, isFalse);

      final pdfs = state.copyWith(filter: LibraryFilter.pdfs);
      expect(pdfs.visibleNotebooks.map((n) => n.id), ['pdf']);

      final exam = state.copyWith(filter: const LibraryFilter.tag('EXAM'));
      expect(exam.visibleNotebooks.map((n) => n.id),
          unorderedEquals(['inSchool', 'inPhysics']));
    });

    test('counts and tags', () {
      expect(state.notebookCountIn(null), 3);
      expect(state.notebookCountIn('school'), 1);
      expect(state.notebookCountIn('physics'), 1);
      expect(state.favoriteCount, 1);
      expect(state.pdfCount, 1);
      // "Exam" and "exam" are one tag; the alphabetically first spelling wins.
      expect(state.tags, ['Exam', 'Lab']);
      expect(state.tagCount('exam'), 2);
      expect(state.isLibraryEmpty, isFalse);
      expect(LibraryState(notebooks: const [], library: const LibraryIndex())
          .isLibraryEmpty, isTrue);
    });

    test('tag filters compare case-insensitively', () {
      expect(const LibraryFilter.tag('Exam'), const LibraryFilter.tag('exam'));
      expect(const LibraryFilter.tag('Exam').hashCode,
          const LibraryFilter.tag('exam').hashCode);
      expect(LibraryFilter.favorites, isNot(LibraryFilter.pdfs));
    });
  });
}
