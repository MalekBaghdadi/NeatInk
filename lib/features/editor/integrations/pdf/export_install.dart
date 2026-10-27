import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../editor_controller.dart';
import 'export_flow.dart';
import 'export_service.dart';

/// Adds the "Export PDF" action to the editor menu. Free of pdfrx, so it
/// can be tested without PDFium.
void installPdfExport(EditorController controller, WidgetRef ref) {
  final service = ref.read(pdfExportServiceProvider);
  controller.extensions.exportPdf =
      (context, c) => runPdfExportFlow(context, c, service);
}
