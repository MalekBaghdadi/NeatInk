import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';
import 'tour.dart';

// The guided tours (v1.12.0): the library, a notebook, a PDF notebook. Each
// starts by itself the first time its screen is on top, once; Settings ›
// "Show me around again" brings them all back, and a notebook's ⋮ menu
// starts its tour any time. Written for someone who has never used a notes
// app: what each button is, what it does, where to find things later.

/// Which tours were shown (in the app's preferences).
class TourMemory extends ChangeNotifier {
  TourMemory(this.prefs);

  final SharedPreferences prefs;

  static const String library = 'library';
  static const String notebook = 'notebook';
  static const String pdf = 'pdf';
  static const List<String> all = [library, notebook, pdf];

  static String _key(String name) => 'tourSeen.$name';

  bool seen(String name) => prefs.getBool(_key(name)) == true;

  Future<void> markSeen(String name) => prefs.setBool(_key(name), true);

  /// Every tour shows again (the next time its screen opens).
  Future<void> resetAll() async {
    for (final name in all) {
      await prefs.remove(_key(name));
    }
    notifyListeners();
  }
}

final tourMemoryProvider = Provider<TourMemory>((ref) {
  final m = TourMemory(ref.watch(sharedPreferencesProvider));
  ref.onDispose(m.dispose);
  return m;
});

/// Whether tours start by themselves. The app turns it on (main.dart); off
/// in tests, so screens open as they are.
final autoToursProvider = Provider<bool>((ref) => false);

/// Starts [steps] as tour [name] when [context]'s screen is on top: now, or
/// when the screens above it close (the first-run tips) and their closing
/// animation is over. Only once ever, unless the tours are reset. Marked as
/// shown before it shows, so closing the app on it does not bring it back
/// every time.
void startTourWhenOnTop(BuildContext context, WidgetRef ref, List<String> names, List<TourStep> Function() steps) {
  final memory = ref.read(tourMemoryProvider);
  if (!ref.read(autoToursProvider) || names.every(memory.seen)) return;
  // Checked after each frame: frames stop while nothing moves, so an idle
  // screen costs nothing, and the screen above closing brings them back. A
  // fullscreen screen above (the tips) does not move this one's
  // secondary animation, so that cannot be listened to instead.
  var settling = 0;
  void attempt() {
    if (!context.mounted || names.every(memory.seen)) return;
    final route = ModalRoute.of(context);
    final onTop = route == null || route.isCurrent;
    // On top, but a screen above may still be sliding away: wait for the
    // frames to stop (at most ~1 s, in case something keeps moving).
    if (!onTop || (SchedulerBinding.instance.hasScheduledFrame && ++settling < 60)) {
      if (!onTop) settling = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) => attempt());
      return;
    }
    final shown = steps();
    for (final name in names) {
      unawaited(memory.markSeen(name));
    }
    unawaited(showTour(context, shown));
  }

  WidgetsBinding.instance
    ..addPostFrameCallback((_) => attempt())
    // Called outside a frame too (Settings resetting the tours).
    ..scheduleFrame();
}

/// The library: where things are.
List<TourStep> libraryTour() => const [
      TourStep(
        icon: Icons.waving_hand_rounded,
        title: "Welcome to Mariam's Notes",
        text: 'This short tour shows where everything is. Tap Next, or Skip tour if you know it already. '
            'You can see it again any time in Settings › Show me around again.',
      ),
      TourStep(
        target: 'library-new',
        icon: Icons.add_rounded,
        title: 'New',
        text: 'Make a new notebook (blank, lined, grid and more), import a PDF to write on, or make a folder.',
      ),
      TourStep(
        target: 'notebook-',
        prefix: true,
        icon: Icons.menu_book_rounded,
        title: 'Your notebooks',
        text: 'Tap a notebook to open it. Hold your finger on one to rename it, move it to a folder, '
            'give it a cover, copy it or delete it.',
      ),
      TourStep(
        target: 'nav-all',
        icon: Icons.folder_outlined,
        title: 'Folders and filters',
        text: 'All notebooks, your favourites, PDFs, folders and tags. Deleted notebooks wait in the Trash '
            'for 30 days, so you can bring them back.',
      ),
      TourStep(
        target: 'library-search',
        icon: Icons.search_rounded,
        title: 'Search',
        text: 'Find any word: in titles, typed text, PDFs, and even in your handwriting.',
      ),
      TourStep(
        target: 'library-sort',
        icon: Icons.sort_rounded,
        title: 'Sort',
        text: 'Show the notebooks you used last first, the oldest first, or by name.',
      ),
      TourStep(
        target: 'library-settings',
        icon: Icons.settings_outlined,
        title: 'Settings and help',
        text: 'Dark mode, a PIN lock, backups, sending writing samples to Malek, tips, and this tour again.',
      ),
      TourStep(
        icon: Icons.check_circle_outline_rounded,
        title: "That's the library",
        text: 'Open a notebook and a second tour shows the writing tools. Tip: hold your finger on any button, '
            'or hover the pen over it, to see what it does.',
      ),
    ];

