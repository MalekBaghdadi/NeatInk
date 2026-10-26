import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/notebook_meta.dart';
import 'package:neatink/features/library/library_naming.dart';
import 'package:neatink/features/library/relative_time.dart';
import 'package:neatink/features/library/tags.dart';

void main() {
  group('tags', () {
    test('normalizeTag trims, drops #, collapses spaces, caps length', () {
      expect(normalizeTag('  #  exam   prep '), 'exam prep');
      expect(normalizeTag('##physics'), 'physics');
      expect(normalizeTag('   '), isNull);
      expect(normalizeTag('#'), isNull);
      expect(normalizeTag('x' * 100)!.length, maxTagLength);
    });

    test('normalizeTags dedupes case-insensitively, keeping first spelling',
        () {
      expect(normalizeTags(['Exam', 'exam', ' #Lab', '', 'EXAM', 'lab']),
          ['Exam', 'Lab']);
    });

    test('hasTag and collectTags ignore case', () {
      final a = NotebookMeta(
        id: 'a',
        title: 'a',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        tags: const ['physics', 'Exam'],
      );
      final b = a.copyWith(id: 'b', tags: const ['exam', 'Week 10', 'Week 9']);
      expect(hasTag(a, 'PHYSICS'), isTrue);
      expect(hasTag(a, 'phys'), isFalse);
      expect(collectTags([a, b]), ['Exam', 'physics', 'Week 9', 'Week 10']);
    });
  });

  group('naming', () {
    test('uniqueName appends the first free number', () {
      expect(uniqueName('New folder', const []), 'New folder');
      expect(uniqueName('New folder', const ['new folder']), 'New folder 2');
      expect(
          uniqueName('New folder', const ['New folder', 'New folder 2']),
          'New folder 3');
    });

    test('cleanName trims, collapses whitespace and rejects blanks', () {
      expect(cleanName('  Lab   notes \n'), 'Lab notes');
      expect(cleanName('   '), isNull);
      expect(cleanName('abcdef', maxLength: 3), 'abc');
    });

    test('defaultNotebookTitle uses a short date', () {
      expect(defaultNotebookTitle(DateTime(2026, 10, 25)),
          'Notebook 25 Oct 2026');
    });
  });

  group('relative time', () {
    final now = DateTime(2026, 10, 25, 15, 30); // A Sunday.

    test('recent times', () {
      expect(formatRelative(now.subtract(const Duration(seconds: 20)), now),
          'just now');
      expect(formatRelative(now.subtract(const Duration(minutes: 5)), now),
          '5 min ago');
      expect(formatRelative(now.subtract(const Duration(hours: 3)), now),
          '3 h ago');
      // Future timestamps (clock skew) read as "just now".
      expect(formatRelative(now.add(const Duration(hours: 1)), now),
          'just now');
    });

    test('calendar days, weekdays and dates', () {
      expect(formatRelative(DateTime(2026, 10, 24, 23), now), 'yesterday');
      expect(formatRelative(DateTime(2026, 10, 21, 9), now), 'Wednesday');
      expect(formatRelative(DateTime(2026, 3, 12), now), '12 Mar');
      expect(formatRelative(DateTime(2024, 3, 12), now), '12 Mar 2024');
    });

    test('formatEdited reads naturally', () {
      expect(formatEdited(now.subtract(const Duration(minutes: 5)), now),
          'Edited 5 min ago');
      expect(formatEdited(DateTime(2026, 10, 24, 9), now), 'Edited yesterday');
      expect(formatEdited(DateTime(2026, 10, 21, 9), now),
          'Edited on Wednesday');
      expect(formatEdited(DateTime(2026, 3, 12), now), 'Edited on 12 Mar');
    });
  });
}
