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

  void setSelection(Selection? next) {
    if (next != null && next.isEmpty) next = null;
    _selection = next;
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
    notifyListeners();
  }
}
