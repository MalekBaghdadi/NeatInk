import 'dart:ui' show Offset;

import '../../canvas/stroke_constraint.dart';
import '../../editor_extensions.dart';
import 'ruler_geometry.dart';
import 'ruler_model.dart';

/// Pulls a pen stroke onto one edge of the ruler: the ink goes straight
/// along the edge, however the pen wanders, and stops at the ruler's ends.
///
/// It keeps the ruler's [geometry] as it was when the pen landed, so the line
/// can't change if the ruler is moved while the stroke is drawn.
class RulerEdgeConstraint implements StrokeConstraint {
  const RulerEdgeConstraint(this.geometry, this.edge);

  final RulerGeometry geometry;
  final RulerEdge edge;

  @override
  Offset project(Offset local) => geometry.project(local, edge);
}

/// The editor's stroke constraint provider for [model]: a pen that lands
/// within [rulerSnapDistance] of an edge of a visible ruler (outside or
/// inside it) draws along that edge; anywhere else it draws freely.
StrokeConstraintProvider rulerConstraintProvider(RulerModel model) => (e) {
      if (!model.visible) return null;
      final geometry = model.geometry;
      final edge = geometry.nearestEdge(e.localPosition, rulerSnapDistance);
      return edge == null ? null : RulerEdgeConstraint(geometry, edge);
    };
