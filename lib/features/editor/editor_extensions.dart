import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../document/notebook_meta.dart';
import '../../document/page_content.dart';
import '../../ink/stroke.dart';
import '../../ink/vec2.dart';
import 'canvas/live_ink.dart';
import 'canvas/viewport_controller.dart';
import 'editor_controller.dart';
import 'editor_tool.dart';
import 'tools/selection.dart';

// Extension points of the editor core.
//
// The core implements the pen and highlighter, the viewport, rendering and
// saving. Everything else (eraser, lasso, text boxes, images, shapes, page
// navigator, tidy, PDF) plugs in through the types below: an
// `EditorIntegration` (editor_integrations.dart) registers them on
// `EditorController.extensions` when the editor screen is created.

/// A pointer event on the canvas, with its position already mapped to the
/// page under it.
class CanvasPointerEvent {
  const CanvasPointerEvent({
    required this.event,
    required this.localPosition,
    required this.hit,
    required this.pressure,
    this.isEraserButton = false,
  });

  /// The raw Flutter event.
  final PointerEvent event;

  /// Position in the document view, in logical pixels.
  final Offset localPosition;

  /// The page under the pointer, or null over gaps and margins. Use
  /// `controller.viewport.localToPage(localPosition, index)` to map the
  /// position onto a specific page (e.g. the page a gesture started on).
  final PageHit? hit;

  /// Pressure normalized to [0, 1] (0.5 when the device reports none).
  final double pressure;

  /// True when the pen's eraser end / button triggered this pointer, so an
  /// eraser should erase even though another tool is selected.
  final bool isEraserButton;

  int get pointer => event.pointer;
  PointerDeviceKind get kind => event.kind;
  Duration get timeStamp => event.timeStamp;
}

/// Handles the pointers of one tool on the canvas.
///
/// The canvas calls [onPointerDown] for each new pointer routed to the
/// tool. Returning true claims the pointer: it then receives
/// [onPointerMove] and exactly one of [onPointerUp] / [onPointerCancel].
/// An unclaimed finger falls back to scrolling.
///
/// Handlers change the document only through `EditorController.execute`.
abstract class CanvasToolHandler {
  bool onPointerDown(CanvasPointerEvent e);

  void onPointerMove(CanvasPointerEvent e);

  /// The pointer lifted: commit the gesture.
  void onPointerUp(CanvasPointerEvent e);

  /// The gesture was aborted (palm detected, a second finger turned it into
  /// a pinch, the system cancelled the touch): discard it.
  void onPointerCancel(CanvasPointerEvent e);

  /// The pen hovers over the canvas (e.g. to show an eraser cursor).
  void onHover(CanvasPointerEvent e) {}

  /// The editor is about to save because it is closing: finish (commit)
  /// any gesture still in progress so it is saved too.
  void commitPending() {}

  /// The tool was selected / deselected in the toolbar.
  void onActivated() {}
  void onDeactivated() {}

  /// The editor is closing.
  void dispose() {}
}

/// Observes the pen/highlighter stroke being drawn. Used for hold-to-snap
/// shapes: watch the samples, set [ActiveStroke.preview] to show the shape,
/// and return the snapped stroke from [onFinish].
abstract class LiveStrokeHook {
  /// A stroke started (its first point is already in [stroke]).
  void onStart(ActiveStroke stroke) {}

  /// Called for every pointer sample of the stroke, including samples that
  /// added no point because the pen was still.
  void onSample(ActiveStroke stroke, CanvasPointerEvent e) {}

  /// The pen lifted. Return the stroke to commit: [finished] itself, or a
  /// replacement with the same id (e.g. `finished.copyWith(points: shape,
  /// shape: ShapeKind.line)`, keeping `raw`).
  Stroke onFinish(ActiveStroke stroke, Stroke finished) => finished;

  /// The stroke was discarded.
  void onCancel(ActiveStroke stroke) {}
}

/// Everything a page painter needs about the page being painted.
class PagePaintContext {
  const PagePaintContext({
    required this.notebookId,
    required this.pageId,
    required this.pageIndex,
    required this.page,
    required this.content,
    this.forThumbnail = false,
  });

