import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/integrations/convert/convert_config.dart';
import 'package:neatink/features/editor/integrations/convert/convert_plan.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/recognition/htr_channel.dart';

import 'harness.dart';

PageStrokes page(String id, List<Stroke> strokes, {int index = 0}) =>
    PageStrokes(pageId: id, pageIndex: index, strokes: strokes);

void main() {
  test('strokes become lines and words, read word by word', () async {
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
    expect(lines[0].words, hasLength(2));
    expect(lines[0].confidence, closeTo(0.85, 1e-9));
    expect(lines[0].strokeIds.every((id) => id.startsWith('l1w')), isTrue);
    expect(lines[1].strokeIds.every((id) => id.startsWith('l2w')), isTrue);
    expect(lines[0].strokeIds.length + lines[1].strokeIds.length, 5 + 7 + 5);
    expect(lines.map((l) => l.pageId), everyElement('p'));
    expect(lines[0].id, isNot(lines[1].id));
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

  test('several pages are read together, in page order', () async {
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
    expect(fake.calls, 1);
  });

  test('big pages are read in chunks, with progress between them', () async {
    final n = ConvertConfig.chunkWords + 6;
    final strokes = [
      for (var i = 0; i < n; i++) ...writeLine('l$i', ['hello'], y: 100.0 + 40 * i),
    ];
    final fake = FakeRecognizer({
      for (var i = 0; i < n; i++) 'l${i}w0': ('w$i', 0.9),
    });
    final progress = <int>[];
    final plans = await recognizePages([page('p', strokes)], fake,
        onProgress: (d, t) => progress.add(d));
    expect(plans.single.lines.map((l) => l.text),
        [for (var i = 0; i < n; i++) 'w$i']);
    expect(fake.calls, 2);
    expect(progress, contains(ConvertConfig.chunkWords));
    expect(progress.last, n);
  });

  test('cancelling stops between chunks', () async {
    final n = ConvertConfig.chunkWords + 6;
    final strokes = [
      for (var i = 0; i < n; i++) ...writeLine('l$i', ['hello'], y: 100.0 + 40 * i),
    ];
    final fake = FakeRecognizer(const {});
    final token = ConvertCancelToken();
    final future = recognizePages([page('p', strokes)], fake,
        cancel: token, onProgress: (d, t) {
      if (d >= ConvertConfig.chunkWords) token.cancel();
    });
    await expectLater(future, throwsA(isA<ConvertCancelled>()));
    expect(fake.calls, 1);
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
}
