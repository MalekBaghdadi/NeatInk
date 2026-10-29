import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/debug/pointer_debug_log.dart';
import 'package:neatink/features/debug/pointer_debug_screen.dart';

/// A pen stroke of [count] samples, 4 ms apart (250 Hz), with pressure
/// rising from [fromPressure] to [toPressure].
List<PointerEvent> penStroke({
  int pointer = 1,
  PointerDeviceKind kind = PointerDeviceKind.stylus,
  int count = 10,
  double fromPressure = 0.2,
  double toPressure = 0.9,
  double tilt = 0.5,
  Offset start = const Offset(100, 100),
  Duration startTime = Duration.zero,
}) {
  double pressureAt(int i) =>
      fromPressure + (toPressure - fromPressure) * i / (count - 1);
  Offset at(int i) => start + Offset(i * 5.0, i * 2.0);
  Duration timeAt(int i) => startTime + Duration(milliseconds: 4 * i);
  return [
    PointerDownEvent(
      pointer: pointer,
      kind: kind,
      device: 7,
      position: at(0),
      pressure: pressureAt(0),
      pressureMax: 1,
      tilt: tilt,
      timeStamp: timeAt(0),
    ),
    for (var i = 1; i < count; i++)
      PointerMoveEvent(
        pointer: pointer,
        kind: kind,
        device: 7,
        position: at(i),
        pressure: pressureAt(i),
        pressureMax: 1,
        tilt: tilt,
        timeStamp: timeAt(i),
      ),
    PointerUpEvent(
      pointer: pointer,
      kind: kind,
      device: 7,
      position: at(count - 1),
      timeStamp: timeAt(count),
    ),
  ];
}

