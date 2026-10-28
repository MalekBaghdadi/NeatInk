import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../document/page_items.dart';
import '../../../../ink/affine2.dart';
import '../../../../ink/ink_rect.dart';
import '../../../../ink/stroke.dart';
import '../../../../ink/vec2.dart';

// Copy, cut and paste (v1.7.0): the lasso's Copy / Cut put the selected
// strokes, text boxes and pictures on an app-wide clipboard, and Paste puts
// them on any page of any notebook. Pictures are files of their notebook, so
// their bytes are read when copying (a cut picture's file may be cleaned up
// before it is pasted elsewhere).

/// A picture on the clipboard: the item as it was, and its file's bytes
/// (read in the background; null when the file could not be read).
class ClipImage {
  ClipImage({required this.item, required this.extension, required this.bytes});

  final ImageItem item;

  /// The file's extension, with the dot (`.jpg`).
  final String extension;
  final Future<Uint8List?> bytes;
}

/// What was copied, in the page coordinates of the page it came from.
class ClipContent {
  ClipContent({
    required this.notebookId,
    required this.strokes,
    required this.texts,
    required this.images,
  }) : bounds = _bounds(strokes, texts, images);

  final String notebookId;
  final List<Stroke> strokes;
  final List<TextItem> texts;
  final List<ClipImage> images;

  /// Around everything copied.
  final InkRect bounds;

  bool get isEmpty => strokes.isEmpty && texts.isEmpty && images.isEmpty;

  static InkRect _bounds(List<Stroke> strokes, List<TextItem> texts, List<ClipImage> images) {
    InkRect? r;
    void add(InkRect b) => r = r == null ? b : r!.union(b);
    for (final s in strokes) {
      if (s.points.isNotEmpty) add(s.paintBounds);
    }
    for (final t in texts) {
      add(t.frame);
    }
    for (final i in images) {
      add(InkRect.fromLTWH(i.item.x, i.item.y, i.item.width, i.item.height));
    }
    return r ?? InkRect.empty;
  }
}

/// The app-wide clipboard (one for every notebook).
class EditorClipboard extends ChangeNotifier {
  ClipContent? _content;

  /// What is on it, or null.
  ClipContent? get content => _content;

  bool get hasContent => _content != null && !_content!.isEmpty;

  void put(ClipContent content) {
    _content = content.isEmpty ? null : content;
    notifyListeners();
  }

  void clear() {
    _content = null;
    notifyListeners();
  }
}

/// The clipboard, shared by every editor while the app runs.
final editorClipboardProvider = Provider<EditorClipboard>((ref) {
  final clipboard = EditorClipboard();
  ref.onDispose(clipboard.dispose);
  return clipboard;
});

/// How far [content] moves so its middle lands on [center], kept inside a
/// page of [pageWidth] x [pageHeight] (its top-left corner on the page when
/// it is larger than the page).
Vec2 pasteOffset(InkRect bounds, Vec2 center, {required double pageWidth, required double pageHeight}) {
  final w = bounds.width, h = bounds.height;
  final left = (center.x - w / 2).clamp(0.0, math.max(0.0, pageWidth - w));
  final top = (center.y - h / 2).clamp(0.0, math.max(0.0, pageHeight - h));
  return Vec2(left - bounds.left, top - bounds.top);
}

/// [content]'s strokes and text boxes moved by [offset], with new ids.
({List<Stroke> strokes, List<TextItem> texts}) pastedInk(ClipContent content, Vec2 offset, String Function() newId) {
  final shift = Affine2.translation(offset.x, offset.y);
  return (
    strokes: [for (final s in content.strokes) s.transformed(shift).copyWith(id: newId())],
    texts: [
      for (final t in content.texts) t.copyWith(id: newId(), x: t.x + offset.x, y: t.y + offset.y),
    ],
  );
}

/// The text of the typed boxes in [texts], in reading order (top to bottom,
/// then left to right), one box per paragraph: what other apps get.
String plainTextOf(List<TextItem> texts) {
  final sorted = [...texts]..sort((a, b) {
      final dy = a.y - b.y;
      if (dy.abs() > 4) return dy.sign.toInt();
      return a.x.compareTo(b.x);
    });
  return [
    for (final t in sorted)
      if (t.text.trim().isNotEmpty) t.text.trim(),
  ].join('\n\n');
}
