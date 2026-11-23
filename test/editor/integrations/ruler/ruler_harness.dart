import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/editor_integrations.dart';
import 'package:neatink/features/editor/integrations/ruler/ruler_integration.dart';
import 'package:neatink/features/editor/integrations/ruler/ruler_model.dart';
import 'package:neatink/features/editor/integrations/ruler/ruler_painter.dart';

import '../../canvas/canvas_harness.dart';

extension RulerInHarness on CanvasHarness {
  /// The ruler model the real integration installed into the editor.
  RulerModel get ruler =>
      tester.widget<RulerOverlay>(find.byType(RulerOverlay)).model;
}

/// Opens the editor with the real ruler integration (and any [more]).
Future<CanvasHarness> openWithRuler(
  WidgetTester tester, {
  List<EditorIntegration> more = const [],
}) =>
    CanvasHarness.open(tester, integrations: [rulerIntegration, ...more]);