  final String notebookId;
  final String pageId;
  final int pageIndex;
  final PageMeta page;
  final PageContent content;

  /// True when painting the library thumbnail rather than the screen.
  final bool forThumbnail;
}

/// Paints one layer of page items (images or text boxes) into the page's
/// committed-content picture, in page coordinates.
///
/// The picture is re-recorded only when the page's content revision
/// changes. When something the painter draws becomes ready later (an image
/// finished decoding), call `EditorController.invalidatePageRender(pageId)`.
abstract class PageLayerPainter {
  /// Loads whatever [paint] needs (decoded images...). The thumbnail
  /// renderer awaits this before painting; the screen does not.
  Future<void> prepare(PagePaintContext context) async {}

  void paint(ui.Canvas canvas, PagePaintContext context);
}

/// What a page background builder is asked to draw.
class PageBackgroundRequest {
  const PageBackgroundRequest({
    required this.notebookId,
    required this.pageIndex,
    required this.page,
    required this.viewport,
  });

  final String notebookId;
  final int pageIndex;
  final PageMeta page;

  /// For the current / settled scale (`viewport.settledScale` is pixels per
  /// point once zooming pauses; multiply by the device pixel ratio for
  /// device pixels).
  final ViewportController viewport;
}

/// Builds the background of a PDF page, sized to the page in points.
/// Return null to use the default placeholder.
typedef PageBackgroundBuilder = Widget? Function(
    BuildContext context, PageBackgroundRequest request);

/// Paints a PDF page background into a thumbnail canvas that is already in
/// page coordinates; [pixelsPerPoint] is the thumbnail's resolution.
typedef ThumbnailBackgroundPainter = Future<void> Function(
    ui.Canvas canvas, PagePaintContext context, double pixelsPerPoint);

/// Builds the PDF page of [page] for a small live thumbnail (the page grid).
/// The widget fills the PDF part of the page ([PageMeta.contentWidth] x
/// [PageMeta.height] points); [scale] is logical pixels per point. Return
/// null to leave the page white.
typedef PageThumbnailBackgroundBuilder = Widget? Function(
    BuildContext context, String notebookId, PageMeta page, double scale);

/// Information about a page widget, for overlay builders.
class EditorPageInfo {
  const EditorPageInfo({
    required this.controller,
    required this.pageId,
    required this.pageIndex,
    required this.page,
  });

  final EditorController controller;
  final String pageId;
  final int pageIndex;
  final PageMeta page;
}

/// Builds a widget stacked over a page (sized to the page, in page points,
/// zoomed with it): tidy animation, lasso selection, text editing, debug
/// overlay. Return null for nothing. Wrap frequently repainting overlays in
/// their own `RepaintBoundary`.
typedef PageOverlayBuilder = Widget? Function(
    BuildContext context, EditorPageInfo page);

/// Builds a widget over the whole document view in screen space (e.g. a
/// floating selection menu). Return null for nothing.
typedef ViewportOverlayBuilder = Widget? Function(
    BuildContext context, EditorController controller);

/// Builds extra options shown in the tool row while a tool is selected
/// (e.g. the shape kinds for the shape tool).
typedef ToolOptionsBuilder = Widget Function(
    BuildContext context, EditorController controller);

/// Last say over a pen / highlighter stroke before it is committed (after
/// the [LiveStrokeHook]): return [stroke] itself, or a replacement with the
/// same id that keeps its `raw` points (e.g. a tidied highlight).
typedef StrokeFinisher = Stroke Function(String pageId, Stroke stroke);

/// A pen stroke that may be a gesture rather than ink (a scribble over
/// writing deletes it). Asked before [LiveStrokeHook.onFinish] and the
/// [StrokeFinisher]s; returns true when it acted on [stroke], which is then
/// not added to the page.
typedef StrokeGesture = bool Function(String pageId, Stroke stroke);

/// A tap on a page at [point] (page points): a pen tap with the pen or
/// highlighter, or a quick finger tap. Returns true when it handled the tap
/// (a pen tap then leaves no dot).
typedef PageTapHandler = bool Function(String pageId, Vec2 point);

