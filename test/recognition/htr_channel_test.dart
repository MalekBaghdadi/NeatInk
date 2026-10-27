import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/recognition/ctc.dart';
import 'package:neatink/recognition/htr_channel.dart';
import 'package:neatink/recognition/lexicon.dart';
import 'package:neatink/recognition/stroke_grouping.dart';
import 'package:neatink/recognition/word_image.dart';

import '../beautify/synthetic_font.dart';
import 'ctc_fixtures.dart';

const MethodChannel _channel = MethodChannel('neatink/htr');

/// The platform side of the channel: replies with canned log-probabilities.
class _FakePlugin {
  _FakePlugin(this.replies);

  /// One reading per image, consumed in order.
  final List<CtcLogProbs> replies;
  final List<int> batchSizes = [];
  final List<Uint8List> images = [];
  PlatformException? failure;
  int next = 0;

  Future<Object?> handle(MethodCall call) async {
    if (failure != null) throw failure!;
    switch (call.method) {
      case 'recognize':
        final sent = ((call.arguments as Map)['images'] as List).cast<Uint8List>();
        batchSizes.add(sent.length);
        images.addAll(sent);
        return [
          for (var i = 0; i < sent.length; i++)
            Float32List.fromList(replies[next++ % replies.length].data),
        ];
      case 'info':
        return {
          'classes': 79,
          'timesteps': 32,
          'blank': 78,
          'charset': testCharset().chars,
          'width': 128,
          'height': 32,
        };
    }
    throw MissingPluginException();
  }
}

void _mock(_FakePlugin? plugin) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, plugin?.handle);
}

List<WordGroup> _words(int n) {
  final strokes = [
    for (var i = 0; i < n; i++)
      ...makeWord('hello', prefix: 'w$i', x: 100 + i * 60.0, y: 300),
  ];
  final words = groupStrokes(strokes).expand((l) => l.words).toList();
  expect(words, hasLength(n));
  return words;
}

