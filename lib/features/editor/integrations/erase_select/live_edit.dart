import '../../../../document/commands.dart';
import '../../editor_controller.dart';

/// Shows an edit on the page while a gesture is still going on, then turns
/// it into exactly one undo step.
///
/// Every [show] reverts the previous preview and applies the new command
/// straight to the document (no undo entry), so the canvas, the selection
/// bounds and the autosave all follow the pen. [commit] reverts the preview
/// and runs the same command through `controller.execute`, which records
/// it. [discard] just reverts it. Because the preview is always undone
/// before anything else happens, the document is never left half-edited.
class LiveEdit {
  LiveEdit(this.controller);

  final EditorController controller;

  EditCommand? _command;
  String? _pageId;

  /// True while a preview is applied.
  bool get isShowing => _command != null;

  /// Replaces the shown preview with [command] (null shows nothing).
  void show(String pageId, EditCommand? command) {
    _revert(notify: true);
    if (command == null || !controller.isPageEditable(pageId)) return;
    _command = command;
    _pageId = pageId;
    controller.doc.notify(command.apply(controller.doc));
  }

  /// Records the shown preview as one undo step. Returns false when there
  /// was nothing to record.
  bool commit() {
    final command = _command;
    if (command == null) return false;
    if (!_revert(notify: false)) return false;
    controller.execute(command);
    return true;
  }

  /// Takes the preview back.
  void discard() => _revert(notify: true);

  /// Reverts the shown command. Returns false when its page is gone (the
  /// preview is dropped; nothing is left to revert).
  bool _revert({required bool notify}) {
    final command = _command;
    if (command == null) return false;
    _command = null;
    final pageId = _pageId!;
    _pageId = null;
    if (!controller.isPageEditable(pageId)) return false;
    final change = command.revert(controller.doc);
    if (notify) controller.doc.notify(change);
    return true;
  }
}
