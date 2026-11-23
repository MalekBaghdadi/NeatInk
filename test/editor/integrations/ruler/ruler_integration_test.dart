import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/canvas/document_view.dart';
import 'package:neatink/features/editor/integrations/ruler/ruler_painter.dart';
import 'package:neatink/features/editor/integrations/ruler/ruler_toggle_button.dart';
import 'package:neatink/features/editor/integrations/ruler/ruler_touch_interceptor.dart';

import 'ruler_harness.dart';
import 'ruler_test_utils.dart';

void main() {
  testWidgets('installs the interceptor, the provider, the overlay and the '
      'button', (tester) async {
    final h = await openWithRuler(tester);
    final ext = h.controller.extensions;
    expect(ext.touchInterceptor, isA<RulerTouchInterceptor>());
    expect(ext.strokeConstraint, isNotNull);
    expect(ext.viewportOverlays.length, 1);
    expect(ext.toolRowActions.length, 1);
    expect(find.byType(RulerOverlay), findsOneWidget);
    // The overlay sits in the document view.
    expect(find.descendant(
        of: find.byType(DocumentView), matching: find.byType(RulerOverlay)),
        findsOneWidget);
    await h.close();
  });

  testWidgets('starts hidden, with nothing drawn', (tester) async {
    final h = await openWithRuler(tester);
    expect(h.ruler.visible, isFalse);
    await h.close();
  });

  testWidgets('the tool row action is a ruler button', (tester) async {
    final h = await openWithRuler(tester);
    final context = tester.element(find.byType(DocumentView));
    final action =
        h.controller.extensions.toolRowActions.single(context, h.controller);
    expect(action, isA<RulerToggleButton>());
    expect((action as RulerToggleButton).model, same(h.ruler));
    await h.close();
  });

  testWidgets('the button in the tool row shows and hides the ruler over the '
      'document view', (tester) async {
    final h = await openWithRuler(tester);
    final toggle = find.byKey(const ValueKey('ruler-toggle'));
    expect(toggle, findsOneWidget);
    expect(h.ruler.visible, isFalse);

    await tester.tap(toggle);
    await tester.pump();
    expect(h.ruler.visible, isTrue);
    // Placed for the document view's size, not the screen's.
    final view = h.viewSize;
    expect(h.ruler.geometry.center,
        offsetCloseTo(Offset(view.width / 2, view.height * 0.38), 1e-6));

    await tester.tap(toggle);
    await tester.pump();
    expect(h.ruler.visible, isFalse);
    await h.close();
  });

  testWidgets('the ruler is drawn over the page only while it shows',
      (tester) async {
    final h = await openWithRuler(tester);
    final paint = find.descendant(
        of: find.byType(RulerOverlay), matching: find.byType(CustomPaint));
    expect(tester.renderObject(paint.first), paintsNothing);
    h.ruler.show(h.viewSize);
    await tester.pump();
    expect(tester.renderObject(paint.first), paints..rrect()..path());
    await h.close();
  });

  testWidgets('every editor gets its own ruler, hidden at first',
      (tester) async {
    var h = await openWithRuler(tester);
    h.ruler.show(h.viewSize);
    h.ruler.translate(const Offset(50, 50));
    final first = h.ruler;
    await h.close();

    h = await openWithRuler(tester);
    expect(identical(h.ruler, first), isFalse);
    expect(h.ruler.visible, isFalse);
    await h.close();
  });

  testWidgets('the ruler model goes away with the editor', (tester) async {
    final h = await openWithRuler(tester);
    final model = h.ruler;
    await h.close();
    expect(() => model.addListener(() {}), throwsFlutterError);
  });

  test('the app installs the ruler right after the shapes', () {
    // default_integrations.dart imports the PDF engine, which the test
    // mirror doesn't have, so read the list instead of importing it.
    final source =
        File('lib/features/editor/default_integrations.dart').readAsStringSync();
    final list = source.substring(source.indexOf('defaultEditorIntegrations'));
    final shapes = list.indexOf('shapesIntegration');
    final ruler = list.indexOf('rulerIntegration');
    final pages = list.indexOf('pagesIntegration');
    expect(shapes, isNonNegative);
    expect(ruler, greaterThan(shapes));
    expect(pages, greaterThan(ruler));
    expect(source,
        contains("import 'integrations/ruler/ruler_integration.dart';"));
  });
}
