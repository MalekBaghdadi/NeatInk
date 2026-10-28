import 'package:flutter/material.dart';

import '../../../document/notebook_meta.dart';
import '../../../document/paper.dart';
import '../../../document/pdf_margins.dart';
import '../../../render/paper_painter.dart';

/// Asks for writing margins beside the pages of a PDF: lined space on both
/// sides for notes. [title] and [message] fit the moment (importing or
/// changing). Returns null when cancelled.
Future<PdfMargins?> showPdfMarginsDialog(
  BuildContext context, {
  required PdfMargins initial,
  String title = 'Space for notes',
  String message = 'Add lined margins beside each PDF page to write in. '
      'You can change this later from the editor menu.',
  String confirmLabel = 'OK',
}) =>
    showDialog<PdfMargins>(
      context: context,
      builder: (_) => _PdfMarginsDialog(
        initial: initial,
        title: title,
        message: message,
        confirmLabel: confirmLabel,
      ),
    );

class _PdfMarginsDialog extends StatefulWidget {
  const _PdfMarginsDialog({
    required this.initial,
    required this.title,
    required this.message,
    required this.confirmLabel,
  });

  final PdfMargins initial;
  final String title;
  final String message;
  final String confirmLabel;

  @override
  State<_PdfMarginsDialog> createState() => _PdfMarginsDialogState();
}

class _PdfMarginsDialogState extends State<_PdfMarginsDialog> {
  late PdfMargins _choice = widget.initial;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final m in PdfMargins.values)
                Semantics(
                  button: true,
                  selected: m == _choice,
                  label: m.label,
                  child: InkWell(
                    key: ValueKey('pdf-margins-${m.name}'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _choice = m),
                    child: Container(
                      width: 104,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: m == _choice ? scheme.primary : scheme.outlineVariant,
                          width: m == _choice ? 2.5 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 64,
                            child: Center(child: _MarginsPreview(margins: m)),
                          ),
                          const SizedBox(height: 6),
                          Text(m.label, style: Theme.of(context).textTheme.labelLarge),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const ValueKey('pdf-margins-ok'),
          onPressed: () => Navigator.of(context).pop(_choice),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// A small page with the PDF (grey text lines) between lined margins.
class _MarginsPreview extends StatelessWidget {
  const _MarginsPreview({required this.margins});

  final PdfMargins margins;

  @override
  Widget build(BuildContext context) {
    const pdfWidth = 46.0, height = 64.0;
    final page = withPdfMargins(
      const PageMeta(id: 'preview', width: pdfWidth, height: height, pdfPageIndex: 0,
          paper: Paper(spacingPt: 6)),
      margins,
    );
    return SizedBox(
      width: page.width,
      height: height,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 2, offset: Offset(0, 1))],
        ),
        child: CustomPaint(painter: _PreviewPainter(page)),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.page);

  final PageMeta page;

  @override
  void paint(Canvas canvas, Size size) {
    paintPdfPageFrame(canvas, size, page);
    // Stand-in text lines on the PDF page.
    final ink = Paint()..color = const Color(0x55000000);
    final left = page.contentLeft + 5;
    for (var y = 8.0; y < size.height - 6; y += 6) {
      final short = (y ~/ 6) % 4 == 3;
      canvas.drawRect(
          Rect.fromLTWH(left, y, (page.contentWidth - 10) * (short ? 0.6 : 1), 2), ink);
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter oldDelegate) => oldDelegate.page.width != page.width;
}
