import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../ink/ink_point.dart';
import '../../../../ink/stroke.dart';
import '../../editor_controller.dart';
import '../../editor_tool.dart';
import 'text_editor.dart';

/// Tuning of the writing bar.
abstract final class WriteBarConfig {
  /// Pause after the pen lifts before the writing is read and added: long
  /// enough for an i-dot or a t-bar, short enough to feel quick.
  static const Duration readAfter = Duration(milliseconds: 1200);

  /// Height of the writing strip, in logical pixels.
  static const double padHeight = 120;

  /// The guide line, as a fraction of the strip's height from its top.
  static const double guideLine = 0.68;

  /// Width of the pen in the strip.
  static const double inkWidth = 2.6;
}

/// [written] put into [value] (v1.13.0, the writing bar): in place of the
/// selection, else at the cursor, else at the end. A space goes before it
/// unless it starts the text, follows a space or an opening bracket, or is
/// closing punctuation (",", ".", ")"...: spaces before those are dropped);
/// a space goes after it when a word follows. The cursor ends after the
/// inserted words.
({TextEditingValue value, int start, int end}) insertWritten(TextEditingValue value, String written) {
  final text = value.text;
  var sel = value.selection;
  if (!sel.isValid) sel = TextSelection.collapsed(offset: text.length);
  var start = sel.start.clamp(0, text.length);
  final end = sel.end.clamp(start, text.length);
  final words = written.trim();
  if (words.isEmpty) return (value: value, start: start, end: start);
  final closing = RegExp(r'^[,.;:!?)\]}%”’]').hasMatch(words);
  if (closing) {
    while (start > 0 && text[start - 1] == ' ') {
      start--;
    }
  }
  final before = text.substring(0, start);
  final after = text.substring(end);
  final spaceBefore = !closing && before.isNotEmpty && !RegExp(r'[\s(\[{“‘"]$').hasMatch(before);
  final spaceAfter = after.isNotEmpty && RegExp(r'^[\p{L}\p{N}(“‘"]', unicode: true).hasMatch(after);
  final inserted = '${spaceBefore ? ' ' : ''}$words';
  final out = '$before$inserted${spaceAfter ? ' ' : ''}$after';
  final caret = start + inserted.length;
  return (
    value: TextEditingValue(text: out, selection: TextSelection.collapsed(offset: caret)),
    start: start,
    end: caret,
  );
}

/// Under the pages while a text box is being edited (v1.13.0): a strip to
/// write in with the pen, whose words go in at the cursor of the box, with
/// Space, Delete, cursor buttons, the keyboard and Done. With the keyboard
/// on it is one slim row (back to the pen, Done).
///
/// Mariam's typed text could only grow at its end: to add a word in the
/// middle she had to delete the rest of the sentence and write it again.
class TextWriteBar extends StatefulWidget {
  const TextWriteBar({super.key, required this.editor, required this.controller});

  final TextBoxEditor editor;
  final EditorController controller;

  @override
  State<TextWriteBar> createState() => _TextWriteBarState();
}

class _PadPoint {
  const _PadPoint(this.at, this.pressure, this.t);

  final Offset at;
  final double pressure;
  final int t;
}

/// The last words the bar added, to take them back.
class _Added {
  const _Added(this.session, this.before, this.after, this.words);

  final TextEditSession session;
  final TextEditingValue before;
  final String after;
  final String words;
}

class _TextWriteBarState extends State<TextWriteBar> {
  final List<List<_PadPoint>> _strokes = [];
  List<_PadPoint>? _current;
  int? _pointer;
  Timer? _timer;
  bool _reading = false;
  String? _problem;
  _Added? _added;
  TextEditSession? _shownFor;

