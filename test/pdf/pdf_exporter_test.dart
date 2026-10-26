import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/pdf/pdf_export_request.dart';
import 'package:neatink/pdf/pdf_exporter.dart';

/// Plays the Kotlin side: records the calls and answers them.
class FakeKotlin {
  FakeKotlin(this.channel) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, _handle);
  }

  final MethodChannel channel;
  final List<String> calls = [];
  final List<Map<Object?, Object?>> pages = [];
  PlatformException? failOn;
  String? failMethod;
  int failAtIndex = -1;
  Completer<void>? gate;

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call.method);
    final args = call.arguments as Map<Object?, Object?>;
    if (call.method == failMethod &&
        (failAtIndex < 0 || args['index'] == failAtIndex)) {
      throw failOn!;
    }
    switch (call.method) {
      case 'begin':
        expect(args.keys,
            containsAll(['outputPath', 'sourcePdfPath', 'title', 'pageCount']));
        return 7;
      case 'addPage':
        expect(args['session'], 7);
        pages.add(args['page']! as Map<Object?, Object?>);
        await gate?.future;
        return null;
      case 'finish':
        return '/out.pdf';
      case 'cancel':
        return null;
    }
    throw MissingPluginException();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/pdf_export');
  late FakeKotlin kotlin;
  late PdfExporter exporter;

  setUp(() {
    kotlin = FakeKotlin(channel);
    exporter = PdfExporter(channel: channel);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  ExportRequest request(int pages) => ExportRequest(
        outputPath: '/out.pdf',
        title: 'T',
        pages: [
          for (var i = 0; i < pages; i++) ExportPage(width: 10.0 + i, height: 20),
        ],
      );

  test('uses the documented channel name', () {
    expect(PdfExporter.channelName, 'neatink/pdf_export');
  });

  test('runs begin, addPage per page, finish and reports progress', () async {
    final progress = <int>[];
    final path = await exporter.export(request(3), onProgress: (done, total) {
      expect(total, 3);
      progress.add(done);
    });
    expect(path, '/out.pdf');
    expect(kotlin.calls, ['begin', 'addPage', 'addPage', 'addPage', 'finish']);
    expect(kotlin.pages.map((p) => p['width']), [10.0, 11.0, 12.0]);
    expect(progress.first, 0);
    expect(progress.last, 3);
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThan(progress[i - 1]));
    }
  });

  test('progress calls from Kotlin are forwarded', () async {
    final done = <int>[];
    kotlin.gate = Completer<void>();
    final future =
        exporter.export(request(1), onProgress: (d, t) => done.add(d));
    await pumpEventQueue();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
          const MethodCall('progress', {'session': 7, 'done': 1, 'total': 1})),
      (_) {},
    );
    expect(done, contains(1));
    kotlin.gate!.complete();
    await future;
  });

  test('rejects an export without pages', () async {
    await expectLater(
      exporter.export(request(0)),
      throwsA(isA<PdfExportException>().having((e) => e.code, 'code', 'empty')),
    );
    expect(kotlin.calls, isEmpty);
  });

  test('maps PlatformException codes and cancels the session', () async {
    kotlin
      ..failMethod = 'addPage'
      ..failAtIndex = 1
      ..failOn = PlatformException(code: 'source_missing', message: 'gone');
    await expectLater(
      exporter.export(request(3)),
      throwsA(isA<PdfExportException>()
          .having((e) => e.code, 'code', 'source_missing')
          .having((e) => e.userMessage, 'userMessage', contains('missing'))),
    );
    expect(kotlin.calls.last, 'cancel');
    expect(kotlin.calls, isNot(contains('finish')));
  });

  test('a write failure in finish becomes write_failed', () async {
    kotlin
      ..failMethod = 'finish'
      ..failOn = PlatformException(code: 'write_failed', message: 'disk');
    await expectLater(
      exporter.export(request(1)),
      throwsA(isA<PdfExportException>()
          .having((e) => e.code, 'code', 'write_failed')),
    );
    expect(kotlin.calls.last, 'cancel');
  });

  test('a missing platform side is reported as unavailable', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await expectLater(
      exporter.export(request(1)),
      throwsA(isA<PdfExportException>()
          .having((e) => e.code, 'code', 'unavailable')),
    );
  });

  test('cancelling stops before the next page and cancels the session',
      () async {
    final token = PdfExportCancelToken();
    final future = exporter.export(request(5), cancel: token,
        onProgress: (done, _) {
      if (done == 1) token.cancel();
    });
    await expectLater(future, throwsA(isA<PdfExportCancelledException>()));
    expect(kotlin.calls.last, 'cancel');
    expect(kotlin.pages.length, lessThan(5));
  });

  group('helpers', () {
    test('safeFileName cleans reserved characters', () {
      expect(safeFileName('Physics: Notes/2024?'), 'Physics Notes 2024.pdf');
      expect(safeFileName('  ..  '), 'Notebook.pdf');
      expect(safeFileName('a' * 200).length, maxExportFileNameLength + 4);
      expect(safeFileName('x', extension: ''), 'x');
    });

    test('exportPercent clamps and rounds', () {
      expect(exportPercent(1, 3), 33);
      expect(exportPercent(5, 3), 100);
      expect(exportPercent(0, 0), 0);
    });
  });
}
