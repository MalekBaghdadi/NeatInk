import 'dart:convert';

import '../../../../ink/stroke.dart' show colorToHex;
import '../../../../recognition/word_image.dart';
import 'convert_corrections.dart';
import 'convert_plan.dart';
import 'png_gray.dart';

// Handwriting samples the owner can send to improve recognition: for every
// recognised word the text it should be, what the model said, the pen data and
// the exact 128x32 picture the model was given. Built only when the user taps
// "Share samples..." and shared through the system share sheet; nothing is
// ever sent automatically.

/// Version of the sample file layout (`format` at the top level).
const int samplesFormat = 1;

/// One recognised line with the pictures of its words ([images] has one entry
/// per word of `line.words`, in order).
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
/// Top level: `format`, `app`, `appVersion`, `createdAt`, `image` (how the
/// word pictures are encoded) and `words`. Each entry of `words`:
///
/// * `page` (1-based), `line` (0-based on its page), `wordInLine`,
///   `wordsInLine`;
/// * `finalText`: the text the user has for this word in the review sheet,
///   when the corrected line still has one word per recognised word (null
///   otherwise), and `corrected` (it differs from `read`);
/// * `read` (the app's final reading), `raw` (the model's own output),
///   `confidence`, `alternatives`;
/// * `lineText` (the whole line as in the review field) and `lineIncluded`
///   (it was ticked to be converted);
/// * `baselineSlope` and `xHeight` of the line (page points), `bounds`
///   `[left, top, right, bottom]` of the word;
/// * `strokes`: `{id, color, size, points: [[x, y, pressure, tMs], ...]}` with
///   the raw pen points in page points;
/// * `image`: `{width, height, scale, strokeWidthPx, png}`, the grey picture
///   sent to the model as base64 PNG (as wide as the word, a fixed height).
Map<String, dynamic> buildSamplesJson({
  required String appVersion,
  required DateTime createdAt,
  required List<SampleLineInput> lines,
}) {
  final words = <Map<String, dynamic>>[];
  final lineOnPage = <int, int>{};
  for (final input in lines) {
    final line = input.line;
    final lineNo =
        lineOnPage.update(input.pageIndex, (n) => n + 1, ifAbsent: () => 0);
    final aligned = alignWords(line.text, line.words.length);
    for (var i = 0; i < line.words.length; i++) {
      final w = line.words[i];
      final finalText = aligned?[i];
      final b = w.group.bounds;
      final image = i < input.images.length ? input.images[i] : null;
      words.add({
        'page': input.pageIndex + 1,
        'line': lineNo,
        'wordInLine': i,
        'wordsInLine': line.words.length,
        'finalText': finalText,
        'corrected': finalText != null && finalText != w.text,
        'read': w.text,
        'raw': w.raw,
        'confidence': _round(w.confidence, 1000),
        'alternatives': List<String>.of(w.alternatives),
        'lineText': line.text,
        'lineIncluded': line.include,
        'baselineSlope': _round(line.line.baselineSlope, 100000),
        'xHeight': _round(line.line.xHeight, 100),
        'bounds': [
          _round(b.left, 100),
          _round(b.top, 100),
          _round(b.right, 100),
          _round(b.bottom, 100),
        ],
        'strokes': [
          for (final s in w.group.strokes)
            {
              'id': s.id,
              'color': colorToHex(s.color),
              'size': s.size,
              'points': [for (final p in s.raw) p.toJson()],
            },
        ],
        'image': image == null ? null : _imageJson(image),
      });
    }
  }
  return {
    'format': samplesFormat,
    'app': "Mariam's Notes",
    'appVersion': appVersion,
    'createdAt': createdAt.toIso8601String(),
    'image': {'encoding': 'png-gray8-base64', 'height': wordImageHeight},
    'wordCount': words.length,
    'words': words,
  };
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
