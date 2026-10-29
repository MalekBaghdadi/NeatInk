import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../recognition/word_image.dart';
import '../../../../storage/atomic_file.dart';
import 'sample_export.dart';

// "Keep my corrections" (v1.7.0): every line converted from the review sheet,
// with the text the user checked or fixed there, is kept on the tablet, so a
// few weeks of normal use give enough of her real handwriting to measure and
// tune recognition. Each line is a format-2 sample entry (see
// [buildSamplesJson]) without the model pictures, which can be drawn again
// from the strokes. Nothing leaves the tablet unless the user taps "Share my
// corrections" in Settings.

/// The lines kept so far, behind an interface so tests can use memory.
abstract interface class KeptCorrections {
  /// Adds sample line entries (the `lines` of [buildSamplesJson]).
  Future<void> addAll(List<Map<String, dynamic>> lines);

  /// How many lines are kept.
  Future<int> count();

  /// Every kept line entry, oldest first.
  Future<List<Map<String, dynamic>>> entries();

  /// Every kept line as one samples file (format 2, oldest first), or null
  /// when nothing is kept.
  Future<String?> exportJson({required String appVersion, required DateTime createdAt});

  /// Deletes every kept line.
  Future<void> clear();
}

/// The `lines` entries of a samples file made from the lines [kept] there:
/// what the review sheet had for them, without pictures, each marked with
/// the time it was kept.
List<Map<String, dynamic>> keptLineEntries(
    List<SampleLineInput> lines, DateTime keptAt) {
  final json = buildSamplesJson(appVersion: '', createdAt: keptAt, lines: [
    for (final l in lines) SampleLineInput(line: l.line, pageIndex: l.pageIndex, images: const []),
  ]);
  return [
    for (final e in json['lines'] as List<dynamic>)
      {...e as Map<String, dynamic>, 'keptAt': keptAt.toIso8601String()},
  ];
}

/// The samples file around [lines].
String keptSamplesFile(List<Map<String, dynamic>> lines,
        {required String appVersion, required DateTime createdAt}) =>
    encodeSamplesJson({
      'format': samplesFormat,
      'app': "Mariam's Notes",
      'appVersion': appVersion,
      'createdAt': createdAt.toIso8601String(),
      'kind': 'kept-corrections',
      'image': {'encoding': 'png-gray8-base64', 'height': wordImageHeight},
      'lineCount': lines.length,
      'lines': lines,
    });

/// `mariams-notes-corrections-yyyymmdd-hhmm.json` for a file made at [t].
String keptCorrectionsFileName(DateTime t) =>
    samplesFileName(t).replaceFirst('-samples-', '-corrections-');

/// Kept in memory (tests, and when the folder can't be used).
class InMemoryKeptCorrections implements KeptCorrections {
  InMemoryKeptCorrections({this.maxLines = 1000});

  final int maxLines;
  final List<Map<String, dynamic>> lines = [];

  @override
  Future<void> addAll(List<Map<String, dynamic>> entries) async {
    lines.addAll(entries);
    if (lines.length > maxLines) lines.removeRange(0, lines.length - maxLines);
  }

  @override
  Future<int> count() async => lines.length;

  @override
  Future<List<Map<String, dynamic>>> entries() async => List.of(lines);

  @override
  Future<String?> exportJson({required String appVersion, required DateTime createdAt}) async =>
      lines.isEmpty ? null : keptSamplesFile(lines, appVersion: appVersion, createdAt: createdAt);

  @override
  Future<void> clear() async => lines.clear();
}

/// One JSON line per kept line in
/// `<application documents>/recognition/kept_corrections.jsonl`. New lines
/// are appended (a line cut short by a crash is skipped when read); past
/// [maxLines] lines or [maxBytes] the oldest are dropped, by an atomic
/// rewrite. Calls are run one after the other.
class FileKeptCorrections implements KeptCorrections {
  FileKeptCorrections({
    Future<Directory> Function()? directory,
    this.maxLines = 1000,
    this.maxBytes = 30 * 1024 * 1024,
  }) : _directory = directory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _directory;
  final int maxLines;
  final int maxBytes;
  Future<void> _queue = Future<void>.value();

