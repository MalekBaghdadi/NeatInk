import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/providers.dart';
import '../../../document/notebook_meta.dart';
import '../../../storage/backup/notebook_backup.dart';
import '../../editor/tool_prefs.dart';
import '../../library/relative_time.dart';
import '../backup_app_data.dart';
import '../backup_service.dart';
import '../convert_style_prefs.dart';
import '../my_words_screen.dart';
import '../settings_controller.dart';
import 'settings_section.dart';

/// Settings › Backup: save every notebook, folder, My words and the
/// settings to one file the user keeps off the tablet, and add notebooks
/// back from such a file. Restoring never replaces or deletes anything.
class BackupSettings extends ConsumerWidget {
  const BackupSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = ref.watch(settingsProvider.select((s) => s.lastBackupAt));
    final now = ref.watch(clockProvider)();
    return SettingsSection(
      title: 'Backup',
      icon: Icons.backup_outlined,
      children: [
        ListTile(
          key: const ValueKey('settings-backup'),
          leading: const Icon(Icons.save_alt_rounded),
          title: const Text('Back up all notebooks'),
          subtitle: Text('One file with every notebook, folder, My words and '
              'your settings (not your PIN). Save it somewhere off this '
              'tablet, like a computer or a USB stick.\n'
              '${last == null ? 'No backup yet.' : 'Last backup: ${formatRelative(last, now)}.'}'),
          isThreeLine: true,
          onTap: () => unawaited(runBackup(context, ref)),
        ),
        ListTile(
          key: const ValueKey('settings-restore'),
          leading: const Icon(Icons.settings_backup_restore_rounded),
          title: const Text('Restore from a backup'),
          subtitle: const Text('Adds the notebooks from a backup file. '
              'Nothing on this tablet is replaced or deleted.'),
          onTap: () => unawaited(runRestore(context, ref)),
        ),
      ],
    );
  }
}

/// Makes a backup and lets the user save it.
Future<void> runBackup(BuildContext context, WidgetRef ref) async {
  final service = ref.read(backupServiceProvider);
  if (service == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final settings = ref.read(settingsProvider.notifier);
  final clock = ref.read(clockProvider);
  final lexicon = ref.read(myWordsLexiconProvider);
  final current = ref.read(settingsProvider);
  final toolPrefs = ToolPrefsStore(ref.read(sharedPreferencesProvider)).load();
  final convertStyle = ref.read(convertStylePrefsProvider);
  await lexicon.load();
  final appData = BackupAppData.collect(
    settings: current,
    toolPrefs: toolPrefs,
    convertStyle: convertStyle,
    myWords: lexicon.words,
  );
  if (!context.mounted) return;

  final progress = ValueNotifier<(int, int)>((0, 0));
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => BackupProgressDialog(
        title: 'Making the backup', unit: 'notebook', progress: progress),
  ));
  String? path;
  String? failure;
  try {
    path = await service.create(appData,
        onProgress: (done, total) => progress.value = (done, total));
  } on BackupException catch (e) {
    failure = e.message;
  } catch (_) {
    failure = 'The backup could not be made.';
  } finally {
    if (navigator.mounted) navigator.pop();
    progress.dispose();
  }
  void tell(String message) => messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
  if (path == null) {
    tell(failure ?? 'The backup could not be made.');
    return;
  }
  try {
    final now = clock();
    if (await service.save(path, backupFileName(now))) {
      settings.update((s) => s.copyWith(lastBackupAt: now));
      tell('Backup saved. Keep it somewhere off this tablet.');
    } else {
      tell('The backup was not saved.');
    }
  } on BackupException catch (e) {
    tell(e.message);
  } catch (_) {
    tell('The backup could not be saved.');
  } finally {
    await service.discard(path);
  }
}

