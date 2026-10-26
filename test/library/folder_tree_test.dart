import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/notebook_meta.dart';
import 'package:neatink/features/library/folder_tree.dart';

Folder folder(String id, {String? parent, String? name}) => Folder(
      id: id,
      name: name ?? id,
      parentId: parent,
      createdAt: DateTime.utc(2026),
    );

FolderTree tree(List<Folder> folders) =>
    FolderTree(LibraryIndex(folders: folders));

void main() {
  group('FolderTree', () {
    test('builds parents, children (sorted by name) and paths', () {
      final t = tree([
        folder('school'),
        folder('physics', parent: 'school', name: 'Physics'),
        folder('maths', parent: 'school', name: 'Maths'),
        folder('labs', parent: 'physics'),
      ]);
      expect(t.parentOf('labs'), 'physics');
      expect(t.parentOf('school'), isNull);
      expect(t.childrenOf('school').map((f) => f.id), ['maths', 'physics']);
      expect(t.childrenOf(null).map((f) => f.id), ['school']);
      expect(t.pathTo('labs').map((f) => f.id), ['school', 'physics', 'labs']);
      expect(t.pathTo(null), isEmpty);
      expect(t.pathTo('unknown'), isEmpty);
      expect(t.hasChildren('physics'), isTrue);
      expect(t.hasChildren('labs'), isFalse);
      expect(t.descendantsOf('school'), {'physics', 'maths', 'labs'});
    });

    test('treats a folder with a missing parent as top level', () {
      final t = tree([folder('a', parent: 'gone'), folder('b')]);
      expect(t.parentOf('a'), isNull);
      expect(t.childrenOf(null).map((f) => f.id), ['a', 'b']);
    });

    test('breaks parent cycles so every folder stays reachable', () {
      final t = tree([
        folder('a', parent: 'c'),
        folder('b', parent: 'a'),
        folder('c', parent: 'b'),
        folder('self', parent: 'self'),
      ]);
      final reachable = t.flatten().map((e) => e.folder.id).toSet();
      expect(reachable, {'a', 'b', 'c', 'self'});
      expect(t.parentOf('self'), isNull);
      // Walking up from any folder terminates.
      for (final id in ['a', 'b', 'c']) {
        expect(t.pathTo(id), isNotEmpty);
      }
    });

    test('canMove refuses moving a folder into itself or a descendant', () {
      final t = tree([
        folder('a'),
        folder('b', parent: 'a'),
        folder('c', parent: 'b'),
        folder('d'),
      ]);
      expect(t.canMove('a', 'a'), isFalse);
      expect(t.canMove('a', 'b'), isFalse);
      expect(t.canMove('a', 'c'), isFalse);
      expect(t.canMove('a', 'd'), isTrue);
      expect(t.canMove('c', 'a'), isTrue);
      expect(t.canMove('c', null), isTrue);
      expect(t.canMove('a', 'missing'), isFalse);
      expect(t.canMove('missing', null), isFalse);
    });

    test('flatten lists depth-first with depths and honours exclude', () {
      final t = tree([
        folder('a', name: 'A'),
        folder('a1', parent: 'a', name: 'A1'),
        folder('a1x', parent: 'a1', name: 'A1x'),
        folder('b', name: 'B'),
      ]);
      expect(
        [for (final e in t.flatten()) '${e.folder.id}@${e.depth}'],
        ['a@0', 'a1@1', 'a1x@2', 'b@0'],
      );
      expect(
        [for (final e in t.flatten(exclude: {'a1'})) e.folder.id],
        ['a', 'b'],
      );
    });
  });

  group('naturalCompare', () {
    test('orders digit runs by value and ignores case', () {
      final names = ['Week 10', 'week 2', 'Week 1', 'Apple', 'week 02b'];
      names.sort(naturalCompare);
      expect(names, ['Apple', 'Week 1', 'week 2', 'week 02b', 'Week 10']);
    });

    test('handles very long digit runs without overflow', () {
      expect(
        naturalCompare('x 123456789012345678901234567890',
            'x 99999999999999999999999999999'),
        greaterThan(0),
      );
    });

    test('is stable for names that differ only in case', () {
      expect(naturalCompare('abc', 'ABC'), isNot(0));
      expect(naturalCompare('abc', 'abc'), 0);
    });
  });
}
