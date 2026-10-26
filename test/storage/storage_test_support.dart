import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:path/path.dart' as p;

/// Creates an empty temp folder that is deleted after the current test.
Future<Directory> createTempRoot() async {
  final dir = await Directory.systemTemp.createTemp('neatink_storage_');
  addTearDown(() async {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // Best effort (e.g. a virus scanner holding a file on Windows).
    }
  });
  return dir;
}

/// Every file below [dir], as paths relative to it with `/` separators.
Future<List<String>> listFilesRecursively(Directory dir) async {
  final out = <String>[];
  await for (final e in dir.list(recursive: true, followLinks: false)) {
    if (e is File) {
      out.add(p.relative(e.path, from: dir.path).replaceAll(r'\', '/'));
    }
  }
  out.sort();
  return out;
}

/// A clock that starts at a fixed instant and advances one minute per call,
/// so timestamps are distinct and predictable.
class StepClock {
  StepClock([DateTime? start])
      : _next = start ?? DateTime.utc(2026, 10, 25, 9);

  DateTime _next;
  final List<DateTime> issued = [];

  DateTime call() {
    final t = _next;
    _next = _next.add(const Duration(minutes: 1));
    issued.add(t);
    return t;
  }
}

/// Points along a gentle wave, already quantized like captured ink.
List<InkPoint> wavePoints(int count, {double x0 = 50, double y0 = 100}) => [
      for (var i = 0; i < count; i++)
        InkPoint.quantized(
          x0 + i * 1.37,
          y0 + (i % 7) * 0.913,
          0.3 + (i % 5) * 0.111,
          i * 8,
        ),
    ];

/// An untidied pen stroke (`points` is `raw`).
Stroke penStroke(String id, {int points = 12, double y0 = 100}) => Stroke(
      id: id,
      tool: StrokeTool.pen,
      penStyle: PenStyle.fountain,
      color: 0xFF1E88E5,
      size: 2.2,
      raw: wavePoints(points, y0: y0),
      wordId: 'w-$id',
    );

/// A tidied stroke: `points` differ from `raw` (quantized like the tidy
/// output after a save, so comparisons after a reload are exact).
Stroke tidiedStroke(String id) {
  final raw = wavePoints(10);
  return Stroke(
    id: id,
    tool: StrokeTool.pen,
    color: 0xFF1E1E1E,
    size: 1.6,
    raw: raw,
    points: [
      for (final pt in raw)
        InkPoint.quantized(pt.x + 0.5, pt.y - 1.25, pt.pressure, pt.t),
    ],
    wordId: 'word-1',
    tidy: const TidyInfo(applied: true, version: 1),
  );
}

/// Deterministic timers for code that uses `dart:async` [Timer]s.
///
/// Run the code under test inside [run]; its timers then fire only when the
/// test calls [elapse]. Microtasks (futures) still run normally, so the
/// test awaits [settle] to let async work finish.
class FakeTimers {
  Duration _now = Duration.zero;
  final List<_FakeTimer> _timers = [];

  late final Zone _zone = Zone.current.fork(
    specification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        final timer = _FakeTimer(_now + duration, callback);
        _timers.add(timer);
        return timer;
      },
    ),
  );

  /// Current fake time since creation.
  Duration get now => _now;

  /// Number of timers that are still waiting to fire.
  int get pendingTimers => _timers.where((t) => t.isActive).length;

  /// Runs [body] so that its timers are fake.
  T run<T>(T Function() body) => _zone.run(body);

  /// Advances fake time by [duration], firing due timers in order, and
  /// lets the futures they start run.
  Future<void> elapse(Duration duration) async {
    final target = _now + duration;
    while (true) {
      final due = _timers.where((t) => t.isActive && t.due <= target).toList()
        ..sort((a, b) => a.due.compareTo(b.due));
      if (due.isEmpty) break;
      final timer = due.first;
      _now = timer.due;
      timer.fire();
      await settle();
    }
    _now = target;
    await settle();
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this.due, this._callback);

  final Duration due;
  final void Function() _callback;
  bool _active = true;

  void fire() {
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _active ? 0 : 1;
}

/// Lets pending microtasks and already-completed futures run.
Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.value();
  }
}
