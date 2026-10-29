import '../../editor_integrations.dart';
import '../convert/convert_providers.dart';
import 'handwriting_indexer.dart';

/// Search handwriting: reads the open notebook's handwriting in the
/// background for the library search (see [HandwritingIndexer]). Follows
/// the `searchHandwriting` setting.
// ignore: prefer_function_declarations_over_variables
final EditorIntegration searchIndexIntegration = (controller, ref) {
  final indexer = HandwritingIndexer(
    controller: controller,
    recognizer: ref.read(htrRecognizerProvider),
  );
  controller.addDisposeCallback(indexer.dispose);
};
