import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../../document/font_kind.dart';
import '../../../../recognition/htr_channel.dart';
import '../../editor_controller.dart';
import '../../tools/selection.dart';
import 'convert_apply.dart';
import 'convert_config.dart';
import 'convert_layout.dart';
import 'convert_plan.dart';

/// Where the convert sheet is.
enum ConvertPhase {
  /// Reading the handwriting (progress bar, Cancel).
  reading,

  /// Recognised lines to review.
  review,

  /// There is no handwriting in scope: "Nothing to convert here yet".
  empty,

  /// Recognition failed; [ConvertSession.errorMessage] says why.
  failed,
}

/// The state behind the convert sheet: which strokes are in scope, what was
/// read, the user's corrections and look, and the final apply.
///
/// Scope is the lasso [selection]'s pen strokes when there is one, else the
/// pen strokes of the page in view, or of every page once [allPages] is set.
/// Recognised pages are cached, so switching the scope only reads what is
/// new.
class ConvertSession extends ChangeNotifier {
  ConvertSession({
    required this.controller,
    required this.recognizer,
    this.selection,
    Uuid? uuid,
    this._metrics = const FlutterTextMetrics(),
  }) : _uuid = uuid ?? const Uuid();

  final EditorController controller;
  final HtrRecognizer recognizer;

  /// The lasso selection the sheet was opened for, or null.
  final Selection? selection;
  final Uuid _uuid;
  final ConvertTextMetrics _metrics;

  ConvertPhase _phase = ConvertPhase.reading;
  double _progress = 0;
  String? _errorMessage;
  bool _allPages = false;
  bool _closed = false;
  int _run = 0;
  ConvertCancelToken? _token;
  final Map<String, PagePlan> _cache = {};

  FontKind _font = FontKind.sans;
  bool _bold = false;
  bool _italic = false;
  double? _fixedSize;
  int? _colorOverride;

  ConvertPhase get phase => _phase;

  /// 0..1 while [phase] is [ConvertPhase.reading].
  double get progress => _progress;

  /// A message safe to show when [phase] is [ConvertPhase.failed].
  String? get errorMessage => _errorMessage;

  /// True when the sheet may offer the "This page / All pages" switch.
  bool get canChooseScope => selection == null;
  bool get allPages => _allPages;

  FontKind get font => _font;
  bool get bold => _bold;
  bool get italic => _italic;

  /// Fixed size in points, or null for auto.
  double? get fixedSize => _fixedSize;
  bool get autoSize => _fixedSize == null;

  /// Colour for every line, or null to keep the ink colour.
  int? get colorOverride => _colorOverride;

  ConvertStyle get style => ConvertStyle(
        font: _font,
        bold: _bold,
        italic: _italic,
        fixedSize: _fixedSize,
        colorOverride: _colorOverride,
      );

  // ---------------------------------------------------------------------------
  // Scope and reading

  /// The pages in scope as (id, index), in page order.
  List<(String, int)> _scopePages() {
    final pages = controller.doc.meta.pages;
    final sel = selection;
    if (sel != null) {
      final index = pages.indexWhere((p) => p.id == sel.pageId);
      return index < 0 ? const [] : [(sel.pageId, index)];
    }
    final indices = _allPages
        ? List.generate(pages.length, (i) => i)
        : [controller.currentPageIndex];
    return [
      for (final i in indices)
        if (i >= 0 && i < pages.length && controller.isPageEditable(pages[i].id))
          (pages[i].id, i),
    ];
  }

  List<PageStrokes> _pagesInScope() {
    final doc = controller.doc;
    final sel = selection;
    return [
      for (final (id, index) in _scopePages())
        PageStrokes(
          pageId: id,
          pageIndex: index,
          strokes: sel != null
              ? sel.strokesOn(doc.page(id))
              : List.of(doc.page(id).strokes),
        ),
    ];
  }