void main() {
  group('PointerDebugLog', () {
    late PointerDebugLog log;

    setUp(() => log = PointerDebugLog());
    tearDown(() => log.dispose());

    void recordAll(Iterable<PointerEvent> events) => events.forEach(log.record);

    test('starts empty with an instruction', () {
      final s = log.summary;
      expect(s.eventCount, 0);
      expect(s.stylusSeen, isFalse);
      expect(s.pressureVaries, isNull);
      expect(s.rateHz, isNull);
      expect(s.verdict, contains('Draw in the test area'));
      expect(log.last, isNull);
    });

    test('a pen with pressure is reported as such', () {
      recordAll(penStroke());
      final s = log.summary;
      expect(s.eventCount, 11);
      expect(s.stylusSeen, isTrue);
      expect(s.touchSeen, isFalse);
      expect(s.invertedStylusSeen, isFalse);
      expect(s.pressureVaries, isTrue);
      expect(s.stylusPressure!.min, closeTo(0.2, 1e-9));
      expect(s.stylusPressure!.max, closeTo(0.9, 1e-9));
      expect(s.tiltReported, isTrue);
      expect(s.maxStylusTilt, closeTo(0.5, 1e-9));
      expect(s.verdict, contains('recognised as a stylus with pressure'));
    });

    test('measures the event rate from move timestamps', () {
      recordAll(penStroke(count: 20));
      expect(log.summary.rateHz, closeTo(250, 0.5));
    });

    test('constant pressure is flagged', () {
      recordAll(penStroke(fromPressure: 1, toPressure: 1));
      expect(log.summary.pressureVaries, isFalse);
      expect(log.summary.verdict, contains('pressure stays constant'));
    });

    test('touch only suggests "Draw with finger"', () {
      recordAll(penStroke(kind: PointerDeviceKind.touch));
      final s = log.summary;
      expect(s.touchSeen, isTrue);
      expect(s.stylusSeen, isFalse);
      expect(s.stylusPressure, isNull, reason: 'touch pressure is ignored');
      expect(s.verdict, contains('Draw with finger'));
    });

    test('the eraser end counts as the pen and is noticed', () {
      recordAll(penStroke(kind: PointerDeviceKind.invertedStylus));
      expect(log.summary.invertedStylusSeen, isTrue);
      expect(log.summary.stylusSeen, isTrue);
    });

    test('hover is noticed but does not make a trace', () {
      log.record(const PointerHoverEvent(
        kind: PointerDeviceKind.stylus,
        position: Offset(10, 10),
        distance: 3,
        distanceMax: 10,
      ));
      expect(log.summary.hoverSeen, isTrue);
      expect(log.traces, isEmpty);
      expect(log.last!.type, 'hover');
      expect(log.last!.distance, 3);
    });

    test('keeps one trace per contact, with every sample', () {
      recordAll(penStroke(pointer: 1));
      recordAll(penStroke(pointer: 2, startTime: const Duration(seconds: 1)));
      expect(log.traces, hasLength(2));
      expect(log.traces.first.samples, hasLength(11));
      expect(log.traces.first.kind, PointerDeviceKind.stylus);
    });

    test('keeps only the most recent events, newest first', () {
      recordAll(penStroke(count: 60));
      final recent = log.recent.toList();
      expect(recent, hasLength(PointerDebugLog.maxRecent));
      expect(recent.first.type, 'up');
    });

    test('bounds the stored trace points by dropping old traces', () {
      const perStroke = 501; // 500 moves + down (+ up = 502 samples)
      final strokes = PointerDebugLog.maxTracePoints ~/ perStroke + 3;
      for (var i = 0; i < strokes; i++) {
        recordAll(penStroke(
          pointer: i + 1,
          count: perStroke,
          startTime: Duration(seconds: i * 10),
        ));
      }
      final stored =
          log.traces.fold<int>(0, (n, t) => n + t.samples.length);
      expect(stored, lessThanOrEqualTo(PointerDebugLog.maxTracePoints));
      expect(log.traces.last.pointer, strokes, reason: 'newest is kept');
    });

    test('maps pressure into 0–1 using the reported range', () {
      log.record(const PointerDownEvent(
        kind: PointerDeviceKind.stylus,
        pressure: 512,
        pressureMin: 0,
        pressureMax: 1024,
      ));
      expect(log.last!.normalizedPressure, closeTo(0.5, 1e-9));
    });

    test('clear forgets everything and notifies', () {
      var notified = 0;
      log.addListener(() => notified++);
      recordAll(penStroke());
      final before = notified;
      log.clear();
      expect(notified, before + 1);
      expect(log.summary.eventCount, 0);
      expect(log.traces, isEmpty);
      expect(log.recent, isEmpty);
      expect(log.summary.kindsSeen, isEmpty);
    });
  });

  test('report: a few lines to paste into a message', () {
    final log = PointerDebugLog();
    for (final e in penStroke()) {
      log.record(e);
    }
    final report = log.report();
    expect(report, contains('Kinds: stylus'));
    expect(report, contains('Pen pressure seen: 0.200 to 0.900'));
    expect(report, contains('Device pressure range: 0.000 to 1.000'));
    expect(report, contains('with pressure'));
    expect(PointerDebugLog().report(), contains('Pen pressure seen: none'));
  });

  group('describeButtons', () {
    test('names pen and mouse buttons', () {
      expect(describeButtons(0, PointerDeviceKind.stylus), '0 (none)');
      expect(describeButtons(kPrimaryButton, PointerDeviceKind.stylus),
          '0x01 (contact)');
      expect(
        describeButtons(
            kPrimaryButton | kSecondaryButton, PointerDeviceKind.stylus),
        '0x03 (contact, pen button)',
      );
      expect(describeButtons(kSecondaryButton, PointerDeviceKind.mouse),
          '0x02 (right)');
      expect(describeButtons(kTertiaryButton, PointerDeviceKind.touch),
          '0x04 (tertiary)');
      expect(describeButtons(0x10, PointerDeviceKind.mouse), '0x10 (other)');
    });
  });

  group('PointerDebugScreen', () {
    Future<void> pumpScreen(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: PointerDebugScreen()));
    }

    /// Sends raw events at the test surface (positions are global).
    Future<void> send(WidgetTester tester, List<PointerEvent> events) async {
      final origin =
          tester.getTopLeft(find.byKey(const ValueKey('pointer-test-surface')));
      for (final e in events) {
        tester.binding.handlePointerEvent(e.copyWith(position: e.position + origin));
      }
      await tester.pump();
    }

    testWidgets('shows what the pen reports', (tester) async {
      await pumpScreen(tester);
      expect(find.text('No events yet.'), findsNWidgets(2));

      await send(tester, penStroke(count: 20));

      expect(find.textContaining('recognised as a stylus with pressure'),
          findsOneWidget);
      expect(find.text('Pen reported as stylus'), findsOneWidget);
      expect(find.text('Seen: stylus'), findsOneWidget);
      expect(find.text('0.20 – 0.90'), findsOneWidget);
      expect(find.text('Not seen (many pens have no eraser end)'),
          findsOneWidget);
      // Last event: the pen lifted.
      expect(find.text('up'), findsOneWidget);
      expect(find.text('250 Hz'), findsOneWidget);
      expect(find.text('Device'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('notices the eraser end', (tester) async {
      await pumpScreen(tester);
      await send(tester, penStroke(kind: PointerDeviceKind.invertedStylus));
      expect(find.text('Eraser end (inverted stylus)'), findsOneWidget);
      expect(find.text('Seen: invertedStylus'), findsOneWidget);
    });

    testWidgets('Clear resets the screen', (tester) async {
      await pumpScreen(tester);
      await send(tester, penStroke());
      expect(find.text('No events yet.'), findsNothing);

      await tester.tap(find.text('Clear'));
      await tester.pump();

      expect(find.text('No events yet.'), findsNWidgets(2));
      expect(find.textContaining('Draw here with the pen'), findsOneWidget);
    });

    testWidgets('lays out in portrait too', (tester) async {
      tester.view.physicalSize = const Size(800, 1280);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: PointerDebugScreen()));
      await send(tester, penStroke());
      expect(tester.takeException(), isNull);
      expect(find.text('Summary'), findsOneWidget);
    });
  });
}
