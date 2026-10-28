import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../document/cover_design.dart';

/// Paints a notebook cover: the colour (softly shaded) and the design's
/// pattern or science illustration. Photos and the page-preview look are
/// drawn by the cover widget; for those this paints only the colour.
///
/// Everything is drawn in code, so covers are sharp at any size and need no
/// image files (no licences, nothing to download). Illustrations are line
/// art on a 300 x 400 canvas (the 3:4 cover) scaled to fit; on light colours
/// the ink is dark instead of white. Random-looking details (brain folds,
/// stars, branches) come from fixed seeds, so a cover never changes.
class CoverPainter extends CustomPainter {
  const CoverPainter({required this.design, required this.color});

  final CoverDesign design;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    paintCoverBackground(canvas, size, color);
    final pattern = design.pattern;
    final art = design.art;
    if (design.kind == CoverKind.pattern && pattern != null) {
      paintCoverPattern(canvas, size, pattern, color);
    } else if (design.kind == CoverKind.art && art != null) {
      paintCoverArt(canvas, size, art, color);
    }
  }

  @override
  bool shouldRepaint(CoverPainter old) => old.design != design || old.color != color;
}

/// Light ink on dark colours, dark ink on light ones.
Color coverInk(Color background) =>
    background.computeLuminance() > 0.45 ? const Color(0xFF1B1B1F) : const Color(0xFFFFFFFF);

/// The cover colour, a little lighter at the top and darker at the bottom.
void paintCoverBackground(Canvas canvas, Size size, Color color) {
  final rect = Offset.zero & size;
  canvas.drawRect(
    rect,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(color, const Color(0xFFFFFFFF), 0.08)!,
          Color.lerp(color, const Color(0xFF000000), 0.18)!,
        ],
      ).createShader(rect),
  );
}

// ---------------------------------------------------------------------------
// Patterns
// ---------------------------------------------------------------------------

/// Draws [pattern] over the whole cover (sizes follow the cover's width).
void paintCoverPattern(Canvas canvas, Size size, CoverPattern pattern, Color color) {
  final ink = coverInk(color);
  final u = size.width / 12; // pattern unit
  Paint line(double alpha, double width) => Paint()
    ..color = ink.withValues(alpha: alpha)
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;
  Paint fill(double alpha) => Paint()..color = ink.withValues(alpha: alpha);
  canvas.save();
  canvas.clipRect(Offset.zero & size);
  final w = size.width, h = size.height;
  switch (pattern) {
    case CoverPattern.plain:
      break;
    case CoverPattern.stripes:
      final p = line(0.13, u * 0.45);
      for (var x = -h; x < w + h; x += u * 1.4) {
        canvas.drawLine(Offset(x, 0), Offset(x + h, h), p);
      }
    case CoverPattern.dots:
      final p = fill(0.2);
      var row = 0;
      for (var y = u * 0.5; y < h + u; y += u * 0.9, row++) {
        for (var x = (row.isOdd ? u * 0.5 : 0.0); x < w + u; x += u) {
          canvas.drawCircle(Offset(x, y), u * 0.13, p);
        }
      }
    case CoverPattern.grid:
      final thin = line(0.10, math.max(0.6, u * 0.03));
      final thick = line(0.18, math.max(1.0, u * 0.06));
      var i = 0;
      for (var x = 0.0; x <= w; x += u * 0.75, i++) {
        canvas.drawLine(Offset(x, 0), Offset(x, h), i % 4 == 0 ? thick : thin);
      }
      i = 0;
      for (var y = 0.0; y <= h; y += u * 0.75, i++) {
        canvas.drawLine(Offset(0, y), Offset(w, y), i % 4 == 0 ? thick : thin);
      }
    case CoverPattern.chevron:
      final p = line(0.17, u * 0.16)..strokeJoin = StrokeJoin.miter;
      for (var y = -u; y < h + u; y += u * 0.9) {
        final path = Path()..moveTo(-u, y);
        var up = true;
        for (var x = -u; x < w + u; x += u * 0.6) {
          path.lineTo(x + u * 0.6, up ? y - u * 0.4 : y);
          up = !up;
        }
        canvas.drawPath(path, p);
      }
    case CoverPattern.waves:
      final p = line(0.16, u * 0.12);
      for (var y = 0.0; y < h + u; y += u * 0.8) {
        final path = Path()..moveTo(0, y);
        for (var x = 0.0; x <= w + 2; x += 2) {
          path.lineTo(x, y + math.sin(x / u * math.pi) * u * 0.18);
        }
        canvas.drawPath(path, p);
      }
    case CoverPattern.diamonds:
      final a = fill(0.10);
      final l = line(0.12, math.max(0.6, u * 0.04));
      final d = u * 1.2;
      var row = 0;
      for (var y = 0.0; y < h + d; y += d, row++) {
        for (var x = row.isOdd ? d / 2 : 0.0; x < w + d; x += d * 1.0) {
          if (((x / d).round() + row).isEven) {
            canvas.drawPath(
              Path()
                ..moveTo(x, y - d / 2)
                ..lineTo(x + d / 2, y)
                ..lineTo(x, y + d / 2)
                ..lineTo(x - d / 2, y)
                ..close(),
              a,
            );
          }
        }
      }
      for (var x = -h; x < w + h; x += d) {
        canvas.drawLine(Offset(x, 0), Offset(x + h, h), l);
        canvas.drawLine(Offset(x + h, 0), Offset(x, h), l);
      }
    case CoverPattern.hexagons:
      final p = line(0.15, math.max(0.8, u * 0.05));
      final r = u * 0.55;
      final dx = r * math.sqrt(3), dy = r * 1.5;
      var row = 0;
      for (var y = 0.0; y < h + r; y += dy, row++) {
        for (var x = row.isOdd ? dx / 2 : 0.0; x < w + dx; x += dx) {
          canvas.drawPath(_polygon(Offset(x, y), r, 6, math.pi / 6), p);
        }
      }
    case CoverPattern.linen:
      final p = line(0.06, math.max(0.5, u * 0.03));
      for (var x = 0.0; x <= w; x += u * 0.16) {
        canvas.drawLine(Offset(x, 0), Offset(x, h), p);
      }
      for (var y = 0.0; y <= h; y += u * 0.16) {
        canvas.drawLine(Offset(0, y), Offset(w, y), p);
      }
  }
  canvas.restore();
}

