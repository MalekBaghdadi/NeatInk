import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/render/text_style.dart';

TextItem box(FontKind font, {bool bold = false, bool italic = false}) =>
    TextItem(
        id: 't',
        x: 0,
        y: 0,
        width: 200,
        height: 20,
        text: 'Hello',
        font: font,
        bold: bold,
        italic: italic);

void main() {
  test('fontFamilyFor returns the registry family of every font', () {
    for (final f in FontKind.values) {
      expect(fontFamilyFor(f), f.family);
    }
    expect(fontFamilyFor(FontKind.sans), 'NI-Roboto');
    expect(fontFamilyFor(FontKind.serif), 'NI-Tinos');
    expect(fontFamilyFor(FontKind.mono), 'NI-RobotoMono');
  });

  test('textStyleFor picks the family and the weight/slant of the file', () {
    final regular = textStyleFor(box(FontKind.lora));
    expect(regular.fontFamily, 'NI-Lora');
    expect(regular.fontWeight, FontWeight.w400);
    expect(regular.fontStyle, FontStyle.normal);
    expect(regular.inherit, isFalse);

    final bold = textStyleFor(box(FontKind.caveat, bold: true));
    expect(bold.fontFamily, 'NI-Caveat');
    expect(bold.fontWeight, FontWeight.w700);

    final italic = textStyleFor(box(FontKind.atkinson, italic: true));
    expect(italic.fontFamily, 'NI-AtkinsonHyperlegible');
    expect(italic.fontStyle, FontStyle.italic);
  });

  test('layoutTextItem works for every font (missing files fall back)', () {
    for (final f in FontKind.values) {
      final painter = layoutTextItem(box(f, bold: true, italic: true));
      expect(painter.height, greaterThan(0), reason: f.name);
      painter.dispose();
    }
  });
}
