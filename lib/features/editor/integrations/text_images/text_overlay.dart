import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../ink/vec2.dart';
import '../../../../render/text_style.dart';
import '../../canvas/viewport_controller.dart';
import '../../editor_extensions.dart';
import '../../editor_tool.dart';
import 'frame_geometry.dart';
import 'text_editor.dart';

/// The page overlay of the text tool:
///
/// * a tap layer for fingers (they normally navigate, so the tool never
///   sees them): tapping a box edits it, tapping paper starts a new box;
/// * the text field of the box being edited, zoomed with the page, inside a
///   frame with a width handle.
PageOverlayBuilder textPageOverlay(TextBoxEditor editor) =>
    (context, page) => TextPageOverlay(editor: editor, info: page);

class TextPageOverlay extends StatelessWidget {
  const TextPageOverlay({super.key, required this.editor, required this.info});

  final TextBoxEditor editor;
  final EditorPageInfo info;

  @override
  Widget build(BuildContext context) {
    final controller = info.controller;
    return ListenableBuilder(
      listenable: Listenable.merge([editor, controller]),
      builder: (context, _) {
        if (controller.tool != EditorTool.text) return const SizedBox.shrink();
        final s = editor.session;
        final editing = s != null && s.pageId == info.pageId ? s : null;
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            // Fingers: pen and mouse go through the tool handler instead.
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: (d) {
                if (!_isFinger(d.kind) ||
                    controller.settings.drawWithFinger ||
                    controller.inputRouter.stylusDown) {
                  return;
                }
                editor.tap(info.pageId,
                    Vec2(d.localPosition.dx, d.localPosition.dy),
                    controller.viewport.scale);
              },
            ),
            if (editing != null) ...[
              IgnorePointer(
                child: CustomPaint(
                  painter: _FramePainter(
                    frame: Rect.fromLTWH(editing.draft.x, editing.draft.y,
                        editing.draft.width, editing.draft.height),
                    viewport: controller.viewport,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              Positioned(
                left: editing.draft.x,
                top: editing.draft.y,
                // A caret needs 1pt of room; keep wrapping equal to the
                // committed layout.
                width: editing.draft.width + 1,
                child: _EditField(editor: editor, session: editing),
              ),
            ],
          ],
        );
      },
    );
  }

  static bool _isFinger(PointerDeviceKind? kind) =>
      kind == PointerDeviceKind.touch || kind == PointerDeviceKind.unknown;
}

class _EditField extends StatelessWidget {
  const _EditField({required this.editor, required this.session});

  final TextBoxEditor editor;
  final TextEditSession session;

  @override
  Widget build(BuildContext context) {
    final item = session.draft;
    final style = textStyleFor(item);
    final background = Color(item.background);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textItemScaler),
      child: ColoredBox(
      color: background,
      child: TextField(
        key: ValueKey('text-field-${item.id}'),
        controller: session.input,
        focusNode: session.focus,
        autofocus: session.wantFocus,
        style: style,
        textAlign: textAlignFor(item.align),
        maxLines: null,
        minLines: 1,
        keyboardType: TextInputType.multiline,
        // With the pen writing bar the keyboard stays away, but a tap still
        // places the cursor where the words go.
        readOnly: !session.keyboard,
        showCursor: true,
        textCapitalization: TextCapitalization.sentences,
        cursorColor: Color(item.color).withAlpha(0xFF),
        scrollPhysics: const NeverScrollableScrollPhysics(),
        // The tool decides what a tap outside means; don't unfocus here.
        onTapOutside: (_) {},
        decoration: InputDecoration.collapsed(
          hintText: 'Type here',
          hintStyle: style.copyWith(color: Color(item.color).withAlpha(0x55)),
        ),
        onChanged: (_) => editor.textChanged(),
      ),
    ));
  }
}

/// Outline of the box being edited plus the width handle on its right edge,
/// drawn at a constant size on screen whatever the zoom.
class _FramePainter extends CustomPainter {
  _FramePainter({
    required this.frame,
    required this.viewport,
    required this.color,
  }) : super(repaint: viewport);

  final Rect frame;
  final ViewportController viewport;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = viewport.scale;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / s;
    canvas.drawRect(frame.inflate(2 / s), line);
    // A faint band shows where a drag moves the box.
    canvas.drawRect(
      frame.inflate(moveBandPx / s),
      Paint()
        ..color = color.withAlpha(0x14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 / s,
    );
    final c = frame.centerRight;
    canvas
      ..drawCircle(c, handleRadiusPx / s, Paint()..color = Colors.white)
      ..drawCircle(c, handleRadiusPx / s, line)
      ..drawLine(c.translate(-4 / s, 0), c.translate(4 / s, 0), line);
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.frame != frame || old.color != color;
}
