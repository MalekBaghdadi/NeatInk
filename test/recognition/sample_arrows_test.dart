import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/recognition/arrows.dart';
import 'package:neatink/recognition/stroke_grouping.dart';

/// Runs the arrow finder on every line of a writing-samples file (Settings ›
/// Writing › Send writing samples) and writes what it found as JSON lines,
/// to check it against the handwriting.
///
/// The samples are personal data: skipped unless `NEATINK_SAMPLES` (the
/// file) and `NEATINK_ARROWS_OUT` (where to write) are set.
void main() {
  final samples = Platform.environment['NEATINK_SAMPLES'];
  final outPath = Platform.environment['NEATINK_ARROWS_OUT'];
  final skip = samples == null || outPath == null ? 'set NEATINK_SAMPLES and NEATINK_ARROWS_OUT' : false;

  test('arrows found in a samples file', () {
    final json = jsonDecode(File(samples!).readAsStringSync()) as Map<String, dynamic>;
    final entries = (json['lines'] ?? json['words']) as List<dynamic>;
    final out = StringBuffer();
    var lines = 0, withArrows = 0;
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i] as Map<String, dynamic>;
      final strokes = [
        for (final s in entry['strokes'] as List<dynamic>) _strokeFromSample(s as Map<String, dynamic>),
      ];
      if (strokes.isEmpty) continue;
      for (final line in groupStrokes(strokes)) {
        lines++;
        final found = findArrows(line);
        if (found.isNotEmpty) withArrows++;
        out.writeln(jsonEncode({
          'entry': i,
          'xHeight': line.xHeight,
          'arrows': [
            for (final a in found)
              {
                'text': a.text,
                'strokes': [for (final s in a.strokes) strokes.indexOf(s)],
              },
          ],
        }));
      }
    }
    File(outPath!).writeAsStringSync(out.toString());
    // ignore: avoid_print
    print('$lines lines, $withArrows with arrows');
  }, skip: skip);
}

Stroke _strokeFromSample(Map<String, dynamic> s) => Stroke(
      id: s['id'] as String,
      tool: StrokeTool.pen,
      color: colorFromHex((s['color'] as String?) ?? '#FF1E1E1E'),
      size: (s['size'] as num?)?.toDouble() ?? 2.2,
      raw: [
        for (final p in s['points'] as List<dynamic>)
          InkPoint(
            ((p as List<dynamic>)[0] as num).toDouble(),
            (p[1] as num).toDouble(),
            p.length > 2 ? (p[2] as num).toDouble() : 0.5,
            p.length > 3 ? (p[3] as num).toInt() : 0,
          ),
      ],
    );
