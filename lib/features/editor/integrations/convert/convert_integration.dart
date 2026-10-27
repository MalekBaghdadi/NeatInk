import 'package:flutter/material.dart';

import '../../editor_integrations.dart';
import '../../editor_tool.dart';
import '../../tools/selection.dart';
import '../erase_select/lasso_handler.dart';
import 'convert_providers.dart';
import 'convert_scope.dart';
import 'convert_sheet.dart';

export 'convert_providers.dart' show htrRecognizerProvider, wordImageRendererProvider;

/// Convert handwriting to typed text.
///
/// Registers two actions on the editor extensions:
///
/// * `convertHandwriting`: the app bar "Convert" button. Its scope is the
///   lasso selection's pen strokes when the selection has any, otherwise the
///   pen strokes of the page in view (the sheet can widen that to all pages);
/// * `convertSelection`: the "Convert" button of the lasso selection menu.
///
/// Both open the "Convert to text" sheet. The recogniser and the word-image
/// renderer come from [htrRecognizerProvider] and [wordImageRendererProvider]
/// (overridden in tests). Only editable pages are converted.
// ignore: prefer_function_declarations_over_variables
final EditorIntegration convertIntegration = (controller, ref) {
  Future<void> open(BuildContext context, Selection? selection) async {
    final pageId = selection?.pageId ??
        (controller.pageCount == 0
            ? null
            : controller.doc.meta.pages[controller.currentPageIndex].id);
    if (pageId == null || !controller.isPageEditable(pageId)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("This page can't be changed, so its handwriting can't be converted."),
      ));
      return;
    }
    await showConvertSheet(
      context,
      controller,
      recognizer: ref.read(htrRecognizerProvider),
      renderer: ref.read(wordImageRendererProvider),
      selection: selection,
    );
  }

  controller.extensions
    ..convertHandwriting = (context, c) {
      final handler = c.extensions.toolHandlers[EditorTool.lasso];
      final selection = handler is LassoHandler ? handler.state.selection : null;
      final useSelection =
          selection != null && hasConvertibleStrokes(c, selection);
      return open(context, useSelection ? selection : null);
    }
    ..convertSelection = (context, c, selection) => open(context, selection);
};
