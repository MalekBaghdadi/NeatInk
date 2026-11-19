import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_info.dart';

/// Opens a web link in another app (the browser); false when none could.
/// Tests use a fake.
typedef LinkOpener = Future<bool> Function(Uri link);

final linkOpenerProvider = Provider<LinkOpener>(
    (ref) => (link) => launchUrl(link, mode: LaunchMode.externalApplication));

/// Settings › About: "Get the newest version" (v1.14.0). The app has no
/// internet permission, so it cannot look for updates itself: this hands the
/// download link of the newest release to the browser, which downloads it;
/// installing it over this app keeps every notebook (same signing key).
class UpdateTile extends ConsumerWidget {
  const UpdateTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      key: const ValueKey('settings-update'),
      leading: const Icon(Icons.system_update_rounded),
      title: const Text('Get the newest version'),
      subtitle: const Text('Downloads the newest $_app in your browser. '
          'You have version ${AppInfo.version}.'),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => _confirm(context, ref),
    );
  }

  static const String _app = AppInfo.name;

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.system_update_rounded),
        title: const Text('Get the newest version'),
        content: const Text(
          'Your browser opens and downloads the newest $_app '
          '(a file of about 45 MB, so the tablet needs the internet for this).\n\n'
          '1. When it has downloaded, tap the file.\n'
          '2. Tap Install or Update.\n\n'
          'Your notebooks stay as they are. You have version ${AppInfo.version}: '
          'check Settings afterwards to see the new number. If it is the same, '
          'you already had the newest one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            key: const ValueKey('update-download'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Download'),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    var opened = false;
    try {
      opened = await ref.read(linkOpenerProvider)(Uri.parse(AppInfo.downloadUrl));
    } catch (e) {
      debugPrint('NeatInk: opening the download link failed: $e');
    }
    if (opened) return;
    // No browser answered: give her the link to open herself.
    await Clipboard.setData(const ClipboardData(text: AppInfo.downloadUrl));
    messenger?.showSnackBar(const SnackBar(
      duration: Duration(seconds: 8),
      content: Text("Couldn't open the browser. The download link is copied: "
          'paste it into your browser.'),
    ));
  }
}
