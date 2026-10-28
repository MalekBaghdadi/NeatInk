import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/integrations/convert/convert_config.dart';
import 'package:neatink/features/editor/integrations/convert/convert_corrections.dart';
import 'package:neatink/features/editor/integrations/convert/convert_plan.dart';
import 'package:neatink/features/editor/integrations/convert/png_gray.dart';
import 'package:neatink/features/editor/integrations/convert/sample_export.dart';
import 'package:neatink/features/settings/app_settings.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/recognition/stroke_grouping.dart';
import 'package:neatink/recognition/text_polish.dart';
import 'package:neatink/recognition/word_image.dart';

import 'harness.dart';

Finder key(String k) => find.byKey(ValueKey(k));

String fieldText(WidgetTester tester, int i) =>
    tester.widget<TextField>(key('convert-text-$i')).controller!.text;

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

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

/// A recognised line of [texts] (one word each, 0.8 sure) as the review sheet
/// holds it.
PlannedLine plannedLine(List<String> texts,
        {String id = 'p/0',
        List<List<String>>? alternatives,
        List<PolishSuggestion> suggestions = const [],
        bool autoFix = false}) =>
    plannedLineOf([for (final t in texts) (t, 0.8)],
        id: id,
        alternatives: alternatives,
        suggestions: suggestions,
        autoFix: autoFix);

const int testImageWidth = 100;

/// A picture like the ones the model is given, whose pixels depend on [seed].
LineImage imageOf(int seed) => LineImage(
      pixels: Uint8List.fromList([
        for (var i = 0; i < testImageWidth * wordImageHeight; i++)
          (i * 7 + seed) % 256,
      ]),
      width: testImageWidth,
      scale: 2.5,
      strokeWidthPx: 2,
      strokes: const [],
      angle: 0.25,
      originX: 12.5,
    );

/// A fix of "Nuerons fire quik" (three words, three fixes).
const nuerons = PolishSuggestion(
  original: 'Nuerons',
  replacement: 'Neurons',
  kind: PolishKind.spelling,
  reason: 'Spelling',
  start: 0,
  end: 7,
);
const fireFix = PolishSuggestion(
  original: 'fire',
  replacement: 'fires',
  kind: PolishKind.grammar,
  reason: 'Grammar',
  start: 8,
  end: 12,
);
const quikFix = PolishSuggestion(
  original: 'quik',
  replacement: 'quick',
  kind: PolishKind.spelling,
  reason: 'Spelling',
  start: 13,
  end: 17,
);

/// Reads a grey 8-bit PNG back: checks the signature and every chunk's CRC
/// and returns (width, height, pixels).
(int, int, Uint8List) decodeGrayPng(Uint8List png) {
  expect(png.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final data = ByteData.sublistView(png);
  var at = 8;
  var width = 0, height = 0;
  final idat = BytesBuilder();
  var ended = false;
  while (at < png.length) {
    final length = data.getUint32(at);
    final type = String.fromCharCodes(png.sublist(at + 4, at + 8));
    final body = png.sublist(at + 8, at + 8 + length);
    final crc = data.getUint32(at + 8 + length);
    expect(crc32(png.sublist(at + 4, at + 8 + length)), crc, reason: type);
    switch (type) {
      case 'IHDR':
        width = ByteData.sublistView(body).getUint32(0);
        height = ByteData.sublistView(body).getUint32(4);
        expect(body.sublist(8), [8, 0, 0, 0, 0]);
      case 'IDAT':
        idat.add(body);
      case 'IEND':
        ended = true;
    }
    at += 12 + length;
  }
  expect(ended, isTrue);
  final raw = Uint8List.fromList(ZLibDecoder().convert(idat.takeBytes()));
  expect(raw.length, (width + 1) * height);
  final pixels = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    expect(raw[y * (width + 1)], 0, reason: 'filter type of row $y');
    pixels.setRange(y * width, (y + 1) * width, raw, y * (width + 1) + 1);
  }
  return (width, height, pixels);
}

