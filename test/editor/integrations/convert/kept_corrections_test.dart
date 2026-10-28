import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/app_info.dart';
import 'package:neatink/features/editor/integrations/convert/kept_corrections.dart';
import 'package:neatink/features/settings/app_settings.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';

import 'harness.dart';

Finder key(String k) => find.byKey(ValueKey(k));

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

List<Stroke> threeLines() => [
      ...writeLine('a', ['hello', 'online'], y: 104),
      ...writeLine('b', ['hello'], y: 156),
      ...writeLine('c', ['hello'], y: 208),
    ];

FakeRecognizer reader() => FakeRecognizer({
      'aw0': ('hello', 0.9),
      'aw1': ('online', 0.9),
      'bw0': ('secnd', 0.9),
      'cw0': ('third', 0.9),
    });

Map<String, dynamic> entry(int i, {int points = 2}) => {
      'line': i,
      'finalText': 'line $i',
      'strokes': [
        {
          'points': [for (var k = 0; k < points; k++) const InkPoint(1, 2, 0.5, 0).toJson()],
        },
      ],
    };

void main() {
  group('the Convert sheet keeps what it converts', () {
    testWidgets('converted lines are kept with the text checked in the sheet', (tester) async {
      final h = await ConvertHarness.open(tester, pages: [threeLines()], recognizer: reader());
      await h.tapConvert();
      await tester.enterText(key('convert-text-1'), 'second');
      await tester.tap(key('convert-include-2'));
      await tester.pump();
      expect(h.kept.lines, isEmpty, reason: 'nothing before converting');

      await tester.tap(key('convert-apply'));
      await settle(tester);
      final lines = h.kept.lines;
      expect([for (final l in lines) l['finalText']], ['hello online', 'second'],
          reason: 'the unticked line stays ink and is not kept');
      expect([for (final l in lines) l['recognizedText']], ['hello online', 'secnd']);
      expect([for (final l in lines) l['corrected']], [false, true]);
      expect(lines.every((l) => (l['images'] as List).isEmpty), isTrue, reason: 'no pictures kept');
      expect(lines.every((l) => (l['strokes'] as List).isNotEmpty), isTrue);
      expect(lines.every((l) => DateTime.tryParse(l['keptAt'] as String) != null), isTrue);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('a closed sheet keeps nothing', (tester) async {
      final h = await ConvertHarness.open(tester, pages: [threeLines()], recognizer: reader());
      await h.tapConvert();
      await tester.tap(key('convert-close'));
      await settle(tester);
      expect(h.kept.lines, isEmpty);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('with the setting off nothing is kept', (tester) async {
      final h = await ConvertHarness.open(tester,
          pages: [threeLines()],
          recognizer: reader(),
          prefsValues: {AppSettings.prefsKey: jsonEncode({'keepCorrections': false})});
      await h.tapConvert();
      await tester.tap(key('convert-apply'));
      await settle(tester);
      expect(h.kept.lines, isEmpty);
      await tester.pump(const Duration(seconds: 6));
    });

    test('the setting is on by default', () {
      expect(const AppSettings().keepCorrections, isTrue);
      expect(AppSettings.fromJson(const {}).keepCorrections, isTrue);
      expect(AppSettings.fromJson(const {'keepCorrections': false}).keepCorrections, isFalse);
    });
  });

  group('FileKeptCorrections', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('kept'));
    tearDown(() => dir.deleteSync(recursive: true));

    FileKeptCorrections store({int maxLines = 1000, int maxBytes = 1 << 30}) =>
        FileKeptCorrections(directory: () async => dir, maxLines: maxLines, maxBytes: maxBytes);

    test('adds, counts, exports one samples file and clears', () async {
      final kept = store();
      expect(await kept.count(), 0);
      expect(await kept.exportJson(appVersion: '1', createdAt: DateTime(2026)), isNull);
      await kept.addAll([entry(0), entry(1)]);
      await kept.addAll([entry(2)]);
      expect(await kept.count(), 3);

      final json = jsonDecode((await kept.exportJson(appVersion: '1.7.0+9', createdAt: DateTime(2026, 11, 2)))!)
          as Map<String, dynamic>;
      expect(json['format'], 2);
      expect(json['kind'], 'kept-corrections');
      expect(json['appVersion'], '1.7.0+9');
      expect(json['lineCount'], 3);
      expect([for (final l in json['lines'] as List) (l as Map)['finalText']], ['line 0', 'line 1', 'line 2']);

      await kept.clear();
      expect(await kept.count(), 0);
      // A new store over the same folder sees the same file.
      await kept.addAll([entry(5)]);
      expect(await store().count(), 1);
    });

    test('keeps only the newest lines', () async {
      final kept = store(maxLines: 3);
      for (var i = 0; i < 5; i++) {
        await kept.addAll([entry(i)]);
      }
      final json = jsonDecode((await kept.exportJson(appVersion: '1', createdAt: DateTime(2026)))!) as Map;
      expect([for (final l in json['lines'] as List) (l as Map)['line']], [2, 3, 4]);
    });

    test('keeps the file under its size', () async {
      final one = utf8.encode(jsonEncode(entry(0, points: 50))).length + 1;
      final kept = store(maxBytes: one * 2 + 10);
      for (var i = 0; i < 4; i++) {
        await kept.addAll([entry(i, points: 50)]);
      }
      expect(await kept.count(), 2);
      expect(File('${dir.path}/recognition/${FileKeptCorrections.fileName}').lengthSync(), lessThanOrEqualTo(one * 2 + 10));
    });

    test('a line cut short by a crash is skipped', () async {
      final kept = store();
      await kept.addAll([entry(0)]);
      final file = File('${dir.path}/recognition/${FileKeptCorrections.fileName}');
      file.writeAsStringSync('{"line": 1, "fin', mode: FileMode.append);
      expect(await kept.count(), 1);
      await kept.addAll([entry(2)]);
      expect(await kept.count(), 2, reason: 'the next line starts on its own line');
    });

    test('the file name follows the samples files', () {
      expect(keptCorrectionsFileName(DateTime(2026, 11, 2, 9, 5)), 'mariams-notes-corrections-20261102-0905.json');
      expect(AppInfo.name, "Mariam's Notes");
    });
  });
}
