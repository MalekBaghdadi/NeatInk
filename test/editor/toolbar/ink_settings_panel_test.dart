import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/tool_prefs.dart';
import 'package:neatink/features/editor/toolbar/ink_settings_model.dart';
import 'package:neatink/features/editor/toolbar/ink_settings_panel.dart';
import 'package:neatink/features/editor/toolbar/ink_sliders.dart';
import 'package:neatink/features/editor/toolbar/toolbar_widgets.dart';
import 'package:neatink/ink/line_style.dart';

import 'toolbar_harness.dart';

/// A model that keeps its numbers in plain fields and logs every callback:
/// the way a selection (package S) or a test double edits something.
class _Probe extends ChangeNotifier {
  _Probe({
    this.size = 2.2,
    this.concentration = 1.0,
    this.line = LineSettings.solid,
    this.color = 0xFF1E1E1E,
    this.recent = const [],
    this.hasHorizontal = true,
    this.hasColor = true,
    this.hasReset = true,
    this.commitOnRelease = false,
    this.customPicker = false,
  });

  double size;
  double concentration;
  LineSettings line;
  bool horizontal = false;
  int? color;
  List<int> recent;
  final bool hasHorizontal;
  final bool hasColor;
  final bool hasReset;
  final bool commitOnRelease;
  final bool customPicker;
  final String title = 'Technical pen';

  final List<String> log = [];
  int resets = 0;

  /// Tells the panel the numbers changed behind its back.
  void ping() => notifyListeners();

  void _set(String entry, VoidCallback apply) {
    log.add(entry);
    apply();
    notifyListeners();
  }

  InkSettingsModel get model => InkSettingsModel(
        title: title,
        listenable: this,
        commitOnRelease: commitOnRelease,
        minSize: ToolPresets.penSizeMin,
        maxSize: ToolPresets.penSizeMax,
        presetColors: ToolPresets.penColors,
        values: () => InkSettingsValues(
          size: size,
          concentration: concentration,
          line: line,
          horizontal: hasHorizontal ? horizontal : null,
          color: color,
          recentColors: recent,
        ),
        resetValues: const InkSettingsValues(size: 2.2),
        onSize: (v) => _set('size $v', () => size = v),
        onConcentration: (v) => _set('conc $v', () => concentration = v),
        onLine: (v) => _set('line ${v.style.name} ${v.waveHeight} ${v.waveWidth}',
            () => line = v),
        onHorizontal:
            hasHorizontal ? (v) => _set('horizontal $v', () => horizontal = v) : null,
        onColor: hasColor ? (v) => _set('color $v', () => color = v) : null,
        onCustomColor: customPicker
            ? (context) async => log.add('custom picker')
            : null,
        onReset: hasReset
            ? () => _set('reset', () {
                  resets++;
                  size = 2.2;
                  concentration = 1.0;
                  line = LineSettings.solid;
                  horizontal = false;
                })
            : null,
      );
}

