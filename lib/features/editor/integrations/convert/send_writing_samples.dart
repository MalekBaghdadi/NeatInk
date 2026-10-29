import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/app_info.dart';
import '../../../../app/diagnostics.dart';
import '../../../../app/providers.dart';
import '../../../../document/page_content.dart';
import '../../../settings/convert_style_prefs.dart';
import '../../../settings/settings_controller.dart';
import '../../editor_controller.dart';
import 'kept_corrections.dart';
import 'sample_share.dart';
import 'writing_samples.dart';

/// "Send writing samples" (Settings and the notebook menu): one file with
/// every kept line and what its text is now (see writing_samples.dart), the
/// auto settings and the recorded problems, handed to the share sheet. [open]
/// is the notebook in the editor, read as it is on screen (its last changes
/// may not be saved yet). Returns whether the file was shared.
Future<bool> sendWritingSamples(BuildContext context, WidgetRef ref, {EditorController? open}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final now = ref.read(clockProvider)();
  try {
    final lines = await ref.read(keptCorrectionsProvider).entries();
    if (lines.isEmpty) {
      messenger?.showSnackBar(const SnackBar(
          content: Text('Nothing to send yet: convert some handwriting first (Convert or Auto).')));
      return false;
    }
    final repository = ref.read(notebookRepositoryProvider);
    Future<PageContent?> load(String notebookId, String pageId) async {
      final c = open;
      if (c != null && c.isReady && c.notebookId == notebookId) {
        final page = c.doc.pages[pageId];
        if (page != null) return page;
        if (!c.doc.meta.pages.any((p) => p.id == pageId)) return PageContent();
      }
      return repository.loadPage(notebookId, pageId);
    }

    final withText = await withTextNow(lines, load);
    final s = ref.read(settingsProvider);
    final json = writingSamplesFile(
      withText,
      appVersion: '${AppInfo.version}+${AppInfo.buildNumber}',
      createdAt: now,
      settings: {
        'autoConvert': s.autoConvert,
        'autoConvertDelayMs': s.autoConvertDelayMs,
        'autocorrect': s.autocorrect,
        'checkSpelling': s.checkSpelling,
        'shapeSnap': s.shapeSnapEnabled,
        'scribbleToDelete': s.scribbleToDelete,
        'drawWithFinger': s.drawWithFinger,
        'typedText': ref.read(convertStylePrefsProvider).toJson(),
      },
      problems: [
        for (final e in await ref.read(diagnosticsLogProvider).entries())
          {'t': e.time.toIso8601String(), 'm': e.message},
      ],
    );
    final shared = await ref.read(sampleShareServiceProvider).share(fileName: writingSamplesFileName(now), json: json);
    if (shared) {
      messenger?.showSnackBar(SnackBar(
          content: Text('Thank you! ${lines.length} ${lines.length == 1 ? 'line' : 'lines'} of your writing shared.')));
    }
    return shared;
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text("Couldn't prepare the writing samples: $e")));
    return false;
  }
}
