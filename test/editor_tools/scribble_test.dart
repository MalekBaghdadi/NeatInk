import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/features/editor/tools/scribble.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/ink_rect.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/ink/vec2.dart';

import 'tool_test_utils.dart';

/// Back and forth between x0 and x1, drifting from y0 to y1, [turns] times.
List<Vec2> scratch(double x0, double x1, double y0, double y1, {int turns = 6}) => joinPaths([
      for (var k = 0; k < turns; k++)
        linePoints(k.isEven ? x0 : x1, y0 + (y1 - y0) * k / turns, k.isEven ? x1 : x0, y0 + (y1 - y0) * (k + 1) / turns),
    ]);

/// Up and down between y0 and y1 while moving from x0 to x1, [turns] times.
List<Vec2> zigzag(double x0, double x1, double y0, double y1, {int turns = 10}) => joinPaths([
      for (var k = 0; k < turns; k++)
        linePoints(x0 + (x1 - x0) * k / turns, k.isEven ? y1 : y0, x0 + (x1 - x0) * (k + 1) / turns, k.isEven ? y0 : y1),
    ]);

bool shape(List<Vec2> pts) => isScribbleShape(strokeOf('s', pts).points);

/// "Handwriting" of a word: small letter-like loops between x0 and x1 on
/// baseline [y] with x-height 8.
List<Stroke> word(String id, double x0, double x1, double y) => [
      for (var x = x0, i = 0; x + 6 <= x1; x += 9, i++)
        strokeOf('$id$i', [
          for (var a = 0; a <= 16; a++) Vec2(x + 3 + 3 * math.cos(a * math.pi / 8), y - 4 + 4 * math.sin(a * math.pi / 8)),
        ]),
    ];

ScribblePlan? plan(List<Vec2> scribble, {List<Stroke> strokes = const [], List<TextItem> texts = const [], Map<String, List<ScribbleWord>> words = const {}}) =>
    planScribble(
      scribble: strokeOf('scribble', scribble),
      strokes: strokes,
      texts: texts,
      wordsOf: (t) => words[t.id] ?? const [],
      measureHeight: (t) => 99,
    );

