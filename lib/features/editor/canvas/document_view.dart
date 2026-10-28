import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../document/notebook_meta.dart';
import '../editor_controller.dart';
import '../editor_extensions.dart';
import 'input_router.dart';
import 'navigation_gesture.dart';
import 'page_view.dart';
import 'viewport_controller.dart';

/// The editor's canvas: a vertical document of pages under one zoom level.
///
/// * Pages are laid out in page points and shown through the viewport
///   transform ([ViewportController.matrix]), applied by a small render
///   object. Panning and zooming only change that transform: no widget
///   rebuilds, no relayout, and page layers are re-composited, not
///   repainted. Ink is vector, so it stays sharp at every zoom.
/// * Only the visible pages (plus the viewport's cache extent) are built;
///   the list is rebuilt when that range or the page list changes.
/// * Raw pointer events ([Listener]) are routed by [InputRouter]: the pen
///   uses the current tool, its eraser end the eraser, fingers navigate
///   (one-finger pan with fling, two-finger pinch), the mouse draws with the
///   primary button. Touches are ignored while the pen is near the screen
///   (palm rejection).
class DocumentView extends StatefulWidget {
  const DocumentView({super.key, required this.controller});

  final EditorController controller;

  @override
  State<DocumentView> createState() => _DocumentViewState();
}

