import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/ink/vec2.dart';
import 'package:neatink/recognition/ctc.dart';
import 'package:neatink/recognition/htr_channel.dart';
import 'package:neatink/recognition/lexicon.dart';
import 'package:neatink/recognition/stroke_grouping.dart';
import 'package:neatink/recognition/user_lexicon.dart';
import 'package:neatink/recognition/word_image.dart';

import '../beautify/synthetic_font.dart';
import 'ctc_fixtures.dart';

const MethodChannel _channel = MethodChannel('neatink/htr');

/// One image as the platform side received it.
class _Received {
  _Received(this.width, this.height, this.pixels);
  final int width;
  final int height;
  final Uint8List pixels;
}

/// The platform side of the channel: replies with canned probabilities.
class _FakePlugin {
  _FakePlugin(this.replies, this.charset);

  /// One reading per image (frames), consumed in order.
  final List<List<Map<String, double>>> replies;
  final CtcCharset charset;
  final List<int> batchSizes = [];
  final List<_Received> images = [];
  PlatformException? failure;

  /// Overrides the reply maps when set.
  Map<String, Object?> Function(Map<String, Object?> good)? tamper;
  int next = 0;

  Future<Object?> handle(MethodCall call) async {
    if (failure != null) throw failure!;
    switch (call.method) {
      case 'recognize':
        final sent = ((call.arguments as Map)['images'] as List).cast<Map<Object?, Object?>>();
        batchSizes.add(sent.length);
        for (final m in sent) {
          images.add(_Received(m['width']! as int, m['height']! as int, m['pixels']! as Uint8List));
        }
        return [
          for (var i = 0; i < sent.length; i++) _reply(replies[next++ % replies.length]),
        ];
      case 'info':
        return {
          'classes': charset.classes,
          'blank': 0,
          'charsetSize': charset.classes,
          'inputHeight': 48,
          'minWidth': 16,
          'maxWidth': 800,
          'inputName': 'x',
        };
    }
    throw MissingPluginException();
  }

  Map<String, Object?> _reply(List<Map<String, double>> frames) {
    final good = <String, Object?>{
      'timesteps': frames.length,
      'classes': charset.classes,
      'probs': Float32List.fromList(probabilitiesOf(charset, frames)),
    };
    return tamper == null ? good : tamper!(good);
  }
}

void _mock(_FakePlugin? plugin) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, plugin?.handle);
}

List<WordGroup> _words(int n, {String text = 'hello'}) {
  final strokes = [
    for (var i = 0; i < n; i++)
      ...makeWord(text, prefix: 'w$i', x: 100 + i * 60.0, y: 300),
  ];
  final words = groupStrokes(strokes).expand((l) => l.words).toList();
  expect(words, hasLength(n));
  return words;
}

