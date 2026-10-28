import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/app/theme.dart';
import 'package:neatink/document/notebook_meta.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/features/editor/tool_prefs.dart';
import 'package:neatink/features/settings/app_settings.dart';
import 'package:neatink/features/settings/backup_app_data.dart';
import 'package:neatink/features/settings/backup_service.dart';
import 'package:neatink/features/settings/my_words_screen.dart';
import 'package:neatink/features/settings/settings_controller.dart';
import 'package:neatink/features/settings/settings_screen.dart';
import 'package:neatink/recognition/user_lexicon.dart';
import 'package:neatink/storage/backup/notebook_backup.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/in_memory_repository.dart';

class FakeBackupService implements BackupService {
  final List<String> calls = [];
  Map<String, Object?>? appData;
  bool saveResult = true;
  String? picked = '/cache/picked.zip';
  BackupInfo? info;
  Object? inspectError;
  List<RestoreItem>? restoredItems;
  List<String> failTitles = const [];
  final List<String> discarded = [];

  @override
  Future<String> create(Map<String, Object?> appData,
      {required BackupProgress onProgress}) async {
    calls.add('create');
    this.appData = appData;
    onProgress(1, 2);
    onProgress(2, 2);
    return '/cache/backup.zip';
  }

  @override
  Future<bool> save(String path, String fileName) async {
    calls.add('save $fileName');
    return saveResult;
  }

  @override
  Future<String?> pick() async => picked;

  @override
  Future<BackupInfo> inspect(String path) async {
    if (inspectError != null) throw inspectError!;
    return info!;
  }

  @override
  Future<RestoreResult> restore(String path, List<RestoreItem> items,
      {required BackupProgress onProgress}) async {
    restoredItems = items;
    final todo = [for (final i in items) if (i.action != RestoreAction.skip) i];
    return RestoreResult(
      restored: [for (final i in todo) if (!failTitles.contains(i.title)) i.targetId],
      failed: [for (final i in todo) if (failTitles.contains(i.title)) i.title],
    );
  }

  @override
  Future<void> discard(String path) async => discarded.add(path);
}

