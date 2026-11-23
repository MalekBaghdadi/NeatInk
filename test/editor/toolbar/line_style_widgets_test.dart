import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/theme.dart';
import 'package:neatink/features/editor/toolbar/line_style_widgets.dart';
import 'package:neatink/ink/line_style.dart';

import 'toolbar_harness.dart';

void main() {
  group('LineStyleGrid', () {
    Finder chip(LineStyle s) =>
        find.byKey(ValueKey('ink-settings-line-${s.name}'));

    Future<void> pumpGrid(
      WidgetTester tester,
      LineSettings line,
      ValueChanged<LineStyle> onSelected, {
      double width = 300,
    }) =>
        tester.pumpWidget(themedApp(Center(
          child: SizedBox(
            width: width,
            child: LineStyleGrid(line: line, onSelected: onSelected),
          ),
        )));

    testWidgets('shows the six styles in two rows of three', (tester) async {
      await pumpGrid(tester, LineSettings.solid, (_) {});
      const order = [
        LineStyle.solid,
        LineStyle.dashed,
        LineStyle.dotted,
        LineStyle.wavy,
        LineStyle.zigzag,
        LineStyle.parallel,
      ];
      final rects = [for (final s in order) tester.getRect(chip(s))];
      // Row 1: left to right on one line.
      for (var i = 0; i < 2; i++) {
        expect(rects[i].top, rects[i + 1].top);
        expect(rects[i].right, lessThan(rects[i + 1].left));
      }
      // Row 2: the same, below row 1, starting under the first chip.
      for (var i = 3; i < 5; i++) {
        expect(rects[i].top, rects[i + 1].top);
        expect(rects[i].right, lessThan(rects[i + 1].left));
      }
      expect(rects[3].top, greaterThan(rects[0].bottom));
      expect(rects[3].left, rects[0].left);
      // The three columns share the width evenly.
      expect(rects[0].width, closeTo(rects[1].width, 0.01));
      expect(rects[0].width, closeTo(rects[2].width, 0.01));
    });

    testWidgets('every chip has the style name as tooltip', (tester) async {
      await pumpGrid(tester, LineSettings.solid, (_) {});
      for (final s in LineStyle.values) {
        expect(find.byTooltip(s.label), findsOneWidget);
      }
      expect(find.byTooltip('Double'), findsOneWidget);
    });

    testWidgets('a tap reports the tapped style', (tester) async {
      final got = <LineStyle>[];
      await pumpGrid(tester, LineSettings.solid, got.add);
      await tester.tap(chip(LineStyle.wavy));
      await tester.tap(chip(LineStyle.parallel));
      expect(got, [LineStyle.wavy, LineStyle.parallel]);
    });

    testWidgets('the chip of the current style does nothing', (tester) async {
      final got = <LineStyle>[];
      await pumpGrid(
          tester, const LineSettings(style: LineStyle.dashed), got.add);
      await tester.tap(chip(LineStyle.dashed));
      expect(got, isEmpty);
    });

    testWidgets('the wave samples follow the wave settings', (tester) async {
      CustomPainter painterOf(LineStyle s) => tester
          .widget<CustomPaint>(find.descendant(
              of: find.descendant(
                  of: chip(s), matching: find.byType(LineStylePreview)),
              matching: find.byType(CustomPaint)))
          .painter!;
      await pumpGrid(tester, const LineSettings(), (_) {});
      final calm = painterOf(LineStyle.wavy);
      await pumpGrid(tester, const LineSettings(), (_) {});
      expect(painterOf(LineStyle.wavy).shouldRepaint(calm), isFalse,
          reason: 'same settings, same sample');
      await pumpGrid(tester, const LineSettings(waveHeight: 8), (_) {});
      expect(painterOf(LineStyle.wavy).shouldRepaint(calm), isTrue);
    });

    testWidgets('only the current style is selected', (tester) async {
      final scheme = AppTheme.light.colorScheme;
      await pumpGrid(
          tester, const LineSettings(style: LineStyle.zigzag), (_) {});
      for (final s in LineStyle.values) {
        final material = tester.widget<Material>(
            find.descendant(of: chip(s), matching: find.byType(Material)).first);
        final selected = s == LineStyle.zigzag;
        expect(material.color == scheme.primaryContainer, selected,
            reason: s.name);
        final shape = material.shape! as StadiumBorder;
        expect(shape.side.color == scheme.primary, selected, reason: s.name);
        expect(shape.side.width, 1.5, reason: 'no layout jump on selecting');
      }
    });

    testWidgets('works in a narrow column without overflow', (tester) async {
      await pumpGrid(tester, LineSettings.solid, (_) {}, width: 120);
      expect(tester.takeException(), isNull);
    });
  });

  group('LineStylePreview', () {
    Future<void> pumpPreview(
      WidgetTester tester,
      LineSettings line, {
      double? width = 80,
      double height = 20,
    }) =>
        tester.pumpWidget(themedApp(Center(
          child: LineStylePreview(
            line: line,
            color: 0xFF112233,
            width: width,
            height: height,
          ),
        )));

    testWidgets('draws every style in the given colour', (tester) async {
      for (final style in LineStyle.values) {
        await pumpPreview(tester, LineSettings(style: style));
        expect(tester.takeException(), isNull, reason: style.name);
        final preview = find.descendant(
            of: find.byType(LineStylePreview),
            matching: find.byType(CustomPaint));
        expect(
          tester.renderObject(preview.first),
          paints..path(color: const Color(0xFF112233)),
          reason: style.name,
        );
      }
    });

    testWidgets('draws nothing, quietly, when there is no room',
        (tester) async {
      for (final w in [0.0, 2.0, 3.0, 4.0]) {
        await pumpPreview(tester, const LineSettings(style: LineStyle.wavy),
            width: w);
        expect(tester.takeException(), isNull, reason: 'width $w');
      }
      await pumpPreview(tester, LineSettings.solid, height: 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fills the width it is given when it has no width',
        (tester) async {
      await tester.pumpWidget(themedApp(Center(
        child: SizedBox(
          width: 123,
          child: LineStylePreview(line: LineSettings.solid, color: 0xFF000000),
        ),
      )));
      expect(tester.getSize(find.byType(LineStylePreview)).width, 123);
    });

    testWidgets('handles extreme wave settings', (tester) async {
      await pumpPreview(
        tester,
        const LineSettings(
          style: LineStyle.zigzag,
          waveHeight: LineSettings.maxWaveHeight,
          waveWidth: LineSettings.minWaveWidth,
        ),
      );
      expect(tester.takeException(), isNull);
      await pumpPreview(
        tester,
        const LineSettings(
          style: LineStyle.wavy,
          waveHeight: LineSettings.minWaveHeight,
          waveWidth: LineSettings.maxWaveWidth,
        ),
        width: 4000,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('LineStylePill', () {
    testWidgets('is a 64 x 32 stadium with a tooltip', (tester) async {
      await tester.pumpWidget(themedApp(Center(
        child: LineStylePill(
          line: const LineSettings(style: LineStyle.parallel),
          color: 0xFF000000,
          tooltip: 'Pen settings',
          onPressed: (_) {},
        ),
      )));
      expect(find.byTooltip('Pen settings'), findsOneWidget);
      final pill = find.descendant(
          of: find.byType(LineStylePill), matching: find.byType(InkWell));
      expect(tester.getSize(pill), const Size(64, 32));
      final material = tester.widget<Material>(find
          .descendant(
              of: find.byType(LineStylePill), matching: find.byType(Material))
          .first);
      expect(material.shape, isA<StadiumBorder>());
    });

    testWidgets('a tap gives the pill context to the callback',
        (tester) async {
      BuildContext? got;
      await tester.pumpWidget(themedApp(Center(
        child: LineStylePill(
          line: LineSettings.solid,
          color: 0xFF000000,
          tooltip: 'Pen settings',
          onPressed: (context) => got = context,
        ),
      )));
      await tester.tap(find.byType(LineStylePill));
      // The pill's own context, so a panel can open right under it.
      expect(got?.widget, isA<LineStylePill>());
    });
  });
}