HtrRecognizer _recognizer({
  Lexicon? lexicon,
  int batchSize = 8,
  UserLexicon? user,
  CtcCharset? charset,
}) =>
    HtrRecognizer(
      channel: _channel,
      renderer: const PolylineWordImageRenderer(),
      lexiconLoader: () async => lexicon,
      charsetLoader: () async => charset ?? testCharset(),
      userLexicon: user,
      batchSize: batchSize,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cs = testCharset();
  final lex = Lexicon.parse('hello 1000\nhelp 900\ncat 5000\ncot 100\n');

  // 25 timesteps like the real model for a ~200 px image.
  List<Map<String, double>> reading(String text) {
    final frames = spell(text, p: 0.9);
    while (frames.length < 25) {
      frames.add({'_': 0.95});
    }
    return frames.take(25).toList();
  }

  _FakePlugin plugin(List<List<Map<String, double>>> replies) => _FakePlugin(replies, cs);

  tearDown(() => _mock(null));

  test('recognizes words: renders images, sends them, decodes the reply', () async {
    final p = plugin([reading('hello'), reading('help')]);
    _mock(p);
    final progress = <int>[];
    final results = await _recognizer(lexicon: lex).recognizeWords(
      _words(2),
      onProgress: (done, total) => progress.add(done),
    );
    expect(results.map((r) => r.text), ['hello', 'help']);
    expect(results.map((r) => r.raw), ['hello', 'help']);
    expect(results.every((r) => r.confidence > 0.3 && r.confidence <= 1), isTrue);
    expect(results[0].group, isA<WordGroup>());
    expect(p.images, hasLength(2));
    expect(progress, [0, 2]);
  });

  test('an arrow between words is left out of the picture and comes back as →', () async {
    final strokes = [
      ...makeWord('hello', prefix: 'a', x: 100, y: 300),
      ...toStrokes([
        densify(const [Vec2(165, 295), Vec2(205, 295)]),
        densify(const [Vec2(199, 290), Vec2(205, 295), Vec2(199, 300)]),
      ], prefix: 'arrow'),
      ...makeWord('hen', prefix: 'b', x: 215, y: 300),
    ];
    final line = groupStrokes(strokes).single;
    final frames = [...spell('hello'), {' ': 0.9, '_': 0.05}, ...spell('hen')];
    final p = plugin([frames]);
    _mock(p);
    final result = (await _recognizer(lexicon: lex).recognizeLines([line])).single;
    expect(result.text, 'hello \u2192 hen');
    final arrow = result.words[1];
    expect(arrow.group.strokes.map((s) => s.id), ['arrow-0', 'arrow-1']);
    expect(result.line.inkStrokes, hasLength(strokes.length), reason: 'the arrow goes with the line');
    // The picture the model got had no arrow in it: narrower than the line.
    expect(p.images.single.width, lessThan((205 - 100) * 48 / 14));
  });

  test('sends variable-size 48 pixel high images, one map per image', () async {
    final strokes = [
      ...makeWord('hen', prefix: 'a', x: 100),
      ...makeWord('hellohellohello', prefix: 'b', x: 100, y: 400),
    ];
    final words = groupStrokes(strokes).expand((l) => l.words).toList();
    expect(words, hasLength(2));
    final p = plugin([reading('hen')]);
    _mock(p);
    await _recognizer().recognizeWords(words);
    expect(p.images, hasLength(2));
    for (final img in p.images) {
      expect(img.height, 48);
      expect(img.width, inInclusiveRange(wordImageMinWidth, wordImageMaxWidth));
      expect(img.pixels.length, img.width * 48);
    }
    expect(p.images[1].width, greaterThan(p.images[0].width * 2));
  });

  test('applies the lexicon to the model output', () async {
    final frames = spellWith('cot', {
      1: {'a': 0.45, 'o': 0.5},
    });
    while (frames.length < 25) {
      frames.add({'_': 0.95});
    }
    _mock(plugin([frames]));
    final results = await _recognizer(lexicon: Lexicon.parse('cat 5000\ncot 100\n'))
        .recognizeWords(_words(1));
    expect(results.single.raw, 'cot');
    expect(results.single.text, 'cat');
    expect(results.single.alternatives, contains('cot'));
  });

  test('works without a word list', () async {
    _mock(plugin([reading('hello')]));
    final results = await _recognizer().recognizeWords(_words(1));
    expect(results.single.text, 'hello');
  });

  test('sends words in batches', () async {
    final p = plugin([reading('hello')]);
    _mock(p);
    final results = await _recognizer(lexicon: lex, batchSize: 2).recognizeWords(_words(5));
    expect(results, hasLength(5));
    expect(p.batchSizes, [2, 2, 1]);
  });

  test('no words means no channel call', () async {
    final p = plugin([reading('hello')]);
    _mock(p);
    expect(await _recognizer().recognizeWords(const []), isEmpty);
    expect(p.batchSizes, isEmpty);
  });

  test('platform errors become HtrException with a user message', () async {
    final p = plugin([reading('hello')])
      ..failure = PlatformException(code: 'model_missing', message: 'no model');
    _mock(p);
    await expectLater(
      _recognizer().recognizeWords(_words(1)),
      throwsA(isA<HtrException>()
          .having((e) => e.code, 'code', 'model_missing')
          .having((e) => e.userMessage, 'userMessage', contains('model'))),
    );
    p.failure = PlatformException(code: 'out_of_memory');
    await expectLater(
      _recognizer().recognizeWords(_words(1)),
      throwsA(isA<HtrException>().having((e) => e.userMessage, 'userMessage', contains('memory'))),
    );
    p.failure = PlatformException(code: 'bad_image', message: 'Image 0 must be 48 pixels high');
    await expectLater(
      _recognizer().recognizeWords(_words(1)),
      throwsA(isA<HtrException>().having((e) => e.code, 'code', 'bad_image')),
    );
  });

  test('a missing plugin is reported as unavailable', () async {
    _mock(null);
    await expectLater(
      _recognizer().recognizeWords(_words(1)),
      throwsA(isA<HtrException>().having((e) => e.code, 'code', 'unavailable')),
    );
  });

  group('malformed replies are protocol errors', () {
    Future<void> expectProtocol(Map<String, Object?> Function(Map<String, Object?> good)? tamper) async {
      final p = plugin([reading('hello')])..tamper = tamper;
      _mock(p);
      await expectLater(
        _recognizer().recognizeWords(_words(1)),
        throwsA(isA<HtrException>().having((e) => e.code, 'code', 'protocol')),
      );
    }

    test('a short reply', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async => <Object?>[]);
      await expectLater(
        _recognizer().recognizeWords(_words(1)),
        throwsA(isA<HtrException>().having((e) => e.code, 'code', 'protocol')),
      );
    });

    test('the wrong number of classes', () => expectProtocol((good) => {...good, 'classes': 79}));

    test('probabilities that do not fit timesteps x classes',
        () => expectProtocol((good) => {...good, 'timesteps': 24}));

    test('no probabilities', () => expectProtocol((good) => {...good}..remove('probs')));
  });

  test('a broken charset asset is reported, and loading is retried later', () async {
    _mock(plugin([reading('hello')]));
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
    _mock(plugin([reading('hello')]));
    final info = await _recognizer().info();
    expect(info.classes, cs.classes);
    expect(info.blank, 0);
    expect(info.charsetSize, cs.classes);
    expect(info.inputHeight, 48);
    expect(info.minWidth, 16);
    expect(info.maxWidth, 800);
  });

  test('recognizeImages returns log-probabilities with the space folded into the blank', () async {
    final frames = <Map<String, double>>[
      {'h': 0.6, '_': 0.05, ' ': 0.3},
      {' ': 0.9},
      {'i': 0.9, '_': 0.05},
    ];
    _mock(plugin([frames]));
    final images = [
      WordImage(pixels: Uint8List(48 * 20), scale: 1, strokeWidthPx: 1.8),
      WordImage(pixels: Uint8List(48 * 30), scale: 1, strokeWidthPx: 1.8),
    ];
    final out = await _recognizer().recognizeImages(images);
    expect(out, hasLength(2));
    expect(out.first.timesteps, 3);
    expect(out.first.classes, cs.classes);
    // frame 1 was 0.9 space: now blank
    expect(out.first.at(1, cs.blank), closeTo(math.log(0.9), 0.01));
    expect(greedyDecode(out.first, cs).text, 'hi');
  });

  group('personal dictionary', () {
    test('words of the personal dictionary correct the reading', () async {
      _mock(plugin([
        spellWith('Malck', {
          3: {'c': 0.55, 'e': 0.35},
        })
      ]));
      final user = UserLexicon()..add('Malek');
      final results = await _recognizer(lexicon: lex, user: user).recognizeWords(_words(1));
      expect(results.single.raw, 'Malck');
      expect(results.single.text, 'Malek');
      // without it, the reading stays
      final plain = await _recognizer(lexicon: lex).recognizeWords(_words(1));
      expect(plain.single.text, 'Malck');
    });

    test('learn teaches unknown words, skips listed ones and saves', () async {
      _mock(plugin([reading('hello')]));
      final store = InMemoryUserLexiconStore();
      final r = _recognizer(lexicon: lex, user: UserLexicon(store: store));
      expect(await r.learn('Malek hello Baghdadi'), 2); // hello is listed
      expect(store.saved, ['Malek', 'Baghdadi']);
      expect(r.userLexicon.contains('baghdadi'), isTrue);
      expect(await r.learn('Malek'), 0);
    });

    test('what the user typed is used by the next recognition', () async {
      _mock(plugin([
        spellWith('Malck', {
          3: {'c': 0.55, 'e': 0.35},
        })
      ]));
      final r = _recognizer(lexicon: lex);
      expect((await r.recognizeWords(_words(1))).single.text, 'Malck');
      await r.learn('Malek');
      expect((await r.recognizeWords(_words(1))).single.text, 'Malek');
    });
  });
}
