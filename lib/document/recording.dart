// Lecture recordings (v1.12.0): pure Dart, no Flutter.
//
// A recording is one audio file in the notebook's `audio/` folder and the
// stretches of wall-clock time it covers ([RecordingSpan]: one per stretch
// between pauses). Notes carry the wall-clock time they were written
// (`Stroke.writtenAt`, `TextItem.times`), so the spans place any note on the
// recording's timeline: playing "with notes" shows each note when the sound
// reaches the moment it was written, and tapping a note plays that moment.

/// A stretch of a recording: wall-clock milliseconds [wallStart]..[wallEnd]
/// (since the epoch) are the audio from [audioStart] ms on.
class RecordingSpan {
  const RecordingSpan({required this.wallStart, required this.wallEnd, required this.audioStart});

  factory RecordingSpan.fromJson(List<dynamic> j) => RecordingSpan(
        wallStart: (j[0] as num).toInt(),
        wallEnd: (j[1] as num).toInt(),
        audioStart: (j[2] as num).toInt(),
      );

  final int wallStart;
  final int wallEnd;
  final int audioStart;

  int get length => wallEnd - wallStart;
  int get audioEnd => audioStart + length;

  RecordingSpan endingAt(int wall) => RecordingSpan(wallStart: wallStart, wallEnd: wall, audioStart: audioStart);

  List<int> toJson() => [wallStart, wallEnd, audioStart];

  @override
  bool operator ==(Object other) =>
      other is RecordingSpan && other.wallStart == wallStart && other.wallEnd == wallEnd && other.audioStart == audioStart;

  @override
  int get hashCode => Object.hash(wallStart, wallEnd, audioStart);
}

/// One recording of a notebook.
class Recording {
  const Recording({
    required this.id,
    required this.title,
    required this.file,
    required this.createdAt,
    required this.spans,
    this.inProgress = false,
  });

  factory Recording.fromJson(Map<String, dynamic> j) => Recording(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Recording',
        file: j['file'] as String,
        createdAt: (j['createdAt'] as num).toInt(),
        spans: [
          for (final s in (j['spans'] as List<dynamic>? ?? const []))
            if (s is List && s.length >= 3) RecordingSpan.fromJson(s),
        ],
        inProgress: j['inProgress'] as bool? ?? false,
      );

  final String id;
  final String title;

  /// The audio file's name in the notebook's `audio/` folder.
  final String file;

  /// When the recording started (ms since the epoch).
  final int createdAt;

  /// Its stretches, in order (never empty for a recording that started).
  final List<RecordingSpan> spans;

  /// Still being recorded, or cut short (the app was closed): the spans end
  /// where they were last saved.
  final bool inProgress;

  /// Length of the sound, in milliseconds.
  int get durationMs => spans.isEmpty ? 0 : spans.last.audioEnd;

  /// Whether a note written at [wall] (ms since the epoch) was written
  /// during this recording, pauses included.
  bool covers(int? wall) => wall != null && spans.isNotEmpty && wall >= spans.first.wallStart && wall <= spans.last.wallEnd;

  /// Where in the sound a note written at [wall] belongs: inside a span, the
  /// moment it was written; during a pause, the moment the sound went on.
  /// Null when the note was not written during the recording.
  int? audioPositionOf(int? wall) {
    if (!covers(wall)) return null;
    for (final s in spans) {
      if (wall! <= s.wallEnd) return wall < s.wallStart ? s.audioStart : s.audioStart + (wall - s.wallStart);
    }
    return durationMs;
  }

  /// The wall-clock moment the sound is at [audioMs]: notes written up to
  /// it have been "written" at this point of the playback.
  int wallTimeAt(int audioMs) {
    if (spans.isEmpty) return createdAt;
    for (final s in spans) {
      if (audioMs < s.audioEnd) return s.wallStart + (audioMs - s.audioStart).clamp(0, s.length);
    }
    return spans.last.wallEnd;
  }

  Recording copyWith({String? title, List<RecordingSpan>? spans, bool? inProgress}) => Recording(
        id: id,
        title: title ?? this.title,
        file: file,
        createdAt: createdAt,
        spans: spans ?? this.spans,
        inProgress: inProgress ?? this.inProgress,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'file': file,
        'createdAt': createdAt,
        'spans': [for (final s in spans) s.toJson()],
        if (inProgress) 'inProgress': true,
      };
}

/// `{"version": 1, "recordings": [...]}`, the notebook's `audio/recordings.json`.
List<Recording> recordingsFromJson(Map<String, dynamic> j) => [
      for (final r in (j['recordings'] as List<dynamic>? ?? const []))
        if (r is Map<String, dynamic> && r['id'] is String && r['file'] is String && r['createdAt'] is num)
          Recording.fromJson(r),
    ];

Map<String, dynamic> recordingsToJson(List<Recording> recordings) => {
      'version': 1,
      'recordings': [for (final r in recordings) r.toJson()],
    };

/// "1:05" or "1:02:05" for [ms] milliseconds.
String formatDuration(int ms) {
  final total = (ms / 1000).floor().clamp(0, 1 << 30);
  final h = total ~/ 3600, m = (total % 3600) ~/ 60, s = total % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}
