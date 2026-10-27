import '../../../../ink/stroke.dart';
import '../../editor_controller.dart';
import '../../tool_prefs.dart';

/// Key of the shape tool's last shape in `ToolPrefs.extra`.
const String shapeKindPrefKey = 'shapes.kind';

/// The shape the shape tool draws (the last one picked; a line at first).
ShapeKind selectedShapeKind(ToolPrefs prefs) =>
    enumByName(ShapeKind.values, prefs.extra[shapeKindPrefKey], ShapeKind.line);

/// Picks the shape the shape tool draws and remembers it.
void selectShapeKind(EditorController controller, ShapeKind kind) =>
    controller.updateToolPrefs((p) {
      if (selectedShapeKind(p) == kind) return p;
      return p.copyWith(extra: {...p.extra, shapeKindPrefKey: kind.name});
    });

/// User-facing name of a shape.
String shapeKindName(ShapeKind kind) => switch (kind) {
      ShapeKind.line => 'Line',
      ShapeKind.arrow => 'Arrow',
      ShapeKind.rectangle => 'Rectangle',
      ShapeKind.ellipse => 'Ellipse',
      ShapeKind.triangle => 'Triangle',
    };