HtrRecognizer _recognizer({Lexicon? lexicon, int batchSize = 32}) => HtrRecognizer(
      channel: _channel,
      renderer: const PolylineWordImageRenderer(),
      lexiconLoader: () async => lexicon,
      charsetLoader: () async => testCharset(),
      batchSize: batchSize,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cs = testCharset();
  final lex = Lexicon.parse('hello 1000\nhelp 900\ncat 5000\ncot 100\n');

  // 32 timesteps like the real model.
  CtcLogProbs reading(String text) {
    final frames = spell(text, p: 0.9);
    while (frames.length < 32) {
      frames.add({'_': 0.95});
    }
    return framesOf(cs, frames.take(32).toList());
  }

  tearDown(() => _mock(null));

  test('recognizes words: renders images, sends them, decodes the reply', () async {
    final plugin = _FakePlugin([reading('hello'), reading('help')]);
    _mock(plugin);
    final progress = <int>[];
    final results = await _recognizer(lexicon: lex).recognizeWords(
      _words(2),
      onProgress: (done, total) => progress.add(done),
    );
    expect(results.map((r) => r.text), ['hello', 'help']);
    expect(results.map((r) => r.raw), ['hello', 'help']);
    expect(results.every((r) => r.confidence > 0.5 && r.confidence <= 1), isTrue);
    expect(results[0].group, isA<WordGroup>());
    expect(plugin.images, hasLength(2));
    expect(plugin.images.every((i) => i.length == 4096), isTrue);
    expect(progress, [0, 2]);
  });

  test('applies the lexicon to the model output', () async {
    final frames = <Map<String, double>>[
      {'c': 0.9, '_': 0.05},
      {'c': 0.9, '_': 0.05},
      {'_': 0.9},
      {'a': 0.45, 'o': 0.5, '_': 0.02},
      {'a': 0.45, 'o': 0.5, '_': 0.02},
      {'_': 0.9},
      {'t': 0.9, '_': 0.05},
      {'t': 0.9, '_': 0.05},
      for (var i = 0; i < 24; i++) {'_': 0.95},
    ];
    _mock(_FakePlugin([framesOf(cs, frames)]));
    final results = await _recognizer(lexicon: Lexicon.parse('cat 5000\ncot 100\n'))
        .recognizeWords(_words(1));
    expect(results.single.raw, 'cot');
    expect(results.single.text, 'cat');
    expect(results.single.alternatives, contains('cot'));
  });

  test('works without a word list', () async {
    _mock(_FakePlugin([reading('hello')]));
    final results = await _recognizer().recognizeWords(_words(1));
    expect(results.single.text, 'hello');
  });

  test('sends words in batches', () async {
    final plugin = _FakePlugin([reading('hello')]);
    _mock(plugin);
    final results = await _recognizer(lexicon: lex, batchSize: 2).recognizeWords(_words(5));
    expect(results, hasLength(5));
    expect(plugin.batchSizes, [2, 2, 1]);
  });

  test('no words means no channel call', () async {
    final plugin = _FakePlugin([reading('hello')]);
    _mock(plugin);
    expect(await _recognizer().recognizeWords(const []), isEmpty);
    expect(plugin.batchSizes, isEmpty);
  });

  test('platform errors become HtrException with a user message', () async {
    final plugin = _FakePlugin([reading('hello')])
      ..failure = PlatformException(code: 'model_missing', message: 'no model');
    _mock(plugin);
    await expectLater(
      _recognizer().recognizeWords(_words(1)),
      throwsA(isA<HtrException>()
          .having((e) => e.code, 'code', 'model_missing')
          .having((e) => e.userMessage, 'userMessage', contains('model'))),
    );
    plugin.failure = PlatformException(code: 'out_of_memory');
    await expectLater(
      _recognizer().recognizeWords(_words(1)),
      throwsA(isA<HtrException>().having((e) => e.userMessage, 'userMessage', contains('memory'))),
    );
  });

  test('a missing plugin is reported as unavailable', () async {
    _mock(null);
    await expectLater(
      _recognizer().recognizeWords(_words(1)),
      throwsA(isA<HtrException>().having((e) => e.code, 'code', 'unavailable')),
    );
  });

  test('a short reply is a protocol error', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async => <Object?>[]);
    await expectLater(
      _recognizer().recognizeWords(_words(1)),
      throwsA(isA<HtrException>().having((e) => e.code, 'code', 'protocol')),
    );
  });

  test('a broken charset asset is reported, and loading is retried later', () async {
    _mock(_FakePlugin([reading('hello')]));
    var fail = true;
    final r = HtrRecognizer(
      channel: _channel,
      renderer: const PolylineWordImageRenderer(),
      lexiconLoader: () async => null,
      charsetLoader: () async {
        if (fail) throw StateError('asset missing');
        return testCharset();
      },
    );
    await expectLater(
      r.recognizeWords(_words(1)),
      throwsA(isA<HtrException>().having((e) => e.code, 'code', 'model_unreadable')),
    );
    fail = false;
    expect((await r.recognizeWords(_words(1))).single.text, 'hello');
  });

  test('info reports the model facts', () async {
    _mock(_FakePlugin([reading('hello')]));
    final info = await _recognizer().info();
    expect(info.classes, 79);
    expect(info.timesteps, 32);
    expect(info.blank, 78);
    expect(info.charset, hasLength(78));
  });

  test('recognizeImages returns log-probabilities as CtcLogProbs', () async {
    _mock(_FakePlugin([reading('hello')]));
    final out = await _recognizer().recognizeImages([Uint8List(4096), Uint8List(4096)]);
    expect(out, hasLength(2));
    expect(out.first.timesteps, 32);
    expect(out.first.classes, 79);
    expect(greedyDecode(out.first, cs).text, 'hello');
  });
}
