
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/integrations/ruler/ruler_model.dart';
import 'package:neatink/features/editor/integrations/ruler/ruler_toggle_button.dart';

import 'ruler_test_utils.dart';

void main() {
  const view = Size(1000, 800);

  Widget host(RulerModel model,
          {Size Function()? viewportSize, ThemeData? theme}) =>
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Row(children: [
            RulerToggleButton(
                model: model, viewportSize: viewportSize ?? () => view),
          ]),
        ),
      );

  IconButton button(WidgetTester tester) =>
      tester.widget<IconButton>(find.byKey(const ValueKey('ruler-toggle')));

  testWidgets('is a ruler icon with the tooltip Ruler', (tester) async {
    final model = RulerModel();
    addTearDown(model.dispose);
    await tester.pumpWidget(host(model));
    expect(find.byIcon(Icons.straighten), findsOneWidget);
    expect(find.byTooltip('Ruler'), findsOneWidget);
    expect(RulerToggleButton.tooltip, 'Ruler');
  });

  testWidgets('tapping shows the ruler, tapping again hides it',
      (tester) async {
    final model = RulerModel();
    addTearDown(model.dispose);
    await tester.pumpWidget(host(model));
    expect(model.visible, isFalse);
    await tester.tap(find.byKey(const ValueKey('ruler-toggle')));
    await tester.pump();
    expect(model.visible, isTrue);
    await tester.tap(find.byKey(const ValueKey('ruler-toggle')));
    await tester.pump();
    expect(model.visible, isFalse);
  });

  testWidgets('places the ruler for the view it is asked about',
      (tester) async {
    final model = RulerModel();
    addTearDown(model.dispose);
    var asked = 0;
    await tester.pumpWidget(host(model, viewportSize: () {
      asked++;
      return const Size(600, 500);
    }));
    expect(asked, 0, reason: 'only asked when the button is pressed');
    await tester.tap(find.byKey(const ValueKey('ruler-toggle')));
    await tester.pump();
    expect(asked, 1);
    expect(model.geometry.center, offsetCloseTo(const Offset(300, 190)));
    expect(model.geometry.length, closeTo(552, 1e-9));
  });

  testWidgets('looks pressed while the ruler shows', (tester) async {
    final model = RulerModel();
    addTearDown(model.dispose);
    await tester.pumpWidget(host(model));
    expect(button(tester).isSelected, isFalse);
    await tester.tap(find.byKey(const ValueKey('ruler-toggle')));
    await tester.pump();
    expect(button(tester).isSelected, isTrue);
  });

  testWidgets('follows the model when the ruler is shown or hidden elsewhere',
      (tester) async {
    final model = RulerModel();
    addTearDown(model.dispose);
    await tester.pumpWidget(host(model));
    model.show(view);
    await tester.pump();
    expect(button(tester).isSelected, isTrue);
    model.hide();
    await tester.pump();
    expect(button(tester).isSelected, isFalse);
  });

  testWidgets('is as big a target as the tool buttons next to it',
      (tester) async {
    final model = RulerModel();
    addTearDown(model.dispose);
    await tester.pumpWidget(host(model));
    final size = tester.getSize(find.byKey(const ValueKey('ruler-toggle')));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('moving the ruler does not disturb the button', (tester) async {
    final model = RulerModel()..show(view);
    addTearDown(model.dispose);
    await tester.pumpWidget(host(model));
    model.translate(const Offset(10, 10));
    model.rotateBy(rad(20));
    await tester.pump();
    expect(button(tester).isSelected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('builds in the light and the dark theme', (tester) async {
    final model = RulerModel()..show(view);
    addTearDown(model.dispose);
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(host(model,
          theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.indigo, brightness: brightness))));
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.straighten), findsOneWidget);
    }
  });
}
