import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/font_kind.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/features/editor/integrations/convert/convert_apply.dart';
import 'package:neatink/features/editor/integrations/convert/convert_session.dart';
import 'package:neatink/features/editor/tools/selection.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/recognition/htr_channel.dart';
import 'package:neatink/render/text_style.dart';

import 'harness.dart';

FakeRecognizer reader([Map<String, (String, double)> extra = const {}]) =>
    FakeRecognizer({
      'aw0': ('first line', 0.9),
      'aw1': ('here', 0.9),
      'bw0': ('second', 0.9),
      'cw0': ('third', 0.9),
      ...extra,
    });

Future<ConvertSession> startSession(ConvertHarness h, {Selection? selection}) async {
  final s = ConvertSession(
      controller: h.controller, recognizer: h.recognizer, selection: selection);
  addTearDown(s.cancel);
  await s.start();
  return s;
}

void main() {
  late List<Stroke> ink;

  setUp(() {
    ink = [
      ...writeLine('a', ['hello', 'online'], y: 104),
      ...writeLine('b', ['hello'], y: 156),
      ...writeLine('c', ['hello'], y: 208),
    ];
  });

  testWidgets('one undo puts every stroke back exactly; redo converts again',
      (tester) async {
    final h = await ConvertHarness.open(tester, pages: [ink], recognizer: reader());
    final before = List<Stroke>.of(h.page.strokes);
    final s = await startSession(h);
    expect(s.phase, ConvertPhase.review);
    expect(s.includedCount, 3);
    final undoBefore = h.undoDepth;

    final outcome = s.apply()!;
    expect(outcome.lines, 3);
    expect(outcome.pages, 1);
    expect(h.undoDepth, undoBefore + 1);
    expect(h.controller.undoLabel, 'Convert to text');
    expect(h.page.strokes, isEmpty);
    expect([for (final t in h.page.texts) t.text],
        ['first line here', 'second', 'third']);

    h.controller.undo();
    expect(h.page.texts, isEmpty);
    expect(h.page.strokes.length, before.length);
    for (var i = 0; i < before.length; i++) {
      expect(identical(h.page.strokes[i], before[i]), isTrue, reason: 'stroke $i');
    }

    h.controller.redo();
    expect(h.page.strokes, isEmpty);
    expect(h.page.texts, hasLength(3));
    h.controller.undo();
    expect(h.page.strokes.length, before.length);
  });

  testWidgets('unticked lines stay as ink and keep their place in the paint order',
      (tester) async {
    final h = await ConvertHarness.open(tester,
        pages: [ink], recognizer: reader({'bw0': ('second', 0.1)}));
    final before = List<Stroke>.of(h.page.strokes);
    final s = await startSession(h);
    expect(s.stayCount, 1);
    expect(s.includedCount, 2);
    s.apply();
    expect([for (final t in h.page.texts) t.text], ['first line here', 'third']);
    expect(h.page.strokes.map((x) => x.id),
        before.where((x) => x.id.startsWith('bw0')).map((x) => x.id));
    h.controller.undo();
    expect(h.page.strokes.map((x) => x.id), before.map((x) => x.id));
  });

  testWidgets('corrected text is what is typed', (tester) async {
    final h = await ConvertHarness.open(tester,
        pages: [ink], recognizer: reader({'bw0': ('sxcond', 0.1)}));
    final s = await startSession(h);
    final doubtful = s.allLines.firstWhere((l) => l.lowConfidence);
    s.setText(doubtful, 'second');
    s.setInclude(doubtful, true);
    expect(s.includedCount, 3);
    s.apply();
    expect(h.page.texts.map((t) => t.text), contains('second'));
    expect(h.page.strokes, isEmpty);
  });

  testWidgets('a line whose text was emptied is left as ink', (tester) async {
    final h = await ConvertHarness.open(tester, pages: [ink], recognizer: reader());
    final s = await startSession(h);
    s.setText(s.allLines.elementAt(1), '  ');
    expect(s.includedCount, 2);
    expect(s.stayCount, 1);
    s.apply();
    expect(h.page.texts, hasLength(2));
    expect(h.page.strokes.every((x) => x.id.startsWith('bw0')), isTrue);
  });

  testWidgets('the typed text sits on the handwriting baseline, snapped to the rule',
      (tester) async {
    // Lined paper: rules at 78, 104, 130, ... ; this line is written at 107.
    final h = await ConvertHarness.open(tester,
        pages: [writeLine('a', ['hello'], y: 107)], recognizer: reader());
    final s = await startSession(h);
    s.apply();
    final t = h.page.texts.single;
    final painter = layoutTextItem(t);
    addTearDown(painter.dispose);
    expect(t.y + painter.computeLineMetrics().first.baseline, closeTo(104, 0.01));
    expect(t.x, closeTo(100, 3));
    expect(t.fontSize, inInclusiveRange(10, 30));
    expect(t.fontSize, lessThanOrEqualTo(0.8 * 26 + 1e-9));
  });

  testWidgets('blank paper keeps the handwriting baseline', (tester) async {
    final h = await ConvertHarness.open(tester,
        paper: const Paper(type: PaperType.blank),
        pages: [writeLine('a', ['hello'], y: 107)],
        recognizer: reader());
    final s = await startSession(h);
    s.apply();
    final t = h.page.texts.single;
    final painter = layoutTextItem(t);
    addTearDown(painter.dispose);
    expect(t.y + painter.computeLineMetrics().first.baseline, closeTo(107, 1.0));
  });

  testWidgets('PDF pages convert too, without snapping to paper lines',
      (tester) async {
    final h = await ConvertHarness.open(tester,
        pdf: true, pages: [writeLine('a', ['hello'], y: 107)], recognizer: reader());
    final s = await startSession(h);
    expect(s.phase, ConvertPhase.review);
    s.apply();
    final t = h.page.texts.single;
    final painter = layoutTextItem(t);
    addTearDown(painter.dispose);
    expect(t.y + painter.computeLineMetrics().first.baseline, closeTo(107, 1.0));
    expect(h.page.strokes, isEmpty);
  });

  testWidgets('style choices reach the boxes', (tester) async {
    final h = await ConvertHarness.open(tester, pages: [ink], recognizer: reader());
    final s = await startSession(h);
    s
      ..setFont(FontKind.lora)
      ..setBold(true)
      ..setItalic(true)
      ..setFixedSize(14)
      ..setColorOverride(0xFF1A237E);
    s.apply();
    for (final t in h.page.texts) {
      expect(t.font, FontKind.lora);
      expect(t.bold, isTrue);
      expect(t.italic, isTrue);
      expect(t.fontSize, lessThanOrEqualTo(14));
      expect(t.color, 0xFF1A237E);
    }
  });

  testWidgets('the ink colour is kept unless overridden', (tester) async {
    final h = await ConvertHarness.open(tester,
        pages: [writeLine('a', ['hello'], y: 107, color: 0xFFB71C1C)],
        recognizer: reader());
    final s = await startSession(h);
    s.apply();
    expect(h.page.texts.single.color, 0xFFB71C1C);
  });

  testWidgets('highlighter strokes are not touched', (tester) async {
    final hl = Stroke(
      id: 'hl',
      tool: StrokeTool.highlighter,
      color: 0xFFFFFF00,
      size: 12,
      raw: [for (var x = 90.0; x < 160; x += 2) InkPoint(x, 98, 0.5, 0)],
    );
    final h = await ConvertHarness.open(tester,
        pages: [[...writeLine('a', ['hello'], y: 104), hl]], recognizer: reader());
    final s = await startSession(h);
    s.apply();
    expect(h.page.strokes.map((x) => x.id), ['hl']);
    h.controller.undo();
    expect(h.page.strokes.map((x) => x.id), contains('hl'));
  });

  testWidgets('selection scope converts only the selected strokes', (tester) async {
    final h = await ConvertHarness.open(tester, pages: [ink], recognizer: reader());
    final ids = [
      for (final x in h.page.strokes)
        if (x.id.startsWith('bw0')) x.id,
    ];
    h.select(ids);
    final s = await startSession(h, selection: h.lasso.state.selection);
    expect(s.canChooseScope, isFalse);
    expect(s.allLines, hasLength(1));
    expect(h.recognizer.wordsRead, 1);
    s.apply();
    expect(h.page.texts.map((t) => t.text), ['second']);
    expect(h.page.strokes.every((x) => !x.id.startsWith('bw0')), isTrue);
    expect(h.page.strokes.where((x) => x.id.startsWith('aw')), isNotEmpty);
    expect(h.page.strokes.where((x) => x.id.startsWith('cw')), isNotEmpty);
  });

  testWidgets('page scope converts the page in view, all pages converts every page',
      (tester) async {
    final p1 = [...writeLine('a', ['hello'], y: 104)];
    final p2 = [...writeLine('b', ['hello'], y: 104), ...writeLine('c', ['hello'], y: 156)];
    final h = await ConvertHarness.open(tester, pages: [p1, p2], recognizer: reader());
    final page1 = List<Stroke>.of(h.pageAt(0).strokes);
    final page2 = List<Stroke>.of(h.pageAt(1).strokes);

    final s = await startSession(h);
    expect(s.canChooseScope, isTrue);
    expect(s.allPages, isFalse);
    expect(s.allLines, hasLength(1));
    expect(h.recognizer.wordsRead, 1);

    // Widening reads only the other page.
    await s.setAllPages(true);
    expect(s.phase, ConvertPhase.review);
    expect(h.recognizer.wordsRead, 3);
    expect(s.plans.map((p) => p.pageIndex), [0, 1]);
    expect(s.includedCount, 3);

    final undoBefore = h.undoDepth;
    final outcome = s.apply()!;
    expect(outcome.pages, 2);
    expect(outcome.lines, 3);
    expect(h.undoDepth, undoBefore + 1); // one undo step for all pages
    expect(h.pageAt(0).texts.map((t) => t.text), ['first line']);
    expect(h.pageAt(1).texts.map((t) => t.text), ['second', 'third']);
    expect(h.pageAt(0).strokes, isEmpty);
    expect(h.pageAt(1).strokes, isEmpty);

    h.controller.undo();
    expect(h.pageAt(0).texts, isEmpty);
    expect(h.pageAt(1).texts, isEmpty);
    expect(h.pageAt(0).strokes.length, page1.length);
    expect(h.pageAt(1).strokes.length, page2.length);
    for (var i = 0; i < page2.length; i++) {
      expect(identical(h.pageAt(1).strokes[i], page2[i]), isTrue);
    }
  });

  testWidgets('this page only leaves the other pages alone', (tester) async {
    final p1 = [...writeLine('a', ['hello'], y: 104)];
    final p2 = [...writeLine('b', ['hello'], y: 104)];
    final h = await ConvertHarness.open(tester, pages: [p1, p2], recognizer: reader());
    final s = await startSession(h);
    s.apply();
    expect(h.pageAt(0).texts, hasLength(1));
    expect(h.pageAt(1).texts, isEmpty);
    expect(h.pageAt(1).strokes, isNotEmpty);
  });

  testWidgets('a read-only page is refused', (tester) async {
    final h = await ConvertHarness.open(tester,
        pages: [ink], unreadablePages: {0}, recognizer: reader());
    expect(h.controller.isPageEditable(h.pageIdAt(0)), isFalse);
    final s = await startSession(h);
    expect(s.phase, ConvertPhase.empty);
    expect(s.apply(), isNull);
    expect(h.recognizer.calls, 0);

    // Even a hand-built conversion does nothing to such a page.
    final outcome = applyConversion(h.controller, [
      PageConversion(pageId: h.pageIdAt(0), strokeIds: {'x'}, items: const []),
    ]);
    expect(outcome, isNull);
    expect(h.undoDepth, 0);
  });

  testWidgets('applying with nothing ticked changes nothing', (tester) async {
    final h = await ConvertHarness.open(tester,
        pages: [ink], recognizer: reader({'aw0': ('x', 0.0), 'aw1': ('x', 0.0), 'bw0': ('y', 0.0), 'cw0': ('z', 0.0)}));
    final s = await startSession(h);
    expect(s.includedCount, 0);
    expect(s.apply(), isNull);
    expect(h.undoDepth, 0);
    expect(h.page.strokes.length, ink.length);
  });

  testWidgets('the page is re-rendered after converting', (tester) async {
    final h = await ConvertHarness.open(tester, pages: [ink], recognizer: reader());
    final gen = h.controller.renderGeneration(h.pageIdAt(0));
    final s = await startSession(h);
    s.apply();
    expect(h.controller.renderGeneration(h.pageIdAt(0)), greaterThan(gen));
  });

  testWidgets('a failing recogniser ends in the failed phase with its message',
      (tester) async {
    final fake = reader()..error = const HtrException('out_of_memory', 'oom');
    final h = await ConvertHarness.open(tester, pages: [ink], recognizer: fake);
    final s = await startSession(h);
    expect(s.phase, ConvertPhase.failed);
    expect(s.errorMessage, 'Not enough memory to read the handwriting.');
    fake.error = null;
    await s.retry();
    expect(s.phase, ConvertPhase.review);
  });

  testWidgets('an unexpected error does not crash', (tester) async {
    final fake = reader()..error = StateError('boom');
    final h = await ConvertHarness.open(tester, pages: [ink], recognizer: fake);
    final s = await startSession(h);
    expect(s.phase, ConvertPhase.failed);
    expect(s.errorMessage, 'Reading the handwriting failed.');
  });

  testWidgets('a page with no pen strokes has nothing to convert', (tester) async {
    final h = await ConvertHarness.open(tester, recognizer: reader());
    final s = await startSession(h);
    expect(s.phase, ConvertPhase.empty);
    expect(s.apply(), isNull);
  });
}
