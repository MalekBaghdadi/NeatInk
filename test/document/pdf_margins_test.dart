import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/commands.dart';
import 'package:neatink/document/notebook_doc.dart';
import 'package:neatink/document/notebook_meta.dart';
import 'package:neatink/document/page_content.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/document/pdf_margins.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';

Stroke line(String id, double x1, double x2, {double y = 100}) => Stroke(
      id: id,
      tool: StrokeTool.pen,
      color: 0xFF000000,
      size: 2,
      raw: [InkPoint(x1, y, 0.5, 0), InkPoint(x2, y, 0.5, 10)],
    );

NotebookDoc pdfDoc(List<PageContent> contents) {
  final pages = [
    for (var i = 0; i < contents.length; i++)
      PageMeta(id: 'p$i', width: 600, height: 800, pdfPageIndex: i),
    const PageMeta(id: 'plain'),
  ];
  return NotebookDoc(
    NotebookMeta(
        id: 'n',
        title: 'Slides',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        kind: NotebookKind.pdf,
        pages: pages),
    pages: {for (var i = 0; i < contents.length; i++) 'p$i': contents[i], 'plain': PageContent()},
  );
}

void main() {
  test('margins widen a PDF page on both sides and make blank paper lined', () {
    const page = PageMeta(id: 'p', width: 600, height: 800, pdfPageIndex: 0);
    final narrow = withPdfMargins(page, PdfMargins.narrow);
    expect((narrow.marginLeft, narrow.marginRight, narrow.width), (150, 150, 900));
    expect(narrow.contentWidth, 600);
    expect(narrow.paper.type, PaperType.lined);
    final wide = withPdfMargins(narrow, PdfMargins.wide);
    expect((wide.marginLeft, wide.width), (300, 1200));
    final none = withPdfMargins(wide, PdfMargins.none);
    expect((none.marginLeft, none.marginRight, none.width), (0, 0, 600));
    expect(PdfMargins.of(narrow), PdfMargins.narrow);
    expect(PdfMargins.of(wide), PdfMargins.wide);
    expect(PdfMargins.of(none), PdfMargins.none);
    // Plain pages have no PDF to put margins beside.
    expect(withPdfMargins(const PageMeta(id: 'x'), PdfMargins.wide), const PageMeta(id: 'x'));
    expect(PdfMargins.byName('wide'), PdfMargins.wide);
    expect(PdfMargins.byName('huge'), PdfMargins.none);
  });

  test('margins survive notebook.json', () {
    final page = withPdfMargins(const PageMeta(id: 'p', width: 600, height: 800, pdfPageIndex: 2), PdfMargins.wide);
    final back = PageMeta.fromJson(page.toJson());
    expect((back.marginLeft, back.marginRight, back.width, back.pdfPageIndex), (300, 300, 1200, 2));
    expect(const PageMeta(id: 'p').toJson().containsKey('marginLeft'), isFalse);
  });

  test('notes move with their PDF page, raw points too, and undo restores them exactly', () {
    final stroke = line('s', 100, 200);
    const text = TextItem(id: 't', x: 50, y: 300, width: 100, height: 20, text: 'note');
    const image = ImageItem(id: 'i', x: 10, y: 400, width: 50, height: 50, asset: 'a.png');
    final doc = pdfDoc([PageContent(strokes: [stroke], texts: [text], images: [image])]);
    final stack = CommandStack();
    final plan = pdfMarginsCommand(doc, PdfMargins.narrow)!;
    expect(plan.hidesNotes, isFalse);
    stack.execute(plan.command, doc);

    final page = doc.page('p0');
    expect(doc.meta.pages.first.width, 900);
    expect(page.strokes.single.raw.first.x, 250);
    expect(page.strokes.single.points.last.x, 350);
    expect(page.texts.single.x, 200);
    expect(page.images.single.x, 160);
    expect(doc.meta.pages.last, const PageMeta(id: 'plain'), reason: 'plain pages stay');
    expect(stack.undoLabel, 'PDF margins');

    stack.undo(doc);
    expect(doc.meta.pages.first.width, 600);
    expect(page.strokes.single, same(stroke));
    expect(page.texts.single, same(text));
    expect(page.images.single, same(image));
    stack.redo(doc);
    expect(page.texts.single.x, 200);
    expect(pdfMarginsCommand(doc, PdfMargins.narrow), isNull, reason: 'nothing to change');
  });

  test('narrower margins say when notes would be off the page', () {
    final doc = pdfDoc([PageContent()]);
    CommandStack().execute(pdfMarginsCommand(doc, PdfMargins.wide)!.command, doc);
    // A note in the left margin, and one on the PDF page.
    doc.page('p0').strokes.add(line('margin', 20, 120));
    expect(pdfMarginsCommand(doc, PdfMargins.narrow)!.hidesNotes, isTrue);
    doc.page('p0').strokes
      ..clear()
      ..add(line('pdf', 400, 500));
    expect(pdfMarginsCommand(doc, PdfMargins.none)!.hidesNotes, isFalse);
  });

  test('skipped pages keep everything', () {
    final doc = pdfDoc([PageContent(strokes: [line('s', 10, 20)]), PageContent()]);
    final plan = pdfMarginsCommand(doc, PdfMargins.wide, skip: {'p0'})!;
    plan.command.apply(doc);
    expect(doc.meta.pages[0].width, 600);
    expect(doc.page('p0').strokes.single.raw.first.x, 10);
    expect(doc.meta.pages[1].width, 1200);
  });

  test('contentOutsideWidth counts the stroke width', () {
    final c = PageContent(strokes: [line('s', 5, 595)]);
    expect(contentOutsideWidth(c, 600), isFalse);
    expect(contentOutsideWidth(c, 590), isTrue);
    expect(contentOutsideWidth(shiftedPageContent(c, -10), 600), isTrue);
  });
}
