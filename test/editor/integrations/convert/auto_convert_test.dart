import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/page_items.dart' show TextCorrection;
import 'package:neatink/app/providers.dart';
import 'package:neatink/document/commands.dart';
import 'package:neatink/document/font_kind.dart';
import 'package:neatink/features/editor/canvas/document_view.dart';
import 'package:neatink/features/editor/editor_tool.dart';
import 'package:neatink/features/editor/integrations/convert/convert_config.dart';
import 'package:neatink/features/editor/integrations/convert/convert_layout.dart';
import 'package:neatink/features/settings/app_settings.dart';
import 'package:neatink/features/settings/convert_style_prefs.dart';
import 'package:neatink/features/settings/settings_controller.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/recognition/htr_channel.dart';
import 'package:neatink/recognition/text_polish.dart';

import 'harness.dart';

FakeRecognizer reader([Map<String, (String, double)> extra = const {}]) =>
    FakeRecognizer({
      'aw0': ('hello', 0.9),
      'aw1': ('online', 0.9),
      'bw0': ('second', 0.9),
      'cw0': ('third', 0.9),
      ...extra,
    });

Finder key(String k) => find.byKey(ValueKey(k));

Future<void> wait(WidgetTester tester, int milliseconds) async {
  await tester.pump(Duration(milliseconds: milliseconds));
  await tester.pump();
}

double rightOf(List<Stroke> strokes) => strokes
    .expand((s) => s.raw)
    .map((p) => p.x)
    .reduce((a, b) => a > b ? a : b);

List<String> texts(ConvertHarness h) => [for (final t in h.page.texts) t.text];

