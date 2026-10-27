import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/app_info.dart';
import '../../../settings/convert_style_prefs.dart';
import '../../../settings/settings_controller.dart';
import '../../editor_integrations.dart';
import '../../editor_tool.dart';
import '../../tools/selection.dart';
import '../erase_select/lasso_handler.dart';
import 'auto_convert_indicator.dart';
import 'auto_convert_session.dart';
import 'convert_layout.dart';
import 'convert_providers.dart';
import 'convert_scope.dart';
import 'convert_sheet.dart';
import 'sample_share.dart';
import 'user_lexicon.dart';

export 'convert_providers.dart' show htrRecognizerProvider, wordImageRendererProvider;
export 'sample_share.dart' show sampleShareServiceProvider;
export 'user_lexicon.dart' show userLexiconProvider;

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
///
/// It also installs an [AutoConvertSession] that follows the `autoConvert`
/// setting: when on, the handwriting is converted by itself about a second
/// after the pen stops, in the look remembered by [convertStylePrefsProvider].
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
    final styleController = ref.read(convertStylePrefsProvider.notifier);
    await showConvertSheet(
      context,
      controller,
      recognizer: ref.read(htrRecognizerProvider),
      renderer: ref.read(wordImageRendererProvider),
      selection: selection,
      initialStyle: ref.read(convertStylePrefsProvider),
      onStyleChosen: styleController.save,
      learner: ref.read(userLexiconProvider),
      sampleShare: ref.read(sampleShareServiceProvider),
      appVersion: '${AppInfo.version}+${AppInfo.buildNumber}',
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

  // Auto-convert: follows the setting, never runs inside the pen path.
  final auto = AutoConvertSession(
    controller: controller,
    recognizer: ref.read(htrRecognizerProvider),
    readStyle: () =>
        ConvertStyle.fromPrefs(ref.read(convertStylePrefsProvider)),
    enabled: ref.read(settingsProvider).autoConvert,
  );
  final subscription = ref.listenManual(
    settingsProvider.select((s) => s.autoConvert),
    (_, enabled) => auto.setEnabled(enabled),
  );
  controller.extensions.viewportOverlays
      .add((context, c) => AutoConvertIndicator(session: auto));
  controller.addDisposeCallback(() {
    subscription.close();
    auto.dispose();
  });
};
