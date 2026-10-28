import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../editor_controller.dart';
import 'lasso_handler.dart';
import 'lasso_state.dart';

/// The "Paste" bubble (screen space): after a lasso tap on an empty spot
/// while the clipboard holds something, it shows just above that spot, and
/// pastes there.
class PasteBubble extends StatelessWidget {
  const PasteBubble({super.key, required this.handler, required this.controller});

  final LassoHandler handler;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final state = handler.state;
    final clipboard = handler.clipboard;
    if (clipboard == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: Listenable.merge([state, clipboard, controller.viewport, controller]),
      builder: (context, _) {
        final target = state.pasteTarget;
        final index = target == null ? -1 : controller.viewport.layout.indexOfPage(target.pageId);
        if (target == null || index < 0 || state.busy || !clipboard.hasContent || !controller.isReady) {
          state.pasteRect = null;
          return const SizedBox.shrink();
        }
        final at = controller.viewport.pageToLocal(index, target.point);
        return CustomSingleChildLayout(
          delegate: _BubbleLayout(at, state),
          child: FilledButton.tonalIcon(
            key: const ValueKey('paste-bubble'),
            icon: const Icon(Icons.content_paste),
            label: const Text('Paste'),
            onPressed: () {
              state.setPasteTarget(null);
              unawaited(handler.pasteAt(target.pageId, target.point));
            },
          ),
        );
      },
    );
  }
}

class _BubbleLayout extends SingleChildLayoutDelegate {
  _BubbleLayout(this.at, this.state);

  final Offset at;
  final LassoState state;

  static const double _gap = 10;
  static const double _margin = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints.loose(constraints.biggest);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxX = math.max(_margin, size.width - childSize.width - _margin);
    final x = (at.dx - childSize.width / 2).clamp(_margin, maxX);
    var y = at.dy - childSize.height - _gap;
    if (y < _margin) y = at.dy + _gap;
    final maxY = math.max(_margin, size.height - childSize.height - _margin);
    final offset = Offset(x.toDouble(), y.clamp(_margin, maxY));
    state.pasteRect = offset & childSize;
    return offset;
  }

  @override
  bool shouldRelayout(_BubbleLayout old) => old.at != at;
}
