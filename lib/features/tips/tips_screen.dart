import 'package:flutter/material.dart';

import '../settings/widgets/settings_section.dart';

/// One tip: an icon, a short title and a sentence or two.
class Tip {
  const Tip(this.icon, this.title, this.body);

  final IconData icon;
  final String title;
  final String body;
}

/// The tips, in the order they are shown. Keep the wording in step with the
/// labels on screen (button names, menu items, settings).
const List<Tip> appTips = [
  Tip(Icons.draw_outlined, 'The pen writes, fingers move',
      'Write with the pen. Scroll with one finger and pinch with two to zoom. '
          'If the pen does not write, turn on Settings › Draw with finger.'),
  Tip(Icons.interests_outlined, 'Hold still for a neat shape',
      'Draw a line, arrow, box, circle or triangle and keep the pen still at '
          'the end: it turns into a clean shape.'),
  Tip(Icons.text_fields, 'Handwriting to typed text',
      'Convert turns your handwriting into typed text. Turn on Auto and it '
          'happens by itself a moment after you stop writing. The button next '
          'to Auto sets the font, size and colour.'),
  Tip(Icons.spellcheck, 'Undo an autocorrect',
      'Words that autocorrect changed have a dotted blue underline. Tap one '
          'to get back what you wrote.'),
  Tip(Icons.highlight_alt, 'Restore original',
      'Select with the lasso and choose Restore original to undo a shape or '
          'a tidied highlight. Your original ink is always kept.'),
  Tip(Icons.grid_view, 'All pages at a glance',
      'Pages shows every page: tap one to jump to it, or use its menu to '
          'move, duplicate, insert or delete pages.'),
  Tip(Icons.picture_as_pdf_outlined, 'Room to write beside a PDF',
      'In a PDF notebook, the More menu (three dots) has PDF margins… to add '
          'writing space beside every page.'),
  Tip(Icons.backup_outlined, 'Back up your notebooks',
      'Your notes are kept only on this tablet. Now and then use Settings › '
          'Back up all notebooks and keep the file somewhere else.'),
];

/// A short list of tips about the app. Opens by itself once (see
/// `TipsOnce`), and any time from Settings.
class TipsScreen extends StatelessWidget {
  const TipsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TipsScreen(), fullscreenDialog: true));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Tips')),
      body: SafeArea(
        top: false,
        child: ListView(
          key: const ValueKey('tips-list'),
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            for (final (i, tip) in appTips.indexed)
              SettingsWidth(
                child: Card(
                  key: ValueKey('tip-$i'),
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: scheme.primaryContainer,
                      foregroundColor: scheme.onPrimaryContainer,
                      child: Icon(tip.icon),
                    ),
                    title: Text(tip.title, style: theme.textTheme.titleMedium),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(tip.body),
                    ),
                  ),
                ),
              ),
            SettingsWidth(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    key: const ValueKey('tips-done'),
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Got it'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