/// Picks a backup, shows what restoring it would do, and restores.
Future<void> runRestore(BuildContext context, WidgetRef ref) async {
  final service = ref.read(backupServiceProvider);
  if (service == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final repo = ref.read(notebookRepositoryProvider);
  final settings = ref.read(settingsProvider.notifier);
  final convertStyle = ref.read(convertStylePrefsProvider.notifier);
  final toolPrefs = ToolPrefsStore(ref.read(sharedPreferencesProvider));
  final lexicon = ref.read(myWordsLexiconProvider);
  void tell(String message) => messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  final String? path;
  try {
    path = await service.pick();
  } catch (_) {
    tell('The file could not be opened.');
    return;
  }
  if (path == null) return;
  try {
    if (!context.mounted) return;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const BackupProgressDialog(title: 'Reading the backup'),
    ));
    BackupInfo? info;
    List<NotebookMeta> local = const [];
    String? failure;
    try {
      info = await service.inspect(path);
      local = await repo.listNotebooks();
    } on BackupException catch (e) {
      failure = e.message;
    } catch (_) {
      failure = 'The backup could not be read.';
    } finally {
      if (navigator.mounted) navigator.pop();
    }
    if (info == null) {
      tell(failure ?? 'The backup could not be read.');
      return;
    }
    if (!context.mounted) return;
    final choice = await showDialog<RestoreChoice>(
      context: context,
      useRootNavigator: true,
      builder: (_) => RestoreDialog(info: info!, local: local),
    );
    if (choice == null || !context.mounted) return;

    final plan = planRestore(info, local,
        copyChanged: choice.copyChanged, newId: const Uuid().v4);
    final progress = ValueNotifier<(int, int)>((0, 0));
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => BackupProgressDialog(
          title: 'Restoring', unit: 'notebook', progress: progress),
    ));
    RestoreResult result;
    try {
      result = await service.restore(path, plan,
          onProgress: (done, total) => progress.value = (done, total));
      // Folders the restored notebooks are in, then fresh caches.
      final ids = result.restored.toSet();
      final metas = [
        for (final item in plan)
          if (ids.contains(item.targetId)) item.notebook.meta,
      ];
      if (metas.isNotEmpty) {
        final merged = mergeRestoredFolders(
            await repo.loadLibrary(), info.library, metas);
        if (merged != null) await repo.saveLibrary(merged);
      }
      await repo.listNotebooks();
      final words = BackupAppData.myWords(info.appData);
      if (words.isNotEmpty) {
        await lexicon.load();
        for (final w in words) {
          lexicon.add(w);
        }
        await lexicon.flush();
      }
      if (choice.settings) {
        final data = info.appData;
        settings.update((current) => BackupAppData.settings(data, current) ?? current);
        final pens = BackupAppData.toolPrefs(info.appData);
        if (pens != null) await toolPrefs.save(pens);
        final look = BackupAppData.convertStyle(info.appData);
        if (look != null) convertStyle.save(look);
      }
    } on BackupException catch (e) {
      tell(e.message);
      return;
    } catch (_) {
      tell('The backup could not be restored.');
      return;
    } finally {
      if (navigator.mounted) navigator.pop();
      progress.dispose();
    }
    final n = result.restored.length;
    tell(n == 0
        ? (choice.settings ? 'Settings restored.' : 'Nothing was restored.')
        : 'Restored $n ${n == 1 ? 'notebook' : 'notebooks'}.');
    if (result.failed.isNotEmpty && context.mounted) {
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (context) => AlertDialog(
          key: const ValueKey('restore-failures'),
          title: const Text('Some notebooks were not restored'),
          content: Text(result.failed.join('\n')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );
    }
  } finally {
    await service.discard(path);
  }
}

/// What the user chose in the [RestoreDialog].
class RestoreChoice {
  const RestoreChoice({required this.copyChanged, required this.settings});

  /// Add the notebooks changed since the backup as copies.
  final bool copyChanged;

  /// Also restore the backup's settings.
  final bool settings;
}

/// Says what restoring [info] onto a device holding [local] does, and asks
/// about the choices: changed notebooks as copies, and the settings.
class RestoreDialog extends StatefulWidget {
  const RestoreDialog({super.key, required this.info, required this.local});

