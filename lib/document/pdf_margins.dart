import 'dart:math' as math;

import '../ink/affine2.dart';
import 'commands.dart';
import 'notebook_doc.dart';
import 'notebook_meta.dart';
import 'page_content.dart';
import 'paper.dart';

/// Writing space beside the pages of an imported PDF: the same width on
/// both sides, as a fraction of the PDF page's width. The margins show the
/// page's paper (lined by default); the PDF page sits between them.
enum PdfMargins {
  none('None', 0),
  narrow('Narrow', 0.25),
  wide('Wide', 0.5);

  const PdfMargins(this.label, this.fraction);

  final String label;

  /// Width of each margin as a fraction of the PDF page's width.
  final double fraction;

  /// Width of each margin, in points, beside a PDF page [pdfWidth] wide.
  double sideFor(double pdfWidth) => (pdfWidth * fraction).roundToDouble();

  /// The preset closest to [page]'s margins.
  static PdfMargins of(PageMeta page) {
    final w = page.contentWidth;
    if (!page.hasMargins || !(w > 0)) return PdfMargins.none;
    final f = math.max(page.marginLeft, page.marginRight) / w;
    var best = PdfMargins.none;
    for (final m in values) {
      if ((m.fraction - f).abs() < (best.fraction - f).abs()) best = m;
    }
    return best;
  }

  /// The preset of the notebook's first PDF page (none without PDF pages).
  static PdfMargins ofNotebook(NotebookMeta meta) {
    for (final p in meta.pages) {
      if (p.isPdf) return of(p);
    }
    return PdfMargins.none;
  }

  static PdfMargins byName(Object? name) {
    for (final m in values) {
      if (m.name == name) return m;
    }
    return PdfMargins.none;
  }
}

/// [page] with [margins]: wider by both margins, the PDF page in between.
/// Plain pages are returned unchanged. Blank paper becomes lined, since
/// the margins are for writing.
PageMeta withPdfMargins(PageMeta page, PdfMargins margins) {
  if (!page.isPdf) return page;
  final pdfWidth = page.contentWidth;
  final side = margins.sideFor(pdfWidth);
  final paper = side > 0 && page.paper.type == PaperType.blank
      ? page.paper.copyWith(type: PaperType.lined)
      : page.paper;
  return page.copyWith(
    width: pdfWidth + 2 * side,
    marginLeft: side,
    marginRight: side,
    paper: paper,
  );
}

/// [content] moved [dx] points to the right (its strokes keep their raw
/// points, moved the same way, so "Restore original" still works).
PageContent shiftedPageContent(PageContent content, double dx) {
  final m = Affine2.translation(dx, 0);
  return PageContent(
    strokes: [for (final s in content.strokes) s.transformed(m, scaleWidth: false)],
    texts: [for (final t in content.texts) t.copyWith(x: t.x + dx)],
    images: [for (final i in content.images) i.copyWith(x: i.x + dx)],
  );
}

/// Whether anything in [content] reaches outside x = 0 .. [width] (with a
/// point of tolerance): notes that narrower margins would hide.
bool contentOutsideWidth(PageContent content, double width) {
  bool out(double left, double right) => left < -1 || right > width + 1;
  for (final s in content.strokes) {
    for (final p in s.points) {
      if (out(p.x - s.size / 2, p.x + s.size / 2)) return true;
    }
  }
  for (final t in content.texts) {
    if (out(t.x, t.x + t.width)) return true;
  }
  for (final i in content.images) {
    if (out(i.x, i.x + i.width)) return true;
  }
  return false;
}

/// The edit that gives every PDF page in [doc] [margins], moving each
/// page's notes with its PDF page so they stay where they were written.
/// Pages in [skip] (e.g. unreadable ones) keep everything. Null when
/// nothing would change.
///
/// [hidesNotes] tells whether notes would end up off a narrower page.
({EditCommand command, bool hidesNotes})? pdfMarginsCommand(
  NotebookDoc doc,
  PdfMargins margins, {
  Set<String> skip = const {},
}) {
  final commands = <EditCommand>[];
  var hides = false;
  for (final before in doc.meta.pages) {
    if (!before.isPdf || skip.contains(before.id)) continue;
    final after = withPdfMargins(before, margins);
    if (after.width == before.width &&
        after.marginLeft == before.marginLeft &&
        after.marginRight == before.marginRight) {
      continue;
    }
    commands.add(UpdatePageMetaCommand(before, after, label: 'PDF margins'));
    final dx = after.contentLeft - before.contentLeft;
    final content = doc.pages[before.id];
    if (content == null || content.isEmpty) continue;
    final moved = dx == 0 ? content : shiftedPageContent(content, dx);
    hides = hides || contentOutsideWidth(moved, after.width);
    if (dx != 0) {
      commands.add(ReplacePageContentCommand(before.id, content, moved, label: 'PDF margins'));
    }
  }
  if (commands.isEmpty) return null;
  return (command: CompositeCommand('PDF margins', commands), hidesNotes: hides);
}