class _DocumentViewState extends State<DocumentView>
    with SingleTickerProviderStateMixin {
  /// A finger that drew for less than this before a second finger arrived
  /// was starting a pinch: its stroke is discarded instead of committed.
  static const Duration _pinchConversionWindow = Duration(milliseconds: 250);

  /// A pan that started this shortly before the pen landed was the palm:
  /// it is undone.
  /// A pan by touches that are still down when the pen lands is undone if it
  /// began at most this long before (a resting palm that moved the page);
  /// v1.6.0: was 400 ms, while a hand rests for seconds.
  static const Duration _palmPanUndoWindow = Duration(seconds: 3);

  /// Pen-down this close to a page edge (logical pixels) still starts on
  /// that page.
  static const double _pageEdgeSlopPx = 6;

  final GlobalKey _viewportKey = GlobalKey();
  late final NavigationGesture _nav = NavigationGesture(_viewport);
  late final Ticker _flingTicker = createTicker(_onFlingTick);
  late final Listenable _pagesChanged = Listenable.merge(
      [_viewport.visibleRange, widget.controller.documentViewChanges]);

  final Map<int, _ToolPointer> _toolPointers = {};
  final Set<int> _ignored = {};

  /// Touches being ignored as a palm (a subset of [_ignored]): while one
  /// is down after the pen was used, new touches are ignored too.
  final Set<int> _palms = {};

  /// A finger that went down alone to navigate: lifted quickly where it
  /// went down, it is a tap ([EditorExtensions.handleTap]).
  ({int pointer, Offset at, Duration time})? _tap;
  static const Duration _tapMaxDuration = Duration(milliseconds: 300);
  static const double _tapMaxTravelPx = 10;

  ClampingScrollSimulation? _flingX;
  ClampingScrollSimulation? _flingY;
  Offset _flingPosition = Offset.zero;

  /// When and from where the current navigation gesture started.
  Duration? _navStartTime;
  ViewportSnapshot? _navStartView;

  /// Trackpad pinch: zoom when the gesture started.
  double _panZoomStartZoom = 1;

  EditorController get _controller => widget.controller;
  ViewportController get _viewport => widget.controller.viewport;

  @override
  void initState() {
    super.initState();
    _viewport.attachViewportBox(_viewportBox);
  }

  @override
  void dispose() {
    _viewport.attachViewportBox(null);
    _flingTicker.dispose();
    super.dispose();
  }

  RenderBox? _viewportBox() {
    final object = _viewportKey.currentContext?.findRenderObject();
    return object is RenderBox ? object : null;
  }

  // ---------------------------------------------------------------------------
  // Build

  @override
  Widget build(BuildContext context) {
    final backdrop = Theme.of(context).colorScheme.surfaceContainerHigh;
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      if (size.isFinite && _viewport.applyViewportSize(size)) {
        // Listeners may not be notified during layout; publish after it.
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) _viewport.publish();
        });
      }
      return Listener(
        key: _viewportKey,
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        onPointerHover: _onPointerHover,
        onPointerSignal: _onPointerSignal,
        onPointerPanZoomStart: _onPanZoomStart,
        onPointerPanZoomUpdate: _onPanZoomUpdate,
        child: ColoredBox(
          color: backdrop,
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ListenableBuilder(
                  listenable: _pagesChanged,
                  builder: (context, _) => _buildPages(),
                ),
                ListenableBuilder(
                  listenable: _controller.documentViewChanges,
                  builder: (context, _) => Stack(
                    fit: StackFit.expand,
                    children: [
                      for (final build in _controller.extensions.viewportOverlays)
                        ?build(context, _controller),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildPages() {
    final layout = _viewport.layout;
    final range = _controller.isReady ? _viewport.computeVisibleRange() : null;
    final pages =
        _controller.isReady ? _controller.doc.meta.pages : const <PageMeta>[];
    return _DocumentTransform(
      viewport: _viewport,
      documentSize: layout.size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (range != null)
            for (var i = range.first; i <= range.last && i < pages.length; i++)
              Positioned.fromRect(
                rect: layout.rects[i],
                child: EditorPageView(
                  key: ValueKey(pages[i].id),
                  controller: _controller,
                  pageIndex: i,
                  page: pages[i],
                ),
              ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Pointer routing

  CanvasPointerEvent _canvasEvent(
    PointerEvent e, {
    double slopPx = 0,
    bool eraserButton = false,
  }) =>
      CanvasPointerEvent(
        event: e,
        localPosition: e.localPosition,
        hit: _viewport.hitTestLocal(e.localPosition, slopPx: slopPx),
        pressure: normalizedPressureOf(e),
        isEraserButton: eraserButton,
      );

  static bool _isTouch(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.touch || kind == PointerDeviceKind.unknown;

  void _onPointerDown(PointerDownEvent e) {
    final router = _controller.inputRouter..observe(e);
    _tap = null; // Another pointer: no longer a lone finger tap.
    if (!_controller.isReady) {
      _ignored.add(e.pointer);
      return;
    }
    _stopFling();
    if (isStylusKind(e.kind)) _rejectPalms(e.timeStamp);

    final touchBusy = _nav.isActive ||
        _toolPointers.values.any((t) => _isTouch(t.kind));
    final intent = router.classifyDown(
      kind: e.kind,
      buttons: e.buttons,
      timeStamp: e.timeStamp,
      touchInUse: touchBusy,
      palmResting: _palms.isNotEmpty,
    );
    switch (intent) {
      case PointerIntent.tool:
        if (!_startTool(e, _controller.activeHandler, eraserButton: false)) {
          // A finger that the tool doesn't want (e.g. outside the pages)
          // still scrolls; a pen or mouse there does nothing.
          if (_isTouch(e.kind)) {
            _startNavigation(e);
          } else {
            _ignored.add(e.pointer);
          }
        }
      case PointerIntent.eraser:
        // Until the eraser is integrated, the eraser end does nothing (it
        // must never draw).
        if (!_startTool(e, _controller.eraserHandler, eraserButton: true)) {
          _ignored.add(e.pointer);
        }
      case PointerIntent.navigate:
        _startNavigation(e);
      case PointerIntent.ignore:
        _ignored.add(e.pointer);
        if (_isTouch(e.kind)) _palms.add(e.pointer);
    }
  }

  bool _startTool(
    PointerDownEvent e,
    CanvasToolHandler? handler, {
    required bool eraserButton,
  }) {
    if (handler == null) return false;
    final ce = _canvasEvent(e, slopPx: _pageEdgeSlopPx, eraserButton: eraserButton);
    if (!handler.onPointerDown(ce)) return false;
    _toolPointers[e.pointer] = _ToolPointer(handler, ce, e.kind, e.timeStamp);
    return true;
  }

  void _startNavigation(PointerDownEvent e) {
    _tap = _isTouch(e.kind) && !_nav.isActive && _toolPointers.isEmpty
        ? (pointer: e.pointer, at: e.localPosition, time: e.timeStamp)
        : null;
    if (_isTouch(e.kind)) {
      // A finger joining a finger that draws (drawing with fingers on)
      // turns both into a pinch.
      final drawing = [
        for (final entry in _toolPointers.entries)
          if (_isTouch(entry.value.kind)) entry,
      ];
      for (final entry in drawing) {
        final tp = entry.value;
        _toolPointers.remove(entry.key);
        if (e.timeStamp - tp.downTime < _pinchConversionWindow) {
          tp.handler.onPointerCancel(tp.last);
        } else {
          tp.handler.onPointerUp(tp.last);
        }
        _beginNavigationPointer(
            entry.key, tp.last.localPosition, tp.last.timeStamp, tp.kind);
      }
    }
    _beginNavigationPointer(e.pointer, e.localPosition, e.timeStamp, e.kind);
  }

  void _beginNavigationPointer(
      int pointer, Offset position, Duration time, PointerDeviceKind kind) {
    if (!_nav.isActive) {
      _navStartTime = time;
      _navStartView = _viewport.snapshot;
    }
    _nav.addPointer(pointer, position, time, kind: kind);
  }

  /// The pen touched the screen: touches already down are a resting palm.
  /// Stop their navigation (undoing a pan that only just started), discard
  /// their finger strokes, and ignore them until they lift.
  void _rejectPalms(Duration penDownTime) {
    if (_nav.isActive) {
      final start = _navStartTime, view = _navStartView;
      if (start != null &&
          view != null &&
          penDownTime - start < _palmPanUndoWindow) {
        _viewport.restore(view);
      }
      final cancelled = _nav.cancel();
      _ignored.addAll(cancelled);
      _palms.addAll(cancelled);
    }
    final palms = [
      for (final entry in _toolPointers.entries)
        if (_isTouch(entry.value.kind)) entry,
    ];
    for (final entry in palms) {
      _toolPointers.remove(entry.key);
      entry.value.handler.onPointerCancel(entry.value.last);
      _ignored.add(entry.key);
      _palms.add(entry.key);
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    _controller.inputRouter.observe(e);
    final tp = _toolPointers[e.pointer];
    if (tp != null) {
      final ce = _canvasEvent(e, eraserButton: tp.last.isEraserButton);
      tp.last = ce;
      tp.handler.onPointerMove(ce);
      return;
    }
    if (_nav.contains(e.pointer)) {
      _nav.movePointer(e.pointer, e.localPosition, e.timeStamp);
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    _controller.inputRouter.observe(e);
    _ignored.remove(e.pointer);
    _palms.remove(e.pointer);
    final tp = _toolPointers.remove(e.pointer);
    if (tp != null) {
      tp.handler.onPointerUp(_canvasEvent(e, eraserButton: tp.last.isEraserButton));
      return;
    }
    if (_nav.contains(e.pointer)) {
      final tap = _tap;
      _tap = null;
      final velocity = _nav.removePointer(e.pointer, e.timeStamp);
      if (tap != null &&
          tap.pointer == e.pointer &&
          e.timeStamp - tap.time <= _tapMaxDuration &&
          (e.localPosition - tap.at).distance <= _tapMaxTravelPx) {
        final hit = _viewport.hitTestLocal(e.localPosition);
        if (hit != null) _controller.extensions.handleTap(hit.pageId, hit.point);
        return;
      }
      if (velocity != null) _startFling(velocity);
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _controller.inputRouter.observe(e);
    if (_tap?.pointer == e.pointer) _tap = null;
    _ignored.remove(e.pointer);
    _palms.remove(e.pointer);
    final tp = _toolPointers.remove(e.pointer);
    if (tp != null) {
      tp.handler.onPointerCancel(_canvasEvent(e, eraserButton: tp.last.isEraserButton));
      return;
    }
    if (_nav.contains(e.pointer)) _nav.removePointer(e.pointer, e.timeStamp);
  }

  void _onPointerHover(PointerHoverEvent e) {
    _controller.inputRouter.observe(e);
    if (!_controller.isReady || !isStylusKind(e.kind)) return;
    final eraser = e.kind == PointerDeviceKind.invertedStylus &&
        _controller.settings.stylusButtonErases;
    final handler =
        eraser ? _controller.eraserHandler : _controller.activeHandler;
    handler?.onHover(_canvasEvent(e, eraserButton: eraser));
  }

  /// Mouse wheel scrolls; with Ctrl held it zooms around the pointer.
  void _onPointerSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      GestureBinding.instance.pointerSignalResolver.register(e, (event) {
        final scroll = event as PointerScrollEvent;
        if (HardwareKeyboard.instance.isControlPressed) {
          _viewport.zoomAt(scroll.localPosition,
              _viewport.zoom * math.exp(-scroll.scrollDelta.dy / 300));
        } else {
          _viewport.panBy(-scroll.scrollDelta);
        }
      });
    } else if (e is PointerScaleEvent) {
      _viewport.zoomAt(e.localPosition, _viewport.zoom * e.scale);
    }
  }

  void _onPanZoomStart(PointerPanZoomStartEvent e) {
    _stopFling();
    _panZoomStartZoom = _viewport.zoom;
  }

  /// Trackpad two-finger pan and pinch.
  void _onPanZoomUpdate(PointerPanZoomUpdateEvent e) {
    _viewport.moveFocal(e.localPosition, e.localPosition + e.localPanDelta,
        _panZoomStartZoom * e.scale);
  }

  // ---------------------------------------------------------------------------
  // Fling

  void _startFling(Offset velocity) {
    _flingX = ClampingScrollSimulation(position: 0, velocity: velocity.dx);
    _flingY = ClampingScrollSimulation(position: 0, velocity: velocity.dy);
    _flingPosition = Offset.zero;
    _flingTicker
      ..stop()
      ..start();
  }

  void _stopFling() {
    if (_flingTicker.isActive) _flingTicker.stop();
  }

  void _onFlingTick(Duration elapsed) {
    final fx = _flingX, fy = _flingY;
    if (fx == null || fy == null) {
      _stopFling();
      return;
    }
    final t = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final position = Offset(fx.x(t), fy.x(t));
    final delta = position - _flingPosition;
    _flingPosition = position;
    final applied = _viewport.panBy(delta);
    final done = fx.isDone(t) && fy.isDone(t);
    // Stop at the document's ends instead of spinning against the clamp.
    final blocked = delta.distanceSquared > 0.25 && applied == Offset.zero;
    if (done || blocked) _stopFling();
  }
}

/// A pointer claimed by a tool handler.
class _ToolPointer {
  _ToolPointer(this.handler, this.last, this.kind, this.downTime);

  final CanvasToolHandler handler;

  /// The latest event delivered for this pointer.
  CanvasPointerEvent last;
  final PointerDeviceKind kind;
  final Duration downTime;
}

/// Lays its child out at [documentSize] (page points) and paints and
/// hit-tests it through the viewport's document → screen transform.
///
/// It listens to the viewport itself and only repaints (re-pushes one
/// transform layer) when the view moves; the pages below are repaint
/// boundaries, so their layers are reused as they are.
class _DocumentTransform extends SingleChildRenderObjectWidget {
  const _DocumentTransform({
    required this.viewport,
    required this.documentSize,
    super.child,
  });

  final ViewportController viewport;
  final Size documentSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderDocumentTransform(viewport, documentSize);

  @override
  void updateRenderObject(
      BuildContext context, _RenderDocumentTransform renderObject) {
    renderObject
      ..viewport = viewport
      ..documentSize = documentSize;
  }
}

class _RenderDocumentTransform extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  _RenderDocumentTransform(this._viewport, this._documentSize);

  ViewportController _viewport;
  ViewportController get viewport => _viewport;
  set viewport(ViewportController value) {
    if (identical(value, _viewport)) return;
    if (attached) _viewport.removeListener(markNeedsPaint);
    _viewport = value;
    if (attached) _viewport.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  Size _documentSize;
  set documentSize(Size value) {
    if (value == _documentSize) return;
    _documentSize = value;
    markNeedsLayout();
  }

  final LayerHandle<TransformLayer> _transformLayer =
      LayerHandle<TransformLayer>();

  @override
  bool get isRepaintBoundary => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _viewport.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _viewport.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _transformLayer.layer = null;
    super.dispose();
  }

  @override
  void performLayout() {
    size = constraints.biggest.isFinite
        ? constraints.biggest
        : constraints.constrain(Size.zero);
    child?.layout(BoxConstraints.tight(_documentSize));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) {
      _transformLayer.layer = null;
      return;
    }
    _transformLayer.layer = context.pushTransform(
      needsCompositing,
      offset,
      _viewport.matrix,
      (context, offset) => context.paintChild(child, offset),
      oldLayer: _transformLayer.layer,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintTransform(
      transform: _viewport.matrix,
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_viewport.matrix);
  }
}