  TextBoxEditor get _editor => widget.editor;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool _penLike(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.mouse ||
      (kind == PointerDeviceKind.touch && widget.controller.settings.drawWithFinger);

  void _down(PointerDownEvent e) {
    if (_pointer != null || !_penLike(e.kind)) return;
    _timer?.cancel();
    _pointer = e.pointer;
    setState(() {
      _problem = null;
      _current = [_PadPoint(e.localPosition, e.pressure.clamp(0.0, 1.0), e.timeStamp.inMilliseconds)];
      _strokes.add(_current!);
    });
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    setState(() => _current?.add(_PadPoint(e.localPosition, e.pressure.clamp(0.0, 1.0), e.timeStamp.inMilliseconds)));
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _current = null;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(WriteBarConfig.readAfter, () => unawaited(_read()));
  }

  void _clearPad() {
    _timer?.cancel();
    setState(() {
      _strokes.clear();
      _current = null;
      _pointer = null;
      _problem = null;
    });
  }

  static List<Stroke> _toStrokes(List<List<_PadPoint>> strokes) => [
        for (var i = 0; i < strokes.length; i++)
          Stroke(
            id: 'write-bar-$i',
            tool: StrokeTool.pen,
            color: 0xFF1E1E1E,
            size: WriteBarConfig.inkWidth,
            raw: [for (final p in strokes[i]) InkPoint(p.at.dx, p.at.dy, p.pressure, p.t)],
          ),
      ];

  /// Reads the strip and puts the words in at the cursor.
  Future<void> _read() async {
    final read = widget.controller.extensions.readHandwriting;
    final s = _editor.session;
    if (read == null || s == null || _reading || _pointer != null || _strokes.isEmpty) return;
    final taken = List.of(_strokes);
    final value = s.input.value;
    final at = value.selection.isValid ? value.selection.start : value.text.length;
    final before = value.text.substring(0, at.clamp(0, value.text.length));
    setState(() => _reading = true);
    var words = '';
    try {
      words = await read(_toStrokes(taken), before: before.trim().isEmpty ? null : before);
    } catch (e) {
      debugPrint('NeatInk: reading the writing bar failed: $e');
    }
    if (!mounted) return;
    setState(() {
      _reading = false;
      _strokes.removeWhere((st) => taken.any((t) => identical(t, st)));
    });
    if (!identical(_editor.session, s)) return;
    if (words.trim().isEmpty) {
      setState(() => _problem = "Couldn't read that. Write it again, a little bigger.");
    } else {
      final old = s.input.value;
      final r = insertWritten(old, words);
      _editor.setValue(r.value);
      if (!s.focus.hasFocus) s.focus.requestFocus();
      setState(() {
        _problem = null;
        _added = _Added(s, old, r.value.text, words.trim());
      });
    }
    // Words written while these were read come next.
    if (_strokes.isNotEmpty && _pointer == null) _schedule();
  }

  void _takeBack() {
    final a = _added;
    final s = _editor.session;
    if (a == null || s == null || !identical(a.session, s)) return;
    if (s.input.text == a.after) _editor.setValue(a.before);
    setState(() => _added = null);
  }

  TextEditingValue? get _value {
    final s = _editor.session;
    if (s == null) return null;
    final v = s.input.value;
    return v.selection.isValid ? v : v.copyWith(selection: TextSelection.collapsed(offset: v.text.length));
  }

  void _set(TextEditingValue v) {
    _editor.setValue(v);
    final s = _editor.session;
    if (s != null && !s.focus.hasFocus) s.focus.requestFocus();
    setState(() => _added = null);
  }

  void _moveCursor(int delta) {
    final v = _value;
    if (v == null) return;
    final sel = v.selection;
    final at = sel.isCollapsed ? sel.start + delta : (delta < 0 ? sel.start : sel.end);
    _set(v.copyWith(selection: TextSelection.collapsed(offset: at.clamp(0, v.text.length))));
  }

  void _space() {
    final v = _value;
    if (v == null) return;
    _set(v.replaced(v.selection, ' '));
  }

  void _backspace() {
    final v = _value;
    if (v == null) return;
    final sel = v.selection;
    if (!sel.isCollapsed) {
      _set(v.replaced(sel, ''));
      return;
    }
    if (sel.start == 0) return;
    var from = sel.start - 1;
    // Never split a character made of two code units.
    final unit = v.text.codeUnitAt(from);
    if (from > 0 && unit >= 0xDC00 && unit <= 0xDFFF) from--;
    _set(v.replaced(TextRange(start: from, end: sel.start), ''));
  }

  void _done() {
    _timer?.cancel();
    final back = _editor.returnTool;
    _editor.commit();
    _editor.returnTool = null;
    if (back != null) widget.controller.selectTool(back);
  }

  /// Scrolls the page so the box being edited is in view above the bar.
  void _reveal(TextEditSession s) {
    final c = widget.controller;
    if (!mounted || !identical(_editor.session, s) || !c.isReady) return;
    final index = c.doc.meta.pages.indexWhere((p) => p.id == s.pageId);
    final viewport = c.viewport;
    if (index < 0 || !viewport.hasSize || index >= viewport.layout.rects.length) return;
    final page = viewport.layout.rects[index];
    final d = s.draft;
    viewport.ensureVisible(Rect.fromLTWH(page.left + d.x, page.top + d.y, d.width, d.height));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_editor, widget.controller]),
      builder: (context, _) {
        final s = _editor.session;
        if (s == null || widget.controller.tool != EditorTool.text) {
          _shownFor = null;
          return const SizedBox.shrink();
        }
        if (!identical(s, _shownFor)) {
          // A new edit: an empty strip, and the box in view.
          _shownFor = s;
          _timer?.cancel();
          _strokes.clear();
          _current = null;
          _pointer = null;
          _problem = null;
          _added = null;
          WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(s));
        }
        final scheme = Theme.of(context).colorScheme;
        final canWrite = widget.controller.extensions.readHandwriting != null;
        return Material(
          key: const ValueKey('write-bar'),
          color: scheme.surfaceContainer,
          elevation: 3,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: s.keyboard || !canWrite ? _keyboardRow(context, canWrite) : _penBar(context),
            ),
          ),
        );
      },
    );
  }

  Widget _keyboardRow(BuildContext context, bool canWrite) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.keyboard_outlined, color: scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Typing with the keyboard. Tap in the text to move the cursor.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
        if (canWrite)
          TextButton.icon(
            key: const ValueKey('write-pen'),
            onPressed: () => _editor.useKeyboard(false),
            icon: const Icon(Icons.draw_outlined),
            label: const Text('Write with the pen'),
          ),
        const SizedBox(width: 8),
        FilledButton(key: const ValueKey('write-done'), onPressed: _done, child: const Text('Done')),
      ],
    );
  }

  Widget _penBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final added = _added;
    final Widget status;
    if (_problem != null) {
      status = Text(_problem!, key: const ValueKey('write-problem'), style: TextStyle(color: scheme.error));
    } else if (added != null && identical(added.session, _editor.session)) {
      status = Row(
        children: [
          Icon(Icons.check_circle_outline, size: 18, color: scheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text('Added “${added.words}”', key: const ValueKey('write-added'), overflow: TextOverflow.ellipsis),
          ),
          TextButton(key: const ValueKey('write-undo'), onPressed: _takeBack, child: const Text('Take back')),
        ],
      );
    } else {
      status = Text(
        'Tap in the text where the words go, then write them here with the pen. '
        'They are added when you stop writing.',
        style: TextStyle(color: scheme.onSurfaceVariant),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 32, child: Align(alignment: Alignment.centerLeft, child: status)),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _pad(context)),
            const SizedBox(width: 10),
            SizedBox(
              width: 220,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _key('write-left', Icons.chevron_left, 'Move the cursor left', () => _moveCursor(-1)),
                      _key('write-right', Icons.chevron_right, 'Move the cursor right', () => _moveCursor(1)),
                      _key('write-space', Icons.space_bar, 'Space', _space),
                      _key('write-backspace', Icons.backspace_outlined, 'Delete the letter before the cursor', _backspace),
                    ],
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    key: const ValueKey('write-keyboard'),
                    onPressed: () {
                      _timer?.cancel();
                      _editor.useKeyboard(true);
                    },
                    icon: const Icon(Icons.keyboard_outlined),
                    label: const Text('Keyboard'),
                  ),
                  const SizedBox(height: 6),
                  FilledButton(key: const ValueKey('write-done'), onPressed: _done, child: const Text('Done')),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _key(String key, IconData icon, String tooltip, VoidCallback onPressed) => Expanded(
        child: IconButton(key: ValueKey(key), tooltip: tooltip, onPressed: onPressed, icon: Icon(icon)),
      );

  Widget _pad(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Listener(
      key: const ValueKey('write-pad'),
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: Container(
        height: WriteBarConfig.padHeight,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _PadPainter(
                  strokes: _strokes,
                  ink: scheme.onSurface,
                  guide: scheme.outlineVariant,
                  version: _strokes.fold(0, (n, s) => n + s.length),
                ),
              ),
            ),
            if (_strokes.isEmpty && !_reading)
              Center(
                child: Text(
                  'Write here',
                  style: TextStyle(fontSize: 20, color: scheme.onSurfaceVariant.withAlpha(0x88)),
                ),
              ),
            if (_reading)
              const Positioned(
                right: 12,
                top: 12,
                child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
              )
            else if (_strokes.isNotEmpty && _pointer == null)
              Positioned(
                right: 2,
                top: 2,
                child: IconButton(
                  key: const ValueKey('write-clear'),
                  tooltip: 'Clear what you wrote here',
                  onPressed: _clearPad,
                  icon: const Icon(Icons.close),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter({required this.strokes, required this.ink, required this.guide, required this.version});

  final List<List<_PadPoint>> strokes;
  final Color ink;
  final Color guide;

  /// Points drawn so far: the strip repaints when it changes.
  final int version;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * WriteBarConfig.guideLine;
    canvas.drawLine(
      Offset(16, y),
      Offset(size.width - 16, y),
      Paint()
        ..color = guide
        ..strokeWidth = 1.5,
    );
    final pen = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = WriteBarConfig.inkWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final s in strokes) {
      if (s.isEmpty) continue;
      if (s.length == 1) {
        canvas.drawCircle(s.first.at, WriteBarConfig.inkWidth / 2, Paint()..color = ink);
        continue;
      }
      final path = Path()..moveTo(s.first.at.dx, s.first.at.dy);
      for (final p in s.skip(1)) {
        path.lineTo(p.at.dx, p.at.dy);
      }
      canvas.drawPath(path, pen);
    }
  }

  @override
  bool shouldRepaint(_PadPainter old) =>
      old.version != version || old.ink != ink || old.guide != guide || old.strokes.length != strokes.length;
}
