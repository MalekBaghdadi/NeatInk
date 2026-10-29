/// Notes shown faint while a lecture recording plays "with notes" (v1.12.0):
/// those written after the moment the sound is at. The page painter and the
/// text layer ask it per stroke and per line of typed text.
abstract interface class InkReveal {
  /// Whether a note written at [writtenAt] (ms since the epoch) is still
  /// ahead of the playback.
  bool isAhead(int? writtenAt);
}

/// How much of its colour a note ahead of the playback keeps.
const double aheadOpacity = 0.16;
