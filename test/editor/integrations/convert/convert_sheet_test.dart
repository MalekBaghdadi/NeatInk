import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/font_kind.dart';
import 'package:neatink/features/editor/integrations/convert/convert_config.dart';
import 'package:neatink/features/editor/integrations/convert/word_crop.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/recognition/htr_channel.dart';
import 'package:neatink/recognition/word_image.dart';

import 'harness.dart';

FakeRecognizer reader([Map<String, (String, double)> extra = const {}]) =>
    FakeRecognizer({
      'aw0': ('hello', 0.9),
      'aw1': ('online', 0.9),
      'bw0': ('second', 0.9),
      'cw0': ('third', 0.9),
      ...extra,
    });

List<Stroke> threeLines() => [
      ...writeLine('a', ['hello', 'online'], y: 104),
      ...writeLine('b', ['hello'], y: 156),
      ...writeLine('c', ['hello'], y: 208),
    ];

Finder key(String k) => find.byKey(ValueKey(k));

String fieldText(WidgetTester tester, int i) =>
    tester.widget<TextField>(key('convert-text-$i')).controller!.text;

bool checked(WidgetTester tester, int i) =>
    tester.widget<Checkbox>(key('convert-include-$i')).value!;

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('progress first, then the review, then convert with an undo',
      (tester) async {
    final fake = reader()..gate = Completer<void>();
    final h = await ConvertHarness.open(tester, pages: [threeLines()], recognizer: fake);
    final before = List<Stroke>.of(h.page.strokes);

    await h.tapConvert();
    expect(key('convert-sheet'), findsOneWidget);
    expect(find.text('Convert to text'), findsOneWidget);
    expect(find.text('Reading your handwriting...'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(key('convert-progress'));
    expect(bar.value, isNotNull); // determinate
    expect(key('convert-cancel'), findsOneWidget);
    expect(key('convert-apply'), findsNothing);

    fake.gate!.complete();
    await settle(tester);
    expect(find.text('Reading your handwriting...'), findsNothing);
    expect(find.text('Convert 3 lines'), findsOneWidget);
    expect(fieldText(tester, 0), 'hello online');
    expect(fieldText(tester, 1), 'second');
    expect(fieldText(tester, 2), 'third');
    expect(checked(tester, 0) && checked(tester, 1) && checked(tester, 2), isTrue);
    expect(find.text('Every line will be converted.'), findsOneWidget);
    expect(key('convert-notsure-0'), findsNothing);

    await tester.tap(key('convert-apply'));
    await settle(tester);
    expect(key('convert-sheet'), findsNothing);
    expect(h.page.strokes, isEmpty);
    expect(h.page.texts.map((t) => t.text), ['hello online', 'second', 'third']);
    expect(find.text('Converted 3 lines. Undo to get your handwriting back.'),
        findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(h.page.texts, isEmpty);
    expect(h.page.strokes.length, before.length);
    for (var i = 0; i < before.length; i++) {
      expect(identical(h.page.strokes[i], before[i]), isTrue);
    }
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('doubtful lines start unticked with a Not sure badge', (tester) async {
    final h = await ConvertHarness.open(tester,
        pages: [threeLines()], recognizer: reader({'bw0': ('sxcond', 0.1)}));
    await h.tapConvert();
    expect(checked(tester, 0), isTrue);
    expect(checked(tester, 1), isFalse);
    expect(checked(tester, 2), isTrue);
    expect(key('convert-notsure-1'), findsOneWidget);
    expect(key('convert-notsure-0'), findsNothing);
    expect(find.text('1 line will stay as handwriting'), findsOneWidget);
    expect(find.text('Convert 2 lines'), findsOneWidget);

    await tester.tap(key('convert-apply'));
    await settle(tester);
    // The unticked line is still ink, nothing was lost.
    expect(h.page.texts.map((t) => t.text), ['hello online', 'third']);
    expect(h.page.strokes.every((s) => s.id.startsWith('bw0')), isTrue);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('ticking a line and fixing its text before converting', (tester) async {
    final h = await ConvertHarness.open(tester,
        pages: [threeLines()], recognizer: reader({'bw0': ('sxcond', 0.1)}));
    await h.tapConvert();
    await tester.tap(key('convert-include-1'));
    await tester.pump();
    expect(find.text('Convert 3 lines'), findsOneWidget);
    expect(find.text('Every line will be converted.'), findsOneWidget);
    await tester.enterText(key('convert-text-1'), 'Second line');
    await tester.pump();
    await tester.tap(key('convert-apply'));
    await settle(tester);
    expect(h.page.texts.map((t) => t.text), contains('Second line'));
    expect(h.page.strokes, isEmpty);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('clearing a line text takes it out of the count', (tester) async {
    final h = await ConvertHarness.open(tester, pages: [threeLines()], recognizer: reader());
    await h.tapConvert();
    await tester.enterText(key('convert-text-0'), '');
    await tester.pump();
    expect(find.text('Convert 2 lines'), findsOneWidget);
    expect(find.text('1 line will stay as handwriting'), findsOneWidget);
  });

  testWidgets('font, bold, italic, size and colour choices are applied', (tester) async {
    final h = await ConvertHarness.open(tester, pages: [threeLines()], recognizer: reader());
    await h.tapConvert();

    expect(find.text(FontKind.sans.label), findsWidgets);
    await tester.tap(key('convert-font'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Grouped by category, every font in its own typeface.
    expect(key('text-font-heading-serif'), findsOneWidget);
    await tester.tap(key('text-font-lora'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<Text>(key('convert-font-label')).data, 'Lora');
    expect(tester.widget<TextField>(key('convert-text-0')).style!.fontFamily,
        FontKind.lora.family);

    await tester.tap(key('convert-bold'));
    await tester.tap(key('convert-italic'));
    await tester.pump();
    expect(tester.widget<TextField>(key('convert-text-0')).style!.fontWeight,
        FontWeight.w700);
    expect(tester.widget<TextField>(key('convert-text-0')).style!.fontStyle,
        FontStyle.italic);

    expect(tester.widget<ChoiceChip>(key('convert-size-auto')).selected, isTrue);
    expect(find.text('Auto (match my handwriting)'), findsOneWidget);
    await tester.tap(key('convert-size-slider'));
    await tester.pump();
    expect(tester.widget<ChoiceChip>(key('convert-size-auto')).selected, isFalse);
    final label = tester.widget<Text>(key('convert-size-label')).data!;
    expect(label, endsWith(' pt'));
    final pt = int.parse(label.replaceAll(' pt', ''));
    expect(pt, inInclusiveRange(10, 32));

    expect(tester.widget<ChoiceChip>(key('convert-colour-keep')).selected, isTrue);
    await tester.tap(key('convert-colour-ff1a237e'));
    await tester.pump();
    expect(tester.widget<ChoiceChip>(key('convert-colour-keep')).selected, isFalse);

    await tester.tap(key('convert-apply'));
    await settle(tester);
    expect(h.page.texts, hasLength(3));
    for (final t in h.page.texts) {
      expect(t.font, FontKind.lora);
      expect(t.bold, isTrue);
      expect(t.italic, isTrue);
      expect(t.fontSize, lessThanOrEqualTo(pt + 1e-9));
      expect(t.color, 0xFF1A237E);
    }
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('Auto goes back to matching the handwriting', (tester) async {
    final h = await ConvertHarness.open(tester, pages: [threeLines()], recognizer: reader());
    await h.tapConvert();
    await tester.tap(key('convert-size-slider'));
    await tester.pump();
    await tester.tap(key('convert-size-auto'));
    await tester.pump();
    expect(tester.widget<ChoiceChip>(key('convert-size-auto')).selected, isTrue);
    expect(tester.widget<Text>(key('convert-size-label')).data, '');
    await tester.tap(key('convert-colour-ff1a237e'));
    await tester.tap(key('convert-colour-keep'));
    await tester.pump();
    expect(tester.widget<ChoiceChip>(key('convert-colour-keep')).selected, isTrue);
  });

  testWidgets('a failure shows its message and Retry reads again', (tester) async {
    final fake = reader()..error = const HtrException('model_missing', 'gone');
    final h = await ConvertHarness.open(tester, pages: [threeLines()], recognizer: fake);
    await h.tapConvert();
    expect(find.text('The handwriting model could not be loaded.'), findsOneWidget);
    expect(key('convert-retry'), findsOneWidget);
    expect(key('convert-apply'), findsNothing);

    fake.error = null;
    await tester.tap(key('convert-retry'));
    await settle(tester);
    expect(key('convert-error'), findsNothing);
    expect(find.text('Convert 3 lines'), findsOneWidget);
    expect(h.page.strokes, isNotEmpty); // nothing changed meanwhile
  });

  testWidgets('an unexpected error also ends in a message, never a crash',
      (tester) async {
    final fake = reader()..error = StateError('boom');
    final h = await ConvertHarness.open(tester, pages: [threeLines()], recognizer: fake);
    await h.tapConvert();
    expect(find.text('Reading the handwriting failed.'), findsOneWidget);
    expect(key('convert-retry'), findsOneWidget);
  });

  testWidgets('no handwriting: a friendly message', (tester) async {
    final h = await ConvertHarness.open(tester, recognizer: reader());
    await h.tapConvert();
    expect(find.text('Nothing to convert here yet'), findsOneWidget);
    expect(key('convert-apply'), findsNothing);
    expect(h.recognizer.calls, 0);
    // The scope switch is still there, so another page can be tried.
    expect(key('convert-scope'), findsOneWidget);
  });

  testWidgets('only highlighter ink counts as nothing to convert', (tester) async {
    final hl = Stroke(
      id: 'hl',
      tool: StrokeTool.highlighter,
      color: 0xFFFFFF00,
      size: 12,
      raw: [for (var x = 90.0; x < 160; x += 2) InkPoint(x, 98, 0.5, 0)],
    );
    final h = await ConvertHarness.open(tester, pages: [[hl]], recognizer: reader());
    await h.tapConvert();
    expect(find.text('Nothing to convert here yet'), findsOneWidget);
  });

  testWidgets('Cancel closes the sheet and changes nothing, even if reading ends later',
      (tester) async {
    final fake = reader()..gate = Completer<void>();
    final h = await ConvertHarness.open(tester, pages: [threeLines()], recognizer: fake);
    final before = h.page.strokes.length;
    await h.tapConvert();
    await tester.tap(key('convert-cancel'));
    await settle(tester);
    expect(key('convert-sheet'), findsNothing);
    fake.gate!.complete();
    await tester.pump(const Duration(milliseconds: 100));
    expect(h.page.strokes.length, before);
    expect(h.page.texts, isEmpty);
    expect(h.undoDepth, 0);
  });

  testWidgets('the close button also leaves everything as it was', (tester) async {
    final h = await ConvertHarness.open(tester, pages: [threeLines()], recognizer: reader());
    await h.tapConvert();
    await tester.tap(key('convert-close'));
    await settle(tester);
    expect(key('convert-sheet'), findsNothing);
    expect(h.undoDepth, 0);
  });

  testWidgets('This page / All pages switch widens the scope in one undo step',
      (tester) async {
    final p1 = writeLine('a', ['hello'], y: 104);
    final p2 = [...writeLine('b', ['hello'], y: 104), ...writeLine('c', ['hello'], y: 156)];
    final h = await ConvertHarness.open(tester, pages: [p1, p2], recognizer: reader());
    await h.tapConvert();
    expect(find.text('Convert 1 line'), findsOneWidget);
    expect(find.text('Page 1'), findsNothing);

    await tester.tap(find.text('All pages'));
    await settle(tester);
    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('Page 2'), findsOneWidget);
    expect(find.text('Convert 3 lines'), findsOneWidget);
    expect(fieldText(tester, 1), 'second');

    final undoBefore = h.undoDepth;
    await tester.tap(key('convert-apply'));
    await settle(tester);
    expect(h.undoDepth, undoBefore + 1);
    expect(h.pageAt(0).texts, hasLength(1));
    expect(h.pageAt(1).texts, hasLength(2));
    expect(find.text('Converted 3 lines. Undo to get your handwriting back.'),
        findsOneWidget);
    h.controller.undo();
    expect(h.pageAt(0).texts, isEmpty);
    expect(h.pageAt(1).texts, isEmpty);
    expect(h.pageAt(0).strokes, isNotEmpty);
    expect(h.pageAt(1).strokes, isNotEmpty);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('"what the recognizer saw" is collapsed, then shows crops and readings',
      (tester) async {
    final h = await ConvertHarness.open(tester,
        pages: [writeLine('a', ['hello'], y: 104)],
        recognizer: reader({'aw0': ('hella', 0.62)}));
    await h.tapConvert();
    expect(find.text('Show what the recognizer saw'), findsOneWidget);
    expect(key('convert-word-0'), findsNothing);

    await tester.tap(key('convert-debug-toggle'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(key('convert-word-0'), findsOneWidget);
    expect(find.textContaining('raw "hella~"'), findsOneWidget);
    expect(find.textContaining('read "hella"'), findsOneWidget);
    expect(find.textContaining('confidence 0.62'), findsOneWidget);
    expect(key('convert-crop-0'), findsOneWidget);
    final painter = tester.widget<CustomPaint>(key('convert-crop-0')).painter!
        as WordCropPainter;
    expect(painter.height, wordImageHeight);
    expect(painter.pixels, hasLength(painter.width * painter.height));
    expect(painter.pixels.any((v) => v < 100), isTrue); // there is ink in it

    await tester.tap(key('convert-debug-toggle'));
    await tester.pump();
    expect(key('convert-word-0'), findsNothing);
  });

  testWidgets('the selection menu has a Convert button that reads only the selection',
      (tester) async {
    final h = await ConvertHarness.open(tester, pages: [threeLines()], recognizer: reader());
    h.select([
      for (final s in h.page.strokes)
        if (s.id.startsWith('bw0')) s.id,
    ]);
    await tester.pump();
    expect(key('selection-convert'), findsOneWidget);

    await tester.tap(key('selection-convert'));
    await settle(tester);
    expect(key('convert-sheet'), findsOneWidget);
    expect(find.text('Convert 1 line'), findsOneWidget);
    expect(fieldText(tester, 0), 'second');
    expect(key('convert-scope'), findsNothing); // a selection fixes the scope
    expect(h.recognizer.wordsRead, 1);

    await tester.tap(key('convert-apply'));
    await settle(tester);
    expect(h.page.texts.map((t) => t.text), ['second']);
    expect(h.page.strokes.where((s) => s.id.startsWith('aw')), isNotEmpty);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('the app bar button uses the selection when there is one',
      (tester) async {
    final h = await ConvertHarness.open(tester, pages: [threeLines()], recognizer: reader());
    h.select([
      for (final s in h.page.strokes)
        if (s.id.startsWith('cw0')) s.id,
    ]);
    await tester.pump();
    await h.tapConvert();
    expect(find.text('Convert 1 line'), findsOneWidget);
    expect(fieldText(tester, 0), 'third');
  });

  testWidgets('no Convert button for a selection without pen strokes', (tester) async {
    final hl = Stroke(
      id: 'hl',
      tool: StrokeTool.highlighter,
      color: 0xFFFFFF00,
      size: 12,
      raw: [for (var x = 90.0; x < 160; x += 2) InkPoint(x, 98, 0.5, 0)],
    );
    final h = await ConvertHarness.open(tester,
        pages: [[...threeLines(), hl]], recognizer: reader());
    h.select(['hl']);
    await tester.pump();
    expect(key('selection-delete'), findsOneWidget);
    expect(key('selection-convert'), findsNothing);
  });

  testWidgets('a read-only page cannot be converted', (tester) async {
    final h = await ConvertHarness.open(tester,
        pages: [threeLines()], unreadablePages: {0}, recognizer: reader());
    expect(tester.widget<TextButton>(key('convert-to-text')).onPressed, isNull);
    expect(h.recognizer.calls, 0);
  });

  testWidgets('wide screens show a labelled button, narrow ones an icon',
      (tester) async {
    await ConvertHarness.open(tester, pages: [threeLines()], recognizer: reader());
    expect(find.text('Convert'), findsOneWidget);
    expect(tester.widget<TextButton>(key('convert-to-text')).onPressed, isNotNull);
  });

  testWidgets('narrow layout: an icon button with a tooltip', (tester) async {
    final h = await ConvertHarness.open(tester,
        pages: [threeLines()], recognizer: reader(), size: const Size(700, 1200));
    expect(find.byType(IconButton).evaluate().any((e) => (e.widget as IconButton).tooltip == 'Convert handwriting to text'),
        isTrue);
    expect(tester.widget<IconButton>(key('convert-to-text')).onPressed, isNotNull);
    await h.tapConvert();
    expect(key('convert-sheet'), findsOneWidget);
    expect(find.text('Convert 3 lines'), findsOneWidget);
  });

  testWidgets('a small screen scrolls instead of overflowing', (tester) async {
    final h = await ConvertHarness.open(tester,
        pages: [threeLines()], recognizer: reader(), size: const Size(600, 560));
    await h.tapConvert();
    expect(key('convert-sheet'), findsOneWidget);
    expect(find.text('Convert 3 lines'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('the low-confidence threshold lives in one config class', () {
    expect(ConvertConfig.lowConfidenceThreshold, 0.35);
  });
}
