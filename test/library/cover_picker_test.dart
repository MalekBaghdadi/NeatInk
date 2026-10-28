import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/document/cover_design.dart';
import 'package:neatink/document/notebook_meta.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/features/editor/integrations/text_images/image_source.dart';
import 'package:neatink/features/library/dialogs/cover_picker.dart';
import 'package:neatink/features/library/dialogs/new_notebook_sheet.dart';
import 'package:neatink/features/library/library_controller.dart';
import 'package:neatink/features/library/widgets/color_swatch_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../editor/integrations/text_images/helpers_test.dart' show solidPng;
import '../fakes/in_memory_repository.dart';

/// Opens [open] from a button; `.result` completes with what it returns.
/// (A record, so the result is not awaited here.)
Future<({Future<T?> result})> launch<T>(WidgetTester tester, Future<T?> Function(BuildContext) open) async {
  late Future<T?> result;
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(onPressed: () => result = open(context), child: const Text('open')),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (result: result);
}

Future<void> tapTile(WidgetTester tester, String key) async {
  final tile = find.byKey(ValueKey(key));
  await tester.scrollUntilVisible(tile, 120,
      scrollable: find.descendant(of: find.byType(CoverPicker), matching: find.byType(Scrollable)).first);
  await tester.tap(tile);
  await tester.pump();
}

Future<void> waitFor(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

void main() {
  final teal = NotebookMeta.coverColors[5];

  testWidgets('choose a science picture and a colour', (tester) async {
    final sheet = await launch<CoverChoice>(
        tester,
        (context) => showCoverPicker(context,
            design: const CoverDesign.preview(), color: NotebookMeta.coverColors.first, pickImage: () async => null));
    await tester.tap(find.byType(ColorSwatchButton).at(5));
    await tester.pump();
    await tapTile(tester, 'cover-art-dna');
    await tester.tap(find.byKey(const ValueKey('cover-done')));
    await tester.pumpAndSettle();
    final choice = (await sheet.result)!;
    expect(choice.design, const CoverDesign.art(CoverArt.dna));
    expect(choice.color, teal);
    expect(choice.photoBytes, isNull);
  });

  testWidgets('cancelling changes nothing', (tester) async {
    final sheet = await launch<CoverChoice>(
        tester,
        (context) => showCoverPicker(context,
            design: const CoverDesign.pattern(CoverPattern.dots), color: teal, pickImage: () async => null));
    await tester.pumpAndSettle();
    await tapTile(tester, 'cover-style-waves');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await sheet.result, isNull);
  });

  testWidgets('a photo from the device', (tester) async {
    late Uint8List png;
    await tester.runAsync(() async => png = await solidPng(30, 40));
    final sheet = await launch<CoverChoice>(
        tester,
        (context) => showCoverPicker(context,
            design: const CoverDesign.preview(), color: teal, pickImage: () async => PickedImage(png)));
    await tester.pumpAndSettle();
    final choose = find.byKey(const ValueKey('cover-choose-photo'));
    await tester.scrollUntilVisible(choose, 200,
        scrollable: find.descendant(of: find.byType(CoverPicker), matching: find.byType(Scrollable)).first);
    await tester.tap(choose);
    await waitFor(tester, () => find.byKey(const ValueKey('cover-photo')).evaluate().isNotEmpty);
    expect(find.text('Choose another picture…'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cover-done')));
    await tester.pumpAndSettle();
    final choice = (await sheet.result)!;
    expect(choice.design.kind, CoverKind.photo);
    expect(choice.photoBytes, isNotNull);
    expect(choice.photoExtension, isNotEmpty);
  });

  testWidgets('the new-notebook sheet opens the cover sheet and keeps its choice', (tester) async {
    final sheet = await launch<NewNotebookRequest>(
        tester,
        (context) => showNewNotebookSheet(context,
            defaultTitle: 'Neuro', defaultPaper: const Paper(), pickImage: () async => null));
    await tester.tap(find.byKey(const Key('newNotebookMoreCovers')));
    await tester.pumpAndSettle();
    await tapTile(tester, 'cover-art-neuron');
    await tester.tap(find.byKey(const ValueKey('cover-done')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('newNotebookCover')), matching: find.byType(CustomPaint)),
        findsWidgets);
    // A quick colour keeps the picture (the paper colours come first).
    await tester.tap(find.byType(ColorSwatchButton).at(Paper.colors.length + 5));
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    final request = (await sheet.result)!;
    expect(request.cover!.design, const CoverDesign.art(CoverArt.neuron));
    expect(request.cover!.color, teal);
    expect(request.coverColor, teal);
  });

  testWidgets('without the cover sheet a new notebook keeps the classic cover', (tester) async {
    final sheet = await launch<NewNotebookRequest>(
        tester, (context) => showNewNotebookSheet(context, defaultTitle: 'Neuro', defaultPaper: const Paper()));
    await tester.tap(find.byType(ColorSwatchButton).at(Paper.colors.length + 5));
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    final request = (await sheet.result)!;
    expect(request.cover, isNull);
    expect(request.coverColor, teal);
  });

  group('library', () {
    late InMemoryNotebookRepository repo;
    late ProviderContainer container;
    late LibraryController library;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      repo = InMemoryNotebookRepository();
      container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        notebookRepositoryProvider.overrideWithValue(repo),
      ]);
      await container.read(libraryControllerProvider.future);
      library = container.read(libraryControllerProvider.notifier);
    });

    tearDown(() => container.dispose());

    test('a new notebook stores its cover photo in its own folder', () async {
      final meta = await library.createNotebook(
        title: 'Bio',
        paper: const Paper(),
        cover: CoverChoice(
            design: const CoverDesign.photo('new'),
            color: teal,
            photoBytes: Uint8List.fromList([1, 2, 3]),
            photoExtension: 'jpg'),
      );
      final photo = meta.cover.photo!;
      expect(photo, isNot('new'));
      expect(photo, endsWith('.jpg'));
      expect(repo.assetBytes(meta.id, photo), [1, 2, 3]);
      expect((await repo.loadMeta(meta.id))!.cover, CoverDesign.photo(photo));
      expect(container.read(libraryControllerProvider).value!.notebooks.single.cover, CoverDesign.photo(photo));
    });

    test('changing the cover keeps everything else', () async {
      final meta = await library.createNotebook(title: 'Chem', paper: const Paper());
      expect(meta.cover, const CoverDesign.preview());
      await library.setFavorite(meta.id, true);
      await library.setCover(meta.id, CoverChoice(design: const CoverDesign.art(CoverArt.molecules), color: teal));
      final stored = (await repo.loadMeta(meta.id))!;
      expect(stored.cover, const CoverDesign.art(CoverArt.molecules));
      expect(stored.coverColor, teal);
      expect(stored.favorite, isTrue);
      expect(stored.title, 'Chem');
      expect(container.read(libraryControllerProvider).value!.notebooks.single.cover,
          const CoverDesign.art(CoverArt.molecules));
    });
  });
}
