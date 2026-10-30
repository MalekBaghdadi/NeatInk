import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/app.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/audio/audio_channel.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/features/editor/default_integrations.dart';
import 'package:neatink/features/editor/editor_integrations.dart';
import 'package:neatink/features/editor/editor_tool.dart';
import 'package:neatink/features/recording/recording_controller.dart';
import 'package:neatink/features/settings/app_settings.dart';
import 'package:neatink/features/tips/tips_screen.dart';
import 'package:neatink/features/tour/tour.dart';
import 'package:neatink/features/tour/tours.dart';
import 'package:neatink/storage/recording_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_audio.dart';
import '../fakes/in_memory_repository.dart';
import '../lock/lock_test_support.dart';

// v1.12.0: a guided tour shows each button and what it does.

Finder key(String k) => find.byKey(ValueKey(k));

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<ProviderContainer> pumpApp(WidgetTester tester, {bool tipsSeen = false}) async {
    resumeAfterTest(tester);
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (tipsSeen) await prefs.setString(AppSettings.prefsKey, '{"tipsSeen": true}');
    final repo = InMemoryNotebookRepository();
    await repo.createNotebook(title: 'Neuro', paper: const Paper(), pageCount: 1);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        notebookRepositoryProvider.overrideWithValue(repo),
        clockProvider.overrideWithValue(() => DateTime(2026, 10, 30, 9)),
        autoToursProvider.overrideWithValue(true),
        // The app's buttons, so the notebook tour has them all to show.
        editorIntegrationsProvider.overrideWithValue(defaultEditorIntegrations),
        audioBackendProvider.overrideWithValue(FakeAudioBackend()),
        recordingStoreProvider.overrideWithValue(InMemoryRecordingStore()),
      ],
      child: const NeatInkApp(),
    ));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(NeatInkApp)));
  }

  testWidgets('after the first-run tips, the library tour starts once and goes button by button', (tester) async {
    final c = await pumpApp(tester);
    expect(find.byType(TipsScreen), findsOneWidget);
    expect(find.byType(TourOverlay), findsNothing, reason: 'it waits for the tips');
    await tester.scrollUntilVisible(key('tips-done'), 200,
        scrollable: find.descendant(of: key('tips-list'), matching: find.byType(Scrollable)));
    await tester.tap(key('tips-done'));
    await tester.pumpAndSettle();

    expect(find.byType(TourOverlay), findsOneWidget);
    expect(find.text("Welcome to Mariam's Notes"), findsOneWidget);
    expect(c.read(tourMemoryProvider).seen(TourMemory.library), isTrue);
    await tester.tap(key('tour-next'));
    await tester.pumpAndSettle();
    expect(find.text('New'), findsWidgets);
    expect(find.textContaining('import a PDF'), findsOneWidget);
    // The lit button is the New button.
    final lit = findTourTarget(const TourStep(target: 'library-new', title: '', text: ''));
    expect(lit, isNotNull);
    expect(lit!.overlaps(tester.getRect(key('library-new'))), isTrue);
    await tester.tap(key('tour-back'));
    await tester.pumpAndSettle();
    expect(find.text("Welcome to Mariam's Notes"), findsOneWidget);
    await tester.tap(key('tour-skip'));
    await tester.pumpAndSettle();
    expect(find.byType(TourOverlay), findsNothing);

    // Next start: no tour.
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester);
    expect(find.byType(TourOverlay), findsNothing);
  });

  testWidgets('"Show me around again" brings the tours back', (tester) async {
    final c = await pumpApp(tester, tipsSeen: true);
    await tester.tap(key('tour-skip'));
    await tester.pumpAndSettle();
    await c.read(tourMemoryProvider).resetAll();
    await tester.pumpAndSettle();
    expect(find.byType(TourOverlay), findsOneWidget);
  });

  testWidgets('every tool says what it does on a long press', (tester) async {
    for (final t in EditorTool.values) {
      expect(t.hint, isNotEmpty);
    }
    await pumpApp(tester, tipsSeen: true);
    await tester.tap(key('tour-skip'));
    await tester.pumpAndSettle();
    await tester.longPress(key('library-search'));
    await tester.pumpAndSettle();
    expect(find.text('Search your notebooks, typed text, PDFs and handwriting'), findsOneWidget);
  });

  testWidgets('a notebook shows its own tour the first time, then from its menu', (tester) async {
    final c = await pumpApp(tester, tipsSeen: true);
    await tester.tap(key('tour-skip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Neuro'));
    await tester.pumpAndSettle();
    expect(find.text('Your notebook'), findsOneWidget);
    expect(c.read(tourMemoryProvider).seen(TourMemory.notebook), isTrue);
    await tester.tap(key('tour-next'));
    await tester.pumpAndSettle();
    expect(find.textContaining('scribble over them'), findsOneWidget, reason: 'the pen');
    await tester.tap(key('tour-skip'));
    await tester.pumpAndSettle();

    await tester.tap(key('editor-menu'));
    await tester.pumpAndSettle();
    await tester.tap(key('menu-tour'));
    await tester.pumpAndSettle();
    expect(find.text('Your notebook'), findsOneWidget);
    // Steps whose button is not there (no recordings yet) are left out.
    final shown = <String>[];
    for (var i = 0; i < 40 && find.byType(TourOverlay).evaluate().isNotEmpty; i++) {
      final title = tester.widgetList<Text>(find.descendant(of: find.byType(TourOverlay), matching: find.byType(Text)));
      shown.add(title.first.data ?? '');
      await tester.tap(key('tour-next'));
      await tester.pumpAndSettle();
    }
    expect(shown, contains('Lasso'));
    expect(shown, contains('Record a lecture'));
    expect(shown, isNot(contains('Recordings')));
  });
}
