import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/ink/affine2.dart';
import 'package:neatink/ink/vec2.dart';
import 'package:neatink/pdf/pdf_coords.dart';

Vec2 map(Affine2 m, double x, double y) => m.apply(Vec2(x, y));

void expectPoint(Vec2 p, double x, double y) {
  expect(p.x, closeTo(x, 1e-9), reason: 'x of $p');
  expect(p.y, closeTo(y, 1e-9), reason: 'y of $p');
}

void main() {
  group('visiblePdfBox', () {
    const media = PdfBox(0, 0, 612, 792);

    test('uses the MediaBox when there is no CropBox', () {
      expect(visiblePdfBox(media, null), media);
    });

    test('uses the CropBox clipped to the MediaBox', () {
      const crop = PdfBox(-10, 20, 300, 900);
      expect(visiblePdfBox(media, crop), const PdfBox(0, 20, 300, 792));
    });

    test('falls back to the MediaBox for an empty intersection or CropBox', () {
      expect(visiblePdfBox(media, const PdfBox(700, 0, 800, 100)), media);
      expect(visiblePdfBox(media, const PdfBox(5, 5, 5, 50)), media);
    });

    test('falls back to US Letter without a usable MediaBox', () {
      expect(visiblePdfBox(null, null), letterPdfBox);
      expect(visiblePdfBox(const PdfBox(0, 0, 0, 0), null), letterPdfBox);
    });

    test('fromCorners orders swapped corners', () {
      expect(PdfBox.fromCorners(100, 200, 10, 20),
          const PdfBox(10, 20, 100, 200));
    });
  });

  group('pdfQuarterTurns', () {
    test('matches PDFium for the usual values', () {
      expect(pdfQuarterTurns(0), 0);
      expect(pdfQuarterTurns(90), 1);
      expect(pdfQuarterTurns(180), 2);
      expect(pdfQuarterTurns(270), 3);
      expect(pdfQuarterTurns(360), 0);
      expect(pdfQuarterTurns(450), 1);
      expect(pdfQuarterTurns(-90), 3);
    });

    test('truncates values that are not multiples of 90', () {
      expect(pdfQuarterTurns(45), 0);
      expect(pdfQuarterTurns(135), 1);
    });
  });

  group('displayedPdfPageSize', () {
    const box = PdfBox(0, 0, 200, 100);
    test('swaps width and height for odd turns', () {
      expect(displayedPdfPageSize(box, 0).width, 200);
      expect(displayedPdfPageSize(box, 1).width, 100);
      expect(displayedPdfPageSize(box, 1).height, 200);
      expect(displayedPdfPageSize(box, 2).height, 100);
      expect(displayedPdfPageSize(box, 3).width, 100);
    });
  });

  group('appToPdfMatrix', () {
    // A 200 x 100 pt page whose CropBox starts at (10, 20).
    const box = PdfBox(10, 20, 210, 120);

    Affine2 matrixFor(int turns) {
      final shown = displayedPdfPageSize(box, turns);
      return appToPdfMatrix(
          box: box,
          quarterTurns: turns,
          appWidth: shown.width,
          appHeight: shown.height);
    }

    test('no rotation: top-left maps to (left, top), y flips', () {
      final m = matrixFor(0);
      expectPoint(map(m, 0, 0), 10, 120);
      expectPoint(map(m, 200, 0), 210, 120);
      expectPoint(map(m, 0, 100), 10, 20);
      expectPoint(map(m, 50, 25), 60, 95);
    });

    test('90 degrees: top-left maps to the unrotated bottom-left', () {
      // Displayed page is 100 wide x 200 tall.
      final m = matrixFor(1);
      expectPoint(map(m, 0, 0), 10, 20);
      expectPoint(map(m, 100, 0), 10, 120);
      expectPoint(map(m, 0, 200), 210, 20);
      expectPoint(map(m, 100, 200), 210, 120);
    });

    test('180 degrees: top-left maps to the bottom-right of the box', () {
      final m = matrixFor(2);
      expectPoint(map(m, 0, 0), 210, 20);
      expectPoint(map(m, 200, 100), 10, 120);
      expectPoint(map(m, 50, 25), 160, 45);
    });

    test('270 degrees: top-left maps to the unrotated top-right', () {
      final m = matrixFor(3);
      expectPoint(map(m, 0, 0), 210, 120);
      expectPoint(map(m, 100, 0), 210, 20);
      expectPoint(map(m, 0, 200), 10, 120);
      expectPoint(map(m, 100, 200), 10, 20);
    });

    test('every rotation maps the displayed page exactly onto the box', () {
      for (var turns = 0; turns < 4; turns++) {
        final shown = displayedPdfPageSize(box, turns);
        final m = matrixFor(turns);
        final corners = [
          map(m, 0, 0),
          map(m, shown.width, 0),
          map(m, 0, shown.height),
          map(m, shown.width, shown.height),
        ];
        for (final c in corners) {
          expect(c.x == box.left || c.x == box.right, isTrue,
              reason: 'turns=$turns corner $c');
          expect(c.y == box.bottom || c.y == box.top, isTrue,
              reason: 'turns=$turns corner $c');
        }
        expect({for (final c in corners) '${c.x},${c.y}'}.length, 4);
      }
    });

    test('the top edge of a page turned 90 degrees is the unrotated left edge',
        () {
      final m = matrixFor(1);
      expectPoint(map(m, 50, 0), 10, 70);
    });

    test('scales when the app page size differs from the PDF page size', () {
      final m = appToPdfMatrix(
          box: const PdfBox(0, 0, 600, 800),
          quarterTurns: 0,
          appWidth: 300,
          appHeight: 400);
      expectPoint(map(m, 150, 200), 300, 400);
      expectPoint(map(m, 0, 0), 0, 800);
    });

    test('scales on rotated pages (app axes follow the display)', () {
      // 600 x 800 box turned 90: displayed 800 x 600, app page is 400 x 300.
      final m = appToPdfMatrix(
          box: const PdfBox(0, 0, 600, 800),
          quarterTurns: 1,
          appWidth: 400,
          appHeight: 300);
      expectPoint(map(m, 400, 300), 600, 800);
      expectPoint(map(m, 0, 0), 0, 0);
      expectPoint(map(m, 400, 0), 0, 800);
    });

    test('a zero app size does not divide by zero', () {
      final m =
          appToPdfMatrix(box: box, quarterTurns: 0, appWidth: 0, appHeight: 0);
      expect(m.a.isFinite && m.d.isFinite, isTrue);
    });

    test('rotation does not change the area scale', () {
      for (var turns = 0; turns < 4; turns++) {
        expect(matrixFor(turns).determinant.abs(), closeTo(1, 1e-9));
      }
    });
  });
}
