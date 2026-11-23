import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/editor_tool.dart';
import 'package:neatink/features/editor/tool_prefs.dart';
import 'package:neatink/ink/line_style.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The tool preferences as version 1.3.0 stored them: no line style,
/// concentration or "Horizontal drawing".
const String oldPrefs = '''
{
  "lastTool": "highlighter",
  "pen": {"color": 4280391411, "size": 3.6, "style": "fountain"},
  "highlighter": {"color": 4294960640, "size": 22},
  "eraser": {"mode": "pixel", "size": 30},
  "recentColors": [4278190335, 4294901760],
  "shape": "ellipse"
}
''';

void main() {
  group('preferences written by 1.3.0', () {
    final prefs =
        ToolPrefs.fromJson(jsonDecode(oldPrefs) as Map<String, dynamic>);

    test('keep everything they had', () {
      expect(prefs.lastTool, EditorTool.highlighter);
      expect(prefs.pen.color, 4280391411);
      expect(prefs.pen.size, 3.6);
      expect(prefs.pen.style, PenStyle.fountain);
      expect(prefs.highlighter.color, 4294960640);
      expect(prefs.highlighter.size, 22);
      expect(prefs.eraser.mode, EraserMode.pixel);
      expect(prefs.eraser.size, 30);
      expect(prefs.recentColors, [4278190335, 4294901760]);
      expect(prefs.extra, {'shape': 'ellipse'});
    });

    test('load a solid, full-strength pen that draws freely', () {
      expect(prefs.pen.line, LineSettings.solid);
      expect(prefs.pen.concentration, 1.0);
      expect(prefs.pen.horizontal, isFalse);
      expect(prefs.highlighter.line, LineSettings.solid);
      expect(prefs.highlighter.concentration, 1.0);
      expect(prefs.highlighter.horizontal, isFalse);
    });

    test('load from the store too', () async {
      SharedPreferences.setMockInitialValues({ToolPrefs.prefsKey: oldPrefs});
      final loaded = ToolPrefsStore(await SharedPreferences.getInstance()).load();
      expect(loaded.pen.size, 3.6);
      expect(loaded.pen.line.isSolid, isTrue);
      expect(loaded.highlighter.concentration, 1.0);
    });

    test('and are written back with the new fields filled in', () {
      final json = prefs.toJson();
      expect(json['pen'], containsPair('concentration', 1.0));
      expect(json['pen'], containsPair('horizontal', false));
      expect(json['shape'], 'ellipse');
    });
  });

  group('the pen settings round trip', () {
    const pen = PenPrefs(
      color: 0xFFD93025,
      size: 1.7,
      style: PenStyle.technical,
      line: LineSettings(style: LineStyle.zigzag, waveHeight: 7.5, waveWidth: 12),
      concentration: 0.45,
      horizontal: true,
    );
    const highlighter = HighlighterPrefs(
      color: 0xFF40C4FF,
      size: 30,
      line: LineSettings(style: LineStyle.dashed),
      concentration: 0.8,
      horizontal: true,
    );

    test('through JSON', () {
      final prefs = const ToolPrefs().copyWith(pen: pen, highlighter: highlighter);
      final back = ToolPrefs.fromJson(
          jsonDecode(jsonEncode(prefs.toJson())) as Map<String, dynamic>);
      expect(back.pen.color, pen.color);
      expect(back.pen.size, pen.size);
      expect(back.pen.style, PenStyle.technical);
      expect(back.pen.line, pen.line);
      expect(back.pen.concentration, 0.45);
      expect(back.pen.horizontal, isTrue);
      expect(back.highlighter.line, highlighter.line);
      expect(back.highlighter.concentration, 0.8);
      expect(back.highlighter.horizontal, isTrue);
      expect(back.highlighter.size, 30);
    });

    test('through the store', () async {
      SharedPreferences.setMockInitialValues({});
      final shared = await SharedPreferences.getInstance();
      final store = ToolPrefsStore(shared);
      await store.save(const ToolPrefs().copyWith(pen: pen, highlighter: highlighter));
      final back = ToolPrefsStore(shared).load();
      expect(back.pen.line.style, LineStyle.zigzag);
      expect(back.pen.line.waveHeight, 7.5);
      expect(back.pen.horizontal, isTrue);
      expect(back.highlighter.line.style, LineStyle.dashed);
    });

    test('copyWith changes one field and keeps the rest', () {
      final changed = pen.copyWith(line: const LineSettings(style: LineStyle.parallel));
      expect(changed.line.style, LineStyle.parallel);
      expect(changed.concentration, 0.45);
      expect(changed.horizontal, isTrue);
      expect(changed.style, PenStyle.technical);
      final hl = highlighter.copyWith(concentration: 0.2);
      expect(hl.concentration, 0.2);
      expect(hl.line.style, LineStyle.dashed);
    });
  });

  group('preferences that are damaged', () {
    test('an unreadable line style is a solid line', () {
      for (final bad in <Object?>['wavy', 3, true, null, <Object?>[]]) {
        final pen = PenPrefs.fromJson({'line': bad});
        expect(pen.line, LineSettings.solid, reason: '$bad');
        final hl = HighlighterPrefs.fromJson({'line': bad});
        expect(hl.line, LineSettings.solid, reason: '$bad');
      }
    });

    test('the concentration is kept in 10..100%', () {
      expect(PenPrefs.fromJson({'concentration': 0}).concentration,
          minConcentration);
      expect(PenPrefs.fromJson({'concentration': 9}).concentration, 1.0);
      expect(PenPrefs.fromJson({'concentration': 'x'}).concentration, 1.0);
      expect(HighlighterPrefs.fromJson({'concentration': 0.5}).concentration, 0.5);
    });

    test('only a real true turns "Horizontal drawing" on', () {
      expect(PenPrefs.fromJson({'horizontal': true}).horizontal, isTrue);
      for (final bad in <Object?>[1, 'true', null, 0]) {
        expect(PenPrefs.fromJson({'horizontal': bad}).horizontal, isFalse,
            reason: '$bad');
      }
    });

    test('an unknown pen style falls back to the ballpoint', () {
      expect(PenPrefs.fromJson({'style': 'quill'}).style, PenStyle.ballpoint);
      expect(PenPrefs.fromJson({'style': 'technical'}).style, PenStyle.technical);
    });

    test('a stored value that cannot be read gives the defaults', () async {
      SharedPreferences.setMockInitialValues({ToolPrefs.prefsKey: 'not json'});
      final loaded = ToolPrefsStore(await SharedPreferences.getInstance()).load();
      expect(loaded.pen.line, LineSettings.solid);
      expect(loaded.pen.size, const PenPrefs().size);
    });
  });

  test('the thickness slider ranges are sensible', () {
    expect(ToolPresets.penSizeMin, lessThan(ToolPresets.penWidths.first));
    expect(ToolPresets.penSizeMax, greaterThan(ToolPresets.penWidths.last));
    expect(ToolPresets.highlighterSizeMin, lessThan(ToolPresets.highlighterWidths.first));
    expect(ToolPresets.highlighterSizeMax, greaterThan(ToolPresets.highlighterWidths.last));
  });
}
