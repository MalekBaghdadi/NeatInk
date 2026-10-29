import 'editor_integrations.dart';
import 'integrations/autocorrect/autocorrect_integration.dart';
import 'integrations/convert/convert_integration.dart';
import 'integrations/erase_select/erase_select_integration.dart';
import 'integrations/highlight/highlight_integration.dart';
import 'integrations/pages/pages_integration.dart';
import 'integrations/pdf/pdf_integration.dart';
import 'integrations/scribble/scribble_integration.dart';
import 'integrations/search_index/search_index_integration.dart';
import 'integrations/shapes/shapes_integration.dart';
import 'integrations/text_images/text_images_integration.dart';

/// The integrations the real app installs into every editor, in order.
///
/// Kept apart from `editor_integrations.dart` so that editor tests, which
/// don't import this file, don't pull in the PDF engine.
final List<EditorIntegration> defaultEditorIntegrations = [
  eraseSelectIntegration,
  textImagesIntegration,
  shapesIntegration,
  highlightIntegration,
  pagesIntegration,
  pdfIntegration,
  convertIntegration,
  autocorrectIntegration,
  scribbleIntegration,
  searchIndexIntegration,
];
