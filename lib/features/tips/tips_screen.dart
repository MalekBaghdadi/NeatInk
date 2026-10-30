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
  Tip(Icons.gesture, 'Scribble to delete',
      'Scribble back and forth over handwriting or typed text with the pen to '
          'delete it. Undo brings it back. The eraser removes typed words too.'),
  Tip(Icons.spellcheck, 'Undo an autocorrect',
      'Words that autocorrect changed have a dotted blue underline. Tap one '
          'to get back what you wrote.'),
  Tip(Icons.format_underlined, 'Wavy underlines',
      'A red wavy line marks a word the app does not know, an amber one a word '
          'that may be a slip. Tap it to pick a spelling or add it to My words.'),
  Tip(Icons.format_size, 'Restyle typed text',
      'Select typed text with the lasso and tap Text style to change its font, '
          'size, bold, italic or underline; Colour changes its colour.'),
  Tip(Icons.mic_none, 'Record a lecture',
      'Tap the microphone at the top of a notebook and write as usual. Later, '
          'the headphones button plays it back; Play with notes shows your '
          'notes appearing as you wrote them. Tap a note to hear that moment.'),
  Tip(Icons.help_outline, 'What does this button do?',
      'Hold your finger on any button, or hover the pen over it, to see what '
          'it does. Settings › Show me around again repeats the guided tours.'),
  Tip(Icons.manage_search, 'Search your handwriting',
      'Search finds words in your handwriting too. The app reads a notebook '
          'while it is open and you pause, so open a notebook once to make it '
          'searchable.'),
  Tip(Icons.content_paste, 'Copy and paste',
      'Select with the lasso and tap Copy or Cut. Then, in any page or '
          'notebook, tap an empty spot with the lasso and choose Paste.'),
  Tip(Icons.highlight_alt, 'Restore original',
      'Select with the lasso and choose Restore original to undo a shape or '
          'a tidied highlight. Your original ink is always kept.'),
  Tip(Icons.grid_view, 'All pages at a glance',
      'Pages shows every page: tap one to jump to it, or use its menu to '
          'move, duplicate, insert or delete pages.'),
  Tip(Icons.picture_as_pdf_outlined, 'Room to write beside a PDF',
      'In a PDF notebook, the More menu (three dots) has PDF margins… to add '
          'writing space beside every page.'),
  Tip(Icons.delete_outline, 'Deleted by mistake?',
      'Deleted notebooks wait in the Trash (at the bottom of the side menu) '
          'for 30 days. Open it to bring one back.'),
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
