import 'package:flutter/widgets.dart' show Offset;

import '../../../../ink/vec2.dart';
import '../../editor_integrations.dart';
import '../../editor_tool.dart';
import 'eraser_cursor.dart';
import 'eraser_handler.dart';
import 'clipboard.dart';
import 'lasso_handler.dart';
import 'paste_bubble.dart';
import 'selection_menu.dart';
import 'selection_overlay.dart';

/// Eraser (whole-stroke and partial) and lasso selection.
///
/// * The eraser tool also receives the pen's eraser end / barrel button
///   (the input router sends those pointers to `controller.eraserHandler`,
///   which is this handler), whatever tool is selected.
/// * The eraser's mode and size are the core tool row's own options.
/// * The lasso selects strokes, text boxes and images; its frame is a page
///   overlay and its menu a viewport overlay.
/// * Cut / Copy / Paste use the app-wide [editorClipboardProvider], so
///   things can move between pages and notebooks: Paste is a bubble after a
///   lasso tap on an empty spot, and More › Paste (the middle of the view).
// ignore: prefer_function_declarations_over_variables
final EditorIntegration eraseSelectIntegration = (controller, ref) {
  final eraser = EraserHandler(controller);
  final clipboard = ref.read(editorClipboardProvider);
  final lasso = LassoHandler(controller, clipboard: clipboard);
  controller.extensions
    ..toolHandlers[EditorTool.eraser] = eraser
    ..toolHandlers[EditorTool.lasso] = lasso
    ..pageOverlays
        .add((context, page) => SelectionPageOverlay(state: lasso.state, page: page))
    ..viewportOverlays.addAll([
      (context, c) => SelectionMenu(handler: lasso, controller: c),
      (context, c) => PasteBubble(handler: lasso, controller: c),
      (context, c) => EraserCursorOverlay(handler: eraser, viewport: c.viewport),
    ])
    ..canPaste = (() => clipboard.hasContent)
    ..paste = (context, c) async {
      if (!c.isReady || c.pageCount == 0) return;
      final index = c.currentPageIndex;
      final page = c.doc.meta.pages[index];
      final center = c.viewport.hasSize
          ? c.viewport.localToPage(c.viewport.viewportSize.center(Offset.zero), index)
          : null;
      await lasso.pasteAt(page.id, center ?? Vec2(page.width / 2, page.height / 2));
    };
  // The menu's Paste item follows the clipboard.
  void changed() => controller.extensionsChanged();
  clipboard.addListener(changed);
  controller.addDisposeCallback(() => clipboard.removeListener(changed));
};
