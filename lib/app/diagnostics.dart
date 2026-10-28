import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../storage/atomic_file.dart';
import 'app_info.dart';

// Diagnostics (v1.7.0): the problems the app ran into, kept on the tablet so
// the user can send them when something goes wrong ("Share diagnostics" in
// Settings). Nothing is sent by itself: NeatInk has no crash reporting and no
// internet permission.
//
// Every problem the app handles is already reported with
// `debugPrint('NeatInk: ...')`; [installDiagnostics] routes those lines (and
// uncaught errors) here, so no call site needs to know about the log.

/// One recorded problem.
typedef DiagnosticEntry = ({DateTime time, String message});

/// The recorded problems, behind an interface so tests can use memory.
abstract interface class DiagnosticsLog {
  /// Records [message] now. Never throws and never waits.
  void record(String message);

  /// What was recorded, oldest first.
  Future<List<DiagnosticEntry>> entries();

  /// Forgets everything.
  Future<void> clear();
}

/// The report the user shares: the app and system versions, then every
/// entry with its time.
String diagnosticsReport(List<DiagnosticEntry> entries, {required DateTime now, String? system}) {
  final out = StringBuffer()
    ..writeln('${AppInfo.name} diagnostics')
    ..writeln('App: ${AppInfo.displayVersion}')
    ..writeln('System: ${system ?? _system()}')
    ..writeln('Made: ${now.toIso8601String()}')
    ..writeln('Problems recorded: ${entries.length}')
    ..writeln();
  for (final e in entries) {
    out
      ..writeln('[${e.time.toIso8601String()}]')
      ..writeln(e.message.trimRight())
      ..writeln();
  }
  return out.toString();
}

String _system() {
  try {
    return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
  } catch (_) {
    return 'unknown';
  }
}

/// `mariams-notes-diagnostics-yyyymmdd-hhmm.txt` for a report made at [t].
String diagnosticsFileName(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'mariams-notes-diagnostics-${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}.txt';
}

/// The longest message kept (a stack trace beyond this is cut).
const int maxDiagnosticMessage = 6000;

/// Kept in memory.
class InMemoryDiagnosticsLog implements DiagnosticsLog {
  InMemoryDiagnosticsLog({this.maxEntries = 300, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final int maxEntries;
  final DateTime Function() _clock;
  final List<DiagnosticEntry> _entries = [];

  @override
  void record(String message) {
    final m = _clip(message);
    if (_entries.isNotEmpty && _isRepeat(_entries.last, m, _clock())) return;
    _entries.add((time: _clock(), message: m));
    if (_entries.length > maxEntries) _entries.removeRange(0, _entries.length - maxEntries);
  }

  @override
  Future<List<DiagnosticEntry>> entries() async => List.of(_entries);

  @override
  Future<void> clear() async => _entries.clear();
}

String _clip(String message) =>
    message.length <= maxDiagnosticMessage ? message : '${message.substring(0, maxDiagnosticMessage)}…';

/// The same message again within a minute is not recorded twice (an error
/// repeated on every save would push the first, useful one out).
bool _isRepeat(DiagnosticEntry last, String message, DateTime now) =>
    last.message == message && now.difference(last.time).inSeconds.abs() < 60;

/// One JSON line per entry in `<application documents>/diagnostics/log.jsonl`;
/// past [maxEntries] the oldest are dropped by an atomic rewrite. Writes run
/// one after the other, in the background. Problems of the log itself go to
/// the console only (never back into the log).
class FileDiagnosticsLog implements DiagnosticsLog {
  FileDiagnosticsLog({
    Future<Directory> Function()? directory,
    this.maxEntries = 300,
    DateTime Function()? clock,
    this.console,
  })  : _directory = directory ?? getApplicationDocumentsDirectory,
        _clock = clock ?? DateTime.now;

  final Future<Directory> Function() _directory;
  final DateTime Function() _clock;
  final int maxEntries;

  /// Where the log's own problems are printed (the original `debugPrint`).
  final void Function(String message)? console;

  Future<void> _queue = Future<void>.value();
  DiagnosticEntry? _last;
  int? _count;

  static const String fileName = 'log.jsonl';

  Future<File> _file() async => File(p.join((await _directory()).path, 'diagnostics', fileName));

  Future<T> _serial<T>(Future<T> Function() task) {
    final run = _queue.then((_) => task());
    _queue = run.then((_) {}, onError: (Object e) => console?.call('NeatInk diagnostics: $e'));
    return run;
  }

  @override
  void record(String message) {
    final now = _clock();
    final m = _clip(message);
    final last = _last;
    if (last != null && _isRepeat(last, m, now)) return;
    _last = (time: now, message: m);
    unawaited(_serial(() async {
      final file = await _file();
      await file.parent.create(recursive: true);
      final line = jsonEncode({'t': now.toIso8601String(), 'm': m});
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
      final count = _count = (_count ?? await _lineCount(file)) + 1;
      if (count > maxEntries + maxEntries ~/ 4) {
        final all = await _read(file);
        final keep = all.length > maxEntries ? all.sublist(all.length - maxEntries) : all;
        await AtomicFile.writeBytes(file.path,
            utf8.encode(keep.map((e) => '${jsonEncode({'t': e.time.toIso8601String(), 'm': e.message})}\n').join()));
        _count = keep.length;
      }
    }).catchError((Object _) {}));
  }

  static Future<int> _lineCount(File file) async {
    var n = 0;
    await for (final chunk in file.openRead()) {
      for (final b in chunk) {
        if (b == 0x0A) n++;
      }
    }
    return n;
  }

  static Future<List<DiagnosticEntry>> _read(File file) async {
    if (!file.existsSync()) return const [];
    final out = <DiagnosticEntry>[];
    for (final line in const LineSplitter().convert(await file.readAsString())) {
      try {
        final j = jsonDecode(line);
        if (j is! Map<String, dynamic>) continue;
        final t = DateTime.tryParse('${j['t']}');
        final m = j['m'];
        if (t != null && m is String) out.add((time: t, message: m));
      } catch (_) {
        // A line cut short (the app was killed while writing): skipped.
      }
    }
    return out;
  }

  @override
  Future<List<DiagnosticEntry>> entries() => _serial(() async {
        try {
          return await _read(await _file());
        } catch (e) {
          console?.call('NeatInk diagnostics unreadable: $e');
          return const <DiagnosticEntry>[];
        }
      });

  @override
  Future<void> clear() => _serial(() async {
        final file = await _file();
        if (file.existsSync()) await file.delete();
        _count = 0;
        _last = null;
      });
}

/// The app's diagnostics log ([installDiagnostics] sets it up; until then,
/// and in tests, entries stay in memory).
DiagnosticsLog appDiagnostics = InMemoryDiagnosticsLog();

/// The log Settings shows and shares. Tests override it.
final diagnosticsLogProvider = Provider<DiagnosticsLog>((ref) => appDiagnostics);

/// Keeps every `debugPrint('NeatInk: ...')` line and every uncaught error in
/// [log] (default: a [FileDiagnosticsLog]), still printed to the console as
/// before. Call once, before anything else runs.
void installDiagnostics({DiagnosticsLog? log}) {
  final console = debugPrint;
  final sink = log ?? FileDiagnosticsLog(console: (m) => console(m));
  appDiagnostics = sink;
  debugPrint = (String? message, {int? wrapWidth}) {
    console(message, wrapWidth: wrapWidth);
    if (message != null && message.startsWith('NeatInk:')) sink.record(message);
  };
}