void main() {
  group('when it converts', () {
    testWidgets('by default 2 s after the last stroke', (tester) async {
      final h = await ConvertHarness.open(tester,
          recognizer: reader(), autoConvert: true, autoConvertDelayMs: null);
      await h.write(writeLine('a', ['hello'], y: 104));
      await wait(tester, 1800); // 1.9 s since the last stroke
      expect(h.page.texts, isEmpty);
      await wait(tester, 200);
      expect(texts(h), ['hello']);
    });

    testWidgets('as long after the last stroke as the setting says', (tester) async {
      final h = await ConvertHarness.open(tester,
          recognizer: reader(), autoConvert: true, autoConvertDelayMs: 4500);
      await h.write(writeLine('a', ['hello'], y: 104));
      await wait(tester, 4300);
      expect(h.page.texts, isEmpty, reason: 'a pause in the middle of a sentence');
      await wait(tester, 300);
      expect(texts(h), ['hello']);

      // A new delay applies to the next stroke.
      h.container
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(autoConvertDelayMs: 1000));
      await h.write(writeLine('b', ['hello'], y: 156));
      await wait(tester, 1100);
      expect(texts(h), ['hello', 'second']);
    });

    testWidgets('about a second after the last stroke, not before',
        (tester) async {
      final h = await ConvertHarness.open(tester,
          recognizer: reader(), autoConvert: true);
      await h.write(writeLine('a', ['hello', 'online'], y: 104));
      final depth = h.undoDepth;

      await wait(tester, 800); // 900 ms since the last stroke
      expect(h.page.texts, isEmpty);
      expect(h.recognizer.calls, 0);
      expect(h.page.strokes, isNotEmpty);

      await wait(tester, 200); // past 1000 ms
      expect(texts(h), ['hello online']);
      expect(h.page.strokes, isEmpty);
      expect(h.recognizer.calls, 1);
      // One undo step, named for what it did.
      expect(h.undoDepth, depth + 1);
      expect(h.controller.undoLabel, 'Auto-convert');
    });

    testWidgets('never in the middle of a letter written with 300 ms gaps',
        (tester) async {
      final h = await ConvertHarness.open(tester,
          recognizer: reader(), autoConvert: true);
      final strokes = writeLine('a', ['hello'], y: 104);
      expect(strokes.length, greaterThanOrEqualTo(3));
      for (final s in strokes) {
        await h.draw(s);
        await wait(tester, 300);
        expect(h.page.texts, isEmpty, reason: 'after ${s.id}');
        expect(h.recognizer.calls, 0);
      }
      await wait(tester, 800);
      expect(texts(h), ['hello']);
      expect(h.recognizer.wordsRead, 1, reason: 'the word is read once, whole');
    });

    testWidgets('putting the pen down again postpones it', (tester) async {
      final h = await ConvertHarness.open(tester,
          recognizer: reader(), autoConvert: true);
      await h.write(writeLine('a', ['hello'], y: 104));
      await wait(tester, 500);

      // A real pen stroke, held down for longer than the idle time.
      final start =
          tester.getCenter(find.byType(DocumentView)) - const Offset(100, 100);
      final g = await tester.startGesture(start, kind: PointerDeviceKind.stylus);
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(10, 4));
        await wait(tester, 400);
      }
      expect(h.controller.inkTool.active, isNotNull);
      expect(h.page.texts, isEmpty, reason: 'pen is down: wait');
      expect(h.recognizer.calls, 0);

      await g.up();
      await wait(tester, 800);
      expect(h.page.texts, isEmpty, reason: '1 s starts at pen up');
      await wait(tester, 400);
      expect(h.page.texts, isNotEmpty);
      expect(h.page.texts.map((t) => t.text), contains('hello'));
    });

    testWidgets('strokes of several lines are read together, one undo step',
        (tester) async {
      final h = await ConvertHarness.open(tester,
          recognizer: reader(), autoConvert: true);
      await h.write([
        ...writeLine('a', ['hello'], y: 104),
        ...writeLine('b', ['hello'], y: 156),
      ]);
      final depth = h.undoDepth;
      await wait(tester, 1100);
      expect(texts(h), ['hello', 'second']);
      expect(h.undoDepth, depth + 1);
      h.controller.undo();
      expect(h.page.texts, isEmpty);
      expect(h.page.strokes, isNotEmpty);
    });
  });

  group('what it leaves alone', () {
    testWidgets('a low-confidence line stays ink and is not read again',
        (tester) async {
      final h = await ConvertHarness.open(tester,
          recognizer: reader({'bw0': ('seoond', 0.2)}), autoConvert: true);
      final b = writeLine('b', ['hello'], y: 156);
      await h.write([...writeLine('a', ['hello'], y: 104), ...b]);
      await wait(tester, 1100);
      expect(texts(h), ['hello']);
      // The doubtful line is exactly as it was drawn.
      expect([for (final s in h.page.strokes) s.id], [for (final s in b) s.id]);
      for (var i = 0; i < b.length; i++) {
        expect(identical(h.page.strokes[i], b[i]), isTrue);
      }
      expect(h.recognizer.wordsRead, 2);

      // A new line later: only that one is read.
      await h.write(writeLine('c', ['hello'], y: 208));
      await wait(tester, 1100);
      expect(texts(h), ['hello', 'third']);
      expect(h.recognizer.wordsRead, 3, reason: 'the doubtful line is not retried');
      expect(h.page.strokes.map((s) => s.id).toSet(),
          {for (final s in b) s.id});
    });

    testWidgets('a doubtful line is read again, whole, when more is written on it',
        (tester) async {
      final h = await ConvertHarness.open(tester,
          recognizer: reader({'bw0': ('helo', 0.1)}), autoConvert: true);
      final first = writeLine('b', ['hello'], y: 156);
      await h.write(first);
      await wait(tester, 1100);
      expect(h.page.texts, isEmpty);
      expect(h.recognizer.wordsRead, 1);

      // The sentence goes on after a pause, on the same line; with the rest
      // of the line the first word reads well.
      h.recognizer.readings['bw0'] = ('hello', 0.9);
      h.recognizer.readings['xw0'] = ('online', 0.9);
      await h.write(writeLine('x', ['online'], y: 156, x: rightOf(first) + 28));
      await wait(tester, 1100);
      expect(texts(h), ['hello online']);
      expect(h.page.strokes, isEmpty);
      expect(h.recognizer.wordsRead, 3, reason: 'the whole line is read again');
    });

    testWidgets('one doubtful word keeps the whole line as ink', (tester) async {
      final h = await ConvertHarness.open(tester,
          recognizer: reader({'aw1': ('onlyne', 0.2)}), autoConvert: true);
      await h.write(writeLine('a', ['hello', 'online'], y: 104));
      await wait(tester, 1100);
      expect(h.page.texts, isEmpty);
      expect(h.page.strokes, isNotEmpty);
      expect(h.undoDepth, greaterThan(0));
      expect(h.controller.undoLabel, 'Pen stroke', reason: 'nothing was changed');
    });

    testWidgets('an unreadable word keeps the whole line as ink', (tester) async {
      final h = await ConvertHarness.open(tester,
          recognizer: reader({'aw1': ('', 0.95)}), autoConvert: true);
      await h.write(writeLine('a', ['hello', 'online'], y: 104));
      await wait(tester, 1100);
      expect(h.page.texts, isEmpty);
      expect(h.controller.undoLabel, 'Pen stroke');
    });

    testWidgets('a confidence of exactly the minimum is good enough',
        (tester) async {
      final h = await ConvertHarness.open(tester,
          recognizer: reader({'aw0': ('hello', 0.25)}), autoConvert: true);
      await h.write(writeLine('a', ['hello'], y: 104));
      await wait(tester, 1100);
      expect(texts(h), ['hello']);
    });

    testWidgets('highlighter strokes and snapped shapes are ignored',
        (tester) async {
      final h = await ConvertHarness.open(tester,
          recognizer: reader(), autoConvert: true);
      final base = writeLine('a', ['hello'], y: 104).first;
      final hl = base.copyWith(id: 'hl', tool: StrokeTool.highlighter);
      final shape = base.copyWith(id: 'sh', shape: ShapeKind.line);
      await h.write([hl, shape]);
      await wait(tester, 2000);
      expect(h.recognizer.calls, 0);
      expect(h.page.strokes, hasLength(2));
    });

    testWidgets('nothing happens with the setting off', (tester) async {
      final h = await ConvertHarness.open(tester, recognizer: reader());
      await h.write(writeLine('a', ['hello'], y: 104));
      await wait(tester, 3000);
      expect(h.page.texts, isEmpty);
      expect(h.recognizer.calls, 0);
    });

    testWidgets('turning the setting off with a timer pending cancels it',
        (tester) async {
      final h = await ConvertHarness.open(tester,
          recognizer: reader(), autoConvert: true);
      await h.write(writeLine('a', ['hello'], y: 104));
      await wait(tester, 400);
      h.setAutoConvert(false);
      await wait(tester, 3000);
      expect(h.page.texts, isEmpty);
      expect(h.recognizer.calls, 0);
      expect(h.page.strokes, isNotEmpty);

      // Back on: only what is written from now on is converted.
      h.setAutoConvert(true);
      await h.write(writeLine('b', ['hello'], y: 156));
      await wait(tester, 1100);
      expect(texts(h), ['second']);
      expect(h.page.strokes.every((s) => s.id.startsWith('aw0')), isTrue);
    });

    testWidgets('turning it on later does not touch old ink', (tester) async {
      final h = await ConvertHarness.open(tester,
          pages: [writeLine('a', ['hello'], y: 104)], recognizer: reader());
      h.setAutoConvert(true);
      await wait(tester, 3000);
      expect(h.page.texts, isEmpty);
      expect(h.recognizer.calls, 0);
    });

    testWidgets('a read-only page is never converted', (tester) async {
      final h = await ConvertHarness.open(tester,
          pages: [const []], unreadablePages: {0}, recognizer: reader(), autoConvert: true);
      await h.write(writeLine('a', ['hello'], y: 104));
      await wait(tester, 3000);
      expect(h.recognizer.calls, 0);
      expect(h.page.texts, isEmpty);
      expect(h.page.strokes, isNotEmpty);
    });

    testWidgets('waits while another tool is selected, then converts',
        (tester) async {
      final h = await ConvertHarness.open(tester,
          recognizer: reader(), autoConvert: true);
      h.controller.selectTool(EditorTool.lasso);
      await tester.pump();
      await h.write(writeLine('a', ['hello'], y: 104));
      await wait(tester, 3000);
      expect(h.page.texts, isEmpty);
      expect(h.recognizer.calls, 0);

      h.controller.selectTool(EditorTool.pen);
      await wait(tester, 500);
      expect(h.page.texts, isEmpty);
      await wait(tester, 700);
      expect(texts(h), ['hello']);
    });

    testWidgets('going to the background leaves the waiting ink alone',
        (tester) async {
      final h = await ConvertHarness.open(tester,
          recognizer: reader(), autoConvert: true);
      await h.write(writeLine('a', ['hello'], y: 104));
      await wait(tester, 300);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(h.page.texts, isEmpty);
      expect(h.recognizer.calls, 0);

      // Writing again converts the new line only.
      await h.write(writeLine('b', ['hello'], y: 156));
      await wait(tester, 1100);
      expect(texts(h), ['second']);
      expect(h.page.strokes.every((s) => s.id.startsWith('aw0')), isTrue);
    });
  });

  group('spelling fixes', () {
    const capital = PolishSuggestion(
      original: 'hello',
      replacement: 'Hello',
      kind: PolishKind.capitalization,
      reason: 'Capital letter',
      start: 0,
      end: 5,
    );
    const secondCapital = PolishSuggestion(
      original: 'second',
      replacement: 'Second',
      kind: PolishKind.capitalization,
      reason: 'Capital letter',
      start: 0,
      end: 6,
    );

    /// Auto-convert on, "Fix spelling automatically" as [fix] says.
    Map<String, Object> prefs({required bool fix}) => {
          AppSettings.prefsKey:
              jsonEncode({'autoConvert': true, 'autocorrect': fix}),
        };

    FakeRecognizer suggesting() => reader()
      ..suggestions['aw0'] = [capital]
      ..suggestions['bw0'] = [secondCapital];

    testWidgets('with the setting off the typed text is what was read',
        (tester) async {
      final h = await ConvertHarness.open(tester,
          recognizer: suggesting(), prefsValues: prefs(fix: false));
      await h.write(writeLine('a', ['hello', 'online'], y: 104));
      await wait(tester, 1100);
      expect(texts(h), ['hello online'],
          reason: 'suggestions are never applied silently');
      expect(h.page.strokes, isEmpty);
    });

    testWidgets('with the setting on the fixes are typed too', (tester) async {
      final h = await ConvertHarness.open(tester,
          recognizer: suggesting(), prefsValues: prefs(fix: true));
      await h.write(writeLine('a', ['hello', 'online'], y: 104));
      await wait(tester, 1100);
      expect(texts(h), ['Hello online']);
      expect(h.page.strokes, isEmpty);
    });

    testWidgets('fixed words are remembered on the box, also when a line joins it',
        (tester) async {
      const fixA = PolishSuggestion(
          original: 'hello', replacement: 'hullo', kind: PolishKind.spelling, reason: 'Spelling', start: 0, end: 5);
      const fixB = PolishSuggestion(
          original: 'second', replacement: 'secant', kind: PolishKind.spelling, reason: 'Spelling', start: 0, end: 6);
      final h = await ConvertHarness.open(tester,
          recognizer: reader()
            ..suggestions['aw0'] = [fixA]
            ..suggestions['bw0'] = [fixB],
          prefsValues: prefs(fix: true));
      final first = writeLine('a', ['hello'], y: 104);
      await h.write(first);
      await wait(tester, 1100);
      final box = h.page.texts.single;
      expect(box.text, 'hullo');
      expect(box.corrections, [const TextCorrection(start: 0, original: 'hello', replacement: 'hullo')]);
      final typedEnd = box.x + const FlutterTextMetrics().naturalWidth(box);
      await h.write(writeLine('b', ['hello'], x: typedEnd + 12, y: 104));
      await wait(tester, 1100);
      final joined = h.page.texts.single;
      expect(joined.text, 'hullo secant');
      expect(joined.liveCorrections, [
        const TextCorrection(start: 0, original: 'hello', replacement: 'hullo'),
        const TextCorrection(start: 6, original: 'second', replacement: 'secant'),
      ]);
    });

    testWidgets('the setting is read again for every pass', (tester) async {
      final h = await ConvertHarness.open(tester,
          recognizer: suggesting(), prefsValues: prefs(fix: false));
      await h.write(writeLine('a', ['hello', 'online'], y: 104));
      await wait(tester, 1100);
      expect(texts(h), ['hello online']);

      h.container
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(autocorrect: true));
      await h.write(writeLine('b', ['hello'], y: 156));
      await wait(tester, 1100);
      expect(texts(h), ['hello online', 'Second']);
    });

    testWidgets('a fix never makes a doubtful line convert', (tester) async {
      final h = await ConvertHarness.open(tester,
          recognizer: suggesting()..readings['aw0'] = ('hello', 0.2),
          prefsValues: prefs(fix: true));
      await h.write(writeLine('a', ['hello'], y: 104));
      await wait(tester, 1100);
      expect(h.page.texts, isEmpty);
      expect(h.page.strokes, isNotEmpty);
    });
  });

  group('undo', () {
    testWidgets('puts the ink back, and it is not converted again',
        (tester) async {
      final h = await ConvertHarness.open(tester,
          recognizer: reader(), autoConvert: true);
      final a = writeLine('a', ['hello'], y: 104);
      await h.write(a);
      final before = List<Stroke>.of(h.page.strokes);
      await wait(tester, 1100);
      expect(texts(h), ['hello']);

      h.controller.undo();
      await tester.pump();
      expect(h.page.texts, isEmpty);
      expect(h.page.strokes.length, before.length);
      for (var i = 0; i < before.length; i++) {
        expect(identical(h.page.strokes[i], before[i]), isTrue);
      }
      await wait(tester, 5000);
      expect(h.page.texts, isEmpty);
      expect(h.recognizer.calls, 1);

      // A new line afterwards converts alone: the restored ink stays ink.
      await h.write(writeLine('b', ['hello'], y: 156));
      await wait(tester, 1100);
      expect(texts(h), ['second']);
      expect(h.recognizer.wordsRead, 2);
      expect({for (final s in h.page.strokes) s.id.split('-').first}, {'aw0'});

      // Redo of the first conversion still works as a plain redo.
      h.controller.undo();
      h.controller.undo();
      h.controller.redo();
      expect(h.page.texts, isEmpty, reason: 'redo of the pen strokes only');
    });
  });

  group('merging into the previous box', () {
    List<Stroke> firstWord = const [];

    Future<ConvertHarness> twoWords(WidgetTester tester,
        {double gap = 20, double y2 = 104}) async {
      final h = await ConvertHarness.open(tester,
          recognizer: reader(), autoConvert: true);
      final first = firstWord = writeLine('a', ['hello'], y: 104);
      await h.write(first);
      await wait(tester, 1100);
      expect(texts(h), ['hello']);
      final second = writeLine('b', ['hello'], x: rightOf(first) + gap, y: y2);
      await h.write(second);
      return h;
    }

    testWidgets('a word just after it on the same baseline is appended',
        (tester) async {
      final h = await twoWords(tester);
      final first = h.page.texts.single;
      final depth = h.undoDepth;
      await wait(tester, 1100);

      expect(texts(h), ['hello second']);
      final merged = h.page.texts.single;
      expect(merged.id, first.id);
      expect(merged.x, first.x);
      expect(merged.y, first.y);
      expect(merged.width, greaterThan(first.width));
      expect(merged.fontSize, first.fontSize);
      expect(h.page.strokes, isEmpty);
      expect(h.undoDepth, depth + 1, reason: 'one step for the whole pass');

      // Undo gives the second word's ink back and the old box.
      h.controller.undo();
      expect(texts(h), ['hello']);
      expect(h.page.strokes.every((s) => s.id.startsWith('bw0')), isTrue);
      expect(h.page.strokes, isNotEmpty);
      h.controller.redo();
      expect(texts(h), ['hello second']);
    });

    testWidgets('a word far away starts a box of its own', (tester) async {
      final h = await twoWords(tester, gap: 220);
      await wait(tester, 1100);
      expect(texts(h), ['hello', 'second']);
    });

    testWidgets('a word written just after the TYPED text joins the sentence',
        (tester) async {
      // The typed text is never as wide as the handwriting was; the writer
      // goes on where the text ends, not where the ink ended.
      final h = await ConvertHarness.open(tester,
          recognizer: reader(), autoConvert: true);
      final first = writeLine('a', ['hello'], y: 104);
      await h.write(first);
      await wait(tester, 1100);
      final box = h.page.texts.single;
      final typedEnd = box.x + const FlutterTextMetrics().naturalWidth(box);
      expect((typedEnd - rightOf(first)).abs(), greaterThan(25),
          reason: 'the test needs typed text of another width than the ink');
      await h.write(writeLine('b', ['hello'], x: typedEnd + 12, y: 104));
      await wait(tester, 1100);
      expect(texts(h), ['hello second']);
      expect(h.page.texts.single.id, box.id);
    });

    group('a sentence that runs on to the next line', () {
      // Five words reach the right edge of the page; the reading has no
      // full stop, so the sentence goes on below.
      FakeRecognizer longReader() => reader({
            'aw2': ('fire', 0.9),
            'aw3': ('when', 0.9),
            'aw4': ('they', 0.9),
            'aw5': ('reach', 0.9),
            'aw6': ('threshold', 0.9),
          });

      Future<ConvertHarness> twoLines(WidgetTester tester, {bool join = true}) async {
        final h = await ConvertHarness.open(tester,
            recognizer: longReader(),
            autoConvert: true,
            prefsValues: {
              ConvertStylePrefs.prefsKey: jsonEncode(ConvertStylePrefs(joinLines: join).toJson()),
            });
        final first = writeLine('a', ['hello', 'online', 'hello', 'online', 'hello', 'online', 'hello'], y: 104, gap: 20);
        expect(rightOf(first), greaterThan(595 * 0.8), reason: 'the test needs ink up to the edge');
        await h.write(first);
        await wait(tester, 1100);
        expect(texts(h), ['hello online fire when they reach threshold']);
        await h.write(writeLine('b', ['hello'], y: 130));
        await wait(tester, 1100);
        return h;
      }

      testWidgets('is joined to the text above, in one box', (tester) async {
        final h = await twoLines(tester);
        expect(texts(h), ['hello online fire when they reach threshold second']);
        expect(h.page.strokes, isEmpty);
        final box = h.page.texts.single;
        expect(box.fontSize, 16, reason: 'the even size on the default ruling');
        expect(box.x + box.width, lessThanOrEqualTo(595 - ConvertConfig.rightMargin + 1e-6));
        // One undo puts the second line's handwriting back, the box as it was.
        h.controller.undo();
        await tester.pump();
        expect(texts(h), ['hello online fire when they reach threshold']);
      });

      testWidgets('the Convert sheet joins them too, in one pass', (tester) async {
        final first = writeLine('a', ['hello', 'online', 'hello', 'online', 'hello', 'online', 'hello'], y: 104, gap: 20);
        final h = await ConvertHarness.open(tester,
            pages: [
              [...first, ...writeLine('b', ['hello'], y: 130)],
            ],
            recognizer: longReader(),
            prefsValues: {
              ConvertStylePrefs.prefsKey: jsonEncode(const ConvertStylePrefs().toJson()),
            });
        await h.tapConvert();
        await tester.tap(key('convert-apply'));
        await tester.pumpAndSettle();
        expect(texts(h), ['hello online fire when they reach threshold second']);
        expect(h.page.strokes, isEmpty, reason: 'the ink of both lines is replaced');
        await tester.pump(const Duration(seconds: 6));
      });

      testWidgets('with joining off it is a box of its own', (tester) async {
        final h = await twoLines(tester, join: false);
        expect(texts(h), ['hello online fire when they reach threshold', 'second']);
      });

      // Like the owner's page (v1.6.0): short lines, big writing two ruled
      // lines apart, written one after the other.
      Future<ConvertHarness> shortLines(WidgetTester tester, String first, String second) async {
        final h = await ConvertHarness.open(tester,
            recognizer: reader({'aw0': (first, 0.9), 'bw0': (second, 0.9)}),
            autoConvert: true,
            prefsValues: {
              ConvertStylePrefs.prefsKey: jsonEncode(const ConvertStylePrefs().toJson()),
            });
        await h.write(writeLine('a', ['hello'], y: 104));
        await wait(tester, 1100);
        await h.write(writeLine('b', ['hello'], y: 156));
        await wait(tester, 1100);
        return h;
      }

      testWidgets('a short line joins the box above when the words carry on', (tester) async {
        final h = await shortLines(tester, 'I am the danger. When', 'a man gets knocked');
        expect(texts(h), ['I am the danger. When a man gets knocked']);
      });

      testWidgets('notes written line after line stay lines (Mariam, 1.9.0)', (tester) async {
        // No full stops, lowercase starts: 1.9.0 joined each line to the one
        // above once a few were written.
        final notes = [
          ['Synapse', 'types'],
          ['chemical', 'synapses', 'use', 'transmitters'],
          ['electrical', 'ones', 'use', 'gap', 'junctions'],
          ['they', 'are', 'faster', 'than'],
          ['chemical', 'ones'],
          ['resting', 'potential', 'is', 'negative'],
        ];
        final h = await ConvertHarness.open(tester,
            recognizer: FakeRecognizer({
              for (final (i, words) in notes.indexed)
                for (final (k, w) in words.indexed) 'l${i}w$k': (w, 0.9),
            }),
            autoConvert: true,
            prefsValues: {
              ConvertStylePrefs.prefsKey: jsonEncode(const ConvertStylePrefs().toJson()),
            });
        for (final (i, words) in notes.indexed) {
          await h.write(writeLine('l$i', [for (final _ in words) 'hello'], y: 104.0 + 26 * i, gap: 20));
          await wait(tester, 1100);
        }
        expect(h.page.strokes, isEmpty);
        expect(texts(h), [
          'Synapse types',
          'chemical synapses use transmitters',
          'electrical ones use gap junctions',
          'they are faster than chemical ones',
          'resting potential is negative',
        ]);
      });

      testWidgets('a list written one word per line stays a list', (tester) async {
        final h = await shortLines(tester, 'brain', 'neurons');
        expect(texts(h), ['brain', 'neurons']);
      });
    });

    testWidgets('text appended on a line never covers the line below it', (tester) async {
      final h = await ConvertHarness.open(tester,
          recognizer: reader({
            'aw0': ('Small case', 0.9),
            'bw0': ('Okay this time', 0.9),
            'cw0': ('why is there no spacing we need to add more words here to wrap', 0.9),
          }),
          autoConvert: true,
          prefsValues: {
            ConvertStylePrefs.prefsKey: jsonEncode(const ConvertStylePrefs().toJson()),
          });
      final first = writeLine('a', ['hello'], y: 104);
      await h.write(first);
      await wait(tester, 1100);
      await h.write(writeLine('b', ['hello'], y: 130));
      await wait(tester, 1100);
      expect(texts(h), ['Small case', 'Okay this time']);
      // Goes on on the first line: joined there, the text would wrap onto
      // the second line, over "Okay this time".
      await h.write(writeLine('c', ['hello'], x: rightOf(first) + 16, y: 104));
      await wait(tester, 1100);
      final boxes = h.page.texts;
      for (var i = 0; i < boxes.length; i++) {
        for (var j = i + 1; j < boxes.length; j++) {
          final a = boxes[i], b = boxes[j];
          final overlap = Rect.fromLTWH(a.x, a.y, a.width, a.height)
              .deflate(0.5)
              .overlaps(Rect.fromLTWH(b.x, b.y, b.width, b.height).deflate(0.5));
          expect(overlap, isFalse, reason: '"${a.text}" and "${b.text}"');
        }
      }
      expect(boxes.map((t) => t.text), contains('Okay this time'));
      expect(h.page.strokes, isEmpty);
    });

    testWidgets('a word on another baseline starts a box of its own',
        (tester) async {
      // One ruled line lower (12 points lower is still the same ruled line).
      final h = await twoWords(tester, y2: 130);
      await wait(tester, 1100);
      expect(texts(h), ['hello', 'second']);
    });

    testWidgets('a box the user moved is left alone', (tester) async {
      final h = await twoWords(tester);
      final first = h.page.texts.single;
      h.controller.execute(PageItemsCommand(h.pageIdAt(0),
          label: 'Move text',
          textChanges: [(first, first.copyWith(x: first.x + 5))]));
      await wait(tester, 1100);
      expect(texts(h), ['hello', 'second']);
    });

    testWidgets('the box is still found after the user undoes a merge',
        (tester) async {
      final h = await twoWords(tester);
      await wait(tester, 1100);
      expect(texts(h), ['hello second']);
      h.controller.undo(); // the merge
      expect(texts(h), ['hello']);

      final third =
          writeLine('c', ['hello'], x: rightOf(firstWord) + 15, y: 104);
      await h.write(third);
      await wait(tester, 1100);
      expect(texts(h), ['hello third']);
    });
  });

  // v1.11.0: Mariam mostly uses Auto, whose lines were never kept, and
  // sharing them had to be one tap.
  group('writing samples', () {
    testWidgets('Auto keeps the lines it types, and the menu sends them with what they say now', (tester) async {
      final h = await ConvertHarness.open(tester, recognizer: reader(), autoConvert: true);
      final first = writeLine('a', ['hello'], y: 104);
      await h.write(first);
      await wait(tester, 1100);
      await h.write(writeLine('b', ['hello'], x: rightOf(first) + 20, y: 104));
      await wait(tester, 1100);
      expect(texts(h), ['hello second']);
      final box = h.page.texts.single;
      expect([for (final e in h.kept.lines) '${e['finalText']} ${e['source']} ${e['boxId'] == box.id} ${e['joinedBox']}'],
          ['hello auto true false', 'second auto true true']);
      expect(h.kept.lines.first['strokes'], isNotEmpty, reason: 'the pen data comes along');

      // She fixes the text by hand; the file says what it is now.
      h.controller.execute(PageItemsCommand(h.pageIdAt(0),
          label: 'Edit text', textChanges: [(box, box.copyWith(text: 'hello seconds'))]));
      await tester.tap(key('editor-menu'));
      await tester.pumpAndSettle();
      await tester.tap(key('menu-writing-samples'));
      await tester.pumpAndSettle();
      final json = jsonDecode(h.share.shared.single.json) as Map<String, dynamic>;
      final lines = (json['lines'] as List).cast<Map<String, dynamic>>();
      expect(lines.map((l) => l['boxTextNow']), ['hello seconds', 'hello seconds']);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('with "Keep my writing samples" off nothing is kept', (tester) async {
      final h = await ConvertHarness.open(tester, recognizer: reader(), autoConvert: true);
      h.container.read(settingsProvider.notifier).update((s) => s.copyWith(keepCorrections: false));
      await h.write(writeLine('a', ['hello'], y: 104));
      await wait(tester, 1100);
      expect(texts(h), ['hello']);
      expect(h.kept.lines, isEmpty);
    });
  });

  group('feedback', () {
    testWidgets('a small chip shows while it reads, and drawing is not blocked',
        (tester) async {
      final fake = reader()..gate = Completer<void>();
      final h = await ConvertHarness.open(tester,
          recognizer: fake, autoConvert: true);
      await h.write(writeLine('a', ['hello'], y: 104));
      await wait(tester, 1100);
      expect(fake.calls, 1);
      expect(find.text('Converting...'), findsOneWidget);
      expect(tester.widget<IgnorePointer>(find.ancestor(
              of: key('auto-convert-working'),
              matching: find.byType(IgnorePointer)).first).ignoring,
          isTrue);

      fake.gate!.complete();
      await wait(tester, 100);
      expect(find.text('Converting...'), findsNothing);
      expect(texts(h), ['hello']);
    });

    testWidgets('a kept line shows a chip that opens the review sheet',
        (tester) async {
      final h = await ConvertHarness.open(tester,
          recognizer: reader({'aw0': ('helo', 0.1)}), autoConvert: true);
      await h.write(writeLine('a', ['hello'], y: 104));
      await wait(tester, 1100);
      expect(h.page.texts, isEmpty);
      expect(key('auto-convert-kept'), findsOneWidget);
      expect(find.text('Not sure about 1 line: kept as handwriting'), findsOneWidget);

      await tester.tap(key('auto-convert-kept'));
      await wait(tester, 400);
      await wait(tester, 400);
      expect(key('convert-sheet'), findsOneWidget);
      expect(key('auto-convert-kept'), findsNothing);
    });

    testWidgets('the kept chip goes away by itself and counts each line once',
        (tester) async {
      final h = await ConvertHarness.open(tester,
          recognizer: reader({'aw0': ('helo', 0.1), 'bw0': ('seoond', 0.1)}),
          autoConvert: true);
      final a = writeLine('a', ['hello'], y: 104);
      await h.write(a);
      await wait(tester, 1100);
      expect(find.text('Not sure about 1 line: kept as handwriting'), findsOneWidget);
      await wait(tester, 6100);
      expect(key('auto-convert-kept'), findsNothing, reason: 'it must not sit over the page');

      // the same line again (more written on it), still unsure: still one line
      await h.write(writeLine('y', ['hello'], y: 104, x: rightOf(a) + 28));
      h.recognizer.readings['yw0'] = ('helo', 0.1);
      await wait(tester, 1100);
      expect(find.text('Not sure about 1 line: kept as handwriting'), findsNothing);
      // a second unsure line
      await h.write(writeLine('b', ['hello'], y: 156));
      await wait(tester, 1100);
      expect(find.text('Not sure about 2 lines: kept as handwriting'), findsOneWidget);
    });

    testWidgets('strokes written while it reads are not split off',
        (tester) async {
      final fake = reader()..gate = Completer<void>();
      final h = await ConvertHarness.open(tester,
          recognizer: fake, autoConvert: true);
      await h.write(writeLine('a', ['hello'], y: 104));
      await wait(tester, 1100);
      expect(fake.calls, 1);

      await h.write(writeLine('c', ['hello'], y: 208));
      fake.gate!.complete();
      await wait(tester, 100);
      expect(h.page.texts, isEmpty, reason: 'the pen moved on: reading dropped');
      expect(h.page.strokes, isNotEmpty);

      await wait(tester, 1100);
      expect(texts(h), ['hello', 'third']);
      expect(fake.calls, 2);
    });

    testWidgets('a failure shows one SnackBar, waits, and retries on the next stroke',
        (tester) async {
      final fake = reader()..error = const HtrException('model_missing', 'gone');
      final h = await ConvertHarness.open(tester,
          recognizer: fake, autoConvert: true);
      await h.write(writeLine('a', ['hello'], y: 104));
      await wait(tester, 1100);
      expect(find.textContaining('The handwriting model could not be loaded.'),
          findsOneWidget);
      expect(fake.calls, 1);
      expect(h.page.texts, isEmpty);
      expect(h.page.strokes, isNotEmpty);

      // It waits for the next stroke instead of trying again by itself.
      await wait(tester, 5000);
      expect(fake.calls, 1);

      // The same failure again is not announced again.
      await h.write(writeLine('b', ['hello'], y: 156));
      await wait(tester, 1100);
      expect(fake.calls, 2);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      // The first message is gone and no second one was queued behind it.
      expect(find.byType(SnackBar), findsNothing);

      // Once the model works, everything that waited is converted.
      fake.error = null;
      await h.write(writeLine('c', ['hello'], y: 208));
      await wait(tester, 1100);
      expect(texts(h), ['hello', 'second', 'third']);
    });

    testWidgets('a recogniser that never answers is given up on', (tester) async {
      final fake = reader()..gate = Completer<void>(); // never completed
      final h = await ConvertHarness.open(tester,
          recognizer: fake, autoConvert: true);
      await h.write(writeLine('a', ['hello'], y: 104));
      await wait(tester, 1100);
      expect(find.text('Converting...'), findsOneWidget);
      await tester.pump(const Duration(minutes: 2, seconds: 1));
      expect(find.text('Converting...'), findsNothing);
      expect(find.textContaining('Reading the handwriting failed.'),
          findsOneWidget);
      expect(h.page.strokes, isNotEmpty);

      // The next stroke tries again.
      fake.gate = null;
      await h.write(writeLine('b', ['hello'], y: 156));
      await wait(tester, 1100);
      expect(texts(h), ['hello', 'second']);
    });

    testWidgets('an unexpected error also ends in a message, never a crash',
        (tester) async {
      final fake = reader()..error = StateError('boom');
      final h = await ConvertHarness.open(tester,
          recognizer: fake, autoConvert: true);
      await h.write(writeLine('a', ['hello'], y: 104));
      await wait(tester, 1100);
      expect(find.textContaining('Reading the handwriting failed.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(h.page.strokes, isNotEmpty);
    });
  });

  group('the toggle', () {
    Future<ConvertHarness> open(WidgetTester tester, Size size,
            {Map<String, Object> prefs = const {}}) =>
        ConvertHarness.open(tester,
            recognizer: reader(), size: size, prefsValues: prefs);

    testWidgets('wide: an "Auto" button next to Convert, highlighted when on',
        (tester) async {
      final h = await open(tester, const Size(1000, 1400));
      expect(key('auto-convert-toggle'), findsOneWidget);
      expect(find.text('Auto'), findsOneWidget);
      expect(find.byTooltip('Auto-convert handwriting to text'), findsOneWidget);
      expect(find.text('Roboto'), findsNothing, reason: 'font only shows when on');
      final convert = tester.getCenter(key('convert-to-text'));
      final auto = tester.getCenter(key('auto-convert-toggle'));
      expect(auto.dx, greaterThan(convert.dx));
      expect(auto.dy, closeTo(convert.dy, 1));

      Color? background() => tester
          .widget<TextButton>(key('auto-convert-toggle'))
          .style
          ?.backgroundColor
          ?.resolve({});
      expect(background(), isNull);
      await tester.tap(key('auto-convert-toggle'));
      await tester.pump();
      expect(h.container.read(settingsProvider).autoConvert, isTrue);
      expect(background(), isNotNull);
      expect(tester.widget<Text>(key('auto-convert-font')).data, 'Roboto');

      await tester.tap(key('auto-convert-toggle'));
      await tester.pump();
      expect(h.container.read(settingsProvider).autoConvert, isFalse);
      expect(background(), isNull);
    });

    testWidgets('the font in use is shown when it is on', (tester) async {
      await open(tester, const Size(1000, 1400), prefs: {
        AppSettings.prefsKey: jsonEncode({'autoConvert': true}),
        ConvertStylePrefs.prefsKey:
            jsonEncode(const ConvertStylePrefs(fontId: 'lora').toJson()),
      });
      expect(tester.widget<Text>(key('auto-convert-font')).data,
          FontKind.lora.label);
    });

    for (final size in const [Size(700, 1200), Size(420, 800), Size(360, 640)]) {
      testWidgets('narrow (${size.width.toInt()} wide): an icon button, no overflow',
          (tester) async {
        final h = await open(tester, size);
        expect(key('auto-convert-toggle'), findsOneWidget);
        expect(find.text('Auto'), findsNothing);
        expect(find.byTooltip('Auto-convert handwriting to text'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(tester.widget<IconButton>(key('auto-convert-toggle')).isSelected,
            isFalse);

        await tester.tap(key('auto-convert-toggle'));
        await tester.pump();
        expect(h.container.read(settingsProvider).autoConvert, isTrue);
        expect(tester.widget<IconButton>(key('auto-convert-toggle')).isSelected,
            isTrue);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('phone width: Pages and Add page move into the menu',
        (tester) async {
      final h = await open(tester, const Size(360, 640));
      expect(key('add-page'), findsNothing);
      expect(key('page-indicator'), findsNothing);
      expect(key('undo'), findsOneWidget);
      expect(key('convert-to-text'), findsOneWidget);
      await tester.tap(key('editor-menu'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(key('menu-add-page'), findsOneWidget);
      await tester.tap(key('menu-add-page'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(h.controller.pageCount, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a mid-size screen keeps the buttons and the page count',
        (tester) async {
      await open(tester, const Size(450, 800));
      expect(key('add-page'), findsNothing);
      expect(key('page-indicator'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tablet keeps every button', (tester) async {
      await open(tester, const Size(700, 1200));
      expect(key('add-page'), findsOneWidget);
      expect(key('page-indicator'), findsOneWidget);
      expect(key('auto-convert-toggle'), findsOneWidget);
    });

    testWidgets('switching it on with the toggle converts what is written next',
        (tester) async {
      final h = await open(tester, const Size(700, 1200));
      await tester.tap(key('auto-convert-toggle'));
      await tester.pump();
      await h.write(writeLine('a', ['hello'], y: 104));
      await wait(tester, 1100);
      expect(texts(h), ['hello']);
    });

    testWidgets('read-only pages keep the toggle (the setting is global)',
        (tester) async {
      await ConvertHarness.open(tester,
          pages: [const []], unreadablePages: {0}, recognizer: reader());
      expect(key('auto-convert-toggle'), findsOneWidget);
    });
  });

  group('the remembered look', () {
    testWidgets('auto-convert types in it', (tester) async {
      final h = await ConvertHarness.open(tester,
          recognizer: reader(),
          autoConvert: true,
          prefsValues: {
            ConvertStylePrefs.prefsKey: jsonEncode(const ConvertStylePrefs(
                    fontId: 'lora',
                    bold: true,
                    italic: true,
                    fixedSize: 20,
                    colorOverride: 0xFF1A237E)
                .toJson()),
          });
      await h.write(writeLine('a', ['hello'], y: 104));
      await wait(tester, 1100);
      final t = h.page.texts.single;
      expect(t.font, FontKind.lora);
      expect(t.bold, isTrue);
      expect(t.italic, isTrue);
      expect(t.fontSize, lessThanOrEqualTo(20));
      expect(t.color, 0xFF1A237E);
    });

    testWidgets('by default: Roboto, auto size, the ink colour', (tester) async {
      final h = await ConvertHarness.open(tester,
          recognizer: reader(), autoConvert: true);
      await h.write(
          writeLine('a', ['hello'], y: 104, color: 0xFF880E4F));
      await wait(tester, 1100);
      final t = h.page.texts.single;
      expect(t.font, FontKind.sans);
      expect(t.bold, isFalse);
      expect(t.color, 0xFF880E4F);
    });

    testWidgets('the manual sheet saves what the user chose, auto uses it',
        (tester) async {
      final h = await ConvertHarness.open(tester,
          pages: [writeLine('a', ['hello'], y: 104)],
          recognizer: reader(),
          autoConvert: true);
      await h.tapConvert();
      await tester.tap(key('convert-font'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(key('text-font-lora'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(key('convert-bold'));
      await tester.pump();
      await tester.tap(key('convert-colour-ff1a237e'));
      await tester.pump();
      await tester.tap(key('convert-apply'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final saved = h.container.read(convertStylePrefsProvider);
      expect(saved.fontId, 'lora');
      expect(saved.bold, isTrue);
      expect(saved.colorOverride, 0xFF1A237E);
      expect(saved.sizeMode, ConvertSizeMode.even);
      final stored = jsonDecode(h.container
          .read(sharedPreferencesProvider)
          .getString(ConvertStylePrefs.prefsKey)!) as Map<String, dynamic>;
      expect(stored['font'], 'lora');
      expect(stored['sizeMode'], 'even');
      await tester.pump(const Duration(seconds: 6));

      // The toggle names that font, and a later auto pass types in it.
      expect(tester.widget<Text>(key('auto-convert-font')).data, 'Lora');
      await h.write(writeLine('b', ['hello'], y: 156));
      await wait(tester, 1100);
      final auto = h.page.texts.firstWhere((t) => t.text == 'second');
      expect(auto.font, FontKind.lora);
      expect(auto.bold, isTrue);
    });

    testWidgets('the manual sheet starts from the remembered look',
        (tester) async {
      final h = await ConvertHarness.open(tester,
          pages: [writeLine('a', ['hello'], y: 104)],
          recognizer: reader(),
          prefsValues: {
            ConvertStylePrefs.prefsKey: jsonEncode(const ConvertStylePrefs(
                    fontId: 'lora', bold: true, sizeMode: ConvertSizeMode.custom, fixedSize: 18)
                .toJson()),
          });
      await h.tapConvert();
      expect(tester.widget<Text>(key('convert-font-label')).data, 'Lora');
      expect(tester.widget<FilterChip>(key('convert-bold')).selected, isTrue);
      expect(tester.widget<Text>(key('convert-size-label')).data, '18 pt');
    });

    testWidgets('closing the sheet without converting remembers nothing',
        (tester) async {
      final h = await ConvertHarness.open(tester,
          pages: [writeLine('a', ['hello'], y: 104)], recognizer: reader());
      await h.tapConvert();
      await tester.tap(key('convert-bold'));
      await tester.pump();
      await tester.tap(key('convert-close'));
      await tester.pump(const Duration(milliseconds: 400));
      // As the harness set it up (joining off), nothing else.
      expect(h.container.read(convertStylePrefsProvider),
          const ConvertStylePrefs(joinLines: false));
    });
  });

  group('late dots', () {
    // A dot (or short bar) written after auto-convert typed its word.
    Stroke dot(String id, double x, double y, {double w = 2, double h = 2}) => Stroke(
          id: id,
          tool: StrokeTool.pen,
          color: 0xFF1E1E1E,
          size: 2,
          raw: [InkPoint(x, y, 0.5, 0), InkPoint(x + w, y + h, 0.5, 30)],
        );

    Future<(ConvertHarness, List<Stroke>)> typed(WidgetTester tester) async {
      final h = await ConvertHarness.open(tester, recognizer: reader(), autoConvert: true);
      final word = writeLine('a', ['hello'], y: 104);
      await h.write(word);
      await wait(tester, 1100);
      expect(texts(h), ['hello']);
      return (h, word);
    }

    testWidgets('a full stop after the word is typed with it', (tester) async {
      final (h, word) = await typed(tester);
      await h.write([dot('p', rightOf(word) + 4, 102)]);
      await wait(tester, 1100);
      expect(texts(h), ['hello.']);
      expect(h.page.strokes, isEmpty);
      // One undo brings the dot back and the text as it was.
      h.controller.undo();
      await tester.pump();
      expect(texts(h), ['hello']);
      expect(h.page.strokes.single.id, 'p');
    });

    testWidgets('an i-dot or t-bar over the word just goes with it', (tester) async {
      final (h, word) = await typed(tester);
      final left = word.map((s) => s.bounds.left).reduce((a, b) => a < b ? a : b);
      await h.write([dot('i', left + 15, 78), dot('t', left + 30, 88, w: 9, h: 1)]);
      await wait(tester, 1100);
      expect(texts(h), ['hello']);
      expect(h.page.strokes, isEmpty);
      expect(find.byKey(const ValueKey('auto-convert-kept')), findsNothing);
    });

    testWidgets('a dot away from any text stays ink', (tester) async {
      final (h, _) = await typed(tester);
      await h.write([dot('far', 420, 400)]);
      await wait(tester, 1100);
      expect(texts(h), ['hello']);
      expect(h.page.strokes.single.id, 'far');
    });
  });
}
