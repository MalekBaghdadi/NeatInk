import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../editor_controller.dart';
import '../../../../document/page_items.dart';
import '../convert/convert_scope.dart';
import '../text_images/text_format_bar.dart';
import '../../tool_prefs.dart';
import '../../toolbar/color_picker_dialog.dart';
import '../../toolbar/toolbar_widgets.dart';
import 'lasso_handler.dart';
import 'lasso_state.dart';
import 'selection_geometry.dart';

/// The floating menu over the selection (screen space): delete, colour,
/// restore original, cut, copy, duplicate, convert, and the style of
/// selected typed text (font, size, bold, italic, underline). It sits above the selection, or below it
/// when there is no room, and hides while the selection is being dragged.
class SelectionMenu extends StatefulWidget {
  const SelectionMenu({super.key, required this.handler, required this.controller});

  final LassoHandler handler;
  final EditorController controller;

  @override
  State<SelectionMenu> createState() => _SelectionMenuState();
}

class _SelectionMenuState extends State<SelectionMenu> {
  bool _colorsOpen = false;
  bool _textOpen = false;

  LassoHandler get _handler => widget.handler;
  EditorController get _controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final state = _handler.state;
    return ListenableBuilder(
      listenable: Listenable.merge([state, _controller.viewport, _controller]),
      builder: (context, _) {
        final sel = state.selection;
        final index = sel == null
            ? -1
            : _controller.viewport.layout.indexOfPage(sel.pageId);
        if (sel == null || index < 0 || state.busy || !_controller.isReady) {
          state.menuRect = null;
          _colorsOpen = false;
          _textOpen = false;
          return const SizedBox.shrink();
        }
        final frame = selectionFrame(sel.bounds, _controller.viewport.scale);
        final tl = _controller.viewport.pageToLocal(index, frame.topLeft);
        final br = _controller.viewport.pageToLocal(index, frame.bottomRight);
        return CustomSingleChildLayout(
          delegate: _MenuLayout(Rect.fromPoints(tl, br), state),
          child: _bar(context),
        );
      },
    );
  }

  /// The Convert button shows when the convert feature is installed and the
  /// selection holds pen strokes to read.
  bool get _canConvert {
    final sel = _handler.state.selection;
    return _controller.extensions.convertSelection != null &&
        sel != null &&
        hasConvertibleStrokes(_controller, sel);
  }

  /// After Copy / Cut: typed text also goes to the system clipboard (for
  /// other apps), and a note says how to paste.
  void _copied(String? text) {
    if (text == null) return;
    if (text.isNotEmpty) Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Copied. To paste, tap an empty spot with the lasso, or use More › Paste.'),
      ));
  }

  /// Opens the first selected text box for typing.
  void _editText() {
    final item = _handler.firstSelectedText;
    final pageId = _handler.state.selection?.pageId;
    final edit = _controller.extensions.editText;
    if (item == null || pageId == null || edit == null) return;
    // Switching to the text tool ends the lasso selection.
    edit(pageId, item);
  }

  void _convert() {
    final sel = _handler.state.selection;
    final action = _controller.extensions.convertSelection;
    if (sel == null || action == null) return;
    action(context, _controller, sel);
  }

  Widget _bar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_handler.firstSelectedText != null && _controller.extensions.editText != null)
                  _MenuButton(
                    key: const ValueKey('selection-edit'),
                    icon: Icons.edit_outlined,
                    label: 'Edit text',
                    onPressed: _editText,
                  ),
                _MenuButton(
                  key: const ValueKey('selection-delete'),
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  onPressed: _handler.deleteSelected,
                ),
                _MenuButton(
                  key: const ValueKey('selection-colour'),
                  icon: Icons.palette_outlined,
                  label: 'Colour',
                  selected: _colorsOpen,
                  onPressed: _handler.canRecolor
                      ? () => setState(() {
                            _colorsOpen = !_colorsOpen;
                            if (_colorsOpen) _textOpen = false;
                          })
                      : null,
                ),
                if (_handler.firstSelectedText != null)
                  _MenuButton(
                    key: const ValueKey('selection-text-style'),
                    icon: Icons.text_format,
                    label: 'Text style',
                    selected: _textOpen,
                    onPressed: () => setState(() {
                      _textOpen = !_textOpen;
                      if (_textOpen) _colorsOpen = false;
                    }),
                  ),
                _MenuButton(
                  key: const ValueKey('selection-restore'),
                  icon: Icons.history,
                  label: 'Restore original',
                  onPressed:
                      _handler.canRestoreOriginal ? _handler.restoreOriginal : null,
                ),
                if (_handler.clipboard != null) ...[
                  _MenuButton(
                    key: const ValueKey('selection-cut'),
                    icon: Icons.content_cut,
                    label: 'Cut',
                    onPressed: () => _copied(_handler.cutSelected()),
                  ),
                  _MenuButton(
                    key: const ValueKey('selection-copy'),
                    icon: Icons.content_copy_outlined,
                    label: 'Copy',
                    onPressed: () => _copied(_handler.copySelected()),
                  ),
                ],
                _MenuButton(
                  key: const ValueKey('selection-duplicate'),
                  icon: Icons.control_point_duplicate,
                  label: 'Duplicate',
                  onPressed: _handler.duplicateSelected,
                ),
                if (_canConvert)
                  _MenuButton(
                    key: const ValueKey('selection-convert'),
                    icon: Icons.text_fields,
                    label: 'Convert to text',
                    onPressed: _convert,
                  ),
              ],
            ),
            if (_colorsOpen) _colors(context),
            if (_textOpen && _handler.firstSelectedText != null) _textStyle(_handler.firstSelectedText!),
          ],
        ),
      ),
    );
  }

  /// Font, size, bold, italic and underline of the selected typed text
  /// (all selected boxes; the first one's style is shown).
  Widget _textStyle(TextItem t) {
    void apply(TextItem Function(TextItem t) change) => _handler.restyleTexts(change);
    Widget toggle(String key, String tip, IconData icon, bool on, TextItem Function(TextItem t) change) =>
        _MenuButton(key: ValueKey(key), icon: icon, label: tip, selected: on, onPressed: () => apply(change));
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PopupMenuButton<FontKind>(
          key: const ValueKey('selection-font'),
          tooltip: 'Font',
          initialValue: t.font,
          onSelected: (f) => apply((x) => x.copyWith(font: f)),
          itemBuilder: (_) => TextFormatBar.fontPickerItems(t.font),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: SizedBox(
              height: toolbarTargetSize,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(t.font.label, style: TextStyle(fontFamily: t.font.family)),
                const Icon(Icons.arrow_drop_down),
              ]),
            ),
          ),
        ),
        _MenuButton(
          key: const ValueKey('selection-size-down'),
          icon: Icons.remove,
          label: 'Smaller',
          onPressed: () => apply((x) => x.copyWith(fontSize: steppedFontSize(x.fontSize, up: false))),
        ),
        SizedBox(
          width: 32,
          child: Text(
            t.fontSize == t.fontSize.roundToDouble() ? t.fontSize.round().toString() : t.fontSize.toStringAsFixed(1),
            key: const ValueKey('selection-size'),
            textAlign: TextAlign.center,
          ),
        ),
        _MenuButton(
          key: const ValueKey('selection-size-up'),
          icon: Icons.add,
          label: 'Larger',
          onPressed: () => apply((x) => x.copyWith(fontSize: steppedFontSize(x.fontSize, up: true))),
        ),
        toggle('selection-bold', 'Bold', Icons.format_bold, t.bold, (x) => x.copyWith(bold: !t.bold)),
        toggle('selection-italic', 'Italic', Icons.format_italic, t.italic, (x) => x.copyWith(italic: !t.italic)),
        toggle('selection-underline', 'Underline', Icons.format_underlined, t.underline,
            (x) => x.copyWith(underline: !t.underline)),
      ],
    );
  }

  Widget _colors(BuildContext context) {
    final current = _handler.commonColor;
    final prefs = _controller.toolPrefs;
    final recent = customRecentColors(prefs);
    final isPreset = current == null || ToolPresets.penColors.contains(current);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 8 * toolbarTargetSize + 16),
      child: Wrap(
        alignment: WrapAlignment.center,
        children: [
          for (final c in ToolPresets.penColors)
            ColorSwatchButton(
              color: c,
              selected: c == current,
              onPressed: () => _handler.recolorSelected(c),
            ),
          CustomColorButton(
            customColor: isPreset ? null : current,
            onPressed: () async {
              final picked = await showColorPickerDialog(
                context,
                initialColor: isPreset
                    ? (recent.isEmpty ? defaultCustomColor : recent.first)
                    : current,
                recentColors: recent,
                title: 'Selection colour',
              );
              if (picked == null) return;
              _controller.updateToolPrefs((p) => ToolPresets.penColors
                      .contains(picked)
                  ? p
                  : p.withRecentColor(picked));
              _handler.recolorSelected(picked);
            },
          ),
        ],
      ),
    );
  }
}

/// A labelled icon button of the menu.
class _MenuButton extends StatelessWidget {
  const _MenuButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: label,
      isSelected: selected,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        minimumSize: const Size.square(toolbarTargetSize),
        foregroundColor: scheme.onSurfaceVariant,
        backgroundColor: selected ? scheme.secondaryContainer : null,
      ),
    );
  }
}

/// Puts the menu above (or below) the selection frame, kept inside the
/// view, and tells the lasso state where it ended up.
class _MenuLayout extends SingleChildLayoutDelegate {
  _MenuLayout(this.target, this.state);

  final Rect target;
  final LassoState state;

  static const double _gap = 12;
  static const double _margin = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxX = math.max(_margin, size.width - childSize.width - _margin);
    final x = (target.center.dx - childSize.width / 2).clamp(_margin, maxX);
    var y = target.top - childSize.height - _gap;
    if (y < _margin) y = target.bottom + _gap;
    final maxY = math.max(_margin, size.height - childSize.height - _margin);
    y = y.clamp(_margin, maxY);
    final offset = Offset(x.toDouble(), y);
    state.menuRect = offset & childSize;
    return offset;
  }

  @override
  bool shouldRelayout(_MenuLayout old) => old.target != target;
}