void main() {
  late SharedPreferences prefs;
  late InMemoryNotebookRepository repo;
  late FakeBackupService service;
  late UserLexicon lexicon;
  final now = DateTime(2026, 10, 28, 15, 30);
  final t0 = DateTime.utc(2026, 10, 1);

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      AppSettings.prefsKey: jsonEncode(
          const AppSettings(pinHash: 'hash', pinSalt: 'salt', autoConvert: true).toJson()),
    });
    prefs = await SharedPreferences.getInstance();
    repo = InMemoryNotebookRepository();
    service = FakeBackupService();
  });

  Future<ProviderContainer> pumpSettings(WidgetTester tester) async {
    // Made inside the test: its save future must belong to the test's
    // fake-async zone, or awaiting it never completes.
    lexicon = UserLexicon(store: InMemoryUserLexiconStore(['Malek']));
    tester.view.physicalSize = const Size(1200, 4600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        notebookRepositoryProvider.overrideWithValue(repo),
        backupServiceProvider.overrideWithValue(service),
        myWordsLexiconProvider.overrideWithValue(lexicon),
        clockProvider.overrideWithValue(() => now),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const SettingsScreen()),
    ));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  NotebookMeta notebook(String id, String title,
          {DateTime? updated, String? folderId}) =>
      NotebookMeta(
          id: id,
          title: title,
          createdAt: t0,
          updatedAt: updated ?? t0,
          kind: NotebookKind.blank,
          defaultPaper: const Paper(),
          pages: const [PageMeta(id: 'p1')],
          folderId: folderId);

  BackupInfo backupOf(List<NotebookMeta> notebooks,
          {Map<String, Object?> appData = const {}, LibraryIndex? library}) =>
      BackupInfo(
        createdAt: DateTime.utc(2026, 10, 20, 9),
        appVersion: '1.6.0',
        notebooks: [for (final n in notebooks) BackupNotebook(n)],
        unreadable: 0,
        library: library ?? const LibraryIndex(),
        appData: appData,
      );

  group('back up', () {
    testWidgets('makes the file, saves it, remembers the date, and never includes the PIN',
        (tester) async {
      final c = await pumpSettings(tester);
      expect(find.textContaining('No backup yet.'), findsOneWidget);

      await tap(tester, 'settings-backup');

      expect(service.calls, ['create', 'save MariamsNotes-backup-2026-10-28.zip']);
      final settings = service.appData![BackupAppData.settingsKey]! as Map<String, Object?>;
      expect(settings['autoConvert'], isTrue);
      expect(settings.keys, isNot(contains('pinHash')));
      expect(settings.keys, isNot(contains('pinSalt')));
      expect(service.appData![BackupAppData.myWordsKey], ['Malek']);
      expect(service.appData![BackupAppData.toolPrefsKey], isA<Map<String, dynamic>>());
      expect(c.read(settingsProvider).lastBackupAt, now);
      expect(find.text('Backup saved. Keep it somewhere off this tablet.'), findsOneWidget);
      expect(find.textContaining('Last backup: just now.'), findsOneWidget);
      expect(service.discarded, ['/cache/backup.zip']);
    });

    testWidgets('cancelling the save dialog keeps no date', (tester) async {
      service.saveResult = false;
      final c = await pumpSettings(tester);
      await tap(tester, 'settings-backup');
      expect(c.read(settingsProvider).lastBackupAt, isNull);
      expect(find.text('The backup was not saved.'), findsOneWidget);
      expect(service.discarded, ['/cache/backup.zip']);
    });
  });

  group('restore', () {
    testWidgets('adds new notebooks, skips unchanged ones, copies changed ones, merges folders and words',
        (tester) async {
      final same = await repo.createNotebook(title: 'Same', paper: const Paper());
      final changed = await repo.createNotebook(title: 'Changed', paper: const Paper());
      final folder = Folder(id: 'f1', name: 'Biology', createdAt: t0);
      service.info = backupOf([
        same,
        changed.copyWith(updatedAt: t0),
        notebook('new1', 'Neurons', folderId: 'f1'),
      ], appData: {
        BackupAppData.myWordsKey: ['Malek', 'Baghdadi'],
      }, library: LibraryIndex(folders: [folder]));
      await pumpSettings(tester);

      await tap(tester, 'settings-restore');
      expect(find.text('The backup from 20 Oct 2026 has 3 notebooks.'), findsOneWidget);
      expect(find.text('1 notebook will be added.'), findsOneWidget);
      expect(find.text('1 notebook already here and unchanged: skipped.'), findsOneWidget);
      expect(find.text('2 words for My words.'), findsOneWidget);
      expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('restore-copy-changed'))).value,
          isTrue);
      expect(find.byKey(const ValueKey('restore-settings')), findsNothing);

      await tap(tester, 'restore-confirm');

      final byTitle = {for (final i in service.restoredItems!) i.notebook.title: i};
      expect(byTitle['Same']!.action, RestoreAction.skip);
      expect(byTitle['Changed']!.action, RestoreAction.copy);
      expect(byTitle['Changed']!.title, 'Changed (from backup)');
      expect(byTitle['Changed']!.targetId, isNot(changed.id));
      expect(byTitle['Neurons']!.action, RestoreAction.add);
      expect((await repo.loadLibrary()).folders.single.name, 'Biology');
      expect(lexicon.words, ['Malek', 'Baghdadi']);
      expect(find.text('Restored 2 notebooks.'), findsOneWidget);
      expect(service.discarded, ['/cache/picked.zip']);
    });

    testWidgets('changed notebooks can be left out', (tester) async {
      final changed = await repo.createNotebook(title: 'Changed', paper: const Paper());
      service.info = backupOf([changed.copyWith(updatedAt: t0)]);
      await pumpSettings(tester);
      await tap(tester, 'settings-restore');
      await tap(tester, 'restore-copy-changed');
      // Nothing left to restore.
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('restore-confirm'))).onPressed,
          isNull);
      await tap(tester, 'restore-cancel');
      expect(service.restoredItems, isNull);
      expect(service.discarded, ['/cache/picked.zip']);
    });

    testWidgets('settings come back only when ticked, and the PIN stays', (tester) async {
      service.info = backupOf([notebook('n1', 'Notes')], appData: {
        BackupAppData.settingsKey: const AppSettings(themeMode: AppThemeMode.dark).toJson()
          ..remove('pinHash')
          ..remove('pinSalt'),
        BackupAppData.toolPrefsKey: const ToolPrefs().toJson(),
      });
      final c = await pumpSettings(tester);
      await tap(tester, 'settings-restore');
      await tap(tester, 'restore-settings');
      await tap(tester, 'restore-confirm');
      final s = c.read(settingsProvider);
      expect(s.themeMode, AppThemeMode.dark);
      expect(s.pinHash, 'hash');
      expect(s.pinSalt, 'salt');
      expect(prefs.getString(ToolPrefs.prefsKey), isNotNull);
    });

    testWidgets('notebooks that fail are listed', (tester) async {
      service.info = backupOf([notebook('n1', 'Good'), notebook('n2', 'Bad')]);
      service.failTitles = ['Bad'];
      await pumpSettings(tester);
      await tap(tester, 'settings-restore');
      await tap(tester, 'restore-confirm');
      expect(find.byKey(const ValueKey('restore-failures')), findsOneWidget);
      expect(find.text('Bad'), findsOneWidget);
    });

    testWidgets('a file that is not a backup says so', (tester) async {
      service.inspectError = const BackupException('This file is not a notebook backup.');
      await pumpSettings(tester);
      await tap(tester, 'settings-restore');
      expect(find.text('This file is not a notebook backup.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.discarded, ['/cache/picked.zip']);
    });

    testWidgets('a cancelled picker does nothing', (tester) async {
      service.picked = null;
      await pumpSettings(tester);
      await tap(tester, 'settings-restore');
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.discarded, isEmpty);
    });
  });

  test('backup file name', () {
    expect(backupFileName(DateTime(2026, 3, 4)), 'MariamsNotes-backup-2026-03-04.zip');
  });
}