void main() {
  group('isScribbleShape', () {
    test('back and forth over a word is a scribble', () {
      expect(shape(scratch(100, 160, 92, 100)), isTrue);
      expect(shape(scratch(100, 160, 100, 92)), isTrue, reason: 'drifting up');
      // Slanted, over slanted writing.
      final slanted = [for (final p in scratch(0, 60, 0, 8)) Vec2(100 + p.x * 0.94 - p.y * 0.34, 100 + p.x * 0.34 + p.y * 0.94)];
      expect(shape(slanted), isTrue);
    });

    test('zig-zagging across a word is a scribble', () {
      expect(shape(zigzag(100, 160, 88, 102)), isTrue);
    });

    test('a short word scribbled up and down is one too', () {
      expect(shape(zigzag(100, 112, 86, 104, turns: 8)), isTrue);
    });

    test('a line, a wavy underline, a circle, an M and a quick tick are not', () {
      expect(shape(linePoints(100, 100, 200, 100)), isFalse);
      expect(shape([for (var x = 0.0; x <= 80; x += 1) Vec2(100 + x, 100 + 2 * math.sin(x * 2 * math.pi / 12))]), isFalse);
      expect(shape([for (var a = 0; a <= 64; a++) Vec2(100 + 20 * math.cos(a * math.pi / 32), 100 + 20 * math.sin(a * math.pi / 32))]), isFalse);
      expect(shape(joinPaths([linePoints(0, 14, 0, 0), linePoints(0, 0, 5, 8), linePoints(5, 8, 10, 0), linePoints(10, 0, 10, 14)])), isFalse);
      expect(shape(joinPaths([linePoints(0, 4, 3, 8), linePoints(3, 8, 12, 0)])), isFalse);
    });

    test('back and forth only twice is not enough', () {
      expect(shape(scratch(100, 160, 92, 100, turns: 3)), isFalse);
    });

    test('a tiny scribble (a filled-in dot) is not one', () {
      expect(shape(scratch(100, 105, 100, 103)), isFalse);
    });
  });

  group('short scribbles', () {
    test('three zig-zags or three passes are a short scribble; a letter M is too', () {
      List<InkPoint> pts(List<Vec2> v) => strokeOf('s', v).points;
      expect(scribbleShapeOf(pts(zigzag(100, 140, 86, 104, turns: 4))), ScribbleShape.short);
      expect(scribbleShapeOf(pts(scratch(100, 160, 92, 100, turns: 4))), ScribbleShape.short);
      expect(scribbleShapeOf(pts(zigzag(100, 160, 86, 104, turns: 10))), ScribbleShape.clear);
      expect(scribbleShapeOf(pts(linePoints(100, 100, 200, 100))), ScribbleShape.none);
      expect(scribbleShapeOf(pts(zigzag(100, 120, 86, 104, turns: 2))), ScribbleShape.none, reason: 'a V');
    });

    test('a quick up-and-down scribble over a word deletes it (it used to become an "A")', () {
      final letters = word('w', 100, 140, 100);
      final p = plan(zigzag(100, 134, 91, 101, turns: 4), strokes: letters)!;
      expect(p.strokeIds, {for (final s in letters) s.id});
    });

    test('a short scribble needs more under it than a clear one', () {
      // A loop spanning 59% of the scribble's width.
      final loop = strokeOf('o', [
        for (var a = 0; a <= 32; a++) Vec2(120 + 10 * math.cos(a * math.pi / 16), 95 + 6 * math.sin(a * math.pi / 16)),
      ]);
      expect(plan(scratch(106, 136, 88, 102, turns: 4), strokes: [loop]), isNull, reason: 'short: needs 60% of the width');
      expect(plan(scratch(106, 136, 88, 102, turns: 6), strokes: [loop])!.strokeIds, {'o'}, reason: 'clear: half is enough');
    });

    test('a scribble much taller than the word it covers still deletes it', () {
      final letters = word('w', 100, 140, 100); // 8 pt tall
      expect(plan(zigzag(98, 142, 72, 108, turns: 8), strokes: letters)!.strokeIds, {for (final s in letters) s.id});
      // Over a flat underline it is ink: nothing tall enough under it.
      final rule = strokeOf('rule', linePoints(98, 104, 142, 104));
      expect(plan(zigzag(98, 142, 72, 108, turns: 8), strokes: [rule]), isNull);
    });

    test('on empty paper a W stays a W', () {
      expect(plan(zigzag(300, 330, 90, 104, turns: 4)), isNull);
    });
  });

  group('planScribble: handwriting', () {
    final hello = word('h', 100, 160, 100);
    final other = word('o', 200, 260, 100);

    test('deletes the strokes it covers, nothing else', () {
      final p = plan(scratch(98, 162, 92, 100), strokes: [...hello, ...other])!;
      expect(p.strokeIds, {for (final s in hello) s.id});
      expect(p.textChanges, isEmpty);
    });

    test('a zig-zag works the same', () {
      final p = plan(zigzag(98, 162, 90, 101), strokes: [...hello, ...other])!;
      expect(p.strokeIds, {for (final s in hello) s.id});
    });

    test('over empty paper it is ink', () {
      expect(plan(scratch(300, 360, 92, 100), strokes: [...hello, ...other]), isNull);
    });

    test('one dot under it is not enough: it is writing over a stray mark', () {
      final dot = strokeOf('dot', [const Vec2(130, 95), const Vec2(131, 95.5)]);
      expect(plan(scratch(100, 160, 92, 100), strokes: [dot]), isNull);
    });

    test('a long line crossing it stays; the word on it goes', () {
      final rule = strokeOf('rule', linePoints(20, 96, 500, 96));
      final p = plan(scratch(98, 162, 92, 100), strokes: [rule, ...hello])!;
      expect(p.strokeIds, isNot(contains('rule')));
      expect(p.strokeIds, containsAll([for (final s in hello) s.id]));
    });

    test('a tall letter crossed out through its middle goes too', () {
      final l = strokeOf('l', linePoints(120, 80, 121, 100));
      final p = plan(scratch(98, 162, 90, 100), strokes: [...hello, l])!;
      expect(p.strokeIds, contains('l'));
    });

    test('shading inside a closed outline keeps the outline', () {
      final cell = strokeOf('cell', [
        for (var a = 0; a <= 64; a++) Vec2(130 + 40 * math.cos(a * math.pi / 32), 96 + 25 * math.sin(a * math.pi / 32)),
      ]);
      final label = word('l', 110, 150, 100);
      // Shading most of the cell: without the rule its outline would go.
      expect(plan(scratch(100, 160, 80, 112, turns: 10), strokes: [cell]), isNull);
      // A label inside it can still be scratched out.
      final p = plan(scratch(108, 152, 90, 102), strokes: [cell, ...label])!;
      expect(p.strokeIds, {for (final s in label) s.id});
      // A small loop under a bigger scribble is not around it: it goes.
      final o = strokeOf('o', [for (var a = 0; a <= 32; a++) Vec2(130 + 6 * math.cos(a * math.pi / 16), 96 + 6 * math.sin(a * math.pi / 16))]);
      expect(plan(scratch(122, 138, 90, 102), strokes: [o])!.strokeIds, {'o'});
    });

    test('a highlight under the word goes with it, a long one stays', () {
      final short = strokeOf('hl', linePoints(100, 96, 160, 96), tool: StrokeTool.highlighter, size: 10);
      final long = strokeOf('hl2', linePoints(20, 96, 400, 96), tool: StrokeTool.highlighter, size: 10);
      final p = plan(scratch(98, 162, 92, 100), strokes: [...hello, short, long])!;
      expect(p.strokeIds, contains('hl'));
      expect(p.strokeIds, isNot(contains('hl2')));
    });
  });

  group('planScribble: typed text', () {
    // "hello world" from x 100: "hello" 100..150, "world" 160..210, line 90..104.
    const box = TextItem(id: 't', x: 100, y: 90, width: 300, height: 14, text: 'hello world', fontSize: 10);
    final words = {
      't': <ScribbleWord>[
        (start: 0, end: 5, boxes: [const InkRect(100, 90, 150, 104)]),
        (start: 6, end: 11, boxes: [const InkRect(160, 90, 210, 104)]),
      ],
    };

    test('deletes the words it covers and keeps the rest of the box', () {
      final p = plan(scratch(158, 212, 92, 102), texts: [box], words: words)!;
      expect(p.strokeIds, isEmpty);
      final (before, after) = p.textChanges.single;
      expect(before, same(box));
      expect(after!.text, 'hello');
      expect(after.height, 99, reason: 'measured again');
      expect(after.id, 't');
      expect(after.x, box.x);
    });

    test('a box with every word gone is removed', () {
      final p = plan(scratch(98, 212, 92, 102), texts: [box], words: words)!;
      final (_, after) = p.textChanges.single;
      expect(after, isNull);
    });

    test('a word only partly under it stays', () {
      expect(plan(scratch(185, 240, 92, 102), texts: [box], words: words), isNull);
    });

    test('ink and text in one scribble', () {
      final ink = word('w', 220, 260, 102);
      final p = plan(scratch(158, 262, 92, 102), strokes: ink, texts: [box], words: words)!;
      expect(p.strokeIds, {for (final s in ink) s.id});
      expect(p.textChanges.single.$2!.text, 'hello');
    });
  });

  group('withoutWords', () {
    List<(int, int)> at(String text, List<String> gone) => [
          for (final m in RegExp(r'\S+').allMatches(text))
            if (gone.contains(m.group(0))) (m.start, m.end),
        ];
    String without(String text, List<String> gone) => withoutWords(text, at(text, gone));

    test('keeps one separator where words were', () {
      expect(without('one two three', ['two']), 'one three');
      expect(without('one two three', ['one']), 'two three');
      expect(without('one two three', ['three']), 'one two');
      expect(without('one two three four', ['two', 'three']), 'one four');
    });

    test('keeps a line break, leading space and a trailing break', () {
      expect(without('one two\nthree', ['two']), 'one\nthree');
      expect(without('  indented word', ['word']), '  indented');
      expect(without('a b\n', ['a']), 'b\n');
    });

    test('nothing left is empty', () {
      expect(without('one two', ['one', 'two']), '');
    });
  });
}
