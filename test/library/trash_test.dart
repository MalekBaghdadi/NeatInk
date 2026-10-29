import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/features/library/library_controller.dart';
import 'package:neatink/features/library/trash_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/in_memory_repository.dart';

void main() {
  late InMemoryNotebookRepository repo;
  late ProviderContainer container;
  var now = DateTime.utc(2026, 10, 29, 9);

  Future<LibraryController> open() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      notebookRepositoryProvider.overrideWithValue(repo),
      clockProvider.overrideWithValue(() => now),
    ]);
    addTearDown(container.dispose);
    await container.read(libraryControllerProvider.future);
    return container.read(libraryControllerProvider.notifier);
  }

  setUp(() {
    now = DateTime.utc(2026, 10, 29, 9);
    repo = InMemoryNotebookRepository(clock: () => now);
  });

  test('deleting moves a notebook to the Trash; Undo brings it back', () async {
    final meta = await repo.createNotebook(title: 'Brain', paper: const Paper());
    final library = await open();
    await library.moveToTrash(meta.id);
    expect(container.read(libraryControllerProvider).value!.notebooks, isEmpty);
    expect((await repo.listTrash()).single.meta.title, 'Brain');

    await library.restoreFromTrash(meta.id);
    expect(container.read(libraryControllerProvider).value!.notebooks.single.title, 'Brain');
    expect(await repo.listTrash(), isEmpty);
  });

  test('the library empties what has been in the Trash for 30 days', () async {
    final old = await repo.createNotebook(title: 'Old', paper: const Paper());
    final recent = await repo.createNotebook(title: 'Recent', paper: const Paper());
    await repo.trashNotebook(old.id);
    now = now.add(const Duration(days: 20));
    await repo.trashNotebook(recent.id);
    now = now.add(const Duration(days: 11));
    await open();
    await Future<void>.delayed(Duration.zero);
    expect((await repo.listTrash()).map((t) => t.meta.title), ['Recent']);
  });

  testWidgets('the Trash screen brings notebooks back and deletes them for good', (tester) async {
    final a = await repo.createNotebook(title: 'Anatomy', paper: const Paper());
    final b = await repo.createNotebook(title: 'Biology', paper: const Paper());
    await repo.trashNotebook(a.id);
    await repo.trashNotebook(b.id);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        notebookRepositoryProvider.overrideWithValue(repo),
        clockProvider.overrideWithValue(() => now.add(const Duration(days: 2))),
      ],
      child: const MaterialApp(home: TrashScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Anatomy'), findsOneWidget);
    expect(find.textContaining('28 days left'), findsNWidgets(2));

    await tester.tap(find.byKey(Key('trash-restore-${a.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Anatomy'), findsNothing);
    expect((await repo.listNotebooks()).single.title, 'Anatomy');

    await tester.tap(find.byKey(Key('trash-delete-${b.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(await repo.listTrash(), isEmpty);
    expect(find.textContaining('The Trash is empty'), findsOneWidget);
  });
}