/// Where the printed text of a page lies (a PDF page's words), in page
/// points. [wordsOn] answers from a cache and returns null while the words
/// are not known yet; [prepare] starts loading them (call it early, e.g.
/// when a highlight starts on the page).
abstract class PageTextWords {
  List<({double left, double top, double right, double bottom})>? wordsOn(String pageId);

  void prepare(String pageId);
}

/// A toolbar / menu action.
typedef EditorAction = Future<void> Function(
    BuildContext context, EditorController controller);

/// A selection-menu action that works on the lasso [selection] (e.g. convert
/// its handwriting to text).
typedef SelectionAction = Future<void> Function(
    BuildContext context, EditorController controller, Selection selection);

/// The editor's plug-in registry, filled by `EditorIntegration`s;
/// if anything changes after the editor is showing, call
/// `EditorController.extensionsChanged()`.
class EditorExtensions {
  /// Handlers for tools other than pen and highlighter. A tool without a
  /// handler is shown disabled in the toolbar.
  final Map<EditorTool, CanvasToolHandler> toolHandlers = {};

  /// Extra tool-row options per tool.
  final Map<EditorTool, ToolOptionsBuilder> toolOptions = {};

  /// Observes pen/highlighter strokes while they are drawn.
  LiveStrokeHook? liveStrokeHook;

  /// Asked in order about taps on a page, until one handles it.
  final List<PageTapHandler> pageTapHandlers = [];

  /// Offers a tap to [pageTapHandlers]; true when one handled it.
  bool handleTap(String pageId, Vec2 point) {
    for (final h in pageTapHandlers) {
      if (h(pageId, point)) return true;
    }
    return false;
  }

  /// Asked in order about every finished pen stroke (not highlighter),
  /// until one takes it as a gesture.
  final List<StrokeGesture> strokeGestures = [];

  /// Run in order on every finished pen/highlighter stroke, after
  /// [liveStrokeHook].
  final List<StrokeFinisher> strokeFinishers = [];

  /// The printed text of PDF pages (for tidying highlights). Null without
  /// the PDF feature.
  PageTextWords? pageTextWords;

  /// Background for pages with a `pdfPageIndex`.
  PageBackgroundBuilder? pageBackgroundBuilder;

  /// Background of a PDF page in the library thumbnail.
  ThumbnailBackgroundPainter? thumbnailBackground;

  /// Background of a PDF page in the page grid's thumbnails.
  PageThumbnailBackgroundBuilder? pageThumbnailBackgroundBuilder;

  /// Painted below highlighter strokes.
  PageLayerPainter? imageLayer;

  /// Painted between highlighter and pen strokes.
  PageLayerPainter? textLayer;

  /// Per-page overlays, bottom to top.
  final List<PageOverlayBuilder> pageOverlays = [];

  /// Screen-space overlays over the document view, bottom to top.
  final List<ViewportOverlayBuilder> viewportOverlays = [];

  /// Toolbar "pages" button (page thumbnail grid). Disabled when null.
  EditorAction? openPageNavigator;

  /// Overflow menu "Export PDF". Disabled when null.
  EditorAction? exportPdf;

  /// App bar button next to Auto: the "Typed text" settings (how converted
  /// handwriting looks), open also when there is nothing to convert.
  EditorAction? convertSettings;

  /// Overflow menu "PDF margins…" (shown for notebooks with PDF pages).
  EditorAction? pdfMargins;

  /// Overflow menu "Page paper". Disabled when null.
  EditorAction? changePagePaper;

  /// App bar "Convert" button: handwriting to typed text, for the lasso
  /// selection if there is one, else the page in view. Hidden when null.
  EditorAction? convertHandwriting;

  /// Selection menu "Convert" button: handwriting in the selection to typed
  /// text. Hidden when null.
  SelectionAction? convertSelection;

  /// Committed pen / highlighter strokes with these ids are not painted
  /// (the tidy animation draws them itself meanwhile). After changing it,
  /// call `EditorController.invalidatePageRender(pageId)`.
  final Set<String> hiddenStrokeIds = {};

  /// Run by `EditorController.close()` after the tools committed their
  /// pending gestures and before saving (tidy commits its pending word).
  final List<VoidCallback> beforeSaveHooks = [];
}
