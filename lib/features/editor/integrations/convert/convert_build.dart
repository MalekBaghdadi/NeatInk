import 'package:uuid/uuid.dart';

import '../../../../document/notebook_meta.dart';
import 'convert_layout.dart';
import 'convert_plan.dart';

/// Lays out the recognised lines of [plan] on its page ([meta]): the lines
/// for which [convert] is true become text boxes, the others only bound the
/// line above them (they stay handwriting). Shared by the review sheet and
/// auto-convert, so both place the text exactly the same way. Each box
/// remembers which of its words autocorrect changed ([TextItem.corrections]).
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
  LayoutLineInput input(PlannedLine l) => LayoutLineInput(
        id: l.id,
        text: l.text,
        geometry: LineGeometry.of(l.line),
        color: l.dominantColor,
        include: convert(l),
      );
  final List<LaidOutLine> laid;
  if (textColumnAt(meta, 0) == null) {
    laid = layoutPage(
      pageWidth: meta.width,
      pageHeight: meta.height,
      ruling: ruling,
      style: style,
      metrics: metrics,
      uuid: uuid,
      lines: [for (final l in plan.lines) input(l)],
    );
  } else {
    // A PDF page with writing margins: each margin (and the PDF between
    // them) is laid out on its own, on its own lines.
    final columns = <double, (TextColumn, List<PlannedLine>)>{};
    for (final l in plan.lines) {
      final column = textColumnAt(meta, l.line.left)!;
      columns.putIfAbsent(column.left, () => (column, <PlannedLine>[])).$2.add(l);
    }
    final order = {for (var i = 0; i < plan.lines.length; i++) plan.lines[i].id: i};
    laid = [
      for (final (column, lines) in columns.values)
        ...layoutPage(
          pageWidth: meta.width,
          pageHeight: meta.height,
          ruling: column.ruling,
          column: column,
          style: style,
          metrics: metrics,
          uuid: uuid,
          lines: [for (final l in lines) input(l)],
        ),
    ]..sort((a, b) => order[a.members.first]!.compareTo(order[b.members.first]!));
  }
  final byId = {for (final l in plan.lines) l.id: l};
  return [
    for (final out in laid)
      out.withItem(out.item.copyWith(
          corrections: locateCorrections(out.item.text, [
            for (final id in out.members) ...?byId[id]?.autoApplied,
          ]))),
  ];
}