  /// Starts (or restarts) reading the handwriting in scope.
  Future<void> start() async {
    final run = ++_run;
    _token?.cancel();
    final token = _token = ConvertCancelToken();
    final scope = _pagesInScope();
    final missing = [
      for (final p in scope)
        if (!_cache.containsKey(p.pageId)) p,
    ];
    if (missing.isNotEmpty) {
      _phase = ConvertPhase.reading;
      _progress = 0;
      _errorMessage = null;
      _notify();
      try {
        final plans = await recognizePages(
          missing,
          recognizer,
          cancel: token,
          onProgress: (done, total) {
            if (run != _run || _closed) return;
            _progress = total == 0 ? 1 : (done / total).clamp(0.0, 1.0);
            _notify();
          },
        );
        for (final plan in plans) {
          _cache[plan.pageId] = plan;
        }
      } on ConvertCancelled {
        return;
      } on HtrException catch (e) {
        if (run != _run || _closed) return;
        _fail(e.userMessage);
        return;
      } catch (e) {
        debugPrint('NeatInk: convert failed: $e');
        if (run != _run || _closed) return;
        _fail('Reading the handwriting failed.');
        return;
      }
    }
    if (run != _run || _closed) return;
    _phase = plans.isEmpty ? ConvertPhase.empty : ConvertPhase.review;
    _notify();
  }

  void _fail(String message) {
    _phase = ConvertPhase.failed;
    _errorMessage = message;
    _notify();
  }

  /// Tries again after a failure.
  Future<void> retry() => start();

  /// Switches between the page in view and every page (only without a
  /// selection). Pages already read are not read again.
  Future<void> setAllPages(bool value) {
    if (!canChooseScope || value == _allPages) return Future.value();
    _allPages = value;
    return start();
  }

  /// Stops reading and ignores whatever is still in flight. The session
  /// stays usable for reading its state, but never notifies again.
  void cancel() {
    _closed = true;
    _run++;
    _token?.cancel();
  }

  /// The recognised pages in scope that have lines, in page order.
  List<PagePlan> get plans {
    final out = <PagePlan>[];
    for (final (id, _) in _scopePages()) {
      final plan = _cache[id];
      if (plan != null && !plan.isEmpty) out.add(plan);
    }
    return out;
  }

  Iterable<PlannedLine> get allLines => plans.expand((p) => p.lines);

  /// Lines that will be turned into text.
  int get includedCount => allLines.where((l) => l.willConvert).length;

  /// Lines that will stay handwriting.
  int get stayCount => allLines.length - includedCount;

  // ---------------------------------------------------------------------------
  // The user's choices

  void setInclude(PlannedLine line, bool value) {
    if (line.include == value) return;
    line.include = value;
    _notify();
  }

  void setText(PlannedLine line, String text) {
    if (line.text == text) return;
    line.text = text;
    _notify();
  }

  void setFont(FontKind value) {
    _font = value;
    _notify();
  }

  void setBold(bool value) {
    _bold = value;
    _notify();
  }

  void setItalic(bool value) {
    _italic = value;
    _notify();
  }

  /// A size in points, clamped to the slider range; null selects auto.
  void setFixedSize(double? value) {
    _fixedSize = value?.clamp(
        ConvertConfig.minFixedSize, ConvertConfig.maxFixedSize).toDouble();
    _notify();
  }

  void setColorOverride(int? value) {
    _colorOverride = value;
    _notify();
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Apply

  /// The changes the current choices would make, one per page.
  List<PageConversion> buildConversions() {
    final out = <PageConversion>[];
    for (final plan in plans) {
      final meta = controller.doc.pageMeta(plan.pageId);
      if (meta == null || !controller.isPageEditable(plan.pageId)) continue;
      final ruling = PageRuling.of(meta.paper, meta.width, meta.height,
          isPdf: meta.isPdf);
      final laid = layoutPage(
        pageWidth: meta.width,
        pageHeight: meta.height,
        ruling: ruling,
        style: style,
        metrics: _metrics,
        uuid: _uuid,
        lines: [
          for (final l in plan.lines)
            LayoutLineInput(
              id: l.id,
              text: l.text,
              geometry: LineGeometry.of(l.line),
              color: l.dominantColor,
              include: l.willConvert,
            ),
        ],
      );
      if (laid.isEmpty) continue;
      final converted = {for (final l in laid) l.id};
      out.add(PageConversion(
        pageId: plan.pageId,
        strokeIds: {
          for (final l in plan.lines)
            if (converted.contains(l.id)) ...l.strokeIds,
        },
        items: [for (final l in laid) l.item],
      ));
    }
    return out;
  }

  /// Replaces the ink of the ticked lines with typed text boxes, as one undo
  /// step. Returns null when nothing was converted.
  ConvertOutcome? apply() {
    if (_phase != ConvertPhase.review) return null;
    return applyConversion(controller, buildConversions());
  }
}
