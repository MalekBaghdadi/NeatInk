import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/notebook_meta.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/line_style.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/pdf/export_builder.dart';
import 'package:neatink/render/paper_painter.dart' show pdfMarginEdgeColor;
import 'package:neatink/pdf/pdf_export_request.dart';
import 'package:neatink/render/stroke_outline.dart';

Stroke stroke(String id, StrokeTool tool, {int color = 0xFF112233}) => Stroke(
      id: id,
      tool: tool,
      color: color,
      size: 3,
      raw: [
        for (var i = 0; i < 12; i++)
          InkPoint(20.0 + i * 8, 40.0 + (i.isEven ? 3 : -3), 0.6, i * 10),
      ],
    );

String assetPath(String a) => '/assets/$a';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildExportPage (ink)', () {
    test('splits highlighter and pen strokes and keeps order', () {
      final page = buildExportPage(
        const PageMeta(id: 'p'),
        PageContent(strokes: [
          stroke('a', StrokeTool.pen, color: 0xFF000001),
          stroke('b', StrokeTool.highlighter, color: 0xFFFFEE00),
          stroke('c', StrokeTool.pen, color: 0xFF000002),
        ]),
        exportPaperLines: false,
        assetPath: assetPath,
      );
      expect(page.ink, hasLength(2));
      expect(page.highlighter, hasLength(1));
      expect(page.ink[0].color & 0xFFFFFF, 0x000001);
      expect(page.ink[1].color & 0xFFFFFF, 0x000002);
    });

    test('highlighter fill is translucent, pen fill is opaque', () {
      final page = buildExportPage(
        const PageMeta(id: 'p'),
        PageContent(strokes: [
          stroke('a', StrokeTool.pen),
          stroke('b', StrokeTool.highlighter),
        ]),
        exportPaperLines: false,
        assetPath: assetPath,
      );
      expect(page.ink.single.color >>> 24, 0xFF);
      final alpha = page.highlighter.single.color >>> 24;
      expect(alpha, inInclusiveRange(40, 140)); // about 0.35
    });

    test('outlines are flat float lists with at least three vertices', () {
      final page = buildExportPage(
        const PageMeta(id: 'p'),
        PageContent(strokes: [stroke('a', StrokeTool.pen)]),
        exportPaperLines: false,
        assetPath: assetPath,
      );
      final xy = page.ink.single.xy;
      expect(xy, isA<Float32List>());
      expect(xy.length.isEven, isTrue);
      expect(xy.length ~/ 2, greaterThanOrEqualTo(3));
      for (var i = 0; i < xy.length; i += 2) {
        expect(xy[i], inInclusiveRange(10, 125));
        expect(xy[i + 1], inInclusiveRange(30, 55));
      }
    });

    group('line styles', () {
      /// A 200 pt horizontal pen line, in [style].
      Stroke styled(
        String id,
        LineStyle style, {
        StrokeTool tool = StrokeTool.pen,
        double concentration = 1,
        int color = 0xFF112233,
      }) =>
          Stroke(
            id: id,
            tool: tool,
            penStyle: PenStyle.technical,
            color: color,
            size: 2,
            raw: [
              for (var x = 0.0; x <= 200; x += 2) InkPoint(x, 100, 0.5, x.round()),
            ],
            line: LineSettings(style: style),
            concentration: concentration,
          );

      ExportPage export(List<Stroke> strokes) => buildExportPage(
            const PageMeta(id: 'p'),
            PageContent(strokes: strokes),
            exportPaperLines: false,
            assetPath: assetPath,
          );

      test('a dashed stroke exports one polygon per dash, all one colour', () {
        final page = export([styled('a', LineStyle.dashed)]);
        expect(page.ink.length, greaterThan(10));
        expect(page.highlighter, isEmpty);
        for (final polygon in page.ink) {
          expect(polygon.xy.length ~/ 2, greaterThanOrEqualTo(3));
          expect(polygon.color, 0xFF112233);
        }
        // Left to right, the dashes cover the whole 200 pt (plus the pen).
        expect(page.ink.first.xy.reduce(math.min), closeTo(-1, 0.1));
        expect(page.ink.last.xy.reduce(math.max), closeTo(201, 0.1));
      });

      test('the polygons are exactly the ones the screen fills', () {
        for (final style in LineStyle.values) {
          final s = styled('a', style);
          final page = export([s]);
          final screen = cachedStrokeOutlines(s);
          expect(page.ink, hasLength(screen.length), reason: style.name);
          for (var i = 0; i < screen.length; i++) {
            expect(page.ink[i].xy.length, screen[i].length * 2,
                reason: '${style.name} #$i');
            expect(page.ink[i].xy[0], closeTo(screen[i].first.dx, 1e-3));
            expect(page.ink[i].xy[1], closeTo(screen[i].first.dy, 1e-3));
          }
        }
      });

      test('dotted, wavy and double strokes export their own polygons', () {
        expect(export([styled('a', LineStyle.dotted)]).ink.length, greaterThan(30));
        expect(export([styled('a', LineStyle.wavy)]).ink, hasLength(1));
        expect(export([styled('a', LineStyle.zigzag)]).ink, hasLength(1));
        expect(export([styled('a', LineStyle.parallel)]).ink, hasLength(2));
        expect(export([styled('a', LineStyle.solid)]).ink, hasLength(1));
      });

      test('the concentration is in the colour of every polygon', () {
        final page = export([styled('a', LineStyle.dashed, concentration: 0.5)]);
        expect(page.ink, isNotEmpty);
        for (final polygon in page.ink) {
          expect(polygon.color >>> 24, closeTo(128, 1));
          expect(polygon.color & 0xFFFFFF, 0x112233);
        }
      });

      test('a styled highlighter goes under the text with its own opacity', () {
        final page = export([
          styled('a', LineStyle.dashed,
              tool: StrokeTool.highlighter, concentration: 0.5, color: 0xFFFFE600),
          styled('b', LineStyle.wavy),
        ]);
        expect(page.ink, hasLength(1));
        expect(page.highlighter.length, greaterThan(5));
        for (final polygon in page.highlighter) {
          // 35% of 50%
          expect(polygon.color >>> 24, closeTo(255 * 0.35 * 0.5, 1));
        }
      });

      test('strokes keep their order and a solid one is one polygon, as before', () {
        final page = export([
          styled('a', LineStyle.solid, color: 0xFF000001),
          styled('b', LineStyle.dashed, color: 0xFF000002),
          styled('c', LineStyle.solid, color: 0xFF000003),
        ]);
        final colors = [for (final p in page.ink) p.color & 0xFFFFFF];
        expect(colors.first, 1);
        expect(colors.last, 3);
        expect(colors.where((c) => c == 2).length, greaterThan(5));
        expect(colors.where((c) => c == 1), hasLength(1));
        expect(colors.indexOf(2), 1);
      });
    });

    test('a stroke without points produces no polygon', () {
      final page = buildExportPage(
        const PageMeta(id: 'p'),
        PageContent(strokes: [
          Stroke(
              id: 'e',
              tool: StrokeTool.pen,
              color: 0xFF000000,
              size: 2,
              raw: const []),
        ]),
        exportPaperLines: false,
        assetPath: assetPath,
      );
      expect(page.ink, isEmpty);
    });
  });

  group('buildExportPage (pages)', () {
    test('a PDF page keeps its index and has no paper', () {
      final page = buildExportPage(
        const PageMeta(id: 'p', width: 612, height: 792, pdfPageIndex: 3),
        PageContent(),
        exportPaperLines: true,
        assetPath: assetPath,
      );
      expect(page.pdfPageIndex, 3);
      expect(page.background, isNull);
      expect(page.lines, isEmpty);
      expect(page.dots, isEmpty);
      expect(page.width, 612);
      expect(page.height, 792);
    });

    test('a PDF page with margins: wider page, paper only beside the PDF', () {
      const meta = PageMeta(
          id: 'p',
          width: 1000,
          height: 600,
          pdfPageIndex: 0,
          marginLeft: 150,
          marginRight: 250,
          paper: Paper(type: PaperType.lined, color: Paper.cream));
      final page = buildExportPage(meta, PageContent(),
          exportPaperLines: true, assetPath: assetPath);
      expect(page.pdfPageIndex, 0);
      expect(page.width, 1000);
      expect((page.marginLeft, page.marginRight), (150, 250));
      expect(page.background, Paper.cream);
      final ruled = page.lines.where((l) => l.y1 == l.y2).toList();
      expect(ruled, isNotEmpty);
      // Every ruled line stays in a margin, never over the PDF page.
      for (final l in ruled) {
        final inLeft = l.x1 >= 0 && l.x2 <= 150;
        final inRight = l.x1 >= 750 && l.x2 <= 1000;
        expect(inLeft || inRight, isTrue, reason: '${l.x1}..${l.x2}');
      }
      expect(ruled.any((l) => l.x1 == 0 && l.x2 == 150), isTrue);
      expect(ruled.any((l) => l.x1 == 750 && l.x2 == 1000), isTrue);
      // Hairlines along the PDF page's edges.
      final edges = page.lines.where((l) => l.x1 == l.x2 && l.color == pdfMarginEdgeColor).map((l) => l.x1);
      expect(edges, containsAll([150.0, 750.0]));
      expect(page.toMap()['marginLeft'], 150);

      final plain = buildExportPage(meta, PageContent(),
          exportPaperLines: false, assetPath: assetPath);
      expect(plain.lines.where((l) => l.y1 == l.y2), isEmpty, reason: 'no ruling when not asked');
      expect(plain.lines, hasLength(2), reason: 'the edges stay');
    });

    test('a lined page gets background and ruling only when asked', () {
      const meta = PageMeta(
          id: 'p', paper: Paper(type: PaperType.lined, color: Paper.cream));
      final withLines = buildExportPage(meta, PageContent(),
          exportPaperLines: true, assetPath: assetPath);
      final without = buildExportPage(meta, PageContent(),
          exportPaperLines: false, assetPath: assetPath);
      expect(withLines.pdfPageIndex, isNull);
      expect(withLines.background, Paper.cream);
      expect(withLines.lines, isNotEmpty);
      expect(without.background, Paper.cream);
      expect(without.lines, isEmpty);
    });

    test('a blank page has no ruling even when asked', () {
      final page = buildExportPage(
        const PageMeta(id: 'p', paper: Paper(type: PaperType.blank)),
        PageContent(),
        exportPaperLines: true,
        assetPath: assetPath,
      );
      expect(page.lines, isEmpty);
      expect(page.dots, isEmpty);
    });

    test('dotted paper exports dot centres as pairs', () {
      final page = buildExportPage(
        const PageMeta(id: 'p', paper: Paper(type: PaperType.dotted)),
        PageContent(),
        exportPaperLines: true,
        assetPath: assetPath,
      );
      expect(page.dots, isNotEmpty);
      expect(page.dots.length.isEven, isTrue);
      expect(page.dotRadius, greaterThan(0));
    });

    test('images resolve through assetPath and empty ones are dropped', () {
      final page = buildExportPage(
        const PageMeta(id: 'p'),
        PageContent(images: const [
          ImageItem(
              id: 'i1', x: 10, y: 20, width: 100, height: 50, asset: 'a.png'),
          ImageItem(
              id: 'i2', x: 0, y: 0, width: 0, height: 50, asset: 'b.png'),
        ]),
        exportPaperLines: false,
        assetPath: assetPath,
      );
      expect(page.images, hasLength(1));
      expect(page.images.single.path, '/assets/a.png');
      expect(page.images.single.width, 100);
    });
  });

  group('exportTextItem', () {
    test('lays out text lines inside the box at the right place', () {
      const item = TextItem(
          id: 't',
          x: 50,
          y: 100,
          width: 300,
          height: 40,
          text: 'Hello world',
          fontSize: 16,
          color: 0xFF336699,
          bold: true,
          underline: true,
          font: FontKind.serif);
      final out = exportTextItem(item);
      expect(out.background, isNull);
      expect(out.lines, hasLength(1));
      final line = out.lines.single;
      expect(line.text, 'Hello world');
      expect(line.x, closeTo(50, 1));
      expect(line.baselineY, greaterThan(100));
      expect(line.baselineY, lessThan(100 + 16 * 1.6));
      expect(line.fontSize, 16);
      expect(line.bold, isTrue);
      expect(line.underline, isTrue);
      expect(line.font, FontKind.serif);
      expect(line.color, 0xFF336699);
      expect(line.width, greaterThan(20));
      expect(line.width, lessThan(300));
    });

    test('exported lines name the registry font file to embed', () {
      const item = TextItem(
          id: 't',
          x: 0,
          y: 0,
          width: 300,
          height: 40,
          text: 'Hello world',
          fontSize: 16,
          italic: true,
          font: FontKind.openSans);
      final line = exportTextItem(item).lines.single;
      expect(line.font, FontKind.openSans);
      final map = line.toMap();
      expect(map['font'], 'open_sans');
      expect(map['fontAsset'], 'assets/fonts/OpenSans/OpenSans-Italic.ttf');
      expect(map['fontAssetItalic'], true);
      expect(map['fontAssetBold'], false);
    });

    test('long text wraps into several lines going down the page', () {
      const item = TextItem(
          id: 't',
          x: 0,
          y: 0,
          width: 80,
          height: 100,
          text: 'one two three four five six seven eight nine ten');
      final lines = exportTextItem(item).lines;
      expect(lines.length, greaterThan(2));
      for (var i = 1; i < lines.length; i++) {
        expect(lines[i].baselineY, greaterThan(lines[i - 1].baselineY));
      }
      expect(lines.map((l) => l.text).join(' '),
          'one two three four five six seven eight nine ten');
    });

    test('a background colour yields a rectangle, blank text no lines', () {
      const item = TextItem(
          id: 't',
          x: 5,
          y: 6,
          width: 100,
          height: 30,
          text: '   ',
          background: 0xFFFFFF00);
      final out = exportTextItem(item);
      expect(out.lines, isEmpty);
      expect(out.background, isNotNull);
      expect(out.background!.x, 5);
      expect(out.background!.y, 6);
      expect(out.background!.width, 100);
      expect(out.background!.height, greaterThanOrEqualTo(30));
    });

    test('text and its background land on the page', () {
      final page = buildExportPage(
        const PageMeta(id: 'p'),
        PageContent(texts: const [
          TextItem(
              id: 't',
              x: 10,
              y: 10,
              width: 200,
              height: 20,
              text: 'Note',
              background: 0x80FFFFFF),
        ]),
        exportPaperLines: false,
        assetPath: assetPath,
      );
      expect(page.textRects, hasLength(1));
      expect(page.textLines, hasLength(1));
    });
  });
}
