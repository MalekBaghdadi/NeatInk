import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/tool_prefs.dart';
import 'package:neatink/features/editor/toolbar/ink_settings_model.dart';
import 'package:neatink/ink/line_style.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'toolbar_harness.dart';

void main() {
  group('InkSettingsModel.forPen', () {
    test('reads the pen prefs and the pen limits', () async {
      final c = await toolbarController();
      final m = InkSettingsModel.forPen(c);
      final v = m.values();
      expect(m.title, 'Ballpoint');
      expect(v.size, 2.2);
      expect(v.concentration, 1.0);
      expect(v.line, LineSettings.solid);
      expect(v.horizontal, isFalse);
      expect(v.color, 0xFF1E1E1E);
      expect(m.minSize, ToolPresets.penSizeMin);
      expect(m.maxSize, ToolPresets.penSizeMax);
      expect(m.presetColors, ToolPresets.penColors);
      expect(m.commitOnRelease, isFalse);
    });

    test('the title is the name of the pen style', () async {
      final c = await toolbarController();
      for (final style in PenStyle.values) {
        c.setPenStyle(style);
        final title = InkSettingsModel.forPen(c).title;
        expect(title, switch (style) {
          PenStyle.ballpoint => 'Ballpoint',
          PenStyle.fountain => 'Fountain pen',
          PenStyle.pencil => 'Pencil',
          PenStyle.technical => 'Technical pen',
        });
      }
    });

    test('every callback writes through the controller tool prefs', () async {
      final c = await toolbarController();
      final m = InkSettingsModel.forPen(c);
      const wavy = LineSettings(
          style: LineStyle.wavy, waveHeight: 4.5, waveWidth: 6.0);

      m.onSize(3.4);
      m.onConcentration(0.55);
      m.onLine(wavy);
      m.onHorizontal!(true);
      m.onColor!(0xFFD93025);

      final pen = c.toolPrefs.pen;
      expect(pen.size, 3.4);
      expect(pen.concentration, 0.55);
      expect(pen.line, wavy);
      expect(pen.horizontal, isTrue);
      expect(pen.color, 0xFFD93025);
      // The model reads it back.
      final v = m.values();
      expect(
          (v.size, v.concentration, v.line, v.horizontal, v.color),
          (3.4, 0.55, wavy, true, 0xFFD93025));
      // The highlighter is a separate set of prefs.
      expect(c.toolPrefs.highlighter.size, const HighlighterPrefs().size);
    });

    test('the changes are saved', () async {
      final c = await toolbarController();
      final m = InkSettingsModel.forPen(c);
      m.onLine(const LineSettings(style: LineStyle.zigzag));
      m.onSize(4.0);
      await pumpEventQueue();
      final stored = ToolPrefsStore(await SharedPreferences.getInstance()).load();
      expect(stored.pen.line.style, LineStyle.zigzag);
      expect(stored.pen.size, 4.0);
    });

    test('the listenable fires for every change', () async {
      final c = await toolbarController();
      final m = InkSettingsModel.forPen(c);
      var fired = 0;
      m.listenable!.addListener(() => fired++);
      m.onSize(3.0);
      m.onLine(const LineSettings(style: LineStyle.dashed));
      expect(fired, 2);
    });

    test('the recent custom colours are offered', () async {
      final c = await toolbarController();
      c.setPenColor(0xFF123456, custom: true);
      c.setPenColor(0xFF654321, custom: true);
      expect(InkSettingsModel.forPen(c).values().recentColors,
          [0xFF654321, 0xFF123456]);
    });

    test('Reset is available only when something differs from the defaults',
        () async {
      final c = await toolbarController();
      final m = InkSettingsModel.forPen(c);
      expect(m.canReset(m.values()), isFalse);
      // The colour and the pen are not part of Reset.
      m.onColor!(0xFFD93025);
      c.setPenStyle(PenStyle.technical);
      expect(m.canReset(m.values()), isFalse);

      m.onSize(5.0);
      expect(m.canReset(m.values()), isTrue);
      m.onReset!();
      expect(m.canReset(m.values()), isFalse);

      m.onHorizontal!(true);
      expect(m.canReset(m.values()), isTrue);
    });

    test('Reset restores the settings and keeps the colour and the pen',
        () async {
      final c = await toolbarController();
      final m = InkSettingsModel.forPen(c);
      c.setPenStyle(PenStyle.technical);
      m.onColor!(0xFF1E5BD8);
      m.onSize(7.7);
      m.onConcentration(0.3);
      m.onLine(const LineSettings(style: LineStyle.parallel));
      m.onHorizontal!(true);

      m.onReset!();

      final pen = c.toolPrefs.pen;
      expect(pen.size, const PenPrefs().size);
      expect(pen.concentration, 1.0);
      expect(pen.line, LineSettings.solid);
      expect(pen.horizontal, isFalse);
      expect(pen.color, 0xFF1E5BD8);
      expect(pen.style, PenStyle.technical);
    });
  });

  group('InkSettingsModel.forHighlighter', () {
    test('reads the highlighter prefs and limits', () async {
      final c = await toolbarController();
      final m = InkSettingsModel.forHighlighter(c);
      final v = m.values();
      expect(m.title, 'Highlighter');
      expect(v.size, 14);
      expect(v.color, 0xFFFFE600);
      expect(m.minSize, ToolPresets.highlighterSizeMin);
      expect(m.maxSize, ToolPresets.highlighterSizeMax);
      expect(m.presetColors, ToolPresets.highlighterColors);
    });

    test('the callbacks write to the highlighter and leave the pen alone',
        () async {
      final c = await toolbarController();
      final m = InkSettingsModel.forHighlighter(c);
      m.onSize(25);
      m.onConcentration(0.4);
      m.onLine(const LineSettings(style: LineStyle.wavy));
      m.onHorizontal!(true);
      m.onColor!(0xFF76FF03);

      final hl = c.toolPrefs.highlighter;
      expect(hl.size, 25);
      expect(hl.concentration, 0.4);
      expect(hl.line.style, LineStyle.wavy);
      expect(hl.horizontal, isTrue);
      expect(hl.color, 0xFF76FF03);
      final pen = c.toolPrefs.pen;
      expect(pen.size, const PenPrefs().size);
      expect(pen.line, LineSettings.solid);
      expect(pen.color, const PenPrefs().color);
    });

    test('Reset restores the highlighter and keeps its colour', () async {
      final c = await toolbarController();
      final m = InkSettingsModel.forHighlighter(c);
      expect(m.canReset(m.values()), isFalse);
      m.onColor!(0xFFFF4081);
      m.onSize(30);
      m.onLine(const LineSettings(style: LineStyle.dotted));
      expect(m.canReset(m.values()), isTrue);
      m.onReset!();
      expect(c.toolPrefs.highlighter.size, const HighlighterPrefs().size);
      expect(c.toolPrefs.highlighter.line, LineSettings.solid);
      expect(c.toolPrefs.highlighter.color, 0xFFFF4081);
      expect(m.canReset(m.values()), isFalse);
    });
  });

  group('InkSettingsValues.differsFrom', () {
    const base = InkSettingsValues(size: 2.2);

    test('ignores the colour, the recent colours and a missing switch', () {
      expect(
          base.differsFrom(const InkSettingsValues(
              size: 2.2, color: 0xFF112233, recentColors: [1, 2])),
          isFalse);
      expect(
          base.differsFrom(const InkSettingsValues(size: 2.2, horizontal: false)),
          isFalse);
    });

    test('sees each of the four settings', () {
      expect(base.differsFrom(const InkSettingsValues(size: 2.3)), isTrue);
      expect(
          base.differsFrom(
              const InkSettingsValues(size: 2.2, concentration: 0.9)),
          isTrue);
      expect(
          base.differsFrom(const InkSettingsValues(
              size: 2.2, line: LineSettings(style: LineStyle.dashed))),
          isTrue);
      expect(
          base.differsFrom(const InkSettingsValues(size: 2.2, horizontal: true)),
          isTrue);
    });
  });

  test('a model without Reset has nothing to reset', () {
    final m = InkSettingsModel(
      title: 'Selection',
      values: () => const InkSettingsValues(size: 3),
      minSize: 0.5,
      maxSize: 12,
      onSize: (_) {},
      onConcentration: (_) {},
      onLine: (_) {},
    );
    expect(m.canReset(m.values()), isFalse);
  });

  test('a model with Reset but no reference values can always reset', () {
    final m = InkSettingsModel(
      title: 'Selection',
      values: () => const InkSettingsValues(size: 2.2),
      minSize: 0.5,
      maxSize: 12,
      onSize: (_) {},
      onConcentration: (_) {},
      onLine: (_) {},
      onReset: () {},
    );
    expect(m.canReset(m.values()), isTrue);
  });
}
