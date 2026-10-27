import 'package:uuid/uuid.dart';

import '../../../../document/notebook_meta.dart';
import 'convert_layout.dart';
import 'convert_plan.dart';

/// Lays out the recognised lines of [plan] on its page ([meta]): the lines
/// for which [convert] is true become text boxes, the others only bound the
/// line above them (they stay handwriting). Shared by the review sheet and
/// auto-convert, so both place the text exactly the same way.
List<LaidOutLine> layoutPlannedPage({
  required PagePlan plan,
  required PageMeta meta,
  required ConvertStyle style,
  required ConvertTextMetrics metrics,
  required Uuid uuid,
  required bool Function(PlannedLine line) convert,
}) {
  final ruling =
      PageRuling.of(meta.paper, meta.width, meta.height, isPdf: meta.isPdf);
  return layoutPage(
    pageWidth: meta.width,
    pageHeight: meta.height,
    ruling: ruling,
    style: style,
    metrics: metrics,
    uuid: uuid,
    lines: [
      for (final l in plan.lines)
        LayoutLineInput(
          id: l.id,
          text: l.text,
          geometry: LineGeometry.of(l.line),
          color: l.dominantColor,
          include: convert(l),
        ),
    ],
  );
}
