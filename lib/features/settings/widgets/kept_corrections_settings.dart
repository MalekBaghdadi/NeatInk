import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../editor/integrations/convert/kept_corrections.dart';
import '../../editor/integrations/convert/send_writing_samples.dart';
import '../settings_controller.dart';

/// Settings › Writing: "Keep my writing samples" and "Send writing samples"
/// (v1.11.0; "Keep / Share my corrections" before). Lines typed from the
/// review sheet or by Auto are kept on the tablet, so recognition and the
/// auto features can be measured and tuned on her writing; they leave the
/// tablet only through the share sheet, in one file
/// ([sendWritingSamples]).
class KeptCorrectionsSettings extends ConsumerStatefulWidget {
  const KeptCorrectionsSettings({super.key});

  @override
  ConsumerState<KeptCorrectionsSettings> createState() => _KeptCorrectionsSettingsState();
}

class _KeptCorrectionsSettingsState extends ConsumerState<KeptCorrectionsSettings> {
  int? _count;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final n = await ref.read(keptCorrectionsProvider).count();
    if (mounted) setState(() => _count = n);
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      await sendWritingSamples(context, ref);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final kept = ref.read(keptCorrectionsProvider);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete kept writing samples?'),
        content: Text('The ${_count ?? 0} lines kept on this tablet are deleted. '
            'Your notebooks are not changed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            key: const ValueKey('kept-corrections-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await kept.clear();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final on = ref.watch(settingsProvider.select((s) => s.keepCorrections));
    final count = _count;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          key: const ValueKey('settings-keep-corrections'),
          secondary: const Icon(Icons.fact_check_outlined),
          title: const Text('Keep my writing samples'),
          subtitle: const Text('Lines typed from your handwriting (with Convert or Auto) are kept on '
              'this tablet, with what you changed afterwards, so the handwriting reader can '
              'be improved for your writing. Nothing is sent unless you send it.'),
          value: on,
          onChanged: (v) => ref.read(settingsProvider.notifier).update((s) => s.copyWith(keepCorrections: v)),
        ),
        ListTile(
          key: const ValueKey('settings-share-corrections'),
          leading: const Icon(Icons.ios_share_rounded),
          title: const Text('Send writing samples'),
          subtitle: Text(count == null
              ? 'Counting…'
              : count == 0
                  ? 'Nothing kept yet.'
                  : '$count ${count == 1 ? 'line' : 'lines'} of your writing. Tap, then pick WhatsApp '
                      '(or email) and send the file to Malek.'),
          enabled: !_busy && (count ?? 0) > 0,
          onTap: () => unawaited(_share()),
          trailing: IconButton(
            key: const ValueKey('settings-delete-corrections'),
            tooltip: 'Delete kept writing samples',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: (count ?? 0) > 0 && !_busy ? () => unawaited(_delete()) : null,
          ),
        ),
      ],
    );
  }
}
