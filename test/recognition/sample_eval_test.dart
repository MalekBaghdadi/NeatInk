import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/recognition/ctc.dart';
import 'package:neatink/recognition/htr_channel.dart';
import 'package:neatink/recognition/lexicon.dart';
import 'package:neatink/recognition/stroke_grouping.dart';
import 'package:neatink/recognition/word_image.dart';

/// Reads lines of a writing-samples file with the app's whole line pipeline
/// (grouping, arrows, line images, decoder, polish), the model answered from
/// files, to measure changes against hand-transcribed truth.
///
/// Personal data: skipped unless these are set:
/// * `NEATINK_SAMPLES`: the samples file; `NEATINK_TRUTH`: `{index: text}`
///   (the lines to read);
/// * `NEATINK_EVAL_DIR`: where the line images go and the model's answers
///   come from;
/// * `NEATINK_EVAL_PASS`: `dump` writes every image the model is asked for
///   (`<key>.pgm`; answers are blank), `read` answers each image from
///   `<key>.f32` (float32 softmax rows written by a script running
///   assets/htr/model.onnx the way HtrPlugin.kt does) and writes the texts
///   to `NEATINK_EVAL_OUT` (`{index: text}`).
void main() {
  final env = Platform.environment;
  final samples = env['NEATINK_SAMPLES'], truthPath = env['NEATINK_TRUTH'], dir = env['NEATINK_EVAL_DIR'];
  final pass = env['NEATINK_EVAL_PASS'];
  final skip = samples == null || truthPath == null || dir == null || (pass != 'dump' && pass != 'read')
      ? 'set NEATINK_SAMPLES, NEATINK_TRUTH, NEATINK_EVAL_DIR and NEATINK_EVAL_PASS'
      : false;

  test('read sample lines with the app pipeline', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final charset = CtcCharset.fromJson(File('assets/htr/charset.json').readAsStringSync());
    final lexicon = Lexicon.parse(File('assets/htr/word_freq.txt').readAsStringSync(),
        studyText: File('assets/htr/subject_words.txt').readAsStringSync());
    final entries = (jsonDecode(File(samples!).readAsStringSync()) as Map<String, dynamic>)['lines'] as List<dynamic>;
    final truth = jsonDecode(File(truthPath!).readAsStringSync()) as Map<String, dynamic>;
    Directory(dir!).createSync(recursive: true);

    const channel = MethodChannel('neatink/htr-eval');
    var asked = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      final images = (call.arguments as Map<Object?, Object?>)['images']! as List<Object?>;
      return [
        for (final img in images.cast<Map<Object?, Object?>>())
          _answer(dir, pass!, img['width'] as int, img['height'] as int, img['pixels'] as Uint8List, charset, () => asked++),
      ];
    });
    final recognizer = HtrRecognizer(
      channel: channel,
      renderer: const PolylineWordImageRenderer(),
      lexiconLoader: () async => lexicon,
      charsetLoader: () async => charset,
    );
    final out = <String, String>{};
    for (final id in truth.keys) {
      final entry = entries[int.parse(id)] as Map<String, dynamic>;
      final strokes = [for (final s in entry['strokes'] as List<dynamic>) _strokeFromSample(s as Map<String, dynamic>)];
      final lines = groupStrokes(strokes);
      final results = lines.isEmpty ? const <LineResult>[] : await recognizer.recognizeLines(lines);
      out[id] = results.map((r) => r.text).where((t) => t.trim().isNotEmpty).join(' ');
    }
    // ignore: avoid_print
    print('$pass: ${truth.length} lines, $asked images');
    final outPath = env['NEATINK_EVAL_OUT'];
    if (pass == 'read' && outPath != null) {
      File(outPath).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 20)));
}

/// The model's answer for one image: blank everywhere while dumping, else
/// the probabilities stored for it.
Map<String, Object> _answer(String dir, String pass, int width, int height, Uint8List pixels, CtcCharset charset, void Function() count) {
  count();
  final key = _key(width, pixels);
  final classes = charset.classes;
  if (pass == 'dump') {
    final pgm = File('$dir/$key.pgm');
    if (!pgm.existsSync()) {
      pgm.writeAsBytesSync([...ascii.encode('P5\n$width $height\n255\n'), ...pixels]);
    }
    final steps = (width / 8).ceil();
    final probs = Float64List(steps * classes);
    for (var t = 0; t < steps; t++) {
      probs[t * classes + charset.blank] = 1;
    }
    return {'probs': probs, 'classes': classes, 'timesteps': steps};
  }
  final raw = File('$dir/$key.f32').readAsBytesSync();
  final floats = Float32List.view(raw.buffer, raw.offsetInBytes, raw.lengthInBytes ~/ 4);
  return {'probs': Float64List.fromList(floats), 'classes': classes, 'timesteps': floats.length ~/ classes};
}

/// FNV-1a 64 of the size and the pixels.
String _key(int width, Uint8List pixels) {
  var h = 0xcbf29ce484222325;
  void add(int b) {
    h ^= b & 0xff;
    h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  for (final b in [width >> 8, width, pixels.length >> 16, pixels.length >> 8, pixels.length]) {
    add(b);
  }
  for (final b in pixels) {
    add(b);
  }
  return h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
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
