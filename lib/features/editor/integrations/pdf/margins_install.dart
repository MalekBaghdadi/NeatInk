import 'package:flutter/material.dart';

import '../../../../document/pdf_margins.dart';
import '../../../library/dialogs/confirm_dialog.dart';
import '../../../library/dialogs/pdf_margins_dialog.dart';
import '../../editor_controller.dart';

/// Adds "PDF margins…" to the editor menu: lined writing space beside the
/// PDF pages, changed for the whole notebook in one undo step. Free of
/// pdfrx, so it can be tested without PDFium.
void installPdfMargins(EditorController controller) {
  controller.extensions.pdfMargins = changePdfMargins;
}

/// Asks for the margins and applies them to every PDF page; notes move
/// with their page. Narrower margins that would hide notes ask first.
Future<void> changePdfMargins(BuildContext context, EditorController c) async {
  if (!c.isReady) return;
  final chosen = await showPdfMarginsDialog(
    context,
    initial: PdfMargins.ofNotebook(c.doc.meta),
    title: 'PDF margins',
    message: 'Lined space beside each PDF page to write in. Your notes move '
        'with their page.',
    confirmLabel: 'Apply',
  );
  if (chosen == null || !context.mounted || !c.isReady) return;
  final plan = pdfMarginsCommand(c.doc, chosen, skip: c.unreadablePageIds);
  if (plan == null) return;
  if (plan.hidesNotes) {
    final ok = await showConfirmDialog(
      context,
      title: 'Hide notes in the margins?',
      message: 'Some notes are written where the margins are now. With '
          'narrower margins they are off the page and hidden (also in '
          'exports). Undo or wider margins bring them back.',
      confirmLabel: 'Apply',
    );
    if (!ok || !context.mounted || !c.isReady) return;
  }
  c.execute(plan.command);
}
