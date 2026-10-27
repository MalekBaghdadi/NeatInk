import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../editor_controller.dart';
import '../../editor_integrations.dart';
import 'export_install.dart';
import 'pdf_background.dart';

export 'export_service.dart' show PdfExportService, pdfExportServiceProvider;

/// PDF-backed notebooks: renders the PDF page behind the ink (editor and
/// thumbnail) and adds the editor's "Export PDF" action (progress dialog,
/// save to a location the user picks, share).
final EditorIntegration pdfIntegration = _install;

void _install(EditorController controller, WidgetRef ref) {
  installPdfBackground(controller);
  installPdfExport(controller, ref);
}
