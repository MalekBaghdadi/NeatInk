import 'dart:convert';

import '../../../../ink/stroke.dart' show Stroke, colorToHex;
import '../../../../recognition/text_polish.dart';
import '../../../../recognition/word_image.dart';
import 'convert_plan.dart';
import 'png_gray.dart';

// Handwriting samples the owner can send to improve recognition: for every
// recognised LINE the text it should be, what the app read, the pen data and
// the exact picture(s) the model was given. Built only when the user taps
// "Share samples..." and shared through the system share sheet; nothing is
// ever sent automatically.

/// Version of the sample file layout (`format` at the top level). Format 1 had
/// one entry per word (128x32 crops); format 2 has one entry per line.
const int samplesFormat = 2;

/// One recognised line with the pictures the model read for it (usually one;
/// see [PlannedLine.images]).
class SampleLineInput {
  const SampleLineInput({
    required this.line,
    required this.pageIndex,
    required this.images,
  });

  final PlannedLine line;
  final int pageIndex;
  final List<WordImage> images;
}

/// The sample file's content as JSON-ready maps and lists.
///
/// Top level: `format` ([samplesFormat]), `app`, `appVersion`, `createdAt`,
/// `image` (how the pictures are encoded), `lineCount` and `lines`. Each entry
/// of `lines`:
///
/// * `page` (1-based) and `line` (0-based on its page);
/// * `recognizedText`: what the app read (before any spelling fix);
///   `finalText`: the text the user has for the line in the review sheet (what
///   they typed or accepted); `corrected`: the two differ;
/// * `confidence` of the line, `lineIncluded` (it was ticked to be converted);
/// * `suggestions`: `{original, replacement, kind, status}` for every spelling
///   or grammar fix offered, `status` being `pending`, `accepted` or `auto`;
/// * `words`: `{text, raw, confidence, alternatives}` for each recognised word
///   (`raw` is what the model alone read there);
/// * `baselineSlope` and `xHeight` of the line (page points), `bounds`
///   `[left, top, right, bottom]` of its ink;
/// * `images`: `{width, height, scale, scaleX, strokeWidthPx, originX, angle,
///   png}`, the grey picture the model was given as base64 PNG (the whole
///   line, a fixed height of 48 pixels; several only for very wide lines;
///   `scaleX` is the horizontal pixels per point, larger than `scale` when the
///   line was stretched);
/// * `strokes`: every pen stroke of the line in writing order,
///   `{id, color, size, points: [[x, y, pressure, tMs], ...]}` with the raw
///   pen points in page points.
Map<String, dynamic> buildSamplesJson({
  required String appVersion,
  required DateTime createdAt,
  required List<SampleLineInput> lines,
}) {
  final entries = <Map<String, dynamic>>[];
  final lineOnPage = <int, int>{};
  for (final input in lines) {
    final line = input.line;
    final lineNo =
        lineOnPage.update(input.pageIndex, (n) => n + 1, ifAbsent: () => 0);
    final ink = line.line.inkStrokes;
    final box = _inkBounds(ink);
    entries.add({
      'page': input.pageIndex + 1,
      'line': lineNo,
      'recognizedText': line.recognizedText,
      'finalText': line.text,
      'corrected': line.text != line.recognizedText,
      'confidence': _round(line.confidence, 1000),
      'lineIncluded': line.include,
      'suggestions': [
        for (final s in line.suggestions) _suggestionJson(s, 'pending'),
        for (final s in line.accepted) _suggestionJson(s, 'accepted'),
        for (final s in line.autoApplied) _suggestionJson(s, 'auto'),
      ],
      'words': [
        for (final w in line.words)
          {
            'text': w.text,
            'raw': w.raw,
            'confidence': _round(w.confidence, 1000),
            'alternatives': List<String>.of(w.alternatives),
          },
      ],
      'baselineSlope': _round(line.line.baselineSlope, 100000),
      'xHeight': _round(line.line.xHeight, 100),
      'bounds': [for (final v in box) _round(v, 100)],
      'images': [
        for (final image in input.images) ?_imageJson(image),
      ],
      'strokes': [
        for (final s in ink)
          {
            'id': s.id,
            'color': colorToHex(s.color),
            'size': s.size,
            'points': [for (final p in s.raw) p.toJson()],
          },
      ],
    });
  }
  return {
    'format': samplesFormat,
    'app': "Mariam's Notes",
    'appVersion': appVersion,
    'createdAt': createdAt.toIso8601String(),
    'image': {'encoding': 'png-gray8-base64', 'height': wordImageHeight},
    'lineCount': entries.length,
    'lines': entries,
  };
}

Map<String, dynamic> _suggestionJson(PolishSuggestion s, String status) => {
      'original': s.original,
      'replacement': s.replacement,
      'kind': s.kind.name,
      'status': status,
    };

/// `[left, top, right, bottom]` of the finite points of [strokes].
List<double> _inkBounds(Iterable<Stroke> strokes) {
  var left = double.infinity, top = double.infinity;
  var right = double.negativeInfinity, bottom = double.negativeInfinity;
  for (final s in strokes) {
    for (final p in s.raw) {
      if (!p.x.isFinite || !p.y.isFinite) continue;
      if (p.x < left) left = p.x;
      if (p.x > right) right = p.x;
      if (p.y < top) top = p.y;
      if (p.y > bottom) bottom = p.y;
    }
  }
  return left.isFinite ? [left, top, right, bottom] : const [0, 0, 0, 0];
}

Map<String, dynamic>? _imageJson(WordImage image) {
  if (image.width <= 0 ||
      image.height <= 0 ||
      image.pixels.length != image.width * image.height) {
    return null;
  }
  return {
    'width': image.width,
    'height': image.height,
    'scale': _round(image.scale, 1000),
    'strokeWidthPx': _round(image.strokeWidthPx, 1000),
    if (image is LineImage) ...{
      'scaleX': _round(image.scaleX, 1000),
      'originX': _round(image.originX, 100),
      'angle': _round(image.angle, 100000),
    },
    'png': base64Encode(encodeGrayPng(image.pixels, image.width, image.height)),
  };
}

double _round(double v, int scale) =>
    v.isFinite ? (v * scale).roundToDouble() / scale : 0;

/// [buildSamplesJson]'s result as the text of the file.
String encodeSamplesJson(Map<String, dynamic> samples) => jsonEncode(samples);

/// `mariams-notes-samples-yyyymmdd-hhmm.json` for a file made at [t].
String samplesFileName(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  final date = '${t.year.toString().padLeft(4, '0')}${two(t.month)}${two(t.day)}';
  return 'mariams-notes-samples-$date-${two(t.hour)}${two(t.minute)}.json';
}