/// A notebook: the tools.
List<TourStep> notebookTour() => const [
      TourStep(
        icon: Icons.edit_note_rounded,
        title: 'Your notebook',
        text: 'Here is what each button does. Write with the pen; your finger scrolls the pages, and two '
            'fingers zoom in and out.',
      ),
      TourStep(
        target: 'tool-pen',
        icon: Icons.edit_rounded,
        title: 'Pen',
        text: 'Write and draw. To delete words quickly, scribble over them back and forth.',
      ),
      TourStep(
        target: 'pen-style',
        title: 'Pen type',
        text: 'Ballpoint, fountain pen or pencil.',
      ),
      TourStep(
        target: 'pen-colour-',
        prefix: true,
        icon: Icons.palette_outlined,
        title: 'Colours',
        text: 'Tap a colour to write in it. The rainbow circle lets you pick any colour.',
      ),
      TourStep(
        target: 'pen-width-',
        prefix: true,
        title: 'Thickness',
        text: 'Thin, medium or thick lines.',
      ),
      TourStep(
        target: 'tool-highlighter',
        icon: Icons.border_color_rounded,
        title: 'Highlighter',
        text: 'Mark important words. A wobbly highlight over a line becomes a neat straight band.',
      ),
      TourStep(
        target: 'tool-eraser',
        icon: Icons.auto_fix_normal_rounded,
        title: 'Eraser',
        text: 'Rub over ink or typed words to erase them. Undo brings them back.',
      ),
      TourStep(
        target: 'tool-lasso',
        icon: Icons.gesture_rounded,
        title: 'Lasso',
        text: 'Draw a loop around some notes. Then move or resize them, change their colour, copy them, '
            'turn them into typed text, or delete them.',
      ),
      TourStep(
        target: 'tool-text',
        icon: Icons.text_fields_rounded,
        title: 'Text box',
        text: 'Tap the page to type with the keyboard.',
      ),
      TourStep(
        target: 'tool-image',
        icon: Icons.add_photo_alternate_outlined,
        title: 'Picture',
        text: 'Add a photo or a picture from the tablet.',
      ),
      TourStep(
        target: 'tool-shape',
        icon: Icons.category_outlined,
        title: 'Shapes',
        text: 'Draw straight lines, arrows, boxes and circles. Tip: with the pen, hold still at the end of a '
            'line or a circle and it snaps neat.',
      ),
      TourStep(
        target: 'convert-to-text',
        icon: Icons.text_fields_rounded,
        title: 'Convert',
        text: 'Turns your handwriting into typed text. You see what it read first and can fix any word.',
      ),
      TourStep(
        target: 'auto-convert-toggle',
        icon: Icons.auto_awesome_rounded,
        title: 'Auto',
        text: 'When it is on, your writing turns into typed text by itself a moment after you stop writing.',
      ),
      TourStep(
        target: 'convert-settings',
        icon: Icons.tune_rounded,
        title: 'Typed text settings',
        text: 'The font, size and colour of the typed text, and whether lines join into sentences.',
      ),
      TourStep(
        target: 'record-lecture',
        icon: Icons.mic_none_rounded,
        title: 'Record a lecture',
        text: 'Records the sound while you write. Afterwards, play it back and watch your notes appear as '
            'you wrote them.',
      ),
      TourStep(
        target: 'open-recordings',
        icon: Icons.headphones_rounded,
        title: 'Recordings',
        text: 'Listen to the lectures you recorded in this notebook: Play, or Play with notes.',
      ),
      TourStep(
        target: 'undo',
        icon: Icons.undo_rounded,
        title: 'Undo and Redo',
        text: 'Made a mistake? Undo takes back the last thing you did; Redo puts it back.',
      ),
      TourStep(
        target: 'open-page-navigator',
        icon: Icons.grid_view_rounded,
        title: 'Pages',
        text: 'See all the pages at once: jump to one, move, copy or delete pages, or change their paper.',
      ),
      TourStep(
        target: 'add-page',
        icon: Icons.note_add_outlined,
        title: 'Add a page',
        text: 'Adds a new page at the end.',
      ),
      TourStep(
        target: 'editor-menu',
        icon: Icons.more_vert_rounded,
        title: 'More',
        text: 'Export as PDF, send writing samples, the paper of this page, rename the notebook, and this '
            'tour again (Show me around).',
      ),
      TourStep(
        icon: Icons.check_circle_outline_rounded,
        title: 'Ready to write',
        text: 'Your notes are saved by themselves as you write. Hold your finger on any button, or hover the '
            'pen over it, to see what it does.',
      ),
    ];

/// A PDF notebook: what is different.
List<TourStep> pdfTour() => const [
      TourStep(
        icon: Icons.picture_as_pdf_outlined,
        title: 'Writing on a PDF',
        text: 'Write, highlight and type on the PDF pages like on paper. The PDF itself never changes: your '
            'notes sit on top of it.',
      ),
      TourStep(
        target: 'editor-menu',
        icon: Icons.more_vert_rounded,
        title: 'Export and margins',
        text: '⋮ › Export PDF makes a new PDF with your notes in it, to send or print. ⋮ › PDF margins adds '
            'lined space beside the pages for your notes.',
      ),
    ];
