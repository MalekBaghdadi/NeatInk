import '../../../../document/commands.dart';
import '../../../../document/page_items.dart';
import '../../editor_controller.dart';

/// Label of the undo step made by a conversion.
const String convertCommandLabel = 'Convert to text';

/// Label of the undo step made by one auto-convert pass.
const String autoConvertCommandLabel = 'Auto-convert';

/// What to change on one page: the strokes to take away and the text boxes
/// to put in their place.
class PageConversion {
  const PageConversion({
    required this.pageId,
    required this.strokeIds,
    required this.items,
    this.replacements = const [],
  });

  final String pageId;
  final Set<String> strokeIds;

  /// New text boxes to add.
  final List<TextItem> items;

  /// Existing text boxes that grow instead of a new box being added
  /// (auto-convert appending a line to the previous box): `(before, after)`.
  final List<(TextItem, TextItem)> replacements;

  /// True when applying this changes the page at all (late dots only take
  /// strokes away).
  bool get hasChanges => items.isNotEmpty || replacements.isNotEmpty || strokeIds.isNotEmpty;
}

/// What a finished conversion did.
class ConvertOutcome {
  const ConvertOutcome({required this.lines, required this.pages});

  /// Text boxes made (one per converted line; lines appended to an existing
  /// box count too).
  final int lines;
  final int pages;
}

/// The command that converts [pages]: for each page the strokes are removed
/// and the text boxes added (or grown), all inside one [CompositeCommand] so
/// a single undo puts every stroke of every page back (the removed [Stroke]
/// objects are kept by [RemoveStrokesCommand], so they come back exactly as
/// they were, in the same paint order). [label] names the undo step.
CompositeCommand buildConvertCommand(List<PageConversion> pages,
        {String label = convertCommandLabel}) =>
    CompositeCommand(label, [
      for (final p in pages) ...[
        RemoveStrokesCommand(p.pageId, p.strokeIds, label: label),
        PageItemsCommand(p.pageId, label: label, textChanges: [
          for (final r in p.replacements) (r.$1, r.$2),
          for (final t in p.items) (null, t),
        ]),
      ],
    ]);

/// Applies [pages] as one undo step. Pages that can't be edited (read-only,
/// gone) and pages with nothing to do are skipped; returns null when nothing
/// was changed.
ConvertOutcome? applyConversion(
    EditorController controller, List<PageConversion> pages,
    {String label = convertCommandLabel}) {
  final usable = [
    for (final p in pages)
      if (p.hasChanges && controller.isPageEditable(p.pageId)) p,
  ];
  if (usable.isEmpty) return null;
  controller.execute(buildConvertCommand(usable, label: label));
  for (final p in usable) {
    controller.invalidatePageRender(p.pageId);
  }
  return ConvertOutcome(
    lines: usable.fold(0, (n, p) => n + p.items.length + p.replacements.length),
    pages: usable.length,
  );
}