Path _polygon(Offset c, double r, int sides, double start) {
  final path = Path();
  for (var i = 0; i < sides; i++) {
    final a = start + i * 2 * math.pi / sides;
    final p = c + Offset(math.cos(a), math.sin(a)) * r;
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

// ---------------------------------------------------------------------------
// Science illustrations
// ---------------------------------------------------------------------------

/// Draws [art] centred on the cover, scaled from its 300 x 400 canvas.
void paintCoverArt(Canvas canvas, Size size, CoverArt art, Color color) {
  final s = math.min(size.width / 300, size.height / 400);
  canvas.save();
  canvas.clipRect(Offset.zero & size);
  canvas.translate((size.width - 300 * s) / 2, (size.height - 400 * s) / 2);
  canvas.scale(s);
  final a = _Art(canvas, coverInk(color), color);
  switch (art) {
    case CoverArt.brain:
      a.brain();
    case CoverArt.neuron:
      a.neuron();
    case CoverArt.synapse:
      a.synapse();
    case CoverArt.network:
      a.network();
    case CoverArt.dna:
      a.dna();
    case CoverArt.cell:
      a.cell();
    case CoverArt.heartbeat:
      a.heartbeat();
    case CoverArt.microbes:
      a.microbes();
    case CoverArt.atom:
      a.atom();
    case CoverArt.molecules:
      a.molecules();
    case CoverArt.periodic:
      a.periodic();
    case CoverArt.waves:
      a.waves();
    case CoverArt.planets:
      a.planets();
    case CoverArt.galaxy:
      a.galaxy();
    case CoverArt.geometry:
      a.geometry();
    case CoverArt.equations:
      a.equations();
  }
  canvas.restore();
}

/// A tiny fixed-seed random generator (the same picture every time).
class _Rand {
  _Rand(this._s);
  int _s;
  double next() {
    _s = (_s * 1103515245 + 12345) & 0x7fffffff;
    return _s / 0x7fffffff;
  }

  double range(double a, double b) => a + (b - a) * next();
}

class _Art {
  _Art(this.c, this.ink, this.background);

  final Canvas c;
  final Color ink;
  final Color background;

  Paint stroke(double width, [double alpha = 0.9]) => Paint()
    ..color = ink.withValues(alpha: alpha)
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  Paint fill([double alpha = 0.9]) => Paint()
    ..color = ink.withValues(alpha: alpha)
    ..isAntiAlias = true;

  /// The cover colour itself (to cut shapes out of the ink).
  Paint get cut => Paint()..color = Color.lerp(background, const Color(0xFF000000), 0.05)!;

  void text(String s, Offset center, double size,
      {double alpha = 0.9, double angle = 0, bool bold = false, String family = 'NI-Roboto', bool cutOut = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontFamily: family,
          fontFamilyFallback: const ['NI-Roboto', 'NI-Lato'],
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          color: cutOut ? background : ink.withValues(alpha: alpha),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    c.save();
    c.translate(center.dx, center.dy);
    c.rotate(angle);
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    c.restore();
    tp.dispose();
  }

  /// Maths symbols drawn as strokes (the bundled fonts carry Latin letters
  /// only): `int` ∫, `sqrt` √ (with an overline [width] long), `pi` π,
  /// `lambda` λ, `theta` θ and `sigma` Σ, [h] high, centred on [at].
  void symbol(String kind, Offset at, double h, {double alpha = 0.9, double width = 0, double angle = 0}) {
    final p = Path();
    final x = at.dx, y = at.dy;
    switch (kind) {
      case 'int':
        p
          ..moveTo(x + 0.22 * h, y - 0.40 * h)
          ..quadraticBezierTo(x + 0.12 * h, y - 0.54 * h, x + 0.03 * h, y - 0.40 * h)
          ..cubicTo(x - 0.03 * h, y - 0.15 * h, x + 0.03 * h, y + 0.15 * h, x - 0.03 * h, y + 0.40 * h)
          ..quadraticBezierTo(x - 0.12 * h, y + 0.54 * h, x - 0.22 * h, y + 0.40 * h);
      case 'sqrt':
        p
          ..moveTo(x - 0.30 * h, y + 0.05 * h)
          ..lineTo(x - 0.20 * h, y)
          ..lineTo(x - 0.08 * h, y + 0.45 * h)
          ..lineTo(x + 0.06 * h, y - 0.50 * h)
          ..lineTo(x + 0.06 * h + width, y - 0.50 * h);
      case 'pi':
        p
          ..moveTo(x - 0.40 * h, y - 0.24 * h)
          ..quadraticBezierTo(x - 0.30 * h, y - 0.34 * h, x + 0.42 * h, y - 0.32 * h)
          ..moveTo(x - 0.16 * h, y - 0.31 * h)
          ..quadraticBezierTo(x - 0.16 * h, y + 0.10 * h, x - 0.26 * h, y + 0.40 * h)
          ..moveTo(x + 0.16 * h, y - 0.32 * h)
          ..quadraticBezierTo(x + 0.12 * h, y + 0.32 * h, x + 0.30 * h, y + 0.36 * h);
      case 'lambda':
        p
          ..moveTo(x - 0.24 * h, y - 0.46 * h)
          ..quadraticBezierTo(x - 0.04 * h, y - 0.46 * h, x + 0.30 * h, y + 0.44 * h)
          ..moveTo(x + 0.04 * h, y - 0.04 * h)
          ..lineTo(x - 0.30 * h, y + 0.44 * h);
      case 'theta':
        p
          ..addOval(Rect.fromCenter(center: at, width: 0.5 * h, height: 0.9 * h))
          ..moveTo(x - 0.25 * h, y)
          ..lineTo(x + 0.25 * h, y);
      case 'sigma':
        p
          ..moveTo(x + 0.30 * h, y - 0.42 * h)
          ..lineTo(x - 0.30 * h, y - 0.42 * h)
          ..lineTo(x + 0.06 * h, y)
          ..lineTo(x - 0.30 * h, y + 0.42 * h)
          ..lineTo(x + 0.30 * h, y + 0.42 * h);
    }
    c.save();
    c.translate(x, y);
    c.rotate(angle);
    c.translate(-x, -y);
    c.drawPath(p, stroke(math.max(1.4, h * 0.075), alpha));
    c.restore();
  }

  void stars(int n, int seed, {Rect area = const Rect.fromLTWH(0, 0, 300, 400), double maxAlpha = 0.8}) {
    final r = _Rand(seed);
    for (var i = 0; i < n; i++) {
      final p = Offset(r.range(area.left, area.right), r.range(area.top, area.bottom));
      c.drawCircle(p, r.range(0.5, 1.7), fill(r.range(0.2, maxAlpha)));
    }
    for (var i = 0; i < 5; i++) {
      final p = Offset(r.range(area.left, area.right), r.range(area.top, area.bottom));
      final k = r.range(3, 6);
      final st = stroke(1.1, 0.8);
      c.drawLine(p - Offset(k, 0), p + Offset(k, 0), st);
      c.drawLine(p - Offset(0, k), p + Offset(0, k), st);
    }
  }

  void graphPaper({double step = 20, double alpha = 0.09}) {
    final p = stroke(0.8, alpha);
    for (var x = 0.0; x <= 300; x += step) {
      c.drawLine(Offset(x, 0), Offset(x, 400), p);
    }
    for (var y = 0.0; y <= 400; y += step) {
      c.drawLine(Offset(0, y), Offset(300, y), p);
    }
  }

  /// A smooth wandering line from [start] (brain folds, flagella).
  Path wander(_Rand r, Offset start, double length, double heading, {double step = 9, double turn = 0.9}) {
    final path = Path()..moveTo(start.dx, start.dy);
    var p = start;
    var h = heading;
    var mid = p;
    for (var d = 0.0; d < length; d += step) {
      h += r.range(-turn, turn);
      final next = p + Offset(math.cos(h), math.sin(h)) * step;
      mid = Offset((p.dx + next.dx) / 2, (p.dy + next.dy) / 2);
      path.quadraticBezierTo(p.dx, p.dy, mid.dx, mid.dy);
      p = next;
    }
    path.lineTo(p.dx, p.dy);
    return path;
  }

  // ---- neuroscience & psychology --------------------------------------------

  void brain() {
    final cerebrum = Path()
      ..moveTo(52, 214)
      ..cubicTo(30, 160, 60, 96, 128, 86)
      ..cubicTo(176, 66, 240, 82, 262, 128)
      ..cubicTo(282, 168, 270, 212, 244, 226)
      ..cubicTo(228, 233, 210, 230, 198, 224)
      ..cubicTo(174, 246, 118, 252, 92, 242)
      ..cubicTo(68, 236, 56, 228, 52, 214)
      ..close();
    final cerebellum = Path()
      ..moveTo(196, 228)
      ..cubicTo(204, 214, 252, 214, 262, 236)
      ..cubicTo(270, 258, 236, 272, 214, 266)
      ..cubicTo(196, 262, 188, 244, 196, 228)
      ..close();
    final stem = Path()
      ..moveTo(176, 240)
      ..cubicTo(184, 270, 182, 300, 174, 330)
      ..lineTo(158, 330)
      ..cubicTo(164, 300, 160, 268, 150, 246);
    c.drawPath(stem, fill(0.12));
    c.drawPath(stem, stroke(3));
    c.drawPath(cerebellum, fill(0.14));
    c.save();
    c.clipPath(cerebellum);
    for (var i = 0; i < 6; i++) {
      final y = 222.0 + i * 8;
      c.drawPath(
          Path()
            ..moveTo(194, y + 6)
            ..quadraticBezierTo(230, y - 6, 268, y + 8),
          stroke(1.8, 0.6));
    }
    c.restore();
    c.drawPath(cerebellum, stroke(3));
    c.drawPath(cerebrum, fill(0.12));
    c.save();
    c.clipPath(cerebrum);
    final r = _Rand(7);
    for (var i = 0; i < 46; i++) {
      final start = Offset(r.range(50, 270), r.range(80, 245));
      c.drawPath(wander(r, start, r.range(26, 52), r.range(0, 2 * math.pi), step: 6, turn: 1.25), stroke(2.2, 0.5));
    }
    // central and lateral sulci
    c.drawPath(
        Path()
          ..moveTo(168, 76)
          ..cubicTo(160, 110, 170, 130, 150, 168),
        stroke(3.2, 0.9));
    c.drawPath(
        Path()
          ..moveTo(92, 212)
          ..cubicTo(130, 196, 160, 190, 196, 168),
        stroke(3.2, 0.9));
    c.restore();
    c.drawPath(cerebrum, stroke(3.4));
  }

  void _branch(_Rand r, Offset from, double heading, double length, double width, int depth) {
    final to = from + Offset(math.cos(heading), math.sin(heading)) * length;
    final bend = Offset(-math.sin(heading), math.cos(heading)) * r.range(-length * 0.15, length * 0.15);
    final mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2) + bend;
    c.drawPath(
        Path()
          ..moveTo(from.dx, from.dy)
          ..quadraticBezierTo(mid.dx, mid.dy, to.dx, to.dy),
        stroke(width, 0.9));
    if (depth == 0) {
      c.drawCircle(to, width * 0.9, fill(0.9));
      return;
    }
    final spread = r.range(0.35, 0.6);
    _branch(r, to, heading - spread, length * r.range(0.62, 0.78), width * 0.66, depth - 1);
    _branch(r, to, heading + spread, length * r.range(0.62, 0.78), width * 0.66, depth - 1);
  }

  void neuron() {
    final r = _Rand(11);
    const soma = Offset(128, 150);
    for (final h in [-2.6, -1.9, -1.2, -0.4, 2.3, 3.1]) {
      _branch(r, soma + Offset(math.cos(h), math.sin(h)) * 22, h, r.range(38, 52), 6, 3);
    }
    // soma: a rounded star around the dendrite roots
    final body = Path();
    for (var i = 0; i <= 60; i++) {
      final t = i / 60 * 2 * math.pi;
      final rad = 30 + 4 * math.sin(6 * t);
      final p = soma + Offset(math.cos(t), math.sin(t)) * rad;
      i == 0 ? body.moveTo(p.dx, p.dy) : body.lineTo(p.dx, p.dy);
    }
    body.close();
    c.drawPath(body, fill(0.22));
    c.drawPath(body, stroke(3.2));
    c.drawCircle(soma, 12, fill(0.55));
    c.drawCircle(soma + const Offset(3, -3), 4, fill(0.95));
    // axon with myelin sheaths and terminals
    final axon = Path()
      ..moveTo(148, 172)
      ..cubicTo(185, 215, 150, 285, 222, 334);
    c.drawPath(axon, stroke(4));
    for (final metric in axon.computeMetrics()) {
      for (var d = 32.0; d < metric.length - 26; d += 25) {
        final tan = metric.getTangentForOffset(d)!;
        c.save();
        c.translate(tan.position.dx, tan.position.dy);
        c.rotate(-tan.angle);
        final rr = RRect.fromRectAndRadius(const Rect.fromLTWH(-9.5, -6, 19, 12), const Radius.circular(6));
        c.drawRRect(rr, fill(0.35));
        c.drawRRect(rr, stroke(2.2));
        c.restore();
      }
      final end = metric.getTangentForOffset(metric.length)!;
      for (final h in [-0.9, -0.3, 0.3, 0.9]) {
        final dir = -end.angle + h;
        final tip = end.position + Offset(math.cos(dir), math.sin(dir)) * 26;
        c.drawLine(end.position, tip, stroke(2.6));
        c.drawCircle(tip, 4.8, fill(0.9));
      }
    }
  }

  void synapse() {
    // presynaptic terminal coming down from the axon
    final pre = Path()
      ..moveTo(128, 0)
      ..lineTo(128, 60)
      ..cubicTo(128, 90, 62, 110, 62, 170)
      ..cubicTo(62, 205, 78, 222, 96, 226)
      ..lineTo(204, 226)
      ..cubicTo(222, 222, 238, 205, 238, 170)
      ..cubicTo(238, 110, 172, 90, 172, 60)
      ..lineTo(172, 0);
    c.drawPath(pre, fill(0.12));
    c.drawPath(pre, stroke(3.4));
    final r = _Rand(5);
    final placed = <Offset>[];
    for (var i = 0; i < 140 && placed.length < 14; i++) {
      final p = Offset(r.range(88, 212), r.range(130, 208));
      if (placed.any((q) => (q - p).distance < 22)) continue;
      placed.add(p);
      c.drawCircle(p, 9, stroke(2.2));
      for (var k = 0; k < 3; k++) {
        c.drawCircle(p + Offset(r.range(-4, 4), r.range(-4, 4)), 1.6, fill(0.9));
      }
    }
    // vesicles releasing into the cleft
    for (final x in const [118.0, 182.0]) {
      c.drawArc(Rect.fromCircle(center: Offset(x, 226), radius: 10), math.pi, math.pi, false, stroke(2.4));
    }
    for (var i = 0; i < 34; i++) {
      c.drawCircle(Offset(r.range(96, 204), r.range(232, 256)), r.range(1.4, 2.4), fill(0.85));
    }
    // postsynaptic membrane with receptors
    final post = Path()
      ..moveTo(40, 300)
      ..cubicTo(80, 262, 220, 262, 260, 300);
    c.drawPath(post, stroke(3.4));
    for (final metric in post.computeMetrics()) {
      for (var d = 40.0; d < metric.length - 30; d += 22) {
        final tan = metric.getTangentForOffset(d)!;
        c.save();
        c.translate(tan.position.dx, tan.position.dy);
        c.rotate(-tan.angle);
        c.drawPath(
            Path()
              ..moveTo(-5, -9)
              ..lineTo(-5, 0)
              ..lineTo(5, 0)
              ..lineTo(5, -9),
            stroke(2.2));
        c.restore();
      }
    }
    final down = Path()
      ..moveTo(40, 300)
      ..cubicTo(70, 330, 70, 370, 64, 400)
      ..moveTo(260, 300)
      ..cubicTo(230, 330, 230, 370, 236, 400);
    c.drawPath(down, stroke(3.4));
    // a signal travelling on
    c.drawPath(
        Path()
          ..moveTo(110, 360)
          ..lineTo(130, 340)
          ..lineTo(150, 365)
          ..lineTo(170, 335)
          ..lineTo(190, 360),
        stroke(2.6, 0.75));
  }

  void network() {
    const layers = [4, 6, 6, 3];
    const xs = [56.0, 122.0, 186.0, 248.0];
    final nodes = <List<Offset>>[];
    for (var l = 0; l < layers.length; l++) {
      final n = layers[l];
      nodes.add([for (var i = 0; i < n; i++) Offset(xs[l], 200 + (i - (n - 1) / 2) * 50)]);
    }
    final r = _Rand(3);
    for (var l = 0; l + 1 < nodes.length; l++) {
      for (final a in nodes[l]) {
        for (final b in nodes[l + 1]) {
          c.drawLine(a, b, stroke(r.range(0.8, 2.4), r.range(0.25, 0.6)));
        }
      }
    }
    for (final layer in nodes) {
      for (final p in layer) {
        c.drawCircle(p, 12, cut);
        c.drawCircle(p, 12, stroke(3));
        c.drawCircle(p, 6, fill(r.range(0.4, 0.95)));
      }
    }
  }

  // ---- biology & medicine ---------------------------------------------------

  void dna() {
    const a = Offset(92, -10), b = Offset(208, 410);
    final axis = b - a;
    final len = axis.distance;
    final dir = axis / len;
    final n = Offset(-dir.dy, dir.dx);
    const amp = 48.0, turns = 3.2;
    Offset at(double t, double phase) => a + dir * (len * t) + n * (amp * math.sin(2 * math.pi * turns * t + phase));
    // rungs (base pairs)
    for (var t = 0.0; t <= 1.0; t += 0.022) {
      final p = at(t, 0), q = at(t, math.pi);
      final m = Offset((p.dx + q.dx) / 2, (p.dy + q.dy) / 2);
      c.drawLine(p, m, stroke(3.2, 0.75));
      c.drawLine(m, q, stroke(3.2, 0.4));
    }
    // two strands, the half behind drawn fainter
    for (final phase in const [0.0, math.pi]) {
      for (var t = 0.0; t < 1.0; t += 0.004) {
        final p = at(t, phase), q = at(t + 0.004, phase);
        final front = math.cos(2 * math.pi * turns * t + phase) > 0;
        c.drawLine(p, q, stroke(front ? 9 : 7, front ? 0.95 : 0.45));
      }
    }
    text('A–T', const Offset(54, 330), 16, alpha: 0.75, bold: true);
    text('G–C', const Offset(250, 70), 16, alpha: 0.75, bold: true);
  }

  void cell() {
    const center = Offset(150, 200);
    c.drawCircle(center, 124, fill(0.10));
    c.drawCircle(center, 124, stroke(3.6));
    c.drawCircle(center, 116, stroke(1.6, 0.6));
    // endoplasmic reticulum folds around the nucleus
    for (var k = 0; k < 3; k++) {
      final rr = 54.0 + k * 9;
      final path = Path();
      for (var i = 0; i <= 80; i++) {
        final t = -0.6 + i / 80 * 2.6;
        final rad = rr + 3 * math.sin(i * 0.9);
        final p = const Offset(132, 186) + Offset(math.cos(t), math.sin(t)) * rad;
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      c.drawPath(path, stroke(1.8, 0.55));
    }
    // nucleus
    c.drawCircle(const Offset(132, 186), 44, fill(0.22));
    c.drawCircle(const Offset(132, 186), 44, stroke(3));
    c.drawCircle(const Offset(132, 186), 39, stroke(1.2, 0.55));
    c.drawCircle(const Offset(140, 176), 13, fill(0.75));
    final r = _Rand(21);
    for (var i = 0; i < 22; i++) {
      final ang = r.range(0, 2 * math.pi), d = r.range(0, 34);
      c.drawCircle(const Offset(132, 186) + Offset(math.cos(ang), math.sin(ang)) * d, 1.4, fill(0.7));
    }
    // mitochondria
    for (final (p, angle) in const [(Offset(210, 132), 0.5), (Offset(92, 270), -0.3), (Offset(214, 248), 1.4)]) {
      c.save();
      c.translate(p.dx, p.dy);
      c.rotate(angle);
      final o = Rect.fromCenter(center: Offset.zero, width: 58, height: 26);
      c.drawOval(o, fill(0.22));
      c.drawOval(o, stroke(2.6));
      final z = Path()..moveTo(-22, 0);
      for (var i = 0; i < 8; i++) {
        z.lineTo(-22 + i * 6.0 + 3, i.isEven ? -8 : 8);
      }
      z.lineTo(24, 0);
      c.drawPath(z, stroke(1.6, 0.8));
      c.restore();
    }
    // Golgi apparatus
    for (var i = 0; i < 4; i++) {
      c.drawArc(Rect.fromCircle(center: const Offset(178, 318), radius: 30.0 - i * 6), -2.6, 1.9, false, stroke(3, 0.8));
    }
    // ribosomes and vesicles
    for (var i = 0; i < 46; i++) {
      final ang = r.range(0, 2 * math.pi), d = r.range(60, 110);
      c.drawCircle(center + Offset(math.cos(ang), math.sin(ang)) * d, r.range(1.2, 2.2), fill(0.75));
    }
    for (final p in const [Offset(236, 196), Offset(84, 126), Offset(120, 312)]) {
      c.drawCircle(p, 7, stroke(2));
    }
  }

  void heartbeat() {
    final heart = Path()
      ..moveTo(150, 236)
      ..cubicTo(78, 190, 46, 150, 58, 110)
      ..cubicTo(70, 72, 124, 64, 150, 104)
      ..cubicTo(176, 64, 230, 72, 242, 110)
      ..cubicTo(254, 150, 222, 190, 150, 236)
      ..close();
    c.drawPath(heart, fill(0.16));
    c.drawPath(heart, stroke(4));
    // inner highlight
    c.drawPath(
        Path()
          ..moveTo(84, 118)
          ..cubicTo(88, 96, 110, 90, 124, 100),
        stroke(3, 0.7));
    // ECG trace
    final ecg = Path()..moveTo(0, 312);
    for (final x0 in const [0.0, 150.0]) {
      ecg
        ..lineTo(x0 + 26, 312)
        ..quadraticBezierTo(x0 + 34, 300, x0 + 42, 312)
        ..lineTo(x0 + 56, 312)
        ..lineTo(x0 + 62, 322)
        ..lineTo(x0 + 72, 262)
        ..lineTo(x0 + 82, 334)
        ..lineTo(x0 + 88, 312)
        ..lineTo(x0 + 104, 312)
        ..quadraticBezierTo(x0 + 118, 294, x0 + 132, 312)
        ..lineTo(x0 + 150, 312);
    }
    c.drawPath(ecg, stroke(3.6));
    graphLine(330);
  }

  void graphLine(double y) {
    for (var x = 0.0; x <= 300; x += 15) {
      c.drawLine(Offset(x, y + 8), Offset(x, y + 14), stroke(1.2, 0.45));
    }
  }

  void microbes() {
    const center = Offset(150, 196);
    c.drawCircle(center, 122, fill(0.10));
    c.save();
    c.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: 118)));
    final r = _Rand(13);
    // rod bacteria with flagella
    for (var i = 0; i < 7; i++) {
      final p = center + Offset(r.range(-90, 90), r.range(-90, 90));
      final angle = r.range(0, math.pi);
      c.save();
      c.translate(p.dx, p.dy);
      c.rotate(angle);
      final body = RRect.fromRectAndRadius(const Rect.fromLTWH(-20, -8, 40, 16), const Radius.circular(8));
      c.drawRRect(body, fill(0.3));
      c.drawRRect(body, stroke(2.4));
      c.drawPath(wander(r, const Offset(20, 0), 30, 0, step: 5, turn: 0.9), stroke(1.4, 0.7));
      c.restore();
    }
    // cocci in chains
    for (var k = 0; k < 3; k++) {
      var p = center + Offset(r.range(-80, 80), r.range(-80, 80));
      var h = r.range(0, 2 * math.pi);
      for (var i = 0; i < 6; i++) {
        c.drawCircle(p, 6, fill(0.55));
        c.drawCircle(p, 6, stroke(1.6));
        h += r.range(-0.5, 0.5);
        p += Offset(math.cos(h), math.sin(h)) * 12.5;
      }
    }
    // an amoeba
    final blob = Path();
    for (var i = 0; i <= 50; i++) {
      final t = i / 50 * 2 * math.pi;
      final rad = 30 + 8 * math.sin(3 * t) + 4 * math.cos(5 * t);
      final p = center + const Offset(-28, 36) + Offset(math.cos(t), math.sin(t)) * rad;
      i == 0 ? blob.moveTo(p.dx, p.dy) : blob.lineTo(p.dx, p.dy);
    }
    c.drawPath(blob..close(), fill(0.18));
    c.drawPath(blob, stroke(2.4));
    c.drawCircle(center + const Offset(-24, 34), 8, fill(0.6));
    c.restore();
    // the eyepiece
    c.drawCircle(center, 122, stroke(8));
    c.drawCircle(center, 112, stroke(1.4, 0.5));
    for (var i = 0; i < 24; i++) {
      final t = i / 24 * 2 * math.pi;
      final out = center + Offset(math.cos(t), math.sin(t)) * 132;
      final inn = center + Offset(math.cos(t), math.sin(t)) * (i % 6 == 0 ? 142 : 137);
      c.drawLine(out, inn, stroke(2, 0.7));
    }
  }

  // ---- chemistry & physics --------------------------------------------------

  void atom() {
    const center = Offset(150, 200);
    for (final angle in const [0.0, math.pi / 3, 2 * math.pi / 3]) {
      c.save();
      c.translate(center.dx, center.dy);
      c.rotate(angle);
      final orbit = Rect.fromCenter(center: Offset.zero, width: 250, height: 86);
      c.drawOval(orbit, stroke(3.2));
      final t = angle * 1.7 + 0.6;
      c.drawCircle(Offset(125 * math.cos(t), 43 * math.sin(t)), 8, fill(0.95));
      c.restore();
    }
    final r = _Rand(4);
    for (var i = 0; i < 12; i++) {
      final ang = i * 2.4, d = i == 0 ? 0.0 : 6 + 2.0 * math.sqrt(i) * 5;
      final p = center + Offset(math.cos(ang), math.sin(ang)) * d * 0.9;
      c.drawCircle(p, 9, cut);
      if (r.next() > 0.5) {
        c.drawCircle(p, 9, fill(0.85));
      } else {
        c.drawCircle(p, 9, stroke(2.6));
      }
    }
  }

  void molecules() {
    void hexagon(Offset ctr, double rad, {bool aromatic = true}) {
      c.drawPath(_polygon(ctr, rad, 6, -math.pi / 2), stroke(3.4));
      if (aromatic) c.drawCircle(ctr, rad * 0.55, stroke(2.4, 0.75));
    }

    const h1 = Offset(104, 120), h2 = Offset(104 + 40 * 1.732, 120 + 0);
    hexagon(h1, 40);
    hexagon(h2, 40, aromatic: false);
    // double bonds of the second ring: inside, along every other edge
    for (final k in const [1, 3, 5]) {
      final a0 = -math.pi / 2 + k * math.pi / 3, a1 = a0 + math.pi / 3;
      final p0 = h2 + Offset(math.cos(a0), math.sin(a0)) * 30;
      final p1 = h2 + Offset(math.cos(a1), math.sin(a1)) * 30;
      final d = (p1 - p0) * 0.12;
      c.drawLine(p0 + d, p1 - d, stroke(2.4, 0.8));
    }
    final top = h1 + Offset(0, -40);
    c.drawLine(top, top + const Offset(0, -30), stroke(3.4));
    text('OH', top + const Offset(0, -44), 20, bold: true);
    final right = h2 + Offset(40 * 0.866, 20);
    c.drawLine(right, right + const Offset(28, 16), stroke(3.4));
    text('NH', right + const Offset(44, 26), 18, bold: true);
    text('2', right + const Offset(62, 32), 12, bold: true);
    // ball-and-stick methane
    const carbon = Offset(160, 296);
    for (final p in const [Offset(104, 270), Offset(212, 254), Offset(146, 352), Offset(220, 338)]) {
      c.drawLine(carbon, p, stroke(5, 0.8));
      c.drawCircle(p, 14, cut);
      c.drawCircle(p, 14, stroke(2.8));
      text('H', p, 13, bold: true);
    }
    c.drawCircle(carbon, 26, fill(0.9));
    text('C', carbon, 22, bold: true, cutOut: true);
  }

  void periodic() {
    const symbols = [
      ('H', 1), ('He', 2), ('Li', 3), ('Be', 4), ('B', 5),
      ('C', 6), ('N', 7), ('O', 8), ('F', 9), ('Ne', 10),
      ('Na', 11), ('Mg', 12), ('Al', 13), ('Si', 14), ('P', 15),
      ('S', 16), ('Cl', 17), ('Ar', 18), ('K', 19), ('Ca', 20),
    ];
    const tw = 50.0, th = 58.0, gap = 6.0, x0 = 13.0, y0 = 74.0;
    for (var i = 0; i < symbols.length; i++) {
      final (sym, z) = symbols[i];
      final col = i % 5, row = i ~/ 5;
      final rect = Rect.fromLTWH(x0 + col * (tw + gap), y0 + row * (th + gap), tw, th);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      final strong = sym == 'C' || sym == 'O';
      c.drawRRect(rr, fill(strong ? 0.9 : 0.06 + (z % 4) * 0.04));
      c.drawRRect(rr, stroke(2.2, 0.85));
      text('$z', rect.topLeft + const Offset(10, 9), 9, alpha: strong ? 1 : 0.75, cutOut: strong);
      text(sym, rect.center + const Offset(0, 4), 22, bold: true, cutOut: strong);
    }
    text('PERIODIC TABLE', const Offset(150, 46), 14, bold: true, alpha: 0.8);
  }

  void waves() {
    final axis = stroke(1.6, 0.5);
    for (final (y, amp, k, width, alpha) in const [
      (110.0, 28.0, 2.0, 3.4, 0.95),
      (200.0, 18.0, 4.0, 3.0, 0.8),
      (290.0, 36.0, 1.2, 3.6, 0.95),
    ]) {
      c.drawLine(Offset(20, y), Offset(282, y), axis);
      c.drawPath(
          Path()
            ..moveTo(282, y)
            ..lineTo(274, y - 4)
            ..moveTo(282, y)
            ..lineTo(274, y + 4),
          axis);
      final path = Path()..moveTo(24, y);
      for (var x = 24.0; x <= 276; x += 2) {
        path.lineTo(x, y - amp * math.sin((x - 24) / 252 * 2 * math.pi * k));
      }
      c.drawPath(path, stroke(width, alpha));
    }
    // wavelength marker on the top wave
    c.drawLine(const Offset(24, 70), const Offset(150, 70), stroke(1.8, 0.8));
    for (final x in const [24.0, 150.0]) {
      c.drawLine(Offset(x, 64), Offset(x, 76), stroke(1.8, 0.8));
    }
    symbol('lambda', const Offset(87, 52), 18);
    text('E = hf', const Offset(214, 238), 18, alpha: 0.85);
    text('T = 1/f', const Offset(80, 350), 18, alpha: 0.85);
  }

  // ---- space & maths --------------------------------------------------------

  void planets() {
    stars(110, 17);
    const p = Offset(160, 212);
    final ring = Rect.fromCenter(center: Offset.zero, width: 250, height: 62);
    c.save();
    c.translate(p.dx, p.dy);
    c.rotate(-0.32);
    c.drawArc(ring, math.pi, math.pi, false, stroke(6, 0.6)); // behind
    c.drawArc(ring.deflate(12), math.pi, math.pi, false, stroke(2, 0.45));
    c.restore();
    c.drawCircle(p, 62, cut);
    c.drawCircle(p, 62, fill(0.2));
    c.save();
    c.clipPath(Path()..addOval(Rect.fromCircle(center: p, radius: 62)));
    for (var i = -4; i <= 4; i++) {
      c.drawLine(Offset(p.dx - 70, p.dy + i * 14 + 10), Offset(p.dx + 70, p.dy + i * 14 - 30), stroke(5, 0.12 + (i.abs() % 2) * 0.1));
    }
    c.restore();
    c.drawCircle(p, 62, stroke(3.4));
    c.save();
    c.translate(p.dx, p.dy);
    c.rotate(-0.32);
    c.drawArc(ring, 0, math.pi, false, stroke(6, 0.95)); // in front
    c.drawArc(ring.deflate(12), 0, math.pi, false, stroke(2, 0.7));
    c.restore();
    // a moon with craters and a small planet
    c.drawCircle(const Offset(68, 96), 22, fill(0.85));
    for (final (o, rr) in const [(Offset(60, 90), 5.0), (Offset(74, 104), 3.5), (Offset(72, 86), 2.5)]) {
      c.drawCircle(o, rr, cut);
    }
    c.drawCircle(const Offset(244, 340), 12, fill(0.7));
    final orbit = stroke(1.4, 0.4);
    for (var t = 0.0; t < 2 * math.pi; t += 0.12) {
      c.drawCircle(const Offset(160, 212) + Offset(math.cos(t) * 140, math.sin(t) * 150), 0.9, orbit..style = PaintingStyle.fill);
    }
  }

  void galaxy() {
    stars(140, 23);
    const center = Offset(150, 200);
    c.save();
    c.translate(center.dx, center.dy);
    c.rotate(-0.45);
    c.scale(1, 0.62);
    final r = _Rand(29);
    for (var arm = 0; arm < 2; arm++) {
      for (var i = 0; i < 700; i++) {
        final t = i / 700 * 3.2 * math.pi;
        final rad = 10 * math.exp(0.245 * t);
        final ang = t + arm * math.pi + r.range(-0.25, 0.25);
        final jitter = r.range(-1, 1) * rad * 0.16;
        final p = Offset(math.cos(ang) * (rad + jitter), math.sin(ang) * (rad + jitter));
        c.drawCircle(p, r.range(0.6, 2.2) * (1.4 - t / (3.2 * math.pi)), fill(r.range(0.25, 0.9)));
      }
    }
    c.drawCircle(
      Offset.zero,
      54,
      Paint()
        ..shader = RadialGradient(colors: [
          ink.withValues(alpha: 0.95),
          ink.withValues(alpha: 0.35),
          ink.withValues(alpha: 0),
        ], stops: const [0, 0.35, 1])
            .createShader(Rect.fromCircle(center: Offset.zero, radius: 54)),
    );
    c.restore();
  }

  void geometry() {
    graphPaper();
    const o = Offset(150, 176);
    const rad = 92.0;
    c.drawCircle(o, rad, stroke(3.2));
    final pts = [for (final a in const [-math.pi / 2, math.pi / 6, 5 * math.pi / 6]) o + Offset(math.cos(a), math.sin(a)) * rad];
    c.drawPath(
        Path()
          ..moveTo(pts[0].dx, pts[0].dy)
          ..lineTo(pts[1].dx, pts[1].dy)
          ..lineTo(pts[2].dx, pts[2].dy)
          ..close(),
        stroke(2.8, 0.85));
    c.drawLine(o, o + const Offset(rad, 0), stroke(2.2, 0.8));
    c.drawCircle(o, 3.5, fill());
    text('r', o + const Offset(rad / 2, -12), 18, bold: true);
    c.drawArc(Rect.fromCircle(center: o, radius: 24), 0, -math.pi / 2.6, false, stroke(2, 0.8));
    symbol('theta', o + const Offset(34, -18), 15);
    // protractor
    const base = Offset(150, 346);
    c.drawArc(Rect.fromCircle(center: base, radius: 74), math.pi, math.pi, false, stroke(3));
    c.drawLine(base - const Offset(80, 0), base + const Offset(80, 0), stroke(3));
    for (var i = 0; i <= 18; i++) {
      final a = math.pi + i * math.pi / 18;
      final out = base + Offset(math.cos(a), math.sin(a)) * 74;
      final inn = base + Offset(math.cos(a), math.sin(a)) * (i % 3 == 0 ? 62 : 67);
      c.drawLine(out, inn, stroke(1.6, 0.8));
    }
    symbol('pi', const Offset(54, 58), 36, alpha: 0.85);
    text('a² + b² = c²', const Offset(214, 54), 16, alpha: 0.85);
  }

  void equations() {
    graphPaper(step: 25, alpha: 0.07);
    const items = [
      ('E = mc²', Offset(150, 196), 44.0, -0.04, 1.0),
      ('f(x) dx', Offset(96, 74), 26.0, -0.12, 0.85),
      ('F = ma', Offset(226, 112), 24.0, 0.08, 0.8),
      ('a² + b² = c²', Offset(104, 284), 24.0, 0.05, 0.85),
      ('V = IR', Offset(214, 340), 22.0, -0.06, 0.75),
      ('n = n(n+1)/2', Offset(102, 376), 18.0, 0.04, 0.6),
      ('PV = nRT', Offset(234, 262), 20.0, -0.1, 0.7),
      ('= h/p', Offset(78, 150), 20.0, 0.1, 0.7),
      ('2', Offset(258, 44), 22.0, 0.0, 0.6),
    ];
    for (final (s, p, size, angle, alpha) in items) {
      text(s, p, size, angle: angle, alpha: alpha, family: 'NI-Caveat', bold: size > 40);
    }
    symbol('int', const Offset(52, 76), 34, alpha: 0.85, angle: -0.12);
    symbol('lambda', const Offset(46, 147), 16, alpha: 0.7, angle: 0.1);
    symbol('sigma', const Offset(52, 376), 16, alpha: 0.6, angle: 0.04);
    symbol('sqrt', const Offset(250, 44), 24, alpha: 0.6, width: 16);
    c.drawPath(
        Path()
          ..moveTo(60, 226)
          ..quadraticBezierTo(150, 238, 244, 222),
        stroke(2.6, 0.7));
  }
}
