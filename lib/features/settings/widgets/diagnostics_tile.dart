import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/diagnostics.dart';
import '../../../app/providers.dart';
import '../../lock/auto_lock_suspension.dart';

/// Hands a diagnostics report to the system share sheet; tests use a fake.
abstract interface class DiagnosticsShareService {
  Future<void> share({required String fileName, required String text});
}

/// Writes the report into `<cache>/diagnostics/` and opens the share sheet.
class DefaultDiagnosticsShareService implements DiagnosticsShareService {
  const DefaultDiagnosticsShareService();

  @override
  Future<void> share({required String fileName, required String text}) async {
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'diagnostics'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(text, flush: true);
    await AutoLockSuspension.during(() => SharePlus.instance.share(ShareParams(
          files: [XFile(file.path, mimeType: 'text/plain')],
          subject: "Mariam's Notes diagnostics",
          title: "Mariam's Notes diagnostics",
        )));
  }
}

final diagnosticsShareServiceProvider =
    Provider<DiagnosticsShareService>((ref) => const DefaultDiagnosticsShareService());

/// Settings › About: "Share diagnostics", the problems the app ran into, to
/// send when something goes wrong; and clearing them.
class DiagnosticsTile extends ConsumerStatefulWidget {
  const DiagnosticsTile({super.key});

  @override
  ConsumerState<DiagnosticsTile> createState() => _DiagnosticsTileState();
}

class _DiagnosticsTileState extends ConsumerState<DiagnosticsTile> {
  int? _count;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final n = (await ref.read(diagnosticsLogProvider).entries()).length;
    if (mounted) setState(() => _count = n);
  }

  Future<void> _share() async {
    final log = ref.read(diagnosticsLogProvider);
    final share = ref.read(diagnosticsShareServiceProvider);
    final now = ref.read(clockProvider)();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final report = diagnosticsReport(await log.entries(), now: now);
      await share.share(fileName: diagnosticsFileName(now), text: report);
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text("Couldn't share the diagnostics: $e")));
    }
  }

  Future<void> _clear() async {
    await ref.read(diagnosticsLogProvider).clear();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final count = _count;
    return ListTile(
      key: const ValueKey('settings-diagnostics'),
      leading: const Icon(Icons.bug_report_outlined),
      title: const Text('Share diagnostics'),
      subtitle: Text('Problems the app ran into, to send when something goes wrong. '
          '${count == null ? '' : count == 0 ? 'None recorded.' : '$count recorded.'}'),
      onTap: () => unawaited(_share()),
      trailing: IconButton(
        key: const ValueKey('settings-diagnostics-clear'),
        tooltip: 'Clear diagnostics',
        icon: const Icon(Icons.delete_outline_rounded),
        onPressed: (count ?? 0) > 0 ? () => unawaited(_clear()) : null,
      ),
    );
  }
}