Future<void> pumpPanel(
  WidgetTester tester,
  InkSettingsModel model, {
  Size screen = const Size(1280, 800),
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) async {
  useScreen(tester, screen);
  await tester.pumpWidget(themedApp(
    Align(alignment: Alignment.topRight, child: InkSettingsPanel(model: model)),
    brightness: brightness,
    textScale: textScale,
  ));
  await tester.pumpAndSettle();
}

void main() {
  Finder slider(String id) => find.byKey(ValueKey('ink-settings-$id'));
  Finder chip(String style) => find.byKey(ValueKey('ink-settings-line-$style'));
  Finder swatch(int argb) => find.byKey(ValueKey('ink-settings-color-$argb'));

  group('labels and layout', () {
    testWidgets('shows every label of the video panel', (tester) async {
      final p = _Probe(line: const LineSettings(style: LineStyle.wavy));
      await pumpPanel(tester, p.model);
      for (final text in [
        'Reset',
        'Technical pen',
        'Thickness',
        'Concentration',
        'Line Style',
        'Wavy Line Height',
        'Wavy Line Width',
        'Horizontal drawing',
        'Color',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.byKey(const ValueKey('ink-settings-panel')), findsOneWidget);
    });

    testWidgets('formats the values like the video', (tester) async {
      final p = _Probe(
        size: 2.0,
        concentration: 1.0,
        line: const LineSettings(style: LineStyle.wavy),
      );
      await pumpPanel(tester, p.model);
      expect(find.text('2.0'), findsOneWidget); // thickness
      expect(find.text('100%'), findsOneWidget); // concentration
      expect(find.text('3.1'), findsOneWidget); // wave height
      expect(find.text('3.7'), findsOneWidget); // wave width
    });

    testWidgets('the sections come in the order of the video', (tester) async {
      final p = _Probe(line: const LineSettings(style: LineStyle.wavy));
      await pumpPanel(tester, p.model);
      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      final order = [
        top('Technical pen'),
        top('Thickness'),
        top('Concentration'),
        top('Line Style'),
        top('Wavy Line Height'),
        top('Wavy Line Width'),
        top('Horizontal drawing'),
        top('Color'),
      ];
      expect(order, [...order]..sort());
      // Reset is left of the centred title.
      expect(tester.getCenter(find.text('Reset')).dx,
          lessThan(tester.getCenter(find.text('Technical pen')).dx));
    });

    testWidgets('is 340 wide on a tablet, with a hairline translucent card',
        (tester) async {
      await pumpPanel(tester, _Probe().model);
      final card = find.byKey(const ValueKey('ink-settings-panel'));
      expect(tester.getSize(card).width, inkSettingsPanelWidth);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('shrinks to a narrow screen', (tester) async {
      await pumpPanel(tester, _Probe().model, screen: const Size(300, 700));
      final card = find.byKey(const ValueKey('ink-settings-panel'));
      expect(tester.getSize(card).width, 300);
    });

    for (final brightness in Brightness.values) {
      for (final screen in const [Size(360, 800), Size(1280, 800)]) {
        for (final style in LineStyle.values) {
          testWidgets(
              'builds without overflow: ${brightness.name}, '
              '${screen.width.toInt()}x${screen.height.toInt()}, ${style.name}',
              (tester) async {
            final p = _Probe(line: LineSettings(style: style));
            await pumpPanel(tester, p.model,
                screen: screen, brightness: brightness);
            expect(tester.takeException(), isNull);
            final card = tester.getRect(find.byKey(const ValueKey('ink-settings-panel')));
            expect(card.right, lessThanOrEqualTo(screen.width));
            expect(card.bottom, lessThanOrEqualTo(screen.height * 0.9 + 0.5));
          });
        }
      }
    }

    testWidgets('scrolls on a short screen instead of overflowing',
        (tester) async {
      final p = _Probe(line: const LineSettings(style: LineStyle.wavy));
      await pumpPanel(tester, p.model, screen: const Size(360, 320));
      expect(tester.takeException(), isNull);
      final card = tester.getRect(find.byKey(const ValueKey('ink-settings-panel')));
      expect(card.height, lessThanOrEqualTo(320 * 0.9 + 0.5));
      // The title stays; the colour grid is reached by scrolling.
      expect(find.text('Technical pen'), findsOneWidget);
      final add = find.byKey(const ValueKey('ink-settings-color-add'));
      await tester.scrollUntilVisible(add, 80,
          scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
      expect(tester.getRect(add).bottom, lessThanOrEqualTo(card.bottom));
    });

    testWidgets('survives a big text size', (tester) async {
      final p = _Probe(line: const LineSettings(style: LineStyle.zigzag));
      await pumpPanel(tester, p.model,
          screen: const Size(360, 800), textScale: 2);
      expect(tester.takeException(), isNull);
    });
  });

  group('line style', () {
    testWidgets('has the six chips', (tester) async {
      await pumpPanel(tester, _Probe().model);
      for (final s in ['solid', 'dashed', 'dotted', 'wavy', 'zigzag', 'parallel']) {
        expect(chip(s), findsOneWidget, reason: s);
      }
    });

    testWidgets('a chip tap sets that style and keeps the wave sliders',
        (tester) async {
      final p = _Probe(
          line: const LineSettings(waveHeight: 6.5, waveWidth: 8.0));
      await pumpPanel(tester, p.model);
      await tester.tap(chip('dashed'));
      await tester.pumpAndSettle();
      expect(p.log, ['line dashed 6.5 8.0']);
      expect(p.line.style, LineStyle.dashed);
    });

    testWidgets('tapping the style that is already set does nothing',
        (tester) async {
      final p = _Probe(line: const LineSettings(style: LineStyle.dotted));
      await pumpPanel(tester, p.model);
      await tester.tap(chip('dotted'));
      await tester.pumpAndSettle();
      expect(p.log, isEmpty);
    });

    testWidgets('the wave sliders show only for wavy and zigzag',
        (tester) async {
      final p = _Probe();
      await pumpPanel(tester, p.model);
      final height = find.text('Wavy Line Height');
      final width = find.text('Wavy Line Width');
      for (final s in ['solid', 'dashed', 'dotted', 'parallel']) {
        p.line = LineSettings(style: LineStyle.values.byName(s));
        p.ping();
        await tester.pumpAndSettle();
        expect(height, findsNothing, reason: s);
        expect(width, findsNothing, reason: s);
        expect(slider('wave-height'), findsNothing, reason: s);
      }
      for (final s in ['wavy', 'zigzag']) {
        p.line = LineSettings(style: LineStyle.values.byName(s));
        p.ping();
        await tester.pumpAndSettle();
        expect(height, findsOneWidget, reason: s);
        expect(width, findsOneWidget, reason: s);
        expect(slider('wave-height'), findsOneWidget, reason: s);
        expect(slider('wave-width'), findsOneWidget, reason: s);
      }
    });

    testWidgets('choosing wavy opens the wave sliders with an animation',
        (tester) async {
      final p = _Probe();
      // Tall enough that the card is never held back by its maximum height.
      await pumpPanel(tester, p.model, screen: const Size(1280, 1800));
      double height() =>
          tester.getSize(find.byKey(const ValueKey('ink-settings-panel'))).height;
      final before = height();
      await tester.tap(chip('wavy'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final mid = height();
      await tester.pumpAndSettle();
      final after = height();
      expect(mid, greaterThan(before));
      expect(mid, lessThan(after));
      // And closes them again the same way.
      await tester.tap(chip('solid'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final closing = height();
      expect(closing, lessThan(after));
      expect(closing, greaterThan(before));
      await tester.pumpAndSettle();
      expect(height(), before);
    });

    testWidgets('the wave sliders edit the line settings', (tester) async {
      final p = _Probe(line: const LineSettings(style: LineStyle.zigzag));
      await pumpPanel(tester, p.model);
      await tester.tap(find.byKey(const ValueKey('ink-settings-wave-height-plus')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ink-settings-wave-width-minus')));
      await tester.pump();
      expect(p.log, ['line zigzag 3.2 3.7', 'line zigzag 3.2 3.6']);
      expect(find.text('3.2'), findsOneWidget);
      expect(find.text('3.6'), findsOneWidget);
    });

    testWidgets('two edits in one frame do not undo each other',
        (tester) async {
      final p = _Probe(line: const LineSettings(style: LineStyle.wavy));
      await pumpPanel(tester, p.model);
      // Both callbacks come from the same build, as with two fingers on two
      // sliders between frames.
      final height = tester.widget<InkSlider>(slider('wave-height')).onChanged!;
      final width = tester.widget<InkSlider>(slider('wave-width')).onChanged!;
      height(8.0);
      width(10.0);
      expect(p.line, const LineSettings(
          style: LineStyle.wavy, waveHeight: 8.0, waveWidth: 10.0));
    });

    testWidgets('the wave sliders keep to their ranges', (tester) async {
      final p = _Probe(line: const LineSettings(style: LineStyle.wavy));
      await pumpPanel(tester, p.model);
      await tester.drag(slider('wave-height'), const Offset(900, 0));
      await tester.pump();
      expect(p.line.waveHeight, LineSettings.maxWaveHeight);
      await tester.drag(slider('wave-height'), const Offset(-1800, 0));
      await tester.pump();
      expect(p.line.waveHeight, LineSettings.minWaveHeight);
      await tester.drag(slider('wave-width'), const Offset(900, 0));
      await tester.pump();
      expect(p.line.waveWidth, LineSettings.maxWaveWidth);
    });
  });

  group('thickness and concentration', () {
    testWidgets('the thickness steppers move by 0.1', (tester) async {
      final p = _Probe(size: 2.0);
      await pumpPanel(tester, p.model);
      await tester.tap(find.byKey(const ValueKey('ink-settings-thickness-plus')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ink-settings-thickness-plus')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ink-settings-thickness-minus')));
      await tester.pump();
      expect(p.log, ['size 2.1', 'size 2.2', 'size 2.1']);
      expect(find.text('2.1'), findsOneWidget);
    });

    testWidgets('the thickness slider spans the model limits', (tester) async {
      final p = _Probe();
      await pumpPanel(tester, p.model);
      await tester.drag(slider('thickness'), const Offset(900, 0));
      await tester.pump();
      expect(p.size, ToolPresets.penSizeMax);
      await tester.drag(slider('thickness'), const Offset(-1800, 0));
      await tester.pump();
      expect(p.size, ToolPresets.penSizeMin);
    });

    testWidgets('the concentration slider goes from 10 to 100 percent',
        (tester) async {
      final p = _Probe();
      await pumpPanel(tester, p.model);
      // No steppers on this one.
      expect(find.byKey(const ValueKey('ink-settings-concentration-plus')), findsNothing);
      await tester.drag(slider('concentration'), const Offset(-900, 0));
      await tester.pump();
      expect(p.concentration, minConcentration);
      expect(find.text('10%'), findsOneWidget);
      await tester.drag(slider('concentration'), const Offset(900, 0));
      await tester.pump();
      expect(p.concentration, 1.0);
      expect(find.text('100%'), findsOneWidget);
      for (final entry in p.log.where((e) => e.startsWith('conc'))) {
        final v = double.parse(entry.split(' ').last);
        expect(roundToDecimals(v, 2), v, reason: entry);
      }
    });

    testWidgets('the panel follows changes made behind its back',
        (tester) async {
      final p = _Probe(size: 2.0);
      await pumpPanel(tester, p.model);
      p.size = 7.5;
      p.concentration = 0.4;
      p.ping();
      await tester.pump();
      expect(find.text('7.5'), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);
    });

    testWidgets('with commitOnRelease one drag is one callback',
        (tester) async {
      final p = _Probe(commitOnRelease: true);
      await pumpPanel(tester, p.model);
      final g = await tester.startGesture(tester.getCenter(slider('thickness')));
      await g.moveBy(const Offset(50, 0));
      await tester.pump();
      await g.moveBy(const Offset(50, 0));
      await tester.pump();
      expect(p.log, isEmpty);
      await g.up();
      await tester.pump();
      expect(p.log, hasLength(1));
      expect(p.log.single, startsWith('size '));
    });

    testWidgets('with commitOnRelease a wave slider drag is one callback too',
        (tester) async {
      final p = _Probe(
          commitOnRelease: true,
          line: const LineSettings(style: LineStyle.wavy));
      await pumpPanel(tester, p.model);
      final g = await tester.startGesture(tester.getCenter(slider('wave-width')));
      await g.moveBy(const Offset(60, 0));
      await g.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(p.log, isEmpty);
      await g.up();
      await tester.pump();
      expect(p.log, hasLength(1));
      expect(p.log.single, startsWith('line wavy 3.1 '));
    });
  });

  group('reset', () {
    testWidgets('is greyed out when nothing differs and does nothing',
        (tester) async {
      final p = _Probe();
      await pumpPanel(tester, p.model);
      final reset = find.byKey(const ValueKey('ink-settings-reset'));
      expect(tester.widget<FilledButton>(reset).onPressed, isNull);
      await tester.tap(reset, warnIfMissed: false);
      expect(p.resets, 0);
    });

    testWidgets('lights up as soon as a setting differs and resets it',
        (tester) async {
      final p = _Probe(size: 5.0);
      await pumpPanel(tester, p.model);
      final reset = find.byKey(const ValueKey('ink-settings-reset'));
      expect(tester.widget<FilledButton>(reset).onPressed, isNotNull);
      await tester.tap(reset);
      await tester.pump();
      expect(p.resets, 1);
      expect(find.text('2.2'), findsOneWidget);
      expect(tester.widget<FilledButton>(reset).onPressed, isNull,
          reason: 'back at the defaults');
    });

    testWidgets('is hidden when the model has no reset', (tester) async {
      await pumpPanel(tester, _Probe(hasReset: false).model);
      expect(find.byKey(const ValueKey('ink-settings-reset')), findsNothing);
      expect(find.text('Reset'), findsNothing);
      expect(find.text('Technical pen'), findsOneWidget);
    });
  });

  group('horizontal drawing', () {
    testWidgets('the switch reflects and edits the setting', (tester) async {
      final p = _Probe();
      await pumpPanel(tester, p.model);
      final sw = find.byKey(const ValueKey('ink-settings-horizontal'));
      expect(tester.widget<SwitchListTile>(sw).value, isFalse);
      await tester.tap(sw);
      await tester.pump();
      expect(p.log, ['horizontal true']);
      expect(tester.widget<SwitchListTile>(sw).value, isTrue);
    });

    testWidgets('is hidden when the model has no such setting',
        (tester) async {
      await pumpPanel(tester, _Probe(hasHorizontal: false).model);
      expect(find.text('Horizontal drawing'), findsNothing);
      expect(find.byKey(const ValueKey('ink-settings-horizontal')), findsNothing);
      expect(find.text('Color'), findsOneWidget);
    });
  });

  group('showInkSettingsPanel', () {
    final opener = find.byKey(const ValueKey('opener'));
    final card = find.byKey(const ValueKey('ink-settings-panel'));

    Future<void> openFrom(
      WidgetTester tester,
      _Probe probe, {
      Alignment at = Alignment.topLeft,
      Size screen = const Size(1280, 800),
      Brightness brightness = Brightness.light,
    }) async {
      useScreen(tester, screen);
      await tester.pumpWidget(themedApp(
        Align(
          alignment: at,
          child: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('opener'),
              onPressed: () => showInkSettingsPanel(context, probe.model),
              child: const Text('open'),
            ),
          ),
        ),
        brightness: brightness,
      ));
      await tester.tap(opener);
      await tester.pumpAndSettle();
    }

    testWidgets('opens right under the widget that opened it, at the right',
        (tester) async {
      await openFrom(tester, _Probe());
      final from = tester.getRect(opener);
      final panel = tester.getRect(card);
      expect(panel.top, closeTo(from.bottom + 4, 0.01));
      expect(panel.right, 1280 - 8);
      expect(panel.width, inkSettingsPanelWidth);
    });

    testWidgets('keeps room for the card when it is opened from a low spot',
        (tester) async {
      await openFrom(tester, _Probe(), at: Alignment.bottomLeft);
      final panel = tester.getRect(card);
      expect(panel.bottom, lessThanOrEqualTo(800 - 8));
      expect(panel.height, greaterThanOrEqualTo(240));
      expect(tester.takeException(), isNull);
    });

    testWidgets('fades and scales in', (tester) async {
      useScreen(tester, const Size(1280, 800));
      final probe = _Probe();
      await tester.pumpWidget(themedApp(Builder(
        builder: (context) => TextButton(
          key: const ValueKey('opener'),
          onPressed: () => showInkSettingsPanel(context, probe.model),
          child: const Text('open'),
        ),
      )));
      await tester.tap(opener);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final fade = tester.widget<FadeTransition>(
          find.ancestor(of: card, matching: find.byType(FadeTransition)).first);
      expect(fade.opacity.value, inExclusiveRange(0, 1));
      final scale = tester.widget<ScaleTransition>(
          find.ancestor(of: card, matching: find.byType(ScaleTransition)).first);
      expect(scale.scale.value, inExclusiveRange(0.9, 1));
      await tester.pumpAndSettle();
      expect(fade.opacity.value, 1);
      expect(scale.scale.value, 1);
    });

    testWidgets('a tap outside closes it, a tap inside does not',
        (tester) async {
      await openFrom(tester, _Probe());
      await tester.tap(find.text('Thickness'));
      await tester.pumpAndSettle();
      expect(card, findsOneWidget);
      await tester.tapAt(const Offset(30, 700));
      await tester.pumpAndSettle();
      expect(card, findsNothing);
    });

    testWidgets('edits made in it reach the model', (tester) async {
      final probe = _Probe();
      await openFrom(tester, probe);
      await tester.tap(chip('zigzag'));
      await tester.pumpAndSettle();
      expect(probe.log, ['line zigzag 3.1 3.7']);
      expect(find.text('Wavy Line Height'), findsOneWidget);
    });

    testWidgets('uses the dark theme of the app', (tester) async {
      await openFrom(tester, _Probe(), brightness: Brightness.dark);
      final material = tester.widget<Material>(
          find.descendant(of: card, matching: find.byType(Material)).first);
      expect(material.color!.computeLuminance(), lessThan(0.1));
    });
  });

  group('colour grid', () {
    testWidgets('shows the presets, the recent colours, then the plus',
        (tester) async {
      final p = _Probe(recent: const [0xFF123456, 0xFF654321]);
      await pumpPanel(tester, p.model);
      final order = [...ToolPresets.penColors, 0xFF123456, 0xFF654321];
      final spots = [for (final c in order) tester.getCenter(swatch(c))];
      final add = tester.getCenter(find.byKey(const ValueKey('ink-settings-color-add')));
      // Reading order: left to right, then down.
      final all = [...spots, add];
      for (var i = 1; i < all.length; i++) {
        final a = all[i - 1], b = all[i];
        expect(b.dy > a.dy || (b.dy == a.dy && b.dx > a.dx), isTrue,
            reason: 'cell $i');
      }
    });

    testWidgets('has six colours to a row', (tester) async {
      final p = _Probe(recent: const [0xFF123456, 0xFF654321]);
      await pumpPanel(tester, p.model);
      final all = [
        ...ToolPresets.penColors,
        0xFF123456,
        0xFF654321,
      ];
      final rows = <double, int>{};
      for (final c in all) {
        rows.update(tester.getCenter(swatch(c)).dy, (n) => n + 1, ifAbsent: () => 1);
      }
      rows.update(
          tester.getCenter(find.byKey(const ValueKey('ink-settings-color-add'))).dy,
          (n) => n + 1,
          ifAbsent: () => 1);
      // 8 presets + 2 recents + the plus = 11 cells: 6 + 5.
      expect(rows.values.toList(), [6, 5]);
    });

    testWidgets('a full palette makes three rows of six', (tester) async {
      final recent = [for (var i = 1; i <= 8; i++) 0xFF000000 | (i * 0x101010)];
      final p = _Probe(recent: recent);
      await pumpPanel(tester, p.model);
      final ys = {
        for (final c in [...ToolPresets.penColors, ...recent])
          tester.getCenter(swatch(c)).dy,
        tester.getCenter(find.byKey(const ValueKey('ink-settings-color-add'))).dy,
      };
      expect(ys, hasLength(3));
    });

    testWidgets('marks the selected colour and lists a colour only once',
        (tester) async {
      // A recent colour equal to a preset must not make a second swatch.
      final p = _Probe(color: 0xFFD93025, recent: const [0xFFD93025]);
      await pumpPanel(tester, p.model);
      expect(swatch(0xFFD93025), findsOneWidget);
      for (final c in ToolPresets.penColors) {
        expect(tester.widget<ColorSwatchButton>(swatch(c)).selected,
            c == 0xFFD93025,
            reason: '$c');
      }
    });

    testWidgets('a selected colour that is in no list still gets a swatch',
        (tester) async {
      final p = _Probe(color: 0xFF0A0B0C);
      await pumpPanel(tester, p.model);
      expect(swatch(0xFF0A0B0C), findsOneWidget);
      expect(tester.widget<ColorSwatchButton>(swatch(0xFF0A0B0C)).selected, isTrue);
      // It comes after the presets, in the same grid.
      expect(tester.getCenter(swatch(0xFF0A0B0C)).dy,
          greaterThan(tester.getCenter(swatch(0xFF1E1E1E)).dy));
    });

    testWidgets('tapping a swatch picks that colour', (tester) async {
      final p = _Probe();
      await pumpPanel(tester, p.model);
      await tester.tap(swatch(0xFF1E5BD8));
      await tester.pump();
      expect(p.log, ['color ${0xFF1E5BD8}']);
      expect(tester.widget<ColorSwatchButton>(swatch(0xFF1E5BD8)).selected, isTrue);
    });

    testWidgets('the plus opens the colour picker and applies the choice',
        (tester) async {
      final p = _Probe();
      await pumpPanel(tester, p.model);
      await tester.tap(find.byKey(const ValueKey('ink-settings-color-add')));
      await tester.pumpAndSettle();
      expect(find.text('Custom colour'), findsOneWidget);
      await tester.tap(find.text('Use colour'));
      await tester.pumpAndSettle();
      expect(p.log, hasLength(1));
      expect(p.log.single, startsWith('color '));
      final argb = int.parse(p.log.single.split(' ').last);
      expect(argb >> 24, 0xFF, reason: 'opaque');
    });

    testWidgets('cancelling the picker changes nothing', (tester) async {
      final p = _Probe();
      await pumpPanel(tester, p.model);
      await tester.tap(find.byKey(const ValueKey('ink-settings-color-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(p.log, isEmpty);
    });

    testWidgets('the rainbow button in the header does the same',
        (tester) async {
      final p = _Probe();
      await pumpPanel(tester, p.model);
      await tester.tap(find.byKey(const ValueKey('ink-settings-color-wheel')));
      await tester.pumpAndSettle();
      expect(find.text('Custom colour'), findsOneWidget);
      await tester.tap(find.text('Use colour'));
      await tester.pumpAndSettle();
      expect(p.log, hasLength(1));
    });

    testWidgets('a model can take over the custom colour flow',
        (tester) async {
      final p = _Probe(customPicker: true);
      await pumpPanel(tester, p.model);
      await tester.tap(find.byKey(const ValueKey('ink-settings-color-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ink-settings-color-wheel')));
      await tester.pumpAndSettle();
      expect(p.log, ['custom picker', 'custom picker']);
      expect(find.text('Custom colour'), findsNothing);
    });

    testWidgets('is hidden when the model has no colour callback',
        (tester) async {
      await pumpPanel(tester, _Probe(hasColor: false).model);
      expect(find.text('Color'), findsNothing);
      expect(find.byKey(const ValueKey('ink-settings-color-add')), findsNothing);
      expect(find.byKey(const ValueKey('ink-settings-color-wheel')), findsNothing);
      expect(find.text('Horizontal drawing'), findsOneWidget);
    });

    testWidgets('no colour selected when the model has none', (tester) async {
      final p = _Probe()..color = null;
      await pumpPanel(tester, p.model);
      for (final c in ToolPresets.penColors) {
        expect(tester.widget<ColorSwatchButton>(swatch(c)).selected, isFalse);
      }
    });
  });
}
