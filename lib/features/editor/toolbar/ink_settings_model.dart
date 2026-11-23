import 'package:flutter/widgets.dart';

import '../../../ink/line_style.dart';
import '../editor_controller.dart';
import '../editor_tool.dart';
import '../tool_prefs.dart';
import 'tool_options.dart' show pickCustomHighlighterColor, pickCustomPenColor;
import 'toolbar_widgets.dart';

/// The numbers the pen settings panel shows. Read fresh (through
/// [InkSettingsModel.values]) every time the panel rebuilds.
@immutable
class InkSettingsValues {
  const InkSettingsValues({
    required this.size,
    this.concentration = 1.0,
    this.line = LineSettings.solid,
    this.horizontal,
    this.color,
    this.recentColors = const [],
  });

  /// Stroke width in points ("Thickness").
  final double size;

  /// Ink density, [minConcentration]..1 ("Concentration").
  final double concentration;

  /// "Line Style" and the two wave sliders.
  final LineSettings line;

  /// The "Horizontal drawing" switch. Null: the panel has no such switch.
  final bool? horizontal;

  /// The selected ARGB colour, or null when none is (or the strokes of a
  /// selection differ).
  final int? color;

  /// Custom colours picked lately, most recent first; the colour grid shows
  /// them after the preset colours.
  final List<int> recentColors;

  /// Whether Reset would change anything: [size], [concentration], [line] or
  /// [horizontal] differ from [other]'s. The colour is never reset.
  bool differsFrom(InkSettingsValues other) =>
      size != other.size ||
      concentration != other.concentration ||
      line != other.line ||
      (horizontal ?? false) != (other.horizontal ?? false);
}

/// What the pen settings panel (`InkSettingsPanel`) edits.
///
/// One panel serves the pen, the highlighter ([InkSettingsModel.forPen],
/// [InkSettingsModel.forHighlighter]) and a lasso selection (package S builds
/// its own model). The panel reads the numbers through [values] each time
/// [listenable] fires, and reports every edit through the `on...` callbacks;
/// it never keeps a copy of its own, so whatever the callbacks change shows
/// up on the next rebuild.
class InkSettingsModel {
  const InkSettingsModel({
    required this.title,
    required this.values,
    required this.minSize,
    required this.maxSize,
    required this.onSize,
    required this.onConcentration,
    required this.onLine,
    this.onHorizontal,
    this.onColor,
    this.onCustomColor,
    this.onReset,
    this.resetValues,
    this.presetColors = const [],
    this.listenable,
    this.commitOnRelease = false,
  });

  /// The pen settings of the editor's pen: edits go to
  /// `controller.toolPrefs` and apply to the next stroke.
  factory InkSettingsModel.forPen(EditorController controller) {
    const defaults = PenPrefs();
    return InkSettingsModel(
      title: penStyleName(controller.toolPrefs.pen.style),
      listenable: controller,
      minSize: ToolPresets.penSizeMin,
      maxSize: ToolPresets.penSizeMax,
      presetColors: ToolPresets.penColors,
      values: () {
        final prefs = controller.toolPrefs;
        final pen = prefs.pen;
        return InkSettingsValues(
          size: pen.size,
          concentration: pen.concentration,
          line: pen.line,
          horizontal: pen.horizontal,
          color: pen.color,
          recentColors: prefs.recentColors,
        );
      },
      resetValues: InkSettingsValues(
        size: defaults.size,
        concentration: defaults.concentration,
        line: defaults.line,
        horizontal: defaults.horizontal,
      ),
      onSize: controller.setPenSize,
      onConcentration: controller.setPenConcentration,
      onLine: controller.setPenLine,
      onHorizontal: controller.setPenHorizontal,
      onColor: controller.setPenColor,
      onCustomColor: (context) => pickCustomPenColor(context, controller),
      onReset: controller.resetPen,
    );
  }

  /// The same for the highlighter.
  factory InkSettingsModel.forHighlighter(EditorController controller) {
    const defaults = HighlighterPrefs();
    return InkSettingsModel(
      title: EditorTool.highlighter.label,
      listenable: controller,
      minSize: ToolPresets.highlighterSizeMin,
      maxSize: ToolPresets.highlighterSizeMax,
      presetColors: ToolPresets.highlighterColors,
      values: () {
        final prefs = controller.toolPrefs;
        final hl = prefs.highlighter;
        return InkSettingsValues(
          size: hl.size,
          concentration: hl.concentration,
          line: hl.line,
          horizontal: hl.horizontal,
          color: hl.color,
          recentColors: prefs.recentColors,
        );
      },
      resetValues: InkSettingsValues(
        size: defaults.size,
        concentration: defaults.concentration,
        line: defaults.line,
        horizontal: defaults.horizontal,
      ),
      onSize: controller.setHighlighterSize,
      onConcentration: controller.setHighlighterConcentration,
      onLine: controller.setHighlighterLine,
      onHorizontal: controller.setHighlighterHorizontal,
      onColor: controller.setHighlighterColor,
      onCustomColor: (context) => pickCustomHighlighterColor(context, controller),
      onReset: controller.resetHighlighter,
    );
  }

  /// The panel's title: the pen's name, "Highlighter", or whatever the
  /// panel is for.
  final String title;

  /// The numbers to show, read on every rebuild (see [listenable]).
  final ValueGetter<InkSettingsValues> values;

  /// The range of the "Thickness" slider, in points.
  final double minSize;
  final double maxSize;

  final ValueChanged<double> onSize;
  final ValueChanged<double> onConcentration;

  /// Gets the whole new [LineSettings]: a chip tap changes the style and
  /// keeps the wave sliders, a wave slider changes one of them.
  final ValueChanged<LineSettings> onLine;

  /// Called with the new switch position. Null, or a null
  /// [InkSettingsValues.horizontal], hides the "Horizontal drawing" row.
  final ValueChanged<bool>? onHorizontal;

  /// Called with the tapped colour. Null hides the whole "Color" section.
  final ValueChanged<int>? onColor;

  /// Opens a colour picker and applies the choice (the "+" cell and the
  /// rainbow button). When null, the panel opens the standard picker and
  /// passes the result to [onColor].
  final Future<void> Function(BuildContext context)? onCustomColor;

  /// The "Reset" button. Null hides it.
  final VoidCallback? onReset;

  /// What [onReset] restores: Reset is greyed out while [values] equals this
  /// (see [InkSettingsValues.differsFrom]). Null keeps Reset enabled.
  final InkSettingsValues? resetValues;

  /// The preset colours at the start of the colour grid.
  final List<int> presetColors;

  /// The panel rebuilds when this fires (the controller, for the pen).
  final Listenable? listenable;

  /// Slider drags report once, when the finger lifts, instead of on every
  /// move, so one drag is one undo step. For models that change the document
  /// (a lasso selection), not for the pen's preferences.
  final bool commitOnRelease;

  /// Whether the Reset button is available and has something to reset.
  bool canReset(InkSettingsValues current) =>
      onReset != null &&
      (resetValues == null || current.differsFrom(resetValues!));
}
