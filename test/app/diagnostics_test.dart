import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/diagnostics.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/app/theme.dart';
import 'package:neatink/features/settings/settings_screen.dart';
import 'package:neatink/features/settings/widgets/diagnostics_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/in_memory_repository.dart';

class _Share implements DiagnosticsShareService {
  final List<({String fileName, String text})> shared = [];

  @override
  Future<void> share({required String fileName, required String text}) async =>
      shared.add((fileName: fileName, text: text));
}

void main() {
  group('InMemoryDiagnosticsLog', () {
    test('records, skips a repeat within a minute, keeps the newest', () async {
      var now = DateTime(2026, 11, 2, 9);
      final log = InMemoryDiagnosticsLog(maxEntries: 3, clock: () => now);
      log.record('NeatInk: autosave failed');
      log.record('NeatInk: autosave failed');
      expect(await log.entries(), hasLength(1), reason: 'the same message again at once');
      now = now.add(const Duration(minutes: 2));
      log.record('NeatInk: autosave failed');
      log.record('NeatInk: b');
      log.record('NeatInk: c');
      final entries = await log.entries();
      expect([for (final e in entries) e.message], ['NeatInk: autosave failed', 'NeatInk: b', 'NeatInk: c']);
      await log.clear();
      expect(await log.entries(), isEmpty);
    });

    test('a very long message is cut', () async {
      final log = InMemoryDiagnosticsLog();
      log.record('x' * (maxDiagnosticMessage + 100));
      expect((await log.entries()).single.message.length, maxDiagnosticMessage + 1);
    });
  });

  group('FileDiagnosticsLog', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('diag'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('writes entries to a file that a new log reads back', () async {
      var t = DateTime(2026, 11, 2, 9);
      final log = FileDiagnosticsLog(directory: () async => dir, clock: () => t = t.add(const Duration(minutes: 5)));
      log.record('NeatInk: one');
      log.record('NeatInk: two\nwith a stack');
      final entries = await log.entries();
      expect([for (final e in entries) e.message], ['NeatInk: one', 'NeatInk: two\nwith a stack']);
      expect(entries.first.time, DateTime(2026, 11, 2, 9, 5));
      final again = await FileDiagnosticsLog(directory: () async => dir).entries();
      expect(again, hasLength(2));
      await log.clear();
      expect(await log.entries(), isEmpty);
    });

    test('keeps the newest entries', () async {
      var t = DateTime(2026);
      final log = FileDiagnosticsLog(directory: () async => dir, maxEntries: 4, clock: () => t = t.add(const Duration(minutes: 1)));
      for (var i = 0; i < 12; i++) {
        log.record('NeatInk: $i');
      }
      final messages = [for (final e in await log.entries()) e.message];
      expect(messages.length, lessThanOrEqualTo(5));
      expect(messages.last, 'NeatInk: 11');
    });

    test('a broken folder never throws from record', () async {
      final log = FileDiagnosticsLog(directory: () async => throw const FileSystemException('no'));
      log.record('NeatInk: x');
      expect(await log.entries(), isEmpty);
    });
  });

  test('the report names the app and lists each problem with its time', () {
    final report = diagnosticsReport(
      [(time: DateTime(2026, 11, 2, 9, 5), message: 'NeatInk: PDF export failed: write_failed: disk full')],
      now: DateTime(2026, 11, 2, 10),
      system: 'android 12',
    );
    expect(report, contains("Mariam's Notes diagnostics"));
    expect(report, contains('System: android 12'));
    expect(report, contains('Problems recorded: 1'));
    expect(report, contains('[2026-11-02T09:05:00.000]\nNeatInk: PDF export failed: write_failed: disk full'));
    expect(diagnosticsFileName(DateTime(2026, 11, 2, 9, 5)), 'mariams-notes-diagnostics-20261102-0905.txt');
  });

  test('installDiagnostics keeps NeatInk lines only, and still prints them', () async {
    final original = debugPrint;
    final printed = <String?>[];
    debugPrint = (m, {wrapWidth}) => printed.add(m);
    addTearDown(() => debugPrint = original);
    final log = InMemoryDiagnosticsLog();
    installDiagnostics(log: log);
    debugPrint('NeatInk: could not save settings');
    debugPrint('some framework chatter');
    expect(printed, ['NeatInk: could not save settings', 'some framework chatter']);
    expect([for (final e in await log.entries()) e.message], ['NeatInk: could not save settings']);
    expect(appDiagnostics, same(log));
  });

  testWidgets('Settings: share the report, clear the log', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final log = InMemoryDiagnosticsLog()..record('NeatInk: autosave failed: disk full');
    final share = _Share();
    tester.view.physicalSize = const Size(1200, 4600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        notebookRepositoryProvider.overrideWithValue(InMemoryNotebookRepository()),
        diagnosticsLogProvider.overrideWithValue(log),
        diagnosticsShareServiceProvider.overrideWithValue(share),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 2, 9, 5)),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const SettingsScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 recorded.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-diagnostics')));
    await tester.pumpAndSettle();
    expect(share.shared.single.fileName, 'mariams-notes-diagnostics-20261102-0905.txt');
    expect(share.shared.single.text, contains('autosave failed: disk full'));

    await tester.tap(find.byKey(const ValueKey('settings-diagnostics-clear')));
    await tester.pumpAndSettle();
    expect(await log.entries(), isEmpty);
    expect(find.textContaining('None recorded.'), findsOneWidget);
  });
}
