import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/features/editor/integrations/convert/convert_config.dart';
import 'package:neatink/features/editor/integrations/convert/convert_plan.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/recognition/htr_channel.dart';
import 'package:neatink/recognition/text_polish.dart';

import 'harness.dart';

PageStrokes page(String id, List<Stroke> strokes, {int index = 0}) =>
    PageStrokes(pageId: id, pageIndex: index, strokes: strokes);

/// "Nuerons" is a spelling slip at the start of "Nuerons fire".
const nuerons = PolishSuggestion(
  original: 'Nuerons',
  replacement: 'Neurons',
  kind: PolishKind.spelling,
  reason: 'Spelling',
  start: 0,
  end: 7,
);

void main() {
  test('strokes become lines, each read as a whole', () async {
    final fake = FakeRecognizer({
      'l1w0': ('hello', 0.9),
      'l1w1': ('online', 0.8),
      'l2w0': ('hello', 0.7),
    });
    final plans = await recognizePages([
      page('p', [
        ...writeLine('l2', ['hello'], y: 160),
        ...writeLine('l1', ['hello', 'online'], y: 100),
      ]),
    ], fake);
    final lines = plans.single.lines;
    expect(lines, hasLength(2));
    expect(lines[0].text, 'hello online');
    expect(lines[1].text, 'hello');
    expect(lines[0].recognizedText, 'hello online');
    expect(lines[0].words, hasLength(2));
    // The line is as sure as its least sure word (not their average).
    expect(lines[0].confidence, closeTo(0.8, 1e-9));
    expect(lines[1].confidence, closeTo(0.7, 1e-9));
    expect(lines[0].strokeIds.every((id) => id.startsWith('l1w')), isTrue);
    expect(lines[1].strokeIds.every((id) => id.startsWith('l2w')), isTrue);
    // "online" has a dotted i: every pen stroke, the dot too, belongs to a line.
    expect(lines[0].strokeIds.length + lines[1].strokeIds.length, 5 + 7 + 5);
    expect(lines.map((l) => l.pageId), everyElement('p'));
    expect(lines[0].id, isNot(lines[1].id));
    expect(fake.calls, 1);
    expect(fake.wordsRead, 3);
  });

  test('every stroke of a line is in its strokeIds, whatever the words are', () async {
    final strokes = writeLine('l1', ['hello', 'online'], y: 100);
    final fake = FakeRecognizer({'l1w0': ('hello', 0.9), 'l1w1': ('online', 0.9)});
    final plans = await recognizePages([page('p', strokes)], fake);
    final line = plans.single.lines.single;
    expect(line.strokeIds, {for (final s in strokes) s.id});
    expect(line.line.inkStrokes.map((s) => s.id), strokes.map((s) => s.id),
        reason: 'in the order they were written');
  });

  test('confident lines start ticked, doubtful ones start unticked', () async {
    final fake = FakeRecognizer({
      'a': ('', 0),
      'l1w0': ('hello', 0.9),
      'l2w0': ('hxllo', ConvertConfig.lowConfidenceThreshold - 0.01),
      'l3w0': ('hello', ConvertConfig.lowConfidenceThreshold),
    });
    final plans = await recognizePages([
      page('p', [
        ...writeLine('l1', ['hello'], y: 100),
        ...writeLine('l2', ['hello'], y: 160),
        ...writeLine('l3', ['hello'], y: 220),
      ]),
    ], fake);
    final lines = plans.single.lines;
    expect(lines[0].lowConfidence, isFalse);
    expect(lines[0].include, isTrue);
    expect(lines[1].lowConfidence, isTrue);
    expect(lines[1].include, isFalse);
    expect(lines[1].willConvert, isFalse);
    // Exactly at the threshold is good enough.
    expect(lines[2].lowConfidence, isFalse);
    expect(lines[2].include, isTrue);
  });

  test('one doubtful word makes the whole line doubtful', () async {
    final fake = FakeRecognizer({
      'l1w0': ('hello', 0.99),
      'l1w1': ('onlxne', 0.1),
    });
    final line = (await recognizePages([
      page('p', writeLine('l1', ['hello', 'online'], y: 100)),
    ], fake))
        .single
        .lines
        .single;
    expect(line.confidence, closeTo(0.1, 1e-9));
    expect(line.lowConfidence, isTrue);
    expect(line.include, isFalse);
  });

  test('a line with an unreadable word starts unticked', () async {
    final fake = FakeRecognizer({
      'l1w0': ('hello', 0.99),
      'l1w1': ('', 0.99),
    });
    final plans = await recognizePages([
      page('p', writeLine('l1', ['hello', 'online'], y: 100)),
    ], fake);
    final line = plans.single.lines.single;
    expect(line.text, 'hello');
    expect(line.lowConfidence, isTrue);
    expect(line.include, isFalse);
    expect(line.strokeIds, hasLength(12)); // the unreadable word's ink is counted
  });

  test('a line the recogniser could not read at all, or is not sure of, is doubtful', () {
    final nothing = plannedLineOf([('', 0.9)]);
    expect(nothing.text, isEmpty);
    expect(nothing.lowConfidence, isTrue);
    expect(nothing.willConvert, isFalse);
    // Not a number counts as not sure at all.
    final unknown = plannedLineOf([('hello', double.nan)]);
    expect(unknown.confidence, 0);
    expect(unknown.lowConfidence, isTrue);
    // A confidence outside 0..1 is clamped.
    expect(plannedLineOf([('hello', 1.7)]).confidence, 1);
    expect(plannedLineOf([('hello', 0.9)], confidence: -0.5).confidence, 0);
  });

  test('the text can be corrected and a line ticked afterwards', () async {
    final fake = FakeRecognizer({'l1w0': ('hxllo', 0.1)});
    final line = (await recognizePages([
      page('p', writeLine('l1', ['hello'], y: 100)),
    ], fake))
        .single
        .lines
        .single;
    expect(line.willConvert, isFalse);
    line
      ..text = 'hello'
      ..include = true;
    expect(line.willConvert, isTrue);
    expect(line.recognizedText, 'hxllo', reason: 'what was read is kept');
    line.text = '   ';
    expect(line.willConvert, isFalse);
  });

  test('highlighter strokes and shapes are not part of any line', () async {
    final hl = Stroke(
      id: 'hl',
      tool: StrokeTool.highlighter,
      color: 0xFFFFFF00,
      size: 12,
      raw: [for (var x = 90.0; x < 160; x += 2) InkPoint(x, 98, 0.5, 0)],
    );
    final fake = FakeRecognizer({'l1w0': ('hello', 0.9)});
    final plans = await recognizePages([
      page('p', [...writeLine('l1', ['hello'], y: 100), hl]),
    ], fake);
    expect(plans.single.lines.single.strokeIds, isNot(contains('hl')));
  });

  test('the line colour is the one most of its ink has', () async {
    final strokes = [
      ...writeLine('l1', ['hello'], y: 100, color: 0xFF0D47A1),
    ];
    final fake = FakeRecognizer({'l1w0': ('hello', 0.9)});
    final plans = await recognizePages([page('p', strokes)], fake);
    expect(plans.single.lines.single.dominantColor, 0xFF0D47A1);
    expect(dominantColorOf(const []), 0xFF1E1E1E);
    final a = writeLine('a', ['hello'], y: 100, color: 0xFF111111);
    final b = writeLine('b', ['hello'], y: 100, color: 0xFF222222).take(1);
    expect(dominantColorOf([...a, ...b]), 0xFF111111);
  });

  test('several pages are read in page order, with one progress over all lines',
      () async {
    final fake = FakeRecognizer({
      'l1w0': ('first', 0.9),
      'm1w0': ('second', 0.9),
    });
    final progress = <(int, int)>[];
    final plans = await recognizePages([
      page('p1', writeLine('l1', ['hello'], y: 100), index: 0),
      page('p2', writeLine('m1', ['hello'], y: 100), index: 1),
      page('p3', const [], index: 2),
    ], fake, onProgress: (d, t) => progress.add((d, t)));
    expect([for (final p in plans) p.pageId], ['p1', 'p2', 'p3']);
    expect(plans[0].lines.single.text, 'first');
    expect(plans[1].lines.single.text, 'second');
    expect(plans[2].isEmpty, isTrue);
    expect(plans[1].pageIndex, 1);
    expect(progress.first, (0, 2));
    expect(progress.last, (2, 2));
    expect(progress.every((p) => p.$2 == 2), isTrue);
    // The pages are read one after the other; the empty one costs nothing.
    expect(fake.calls, 2);
  });

  group('chunks', () {
    final n = ConvertConfig.chunkLines + 6;
    final chunks = (n / ConvertConfig.chunkLines).ceil();

    List<Stroke> manyLines() => [
          for (var i = 0; i < n; i++)
            ...writeLine('l$i', ['hello'], y: 100.0 + 40 * i),
        ];

    test('big pages are read a few lines at a time, with progress between them',
        () async {
      final fake = FakeRecognizer({
        for (var i = 0; i < n; i++) 'l${i}w0': ('w$i', 0.9),
      });
      final progress = <int>[];
      final plans = await recognizePages([page('p', manyLines())], fake,
          onProgress: (d, t) => progress.add(d));
      expect(plans.single.lines.map((l) => l.text),
          [for (var i = 0; i < n; i++) 'w$i']);
      expect(plans.single.lines.map((l) => l.id).toSet(), hasLength(n));
      expect(fake.calls, chunks);
      expect(chunks, greaterThan(1));
      expect(progress, contains(ConvertConfig.chunkLines));
      expect(progress.last, n);
      // Progress never goes back.
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
      }
    });

    test('each chunk is told the text of the line above it', () async {
      final fake = FakeRecognizer({
        for (var i = 0; i < n; i++) 'l${i}w0': ('w$i', 0.9),
        'm0w0': ('new page', 0.9),
      });
      await recognizePages([
        page('p', manyLines()),
        page('q', writeLine('m0', ['hello'], y: 100), index: 1),
      ], fake);
      expect(fake.previousTexts, [
        null, // the first line of a page starts a sentence
        'w${ConvertConfig.chunkLines - 1}',
        'w${2 * ConvertConfig.chunkLines - 1}',
        null, // ... and so does the first line of the next page
      ]);
    });

    test('the first line is told the typed text that comes before it', () async {
      // Auto-convert reads only new writing: the box above decides whether it
      // starts a sentence (so "test my app" is not given a capital).
      final fake = FakeRecognizer({'l0w0': ('test', 0.9)});
      await recognizePages([
        PageStrokes(
          pageId: 'p',
          pageIndex: 0,
          strokes: writeLine('l0', ['hello'], y: 200),
          texts: const [
            TextItem(id: 'a', x: 60, y: 100, width: 300, height: 40, text: 'I wrote this so I can'),
            TextItem(id: 'b', x: 60, y: 400, width: 300, height: 20, text: 'Later.'),
          ],
        ),
      ], fake);
      expect(fake.previousTexts, ['I wrote this so I can']);
    });

    test('a line that read as nothing is not the line above', () async {
      final last = ConvertConfig.chunkLines - 1;
      final fake = FakeRecognizer({
        for (var i = 0; i < n; i++) 'l${i}w0': ('w$i', 0.9),
        'l${last}w0': ('', 0.9),
      });
      await recognizePages([page('p', manyLines())], fake);
      expect(fake.previousTexts[1], 'w${last - 1}');
    });

    test('cancelling stops between chunks', () async {
      final fake = FakeRecognizer(const {});
      final token = ConvertCancelToken();
      final future = recognizePages([page('p', manyLines())], fake,
          cancel: token, onProgress: (d, t) {
        if (d >= ConvertConfig.chunkLines) token.cancel();
      });
      await expectLater(future, throwsA(isA<ConvertCancelled>()));
      expect(fake.calls, 1);
    });

    test('cancelling before the start reads nothing', () async {
      final fake = FakeRecognizer(const {});
      final token = ConvertCancelToken()..cancel();
      await expectLater(
        recognizePages([page('p', manyLines())], fake, cancel: token),
        throwsA(isA<ConvertCancelled>()),
      );
      expect(fake.calls, 0);
    });
  });

  test('recogniser failures reach the caller', () async {
    final fake = FakeRecognizer(const {})
      ..error = const HtrException('model_missing', 'gone');
    await expectLater(
      recognizePages([page('p', writeLine('l1', ['hello'], y: 100))], fake),
      throwsA(isA<HtrException>()),
    );
  });

  test('a page without pen strokes costs no recognition', () async {
    final fake = FakeRecognizer(const {});
    final plans = await recognizePages([page('p', const [])], fake);
    expect(plans.single.isEmpty, isTrue);
    expect(fake.calls, 0);
  });

  group('spelling and grammar fixes', () {
    Future<PlannedLine> read({required bool autoFix}) async {
      final fake = FakeRecognizer({
        'l1w0': ('Nuerons', 0.9),
        'l1w1': ('fire', 0.9),
      })
        ..suggestions['l1w0'] = [nuerons];
      final plans = await recognizePages([
        page('p', writeLine('l1', ['hello', 'online'], y: 100)),
      ], fake, autoFix: autoFix);
      return plans.single.lines.single;
    }

    test('by default they are only offered: the text is what was read', () async {
      final line = await read(autoFix: false);
      expect(line.text, 'Nuerons fire');
      expect(line.recognizedText, 'Nuerons fire');
      expect(line.suggestions, [nuerons]);
      expect(line.autoApplied, isEmpty);
      expect(line.accepted, isEmpty);
      expect(line.polishedText, 'Nuerons fire');
    });

    test('with auto-fix they are in the text and can be taken back', () async {
      final line = await read(autoFix: true);
      expect(line.text, 'Neurons fire');
      expect(line.recognizedText, 'Nuerons fire', reason: 'what was read is kept');
      expect(line.suggestions, isEmpty);
      expect(line.autoApplied, [nuerons]);
      expect(line.polishedText, 'Neurons fire');

      expect(line.revertAutoFix(nuerons), isTrue);
      expect(line.text, 'Nuerons fire');
      expect(line.autoApplied, isEmpty);
      expect(line.suggestions, [nuerons]);
      expect(line.polishedText, 'Nuerons fire');
    });

    test('accepting an offered fix changes the text and remembers it', () async {
      final line = await read(autoFix: false);
      expect(line.acceptSuggestion(nuerons), isTrue);
      expect(line.text, 'Neurons fire');
      expect(line.suggestions, isEmpty);
      expect(line.accepted, [nuerons]);
      // Taking the fix is not a correction of the recogniser.
      expect(line.polishedText, 'Neurons fire');
      expect(line.recognizedText, 'Nuerons fire');
      // It cannot be taken twice.
      expect(line.acceptSuggestion(nuerons), isFalse);
      expect(line.text, 'Neurons fire');
      // And it can be taken back.
      expect(line.revertAutoFix(nuerons), isTrue);
      expect(line.text, 'Nuerons fire');
      expect(line.accepted, isEmpty);
      expect(line.suggestions, [nuerons]);
    });

    test('a fix for a word the user has since rewritten changes nothing', () async {
      final line = await read(autoFix: false);
      line.text = 'Brains fire';
      expect(line.acceptSuggestion(nuerons), isFalse);
      expect(line.text, 'Brains fire');
      expect(line.suggestions, [nuerons]);
      expect(line.accepted, isEmpty);
    });

    test('a fix inside a longer word is not applied', () async {
      final line = await read(autoFix: false);
      line.text = 'Nuerons1 fire';
      expect(line.acceptSuggestion(nuerons), isFalse);
      expect(line.text, 'Nuerons1 fire');
    });

    test('two fixes keep their places after one is applied', () async {
      const fire = PolishSuggestion(
        original: 'fire',
        replacement: 'fires',
        kind: PolishKind.grammar,
        reason: 'Grammar',
        start: 8,
        end: 12,
      );
      final fake = FakeRecognizer({
        'l1w0': ('Nuerons', 0.9),
        'l1w1': ('fire', 0.9),
      })
        ..suggestions['l1w0'] = [nuerons, fire];
      final line = (await recognizePages([
        page('p', writeLine('l1', ['hello', 'online'], y: 100)),
      ], fake))
          .single
          .lines
          .single;
      expect(line.acceptSuggestion(fire), isTrue);
      expect(line.acceptSuggestion(nuerons), isTrue);
      expect(line.text, 'Neurons fires');
      expect(line.polishedText, 'Neurons fires');
    });

    test('fixes never change which lines are ticked or which strokes belong to them',
        () async {
      final off = await read(autoFix: false);
      final on = await read(autoFix: true);
      expect(on.include, off.include);
      expect(on.lowConfidence, off.lowConfidence);
      expect(on.strokeIds, off.strokeIds);
      expect(on.confidence, off.confidence);
    });
  });

  group('textBeforeLine', () {
    const above = TextItem(id: 'a', x: 60, y: 100, width: 300, height: 40, text: 'Above');
    const higher = TextItem(id: 'h', x: 60, y: 40, width: 300, height: 20, text: 'Higher.');
    const below = TextItem(id: 'b', x: 60, y: 300, width: 300, height: 20, text: 'Below.');
    const beside = TextItem(id: 's', x: 60, y: 185, width: 100, height: 20, text: 'Beside');

    String? before(List<TextItem> texts, {double left = 60}) =>
        textBeforeLine(texts, left: left, baselineY: 200, xHeight: 8);

    test('the nearest box above', () {
      expect(before([higher, above, below]), 'Above');
    });

    test('a box on the same line to the left comes after the ones above', () {
      expect(before([above, beside], left: 200), 'Beside');
      // ... but not when the writing starts left of its end.
      expect(before([above, beside], left: 100), 'Above');
    });

    test('nothing before the line', () {
      expect(before([below]), isNull);
      expect(before(const []), isNull);
    });
  });
}
