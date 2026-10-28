import 'package:flutter/widgets.dart';

import '../../../../ink/vec2.dart';
import '../../tools/selection.dart';

/// What the lasso tool shows: the lasso being drawn, the current selection
/// and whether it is being dragged. The page overlay and the floating menu
/// listen to it.
class LassoState extends ChangeNotifier {
  Selection? _selection;
  String? _lassoPageId;
  List<Vec2> _lassoPath = const [];
  bool _busy = false;

  /// The selected things, or null when nothing is selected.
  Selection? get selection => _selection;

  /// The page and (closed-on-release) path of the lasso being drawn.
  String? get lassoPageId => _lassoPageId;
  List<Vec2> get lassoPath => _lassoPath;

  /// True while the selection is being moved / resized or a lasso is being
  /// drawn: the menu stays out of the way.
  bool get busy => _busy;

  /// Where the floating menu is on screen (viewport-local), so the canvas
  /// doesn't treat taps on its buttons as lasso gestures. Set by the menu's
  /// layout; null when the menu is hidden. Does not notify.
  Rect? menuRect;

  /// Where a lasso tap on an empty spot asked to paste: the "Paste" bubble
  /// shows there while the clipboard has something. Null: no bubble.
  ({String pageId, Vec2 point})? get pasteTarget => _pasteTarget;
  ({String pageId, Vec2 point})? _pasteTarget;

  /// Where the "Paste" bubble is on screen, like [menuRect].
  Rect? pasteRect;

  void setPasteTarget(({String pageId, Vec2 point})? target) {
    if (_pasteTarget == target) return;
    _pasteTarget = target;
    if (target == null) pasteRect = null;
    notifyListeners();
  }

  void setSelection(Selection? next) {
    if (next != null && next.isEmpty) next = null;
    _selection = next;
    if (next != null) {
      _pasteTarget = null;
      pasteRect = null;
    }
    notifyListeners();
  }

  void setLasso(String? pageId, List<Vec2> path) {
    _lassoPageId = pageId;
    _lassoPath = path;
    notifyListeners();
  }

  void setBusy(bool busy) {
    if (_busy == busy) return;
    _busy = busy;
    notifyListeners();
  }

  void clear() {
    _selection = null;
    _lassoPageId = null;
    _lassoPath = const [];
    _busy = false;
    menuRect = null;
    _pasteTarget = null;
    pasteRect = null;
    notifyListeners();
  }
}