  final BackupInfo info;
  final List<NotebookMeta> local;

  @override
  State<RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends State<RestoreDialog> {
  bool _copyChanged = true;
  bool _settings = false;

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final plan = planRestore(info, widget.local, copyChanged: true, newId: () => '');
    int count(RestoreReason r) => plan.where((i) => i.reason == r).length;
    final missing = count(RestoreReason.missing);
    final unchanged = count(RestoreReason.unchanged);
    final changed = count(RestoreReason.changed);
    final words = BackupAppData.myWords(info.appData).length;
    final hasSettings = BackupAppData.hasSettings(info.appData);
    String notebooks(int n) => n == 1 ? '1 notebook' : '$n notebooks';
    final canRestore = missing > 0 ||
        (changed > 0 && _copyChanged) ||
        (hasSettings && _settings) ||
        words > 0;
    final created = info.createdAt;

    return AlertDialog(
      title: const Text('Restore from backup'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${created == null ? 'This backup' : 'The backup from ${formatDate(created)}'} '
              'has ${notebooks(info.notebooks.length)}.',
              key: const ValueKey('restore-summary'),
            ),
            const SizedBox(height: 12),
            Text(
              missing == 0
                  ? 'No new notebooks to add.'
                  : '${notebooks(missing)} will be added.',
              key: const ValueKey('restore-missing'),
            ),
            if (unchanged > 0)
              Text(
                '${notebooks(unchanged)} already here and unchanged: skipped.',
                key: const ValueKey('restore-unchanged'),
              ),
            if (words > 0)
              Text(
                '$words ${words == 1 ? 'word' : 'words'} for My words.',
                key: const ValueKey('restore-words'),
              ),
            if (info.unreadable > 0)
              Text(
                '${notebooks(info.unreadable)} in the backup could not be read '
                'and will be skipped.',
                key: const ValueKey('restore-unreadable'),
              ),
            if (changed > 0)
              CheckboxListTile(
                key: const ValueKey('restore-copy-changed'),
                contentPadding: EdgeInsets.zero,
                value: _copyChanged,
                onChanged: (v) => setState(() => _copyChanged = v ?? false),
                title: Text('Also add ${notebooks(changed)} you changed '
                    'since this backup, as copies'),
                subtitle: const Text(
                    'Titled "… (from backup)". Your current versions stay as they are.'),
              ),
            if (hasSettings)
              CheckboxListTile(
                key: const ValueKey('restore-settings'),
                contentPadding: EdgeInsets.zero,
                value: _settings,
                onChanged: (v) => setState(() => _settings = v ?? false),
                title: const Text('Also restore the settings from the backup'),
                subtitle: const Text(
                    'Theme, writing settings, pens and typed text. Your PIN is not changed.'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('restore-cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('restore-confirm'),
          onPressed: canRestore
              ? () => Navigator.pop(context,
                  RestoreChoice(copyChanged: _copyChanged, settings: _settings))
              : null,
          child: const Text('Restore'),
        ),
      ],
    );
  }
}

/// A dialog that cannot be dismissed while a backup step runs. With
/// [progress], it shows "3 of 12 notebooks".
class BackupProgressDialog extends StatelessWidget {
  const BackupProgressDialog({
    super.key,
    required this.title,
    this.unit,
    this.progress,
  });

  final String title;
  final String? unit;
  final ValueNotifier<(int, int)>? progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        key: const ValueKey('backup-progress'),
        title: Text(title),
        content: p == null
            ? const LinearProgressIndicator()
            : ValueListenableBuilder<(int, int)>(
                valueListenable: p,
                builder: (context, v, _) {
                  final (done, total) = v;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(
                          value: total <= 0 ? null : (done / total).clamp(0.0, 1.0)),
                      const SizedBox(height: 12),
                      if (total > 0 && unit != null)
                        Text('$done of $total $unit${total == 1 ? '' : 's'}'),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