void main() {
  group('PNG writer', () {
    test('crc32 matches the standard check value', () {
      expect(crc32('123456789'.codeUnits), 0xCBF43926);
      expect(crc32(const []), 0);
    });

    test('what is written reads back pixel for pixel', () {
      final pixels = imageOf(3).pixels;
      final png = encodeGrayPng(pixels, testImageWidth, wordImageHeight);
      final (w, h, back) = decodeGrayPng(png);
      expect(w, testImageWidth);
      expect(h, wordImageHeight);
      expect(back, pixels);
    });

    test('a small odd-sized image too', () {
      final pixels = Uint8List.fromList([0, 255, 128, 7, 8, 9, 10]);
      final (w, h, back) = decodeGrayPng(encodeGrayPng(pixels, 7, 1));
      expect((w, h), (7, 1));
      expect(back, pixels);
    });

    test('the wrong amount of pixels is refused', () {
      expect(() => encodeGrayPng(Uint8List(5), 2, 2), throwsArgumentError);
      expect(() => encodeGrayPng(Uint8List(0), 0, 0), throwsArgumentError);
    });
  });

  group('splitting corrected text back into words', () {
    test('splitWords collapses spaces and line breaks', () {
      expect(splitWords('  hello \n  online  '), ['hello', 'online']);
      expect(splitWords('   '), isEmpty);
      expect(splitWords(''), isEmpty);
    });

    test('alignWords needs the same number of words', () {
      expect(alignWords('Hello online', 2), ['Hello', 'online']);
      expect(alignWords('Hello online now', 2), isNull);
      expect(alignWords('Hello', 2), isNull);
      expect(alignWords('', 0), isEmpty);
    });

    test('correctedWords: changed words that look like words', () {
      List<String> fix(List<String> was, String now) =>
          correctedWords(recognised: was, finalText: now);
      expect(fix(['hello', 'online'], 'Hello online'), ['Hello']);
      expect(fix(['hello', 'online'], 'hello online'), isEmpty);
      expect(fix(['mariem', 'wrote'], 'Mariam wrote'), ['Mariam']);
      // Punctuation around a word is not part of it.
      expect(fix(['hello'], '"Hello,"'), ['Hello']);
      expect(fix(['hello,'], 'hello,'), isEmpty);
      expect(fix(['hello,'], 'hello.'), isEmpty);
      // Names with apostrophes and hyphens.
      expect(fix(['anne', 'oriens'], "Anne-Marie O'Brien"), ['Anne-Marie', "O'Brien"]);
      // Not words: digits, a single letter, symbols.
      expect(fix(['third', 'a', 'cat'], 'th1rd I c@t'), isEmpty);
      expect(fix(['one'], '42'), isEmpty);
      // The number of words changed: nothing can be matched up.
      expect(fix(['hello', 'online'], 'Hello on line'), isEmpty);
      expect(fix(['hello', 'online'], 'Hello'), isEmpty);
      // Every word once.
      expect(fix(['aa', 'bb'], 'Zed Zed'), ['Zed']);
    });

    test('looksLikeWord', () {
      for (final ok in ['ab', 'Mariam', "O'Brien", 'Anne-Marie']) {
        expect(looksLikeWord(ok), isTrue, reason: ok);
      }
      for (final bad in ['a', '', 'x1', 'a b', '123', 'ça']) {
        expect(looksLikeWord(bad), isFalse, reason: bad);
      }
    });
  });

  group('the samples JSON', () {
    Map<String, dynamic> build(List<SampleLineInput> lines) => buildSamplesJson(
          appVersion: 'x',
          createdAt: DateTime.utc(2026),
          lines: lines,
        );

    Map<String, dynamic> single(PlannedLine line, [List<WordImage>? images]) =>
        (build([
          SampleLineInput(line: line, pageIndex: 0, images: images ?? [imageOf(1)]),
        ])['lines'] as List)
            .single as Map<String, dynamic>;

    test('has the format, version, and one entry per line', () {
      final l1 = plannedLine(['hello', 'online']);
      final l2 = plannedLine(['third'], id: 'p/1');
      final l3 = plannedLine(['second'], id: 'p/1');
      final json = buildSamplesJson(
        appVersion: '1.1.0+2',
        createdAt: DateTime.utc(2026, 10, 27, 9, 30),
        lines: [
          SampleLineInput(line: l1, pageIndex: 0, images: [imageOf(1)]),
          SampleLineInput(line: l2, pageIndex: 2, images: [imageOf(3)]),
          SampleLineInput(line: l3, pageIndex: 0, images: [imageOf(2)]),
        ],
      );
      expect(json['format'], 2);
      expect(samplesFormat, 2);
      expect(json['appVersion'], '1.1.0+2');
      expect(json['createdAt'], '2026-10-27T09:30:00.000Z');
      expect(json['lineCount'], 3);
      expect(json.containsKey('words'), isFalse, reason: 'one entry per line now');
      expect(json.containsKey('wordCount'), isFalse);
      expect(json['image'], containsPair('encoding', 'png-gray8-base64'));
      expect(json['image'], containsPair('height', wordImageHeight));
      final lines = (json['lines'] as List).cast<Map<String, dynamic>>();
      expect(lines, hasLength(3));
      // Pages are 1-based, lines are counted on their own page.
      expect(lines.map((l) => (l['page'], l['line'])), [(1, 0), (3, 0), (1, 1)]);
      expect(lines.map((l) => (l['words'] as List).length), [2, 1, 1]);
      expect(lines.map((l) => l['recognizedText']),
          ['hello online', 'third', 'second']);
      // It really is JSON.
      expect(jsonDecode(encodeSamplesJson(json)), json);
    });

    test('a corrected line has the recognised and the final text', () {
      final line = plannedLineOf([('hello', 0.8), ('onlyne', 0.6)]);
      line.text = 'Hello online';
      final l = single(line);
      expect(l['recognizedText'], 'hello onlyne');
      expect(l['finalText'], 'Hello online');
      expect(l['corrected'], isTrue);
      expect(l['lineIncluded'], isTrue);
      expect(l['confidence'], 0.6, reason: 'that of the least sure word');
      final words = (l['words'] as List).cast<Map<String, dynamic>>();
      expect(words.map((w) => w['text']), ['hello', 'onlyne']);
      expect(words.map((w) => w['raw']), ['hello~', 'onlyne~']);
      expect(words.map((w) => w['confidence']), [0.8, 0.6]);
    });

    test('an untouched line has no corrections', () {
      final l = single(plannedLine(['hello', 'online']));
      expect(l['corrected'], isFalse);
      expect(l['finalText'], l['recognizedText']);
      expect(l['suggestions'], isEmpty);
    });

    test('a line corrected only by spelling fixes is not a correction of the recogniser',
        () {
      // The fix is in the text, but what was read is kept next to it.
      final line = plannedLine(['Nuerons', 'fire'],
          suggestions: [nuerons], autoFix: true);
      final l = single(line);
      expect(l['recognizedText'], 'Nuerons fire');
      expect(l['finalText'], 'Neurons fire');
      expect(l['suggestions'], [
        {'original': 'Nuerons', 'replacement': 'Neurons', 'kind': 'spelling', 'status': 'auto'},
      ]);
    });

    test('suggestions say whether they are pending, accepted or were applied for the user',
        () {
      final line = plannedLine(['Nuerons', 'fire', 'quik'],
          suggestions: [nuerons, fireFix, quikFix], autoFix: true);
      expect(line.text, 'Neurons fires quick');
      expect(line.revertAutoFix(fireFix), isTrue); // pending again
      expect(line.revertAutoFix(quikFix), isTrue);
      expect(line.acceptSuggestion(quikFix), isTrue); // accepted by the user
      final l = single(line);
      expect(l['recognizedText'], 'Nuerons fire quik');
      expect(l['finalText'], 'Neurons fire quick');
      final fixes = (l['suggestions'] as List).cast<Map<String, dynamic>>();
      expect([for (final f in fixes) (f['original'], f['status'])], [
        ('fire', 'pending'),
        ('quik', 'accepted'),
        ('Nuerons', 'auto'),
      ]);
      expect(fixes.map((f) => f['kind']), ['grammar', 'spelling', 'spelling']);
      expect(fixes[1]['replacement'], 'quick');
    });

    test('carries every pen stroke in order, the line geometry and alternatives', () {
      final line = plannedLine(['hello', 'online'], alternatives: [
        ['hallo', 'jello'],
        const [],
      ]);
      final l = single(line);
      final words = (l['words'] as List).cast<Map<String, dynamic>>();
      expect(words.first['alternatives'], ['hallo', 'jello']);
      expect(words.last['alternatives'], isEmpty);
      expect(l['xHeight'], closeTo(line.line.xHeight, 0.01));
      expect(l['baselineSlope'], closeTo(line.line.baselineSlope, 1e-5));
      final ink = line.line.inkStrokes;
      var left = double.infinity, top = double.infinity;
      var right = double.negativeInfinity, bottom = double.negativeInfinity;
      for (final s in ink) {
        for (final p in s.raw) {
          if (p.x < left) left = p.x;
          if (p.x > right) right = p.x;
          if (p.y < top) top = p.y;
          if (p.y > bottom) bottom = p.y;
        }
      }
      expect(l['bounds'], [
        closeTo(left, 0.01),
        closeTo(top, 0.01),
        closeTo(right, 0.01),
        closeTo(bottom, 0.01),
      ]);

      final strokes = (l['strokes'] as List).cast<Map<String, dynamic>>();
      // Every stroke of the line, in the order written ("hello hello").
      expect(strokes, hasLength(5 + 5));
      expect(strokes.map((s) => s['id']), ink.map((s) => s.id));
      expect(strokes.map((s) => s['id']).toSet(), line.strokeIds);
      expect(strokes.first['size'], ink.first.size);
      expect(strokes.first['color'], colorToHex(ink.first.color));
      final points = strokes.first['points'] as List;
      expect(points, hasLength(ink.first.raw.length));
      final p0 = ink.first.raw.first;
      expect(points.first, [
        closeTo(p0.x, 0.01),
        closeTo(p0.y, 0.01),
        closeTo(p0.pressure, 0.001),
        p0.t,
      ]);
      final pEnd = ink.last.raw.last;
      expect((strokes.last['points'] as List).last, [
        closeTo(pEnd.x, 0.01),
        closeTo(pEnd.y, 0.01),
        closeTo(pEnd.pressure, 0.001),
        pEnd.t,
      ]);
    });

    test('the pen data is the raw ink, not what is displayed', () {
      final line = plannedLine(['hello']);
      final base = line.line;
      final first = base.inkStrokes.first;
      // A stroke whose displayed points differ from what the pen produced.
      final snapped = first.copyWith(
        points: [for (final p in first.raw) InkPoint(p.x + 50, p.y, p.pressure, p.t)],
      );
      expect(snapped.points.first.x, isNot(snapped.raw.first.x));
      final shifted = RecognizedLine(
        words: base.words,
        baselineY: base.baselineY,
        baselineSlope: base.baselineSlope,
        left: base.left,
        right: base.right,
        xHeight: base.xHeight,
        inkStrokes: [snapped, ...base.inkStrokes.skip(1)],
      );
      final sampled = PlannedLine(
        id: 'p/0',
        pageId: 'p',
        line: shifted,
        words: line.words,
        text: line.text,
        confidence: line.confidence,
        dominantColor: line.dominantColor,
        strokeIds: line.strokeIds,
        lowConfidence: false,
      );
      final l = single(sampled);
      final points = ((l['strokes'] as List).first as Map)['points'] as List;
      expect((points.first as List).first, closeTo(first.raw.first.x, 0.01));
    });

    test('the picture is the model input, pixel for pixel, with how it was made', () {
      final image = imageOf(5);
      final l = single(plannedLine(['hello']), [image]);
      final images = (l['images'] as List).cast<Map<String, dynamic>>();
      expect(images, hasLength(1));
      final img = images.single;
      expect(img['scale'], 2.5);
      expect(img['strokeWidthPx'], 2);
      expect(img['originX'], 12.5);
      expect(img['angle'], 0.25);
      expect((img['width'], img['height']), (testImageWidth, wordImageHeight));
      final (iw, ih, pixels) = decodeGrayPng(base64Decode(img['png'] as String));
      expect((iw, ih), (testImageWidth, wordImageHeight));
      expect(pixels, image.pixels);
    });

    test('a very wide line has all its pictures, in order', () {
      final l = single(plannedLine(['hello']), [imageOf(1), imageOf(2), imageOf(3)]);
      final images = (l['images'] as List).cast<Map<String, dynamic>>();
      expect(images, hasLength(3));
      final firstPixels = [
        for (final i in images)
          decodeGrayPng(base64Decode(i['png'] as String)).$3.first,
      ];
      expect(firstPixels, [for (final seed in [1, 2, 3]) imageOf(seed).pixels.first]);
    });

    test('a line without a picture still has its entry', () {
      final l = single(plannedLine(['hello']), const []);
      expect(l['images'], isEmpty);
      expect(l['recognizedText'], 'hello');
      expect(l['strokes'], isNotEmpty);
    });

    test('a picture that does not fit its size is left out, not written wrong', () {
      final broken = LineImage(
        pixels: Uint8List(10),
        width: testImageWidth,
        scale: 1,
        strokeWidthPx: 1,
        strokes: const [],
        angle: 0,
        originX: 0,
      );
      expect(single(plannedLine(['hello']), [broken])['images'], isEmpty);
    });

    test('an unticked line says so', () {
      final line = plannedLine(['hello'])..include = false;
      expect(single(line)['lineIncluded'], isFalse);
    });

    test('the file name has the date and time', () {
      expect(samplesFileName(DateTime(2026, 10, 27, 9, 5)),
          'mariams-notes-samples-20261027-0905.json');
      expect(samplesFileName(DateTime(2027, 1, 2, 23, 59)),
          'mariams-notes-samples-20270102-2359.json');
    });
  });

  group('in the review sheet', () {
    testWidgets('alternative readings show as chips (at most four) and replace the word',
        (tester) async {
      final fake = reader();
      fake.alternatives['aw0'] = ['hallo', 'hello', 'jello', 'hella', 'hells', 'extra'];
      fake.alternatives['aw1'] = ['online', 'on line'];
      final h = await ConvertHarness.open(tester,
          pages: [threeLines()], recognizer: fake);
      await h.tapConvert();
      await tester.tap(key('convert-debug-toggle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Not the reading in use, no repeats, best first, four at most.
      expect(
          [for (var a = 0; a < 4; a++) tester.widget<ActionChip>(key('convert-alt-0-$a')).label]
              .map((t) => (t as Text).data),
          ['hallo', 'jello', 'hella', 'hells']);
      expect(key('convert-alt-0-4'), findsNothing);
      expect(find.text('extra'), findsNothing);
      // The second word: only "on line" is different from what was read.
      expect(find.text('on line'), findsOneWidget);
      expect(key('convert-alt-1-1'), findsNothing);
      // Words without alternatives have no chips at all.
      expect(key('convert-alt-2-0'), findsNothing);

      await tester.tap(key('convert-alt-0-1'));
      await tester.pump();
      expect(fieldText(tester, 0), 'jello online');
      await tester.tap(key('convert-alt-0-0'));
      await tester.pump();
      expect(fieldText(tester, 0), 'hallo online');
      await tester.tap(find.text('on line'));
      await tester.pump();
      expect(fieldText(tester, 0), 'hallo on line');

      await tester.tap(key('convert-apply'));
      await settle(tester);
      expect(h.page.texts.first.text, 'hallo on line');
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('picking an alternative still finds the word after the text was edited',
        (tester) async {
      final fake = reader();
      fake.alternatives['aw1'] = ['onlyne'];
      final h = await ConvertHarness.open(tester,
          pages: [threeLines()], recognizer: fake);
      await h.tapConvert();
      await tester.tap(key('convert-debug-toggle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(key('convert-text-0'), 'well online here');
      await tester.pump();
      await tester.tap(find.text('onlyne'));
      await tester.pump();
      expect(fieldText(tester, 0), 'well onlyne here');

      // A word that can no longer be found is left alone.
      await tester.enterText(key('convert-text-0'), 'something else entirely');
      await tester.pump();
      await tester.tap(find.text('onlyne'));
      await tester.pump();
      expect(fieldText(tester, 0), 'something else entirely');
    });

    testWidgets('no alternatives at all: nothing breaks', (tester) async {
      final h = await ConvertHarness.open(tester,
          pages: [threeLines()], recognizer: reader());
      await h.tapConvert();
      await tester.tap(key('convert-debug-toggle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ActionChip), findsNothing);
      expect(key('convert-word-0'), findsOneWidget);
    });

    testWidgets('corrected words go to the personal dictionary when converting',
        (tester) async {
      final h = await ConvertHarness.open(tester,
          pages: [threeLines()], recognizer: reader());
      await h.tapConvert();
      await tester.enterText(key('convert-text-0'), 'Hello online'); // a capital
      await tester.enterText(key('convert-text-1'), 'second line'); // words added
      await tester.enterText(key('convert-text-2'), 'th1rd'); // not a word
      await tester.pump();
      expect(h.learner.words, isEmpty, reason: 'nothing before converting');

      await tester.tap(key('convert-apply'));
      await settle(tester);
      expect(h.learner.words, ['Hello']);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('names are learned; unticked lines and cancelled sheets teach nothing',
        (tester) async {
      final h = await ConvertHarness.open(tester,
          pages: [threeLines()],
          recognizer: reader({'bw0': ('mariem', 0.9), 'cw0': ('anne', 0.9)}));
      await h.tapConvert();
      await tester.enterText(key('convert-text-1'), 'Mariam');
      await tester.enterText(key('convert-text-2'), 'Anne-Marie');
      await tester.tap(key('convert-include-2'));
      await tester.pump();
      await tester.tap(key('convert-close'));
      await settle(tester);
      expect(h.learner.words, isEmpty);

      await h.tapConvert();
      await tester.enterText(key('convert-text-1'), 'Mariam');
      await tester.enterText(key('convert-text-2'), 'Anne-Marie');
      await tester.tap(key('convert-include-2'));
      await tester.pump();
      await tester.tap(key('convert-apply'));
      await settle(tester);
      expect(h.learner.words, ['Mariam'], reason: 'the unticked line stays ink');
      await tester.pump(const Duration(seconds: 6));
    });

    group('spelling fixes and the personal dictionary', () {
      const capital = PolishSuggestion(
        original: 'hello',
        replacement: 'Hello',
        kind: PolishKind.capitalization,
        reason: 'Capital letter',
        start: 0,
        end: 5,
      );

      FakeRecognizer suggesting() => reader()..suggestions['aw0'] = [capital];

      testWidgets('accepting a suggested fix teaches nothing', (tester) async {
        final h = await ConvertHarness.open(tester,
            pages: [threeLines()], recognizer: suggesting());
        await h.tapConvert();
        await tester.tap(key('convert-suggest-0-0'));
        await tester.pump();
        expect(fieldText(tester, 0), 'Hello online');

        await tester.tap(key('convert-apply'));
        await settle(tester);
        expect(h.page.texts.first.text, 'Hello online');
        expect(h.learner.words, isEmpty,
            reason: 'taking a fix is not a correction of the recogniser');
        await tester.pump(const Duration(seconds: 6));
      });

      testWidgets('typing the same capital by hand does teach it (for comparison)',
          (tester) async {
        final h = await ConvertHarness.open(tester,
            pages: [threeLines()], recognizer: reader());
        await h.tapConvert();
        await tester.enterText(key('convert-text-0'), 'Hello online');
        await tester.pump();
        await tester.tap(key('convert-apply'));
        await settle(tester);
        expect(h.learner.words, ['Hello']);
        await tester.pump(const Duration(seconds: 6));
      });

      testWidgets('a word the user rewrites after accepting a fix is still learned',
          (tester) async {
        final h = await ConvertHarness.open(tester,
            pages: [threeLines()], recognizer: suggesting());
        await h.tapConvert();
        await tester.tap(key('convert-suggest-0-0'));
        await tester.pump();
        await tester.enterText(key('convert-text-0'), 'Hello onlinne');
        await tester.pump();
        await tester.tap(key('convert-apply'));
        await settle(tester);
        expect(h.learner.words, ['onlinne']);
        await tester.pump(const Duration(seconds: 6));
      });

      testWidgets('fixes applied by the setting teach nothing either, and the setting is used',
          (tester) async {
        final h = await ConvertHarness.open(tester,
            pages: [threeLines()],
            recognizer: suggesting(),
            prefsValues: {
              AppSettings.prefsKey: jsonEncode({'autoFixSpelling': true}),
            });
        await h.tapConvert();
        expect(fieldText(tester, 0), 'Hello online');
        await tester.tap(key('convert-apply'));
        await settle(tester);
        expect(h.page.texts.first.text, 'Hello online');
        expect(h.learner.words, isEmpty);
        await tester.pump(const Duration(seconds: 6));
      });

      testWidgets('a fix that was undone is not applied, and the rest is still learned',
          (tester) async {
        final h = await ConvertHarness.open(tester,
            pages: [threeLines()],
            recognizer: suggesting(),
            prefsValues: {
              AppSettings.prefsKey: jsonEncode({'autoFixSpelling': true}),
            });
        await h.tapConvert();
        await tester.tap(key('convert-undo-0-0'));
        await tester.pump();
        expect(fieldText(tester, 0), 'hello online');
        await tester.enterText(key('convert-text-0'), 'hello onlinne');
        await tester.pump();
        await tester.tap(key('convert-apply'));
        await settle(tester);
        expect(h.page.texts.first.text, 'hello onlinne');
        expect(h.learner.words, ['onlinne']);
        await tester.pump(const Duration(seconds: 6));
      });
    });

    testWidgets('Share samples builds one file and opens the share sheet',
        (tester) async {
      final fake = reader();
      fake.alternatives['aw0'] = ['hallo'];
      final h = await ConvertHarness.open(tester,
          pages: [threeLines()], recognizer: fake);
      await h.tapConvert();
      await tester.enterText(key('convert-text-0'), 'Hello online');
      await tester.pump();

      expect(find.text('Share samples for improving recognition'), findsOneWidget);
      expect(find.textContaining('Nothing is sent unless you pick'), findsOneWidget);
      await tester.ensureVisible(key('convert-share-samples'));
      await tester.tap(key('convert-share-samples'));
      await settle(tester);

      expect(h.share.shared, hasLength(1));
      final shared = h.share.shared.single;
      expect(shared.fileName,
          matches(RegExp(r'^mariams-notes-samples-\d{8}-\d{4}\.json$')));
      final json = jsonDecode(shared.json) as Map<String, dynamic>;
      expect(json['format'], 2);
      expect(json['appVersion'], isA<String>());
      expect(json['lineCount'], 3);
      final lines = (json['lines'] as List).cast<Map<String, dynamic>>();
      expect(lines.map((l) => l['recognizedText']),
          ['hello online', 'second', 'third']);
      expect(lines.map((l) => l['finalText']),
          ['Hello online', 'second', 'third']);
      expect(lines.map((l) => l['corrected']), [true, false, false]);
      expect(lines.map((l) => (l['page'], l['line'])), [(1, 0), (1, 1), (1, 2)]);
      final words = (lines[0]['words'] as List).cast<Map<String, dynamic>>();
      expect(words.map((w) => w['text']), ['hello', 'online']);
      expect(words.first['alternatives'], ['hallo']);
      // Every pen stroke of the line, the i's dot too.
      expect(lines.map((l) => (l['strokes'] as List).length), [5 + 7, 5, 5]);
      // The picture is what the recogniser got: the whole line, ink on white.
      final image = (lines[0]['images'] as List).single as Map<String, dynamic>;
      final (w, hh, pixels) = decodeGrayPng(base64Decode(image['png'] as String));
      expect((w, hh), (image['width'], wordImageHeight));
      expect(w, greaterThanOrEqualTo(wordImageMinWidth));
      expect(pixels.any((v) => v < 100), isTrue);
      expect(pixels.any((v) => v == 255), isTrue);

      expect(find.text('Thank you! The samples file was shared.'), findsOneWidget);
      // Sharing changed nothing in the notebook.
      expect(h.page.texts, isEmpty);
      expect(h.undoDepth, 0);
      expect(key('convert-sheet'), findsOneWidget);
    });

    testWidgets('dismissing the share sheet is not an error; a failure says so',
        (tester) async {
      final h = await ConvertHarness.open(tester,
          pages: [threeLines()], recognizer: reader());
      await h.tapConvert();
      h.share.answer = false;
      await tester.ensureVisible(key('convert-share-samples'));
      await tester.tap(key('convert-share-samples'));
      await settle(tester);
      expect(h.share.shared, hasLength(1));
      expect(find.textContaining('Nothing is sent unless you pick'), findsOneWidget);

      h.share.error = StateError('disk full');
      await tester.tap(key('convert-share-samples'));
      await settle(tester);
      expect(find.text("Couldn't prepare the samples. Please try again."),
          findsOneWidget);
      expect(tester.widget<TextButton>(key('convert-share-samples')).onPressed,
          isNotNull, reason: 'try again is possible');
    });

    test('the auto-convert tuning numbers live in the config class', () {
      expect(ConvertConfig.autoMinConfidence, 0.25);
      expect(ConvertConfig.autoIdleMs, 2000);
      expect(ConvertConfig.mergeBaselineTol, 0.6);
      expect(ConvertConfig.mergeMaxGap, 2.5);
    });
  });
}
