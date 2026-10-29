import '../../../../document/page_content.dart';
import 'auto_convert_session.dart';
import 'kept_corrections.dart';
import 'sample_export.dart';

// "Send writing samples" (v1.11.0): one tap gives the owner what improves the
// handwriting reader and the auto features. Every line typed from the review
// sheet or by Auto is kept on the tablet (format-2 sample entries: the pen
// strokes, what was read, the words' confidences and alternatives, the fixes
// made). At sending time each kept line also gets the text its box holds NOW:
// the user's later edits, words she took back from autocorrect and
// conversions she undid (the box is gone) are the corrections that make the
// lines ground truth. The file also carries the auto settings and the
// recorded problems. Nothing leaves the tablet unless she sends it.

/// Kept entries for the lines auto-convert typed in notebook [notebookId]:
/// like the review sheet's ([keptLineEntries]) with `source: auto`, where
/// they went (`notebookId`, `pageId`, `boxId`) and whether they carried on a
/// box already there (`joinedBox`: a joined line or sentence).
List<Map<String, dynamic>> autoKeptEntries(String notebookId, List<AutoConvertedLine> lines, DateTime keptAt) {
  final entries = keptLineEntries(
    [for (final l in lines) SampleLineInput(line: l.line, pageIndex: l.pageIndex, images: const [])],
    keptAt,
  );
  return [
    for (var i = 0; i < entries.length; i++)
      {
        ...entries[i],
        'source': 'auto',
        'notebookId': notebookId,
        'pageId': lines[i].pageId,
        'boxId': lines[i].boxId,
        'joinedBox': lines[i].joinedBox,
      },
  ];
}

/// [entries] with the current text of the box each was typed into:
/// `boxTextNow` (null and `boxGone: true` when the box no longer exists:
/// the conversion was undone or the text deleted). [loadPage] gives a page
/// as it is now (null when it can't be read); each page is read once.
Future<List<Map<String, dynamic>>> withTextNow(
  List<Map<String, dynamic>> entries,
  Future<PageContent?> Function(String notebookId, String pageId) loadPage,
) async {
  final pages = <String, PageContent?>{};
  final out = <Map<String, dynamic>>[];
  for (final e in entries) {
    final notebookId = e['notebookId'], pageId = e['pageId'], boxId = e['boxId'];
    if (notebookId is! String || pageId is! String || boxId is! String) {
      out.add(e);
      continue;
    }
    final key = '$notebookId/$pageId';
    final PageContent? page;
    if (pages.containsKey(key)) {
      page = pages[key];
    } else {
      try {
        page = pages[key] = await loadPage(notebookId, pageId);
      } catch (_) {
        out.add(e);
        pages[key] = null;
        continue;
      }
    }
    if (page == null) {
      out.add(e);
      continue;
    }
    final box = page.textById(boxId);
    out.add({...e, 'boxTextNow': box?.text, 'boxGone': box == null});
  }
  return out;
}

/// The "writing samples" file: a samples file (format 2, `kind:
/// writing-samples`, so the desktop tools read its `lines`) with the app's
/// auto [settings] and the recorded [problems] (`{t, m}`).
String writingSamplesFile(
  List<Map<String, dynamic>> lines, {
  required String appVersion,
  required DateTime createdAt,
  required Map<String, Object?> settings,
  required List<Map<String, String>> problems,
}) =>
    encodeSamplesJson({
      'format': samplesFormat,
      'app': "Mariam's Notes",
      'appVersion': appVersion,
      'createdAt': createdAt.toIso8601String(),
      'kind': 'writing-samples',
      'settings': settings,
      'problems': problems,
      'lineCount': lines.length,
      'lines': lines,
    });

/// `mariams-notes-writing-yyyymmdd-hhmm.json` for a file made at [t].
String writingSamplesFileName(DateTime t) => samplesFileName(t).replaceFirst('-samples-', '-writing-');
