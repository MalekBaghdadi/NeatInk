import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/toolbar/ink_sliders.dart';

import 'toolbar_harness.dart';

void main() {
  group('roundToDecimals', () {
    test('gives the clean decimal', () {
      expect(roundToDecimals(2.3000000000000003, 1), 2.3);
      expect(roundToDecimals(0.1 + 0.2, 1), 0.3);
      expect(roundToDecimals(0.376, 2), 0.38);
      expect(roundToDecimals(12, 1), 12.0);
    });

    test('leaves values that are not numbers alone', () {
      expect(roundToDecimals(double.nan, 1), isNaN);
      expect(roundToDecimals(double.infinity, 1), double.infinity);
    });
  });

  group('stepTenth', () {
    test('moves a value on the grid by exactly 0.1', () {
      expect(stepTenth(2.0, 1, min: 0.5, max: 12), 2.1);
      expect(stepTenth(2.0, -1, min: 0.5, max: 12), 1.9);
      // 2.3 * 10 is 22.999999999999996: a naive floor would stay at 2.3.
      expect(stepTenth(2.3, 1, min: 0.5, max: 12), 2.4);
      expect(stepTenth(2.4, -1, min: 0.5, max: 12), 2.3);
      expect(stepTenth(2.2, 1, min: 0.5, max: 12), 2.3);
    });

    test('moves a value between two grid points to the next one', () {
      expect(stepTenth(2.25, 1, min: 0.5, max: 12), 2.3);
      expect(stepTenth(2.25, -1, min: 0.5, max: 12), 2.2);
      expect(stepTenth(2.21, 1, min: 0.5, max: 12), 2.3);
      expect(stepTenth(2.29, -1, min: 0.5, max: 12), 2.2);
    });

    test('stays within the range', () {
      expect(stepTenth(12.0, 1, min: 0.5, max: 12), 12.0);
      expect(stepTenth(0.5, -1, min: 0.5, max: 12), 0.5);
      expect(stepTenth(11.95, 1, min: 0.5, max: 12), 12.0);
      // Far outside the range it lands on the nearest end.
      expect(stepTenth(30, -1, min: 0.5, max: 12), 12.0);
      expect(stepTenth(-5, 1, min: 0.5, max: 12), 0.5);
    });

    test('does not drift over a whole sweep', () {
      var v = 0.5;
      for (var i = 0; i < 115; i++) {
        v = stepTenth(v, 1, min: 0.5, max: 12);
      }
      expect(v, 12.0);
      for (var i = 0; i < 115; i++) {
        v = stepTenth(v, -1, min: 0.5, max: 12);
      }
      expect(v, 0.5);
    });

    test('a value that is not a number gives the minimum', () {
      expect(stepTenth(double.nan, 1, min: 0.5, max: 12), 0.5);
      expect(stepTenth(double.infinity, -1, min: 0.5, max: 12), 0.5);
    });

    test('an inverted range does not throw', () {
      expect(stepTenth(2, 1, min: 5, max: 1), 5.0);
    });
  });

  group('InkValueSlider', () {
    final slider = find.byKey(const ValueKey('ink-settings-thickness'));
    final plus = find.byKey(const ValueKey('ink-settings-thickness-plus'));
    final minus = find.byKey(const ValueKey('ink-settings-thickness-minus'));

    /// A slider row whose value follows its own callbacks, like a panel
    /// whose model stores them, and records every call.
    Widget row(
      List<double> calls, {
      double value = 2.0,
      double min = 0.5,
      double max = 12,
      bool steppers = true,
      bool commitOnRelease = false,
      double width = 300,
    }) =>
        themedApp(Center(
          child: SizedBox(
            width: width,
            child: StatefulBuilder(
              builder: (context, setState) => InkValueSlider(
                id: 'thickness',
                label: 'Thickness',
                value: value,
                min: min,
                max: max,
                steppers: steppers,
                commitOnRelease: commitOnRelease,
                onChanged: (v) {
                  calls.add(v);
                  setState(() => value = v);
                },
              ),
            ),
          ),
        ));

    testWidgets('shows the label and the value with one decimal',
        (tester) async {
      await tester.pumpWidget(row([]));
      expect(find.text('Thickness'), findsOneWidget);
      expect(find.text('2.0'), findsOneWidget);
    });

    testWidgets('the steppers move the value by 0.1', (tester) async {
      final calls = <double>[];
      await tester.pumpWidget(row(calls));
      await tester.tap(plus);
      await tester.pump();
      expect(calls, [2.1]);
      expect(find.text('2.1'), findsOneWidget);
      await tester.tap(minus);
      await tester.pump();
      await tester.tap(minus);
      await tester.pump();
      expect(calls, [2.1, 2.0, 1.9]);
      expect(find.text('1.9'), findsOneWidget);
    });

    testWidgets('a stepper is greyed out at its end of the range',
        (tester) async {
      await tester.pumpWidget(row([], value: 12.0));
      expect(tester.widget<InkStepButton>(plus).onPressed, isNull);
      expect(tester.widget<InkStepButton>(minus).onPressed, isNotNull);
      await tester.pumpWidget(row([], value: 0.5));
      expect(tester.widget<InkStepButton>(minus).onPressed, isNull);
      expect(tester.widget<InkStepButton>(plus).onPressed, isNotNull);
    });

    testWidgets('dragging the slider reports values on the 0.1 grid',
        (tester) async {
      final calls = <double>[];
      await tester.pumpWidget(row(calls));
      await tester.drag(slider, const Offset(400, 0));
      await tester.pump();
      expect(calls, isNotEmpty);
      expect(calls.last, 12.0);
      for (final v in calls) {
        expect(v, inInclusiveRange(0.5, 12.0));
        expect(roundToDecimals(v, 1), v, reason: '$v is not a clean decimal');
      }
      await tester.drag(slider, const Offset(-800, 0));
      await tester.pump();
      expect(calls.last, 0.5);
    });

    testWidgets('with commitOnRelease a drag reports once, when it ends',
        (tester) async {
      final calls = <double>[];
      await tester.pumpWidget(row(calls, commitOnRelease: true));
      final g = await tester.startGesture(tester.getCenter(slider));
      await g.moveBy(const Offset(60, 0));
      await tester.pump();
      await g.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(calls, isEmpty, reason: 'nothing is committed mid-drag');
      // The thumb and the number follow the finger meanwhile.
      expect(find.text('2.0'), findsNothing);
      await g.up();
      await tester.pump();
      expect(calls, hasLength(1));
      expect(find.text(calls.single.toStringAsFixed(1)), findsOneWidget);
    });

    testWidgets('dragging back to the start commits nothing', (tester) async {
      final calls = <double>[];
      await tester.pumpWidget(row(calls, commitOnRelease: true));
      // Start on the thumb itself (2.0 of 0.5..12 sits at 13% of the track).
      final box = tester.getRect(slider);
      final thumb = Offset(box.left + 15 + 270 * (2.0 - 0.5) / 11.5, box.center.dy);
      final g = await tester.startGesture(thumb);
      await g.moveBy(const Offset(80, 0));
      await tester.pump();
      await g.moveTo(thumb);
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(calls, isEmpty);
      expect(find.text('2.0'), findsOneWidget);
    });

    testWidgets('stepper taps commit at once even with commitOnRelease',
        (tester) async {
      final calls = <double>[];
      await tester.pumpWidget(row(calls, commitOnRelease: true));
      await tester.tap(plus);
      await tester.pump();
      expect(calls, [2.1]);
    });

    testWidgets('an accessibility step goes by 0.1 and commits at once',
        (tester) async {
      final handle = tester.ensureSemantics();
      final calls = <double>[];
      await tester.pumpWidget(row(calls, commitOnRelease: true));
      final increase = find.semantics.byAction(SemanticsAction.increase);
      tester.semantics.increase(increase);
      await tester.pump();
      expect(calls, [2.1]);
      tester.semantics.decrease(find.semantics.byAction(SemanticsAction.decrease));
      await tester.pump();
      expect(calls, [2.1, 2.0]);
      handle.dispose();
    });

    testWidgets('without steppers only the value is shown', (tester) async {
      await tester.pumpWidget(row([], steppers: false));
      expect(plus, findsNothing);
      expect(minus, findsNothing);
      expect(find.text('2.0'), findsOneWidget);
    });

    testWidgets('a value outside the range does not break the slider',
        (tester) async {
      await tester.pumpWidget(row([], value: 20));
      expect(tester.takeException(), isNull);
      // The real number is still shown; the thumb sits at the end.
      expect(find.text('20.0'), findsOneWidget);
      expect(tester.widget<InkSlider>(slider).value, 12.0);
      expect(tester.widget<InkStepButton>(plus).onPressed, isNull);
    });

    testWidgets('a value that is not a number does not break the slider',
        (tester) async {
      await tester.pumpWidget(row([], value: double.nan));
      expect(tester.takeException(), isNull);
      expect(tester.widget<InkSlider>(slider).value, 0.5);
    });

    testWidgets('an empty range makes a disabled slider', (tester) async {
      await tester.pumpWidget(row([], value: 3, min: 3, max: 3));
      expect(tester.takeException(), isNull);
      expect(tester.widget<InkSlider>(slider).onChanged, isNull);
    });

    testWidgets('a long label and a narrow row do not overflow',
        (tester) async {
      await tester.pumpWidget(themedApp(Center(
        child: SizedBox(
          width: 160,
          child: InkValueSlider(
            id: 'wave-height',
            label: 'Wavy Line Height of the very long kind',
            value: 3.1,
            min: 0.5,
            max: 12,
            onChanged: (_) {},
          ),
        ),
      )));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the slider has a 36 dp tall touch area', (tester) async {
      await tester.pumpWidget(row([]));
      expect(tester.getSize(slider).height, InkSlider.touchHeight);
    });
  });
}
