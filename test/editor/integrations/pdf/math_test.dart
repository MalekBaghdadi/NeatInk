import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/integrations/pdf/pdf_background_math.dart';

void main() {
  test('thumbnail region keeps the page aspect ratio', () {
    final r = thumbnailRegion(595, 842, 320 / 595)!;
    expect(r.fullWidth, 320);
    expect(r.fullHeight, 453);
    expect(r.isFullPage, isTrue);
  });

  test('thumbnail region is capped', () {
    final r = thumbnailRegion(595, 842, 20)!;
    expect(r.fullWidth, maxThumbnailBackgroundPx);
  });

  test('unusable sizes give null', () {
    expect(thumbnailRegion(0, 842, 1), isNull);
    expect(thumbnailRegion(595, double.nan, 1), isNull);
    expect(thumbnailRegion(595, 842, 0), isNull);
  });
}