  static const String fileName = 'kept_corrections.jsonl';

  Future<File> _file() async => File(p.join((await _directory()).path, 'recognition', fileName));

  Future<T> _serial<T>(Future<T> Function() task) {
    final run = _queue.then((_) => task());
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<List<String>> _readLines(File file) async {
    if (!file.existsSync()) return const [];
    final out = <String>[];
    for (final line in const LineSplitter().convert(await file.readAsString())) {
      if (line.trim().isEmpty) continue;
      try {
        if (jsonDecode(line) is Map<String, dynamic>) out.add(line);
      } catch (_) {
        // A line cut short (the app was killed while writing): skipped.
      }
    }
    return out;
  }

  @override
  Future<void> addAll(List<Map<String, dynamic>> entries) => _serial(() async {
        if (entries.isEmpty) return;
        final file = await _file();
        await file.parent.create(recursive: true);
        // After a line cut short by a crash, start on a new line.
        final lead = file.existsSync() && file.lengthSync() > 0 && !await _endsWithNewline(file) ? '\n' : '';
        final text = '$lead${entries.map(jsonEncode).join('\n')}\n';
        await file.writeAsString(text, mode: FileMode.append, flush: true);
        if (file.lengthSync() <= maxBytes && !await _tooManyLines(file)) return;
        final lines = await _readLines(file);
        var keep = lines.length > maxLines ? lines.sublist(lines.length - maxLines) : lines;
        var bytes = keep.fold<int>(0, (n, l) => n + utf8.encode(l).length + 1);
        var start = 0;
        while (bytes > maxBytes && start < keep.length - 1) {
          bytes -= utf8.encode(keep[start]).length + 1;
          start++;
        }
        keep = keep.sublist(start);
        await AtomicFile.writeBytes(file.path, utf8.encode('${keep.join('\n')}\n'));
      });

  static Future<bool> _endsWithNewline(File file) async {
    final raf = await file.open();
    try {
      await raf.setPosition(await raf.length() - 1);
      return (await raf.readByte()) == 0x0A;
    } finally {
      await raf.close();
    }
  }

  /// Cheap check before reading everything: count newlines.
  Future<bool> _tooManyLines(File file) async {
    var n = 0;
    await for (final chunk in file.openRead()) {
      for (final b in chunk) {
        if (b == 0x0A) n++;
      }
    }
    return n > maxLines;
  }

  @override
  Future<int> count() => _serial(() async {
        try {
          return (await _readLines(await _file())).length;
        } catch (e) {
          debugPrint('NeatInk: kept corrections unreadable: $e');
          return 0;
        }
      });

  @override
  Future<List<Map<String, dynamic>>> entries() => _serial(() async {
        try {
          return [for (final l in await _readLines(await _file())) jsonDecode(l) as Map<String, dynamic>];
        } catch (e) {
          debugPrint('NeatInk: kept corrections unreadable: $e');
          return const [];
        }
      });

  @override
  Future<String?> exportJson({required String appVersion, required DateTime createdAt}) => _serial(() async {
        final lines = await _readLines(await _file());
        if (lines.isEmpty) return null;
        return keptSamplesFile(
          [for (final l in lines) jsonDecode(l) as Map<String, dynamic>],
          appVersion: appVersion,
          createdAt: createdAt,
        );
      });

  @override
  Future<void> clear() => _serial(() async {
        final file = await _file();
        if (file.existsSync()) await file.delete();
      });
}

/// The kept corrections of this app. Tests override it.
final keptCorrectionsProvider = Provider<KeptCorrections>((ref) => FileKeptCorrections());
