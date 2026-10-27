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
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/recognition/htr_channel.dart';
import 'package:neatink/recognition/stroke_grouping.dart';
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

/// A recognised line of [texts] (one word each) as the review sheet holds it.
PlannedLine plannedLine(List<String> texts,
    {String id = 'p/0', List<List<String>>? alternatives}) {
  final strokes = writeLine('a', [for (final _ in texts) 'hello'], y: 104);
  final line = groupStrokes(strokes).single;
  expect(line.words, hasLength(texts.length));
  return plannedLineFrom(
    id: id,
    pageId: 'p',
    line: line,
    words: [
      for (var i = 0; i < texts.length; i++)
        WordResult(
          group: line.words[i],
          text: texts[i],
          confidence: 0.8,
          raw: '${texts[i]}~',
          alternatives: alternatives?[i] ?? const [],
        ),
    ],
  );
}

const int testImageWidth = 100;

WordImage imageOf(int seed) => WordImage(
      pixels: Uint8List.fromList([
        for (var i = 0; i < testImageWidth * wordImageHeight; i++)
          (i * 7 + seed) % 256,
      ]),
      width: testImageWidth,
      scale: 2.5,
      strokeWidthPx: 2,
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
    test('has the format, version, and one entry per word', () {
      final l1 = plannedLine(['hello', 'online']);
      final l2 = plannedLine(['third'], id: 'p/1');
      final json = buildSamplesJson(
        appVersion: '1.1.0+2',
        createdAt: DateTime.utc(2026, 10, 27, 9, 30),
        lines: [
          SampleLineInput(line: l1, pageIndex: 0, images: [imageOf(1), imageOf(2)]),
          SampleLineInput(line: l2, pageIndex: 2, images: [imageOf(3)]),
        ],
      );
      expect(json['format'], 1);
      expect(json['appVersion'], '1.1.0+2');
      expect(json['createdAt'], '2026-10-27T09:30:00.000Z');
      expect(json['wordCount'], 3);
      expect(json['image'], containsPair('encoding', 'png-gray8-base64'));
      expect(json['image'], containsPair('height', wordImageHeight));
      final words = (json['words'] as List).cast<Map<String, dynamic>>();
      expect(words, hasLength(3));
      expect(words.map((w) => (w['page'], w['line'], w['wordInLine'])), [
        (1, 0, 0),
        (1, 0, 1),
        (3, 0, 0),
      ]);
      expect(words.map((w) => w['wordsInLine']), [2, 2, 1]);
      // It really is JSON.
      expect(jsonDecode(encodeSamplesJson(json)), json);
    });

    test('a corrected line is split back to the words it was read from', () {
      final line = plannedLine(['hello', 'onlyne']);
      line.text = 'Hello online';
      final json = buildSamplesJson(
        appVersion: 'x',
        createdAt: DateTime.utc(2026),
        lines: [
          SampleLineInput(line: line, pageIndex: 0, images: [imageOf(1), imageOf(2)]),
        ],
      );
      final words = (json['words'] as List).cast<Map<String, dynamic>>();
      expect(words[0]['finalText'], 'Hello');
      expect(words[0]['read'], 'hello');
      expect(words[0]['raw'], 'hello~');
      expect(words[0]['corrected'], isTrue);
      expect(words[1]['finalText'], 'online');
      expect(words[1]['read'], 'onlyne');
      expect(words[1]['corrected'], isTrue);
      expect(words[0]['lineText'], 'Hello online');
      expect(words[0]['lineIncluded'], isTrue);
      expect(words[0]['confidence'], 0.8);
    });

    test('an untouched line has no corrections', () {
      final line = plannedLine(['hello', 'online']);
      final json = buildSamplesJson(
        appVersion: 'x',
        createdAt: DateTime.utc(2026),
        lines: [
          SampleLineInput(line: line, pageIndex: 0, images: [imageOf(1), imageOf(2)]),
        ],
      );
      for (final w in (json['words'] as List).cast<Map<String, dynamic>>()) {
        expect(w['corrected'], isFalse);
        expect(w['finalText'], w['read']);
      }
    });

    test('when the word count changed only the line text is given', () {
      final line = plannedLine(['hello', 'online']);
      line.text = 'Hello on line';
      final json = buildSamplesJson(
        appVersion: 'x',
        createdAt: DateTime.utc(2026),
        lines: [
          SampleLineInput(line: line, pageIndex: 0, images: [imageOf(1), imageOf(2)]),
        ],
      );
      for (final w in (json['words'] as List).cast<Map<String, dynamic>>()) {
        expect(w['finalText'], isNull);
        expect(w['corrected'], isFalse);
        expect(w['lineText'], 'Hello on line');
        expect(w['read'], isNotEmpty);
        expect(w['raw'], isNotEmpty);
      }
    });

    test('carries the pen data, line geometry, alternatives and the picture', () {
      final line = plannedLine(['hello'], alternatives: [
        ['hallo', 'jello'],
      ]);
      final image = imageOf(5);
      final json = buildSamplesJson(
        appVersion: 'x',
        createdAt: DateTime.utc(2026),
        lines: [
          SampleLineInput(line: line, pageIndex: 0, images: [image]),
        ],
      );
      final w = (json['words'] as List).single as Map<String, dynamic>;
      expect(w['alternatives'], ['hallo', 'jello']);
      expect(w['xHeight'], closeTo(line.line.xHeight, 0.01));
      expect(w['baselineSlope'], closeTo(line.line.baselineSlope, 1e-5));
      final b = line.words.single.group.bounds;
      expect(w['bounds'], [
        closeTo(b.left, 0.01),
        closeTo(b.top, 0.01),
        closeTo(b.right, 0.01),
        closeTo(b.bottom, 0.01),
      ]);

      final strokes = (w['strokes'] as List).cast<Map<String, dynamic>>();
      final source = line.words.single.group.strokes;
      expect(strokes, hasLength(source.length));
      expect(strokes.first['id'], source.first.id);
      expect(strokes.first['size'], source.first.size);
      final points = strokes.first['points'] as List;
      expect(points, hasLength(source.first.raw.length));
      final p0 = source.first.raw.first;
      expect(points.first, [
        closeTo(p0.x, 0.01),
        closeTo(p0.y, 0.01),
        closeTo(p0.pressure, 0.001),
        p0.t,
      ]);

      final img = w['image'] as Map<String, dynamic>;
      expect(img['scale'], 2.5);
      expect((img['width'], img['height']), (testImageWidth, wordImageHeight));
      final (iw, ih, pixels) =
          decodeGrayPng(base64Decode(img['png'] as String));
      expect((iw, ih), (testImageWidth, wordImageHeight));
      expect(pixels, image.pixels);
    });

    test('a word without a picture still has its entry', () {
      final line = plannedLine(['hello']);
      final json = buildSamplesJson(
        appVersion: 'x',
        createdAt: DateTime.utc(2026),
        lines: [SampleLineInput(line: line, pageIndex: 0, images: const [])],
      );
      expect(((json['words'] as List).single as Map)['image'], isNull);
    });

    test('an unticked line says so', () {
      final line = plannedLine(['hello'])..include = false;
      final json = buildSamplesJson(
        appVersion: 'x',
        createdAt: DateTime.utc(2026),
        lines: [SampleLineInput(line: line, pageIndex: 0, images: [imageOf(1)])],
      );
      expect(((json['words'] as List).single as Map)['lineIncluded'], isFalse);
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
      expect(json['format'], 1);
      expect(json['appVersion'], isA<String>());
      final words = (json['words'] as List).cast<Map<String, dynamic>>();
      expect(words.map((w) => w['read']), ['hello', 'online', 'second', 'third']);
      expect(words.map((w) => w['finalText']),
          ['Hello', 'online', 'second', 'third']);
      expect(words[0]['corrected'], isTrue);
      expect(words[0]['alternatives'], ['hallo']);
      expect(words[2]['line'], 1);
      // The picture is what the recogniser got: ink on white.
      final image = words[0]['image'] as Map<String, dynamic>;
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
      expect(ConvertConfig.autoMinConfidence, 0.5);
      expect(ConvertConfig.autoIdleMs, 1000);
      expect(ConvertConfig.mergeBaselineTol, 0.6);
      expect(ConvertConfig.mergeMaxGap, 2.5);
    });
  });
}
