import '../../../../document/commands.dart';
import '../../../../document/page_items.dart';
import '../../editor_controller.dart';

/// Label of the undo step made by a conversion.
const String convertCommandLabel = 'Convert to text';

/// What to change on one page: the strokes to take away and the text boxes
/// to put in their place.
class PageConversion {
  const PageConversion({
    required this.pageId,
    required this.strokeIds,
    required this.items,
  });

  final String pageId;
  final Set<String> strokeIds;
  final List<TextItem> items;
}

/// What a finished conversion did.
class ConvertOutcome {
  const ConvertOutcome({required this.lines, required this.pages});

  /// Text boxes made (one per converted line).
  final int lines;
  final int pages;
}

/// The command that converts [pages]: for each page the strokes are removed
/// and the text boxes added, all inside one [CompositeCommand] so a single
/// undo puts every stroke of every page back (the removed [Stroke] objects
/// are kept by [RemoveStrokesCommand], so they come back exactly as they
/// were, in the same paint order).
CompositeCommand buildConvertCommand(List<PageConversion> pages) =>
    CompositeCommand(convertCommandLabel, [
      for (final p in pages) ...[
        RemoveStrokesCommand(p.pageId, p.strokeIds, label: convertCommandLabel),
        PageItemsCommand(p.pageId,
            label: convertCommandLabel,
            textChanges: [for (final t in p.items) (null, t)]),
      ],
    ]);

/// Applies [pages] as one undo step. Pages that can't be edited (read-only,
/// gone) and pages with nothing to do are skipped; returns null when nothing
/// was changed.
ConvertOutcome? applyConversion(
    EditorController controller, List<PageConversion> pages) {
  final usable = [
    for (final p in pages)
      if (p.items.isNotEmpty && controller.isPageEditable(p.pageId)) p,
  ];
  if (usable.isEmpty) return null;
  controller.execute(buildConvertCommand(usable));
  for (final p in usable) {
    controller.invalidatePageRender(p.pageId);
  }
  return ConvertOutcome(
    lines: usable.fold(0, (n, p) => n + p.items.length),
    pages: usable.length,
  );
}
