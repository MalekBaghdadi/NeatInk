import '../../editor_integrations.dart';
import 'page_navigator.dart';
import 'page_ops.dart';
import 'paper_picker.dart';
import 'quick_nav.dart';

export 'page_ops.dart' show PageOps;

/// Page tools: the thumbnail grid (jump, reorder, duplicate, insert,
/// delete with undo, change paper), a "Page paper" action for the page in
/// view, and a floating previous / next / jump-to-page control.
// ignore: prefer_function_declarations_over_variables
final EditorIntegration pagesIntegration = (controller, ref) {
  final ops = PageOps(controller);
  controller.extensions
    ..openPageNavigator =
        ((context, c) => showPageNavigator(context, c))
    ..changePagePaper = (context, c) async {
      if (!c.isReady) return;
      final index = c.currentPageIndex;
      if (!ops.canChangePaper(index)) return;
      final choice = await showPaperPicker(context,
          initial: c.doc.meta.pages[index].paper);
      if (choice == null) return;
      if (choice.allPages) {
        ops.setPaperAll(choice.paper);
      } else {
        ops.setPaper(index, choice.paper);
      }
    }
    ..viewportOverlays
        .add((context, c) => QuickPageNav(controller: c, ops: ops));
};
