import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../editor_controller.dart';
import '../../editor_integrations.dart';
import '../../editor_tool.dart';
import 'image_editor.dart';
import 'image_layer.dart';
import 'image_source.dart';
import 'image_tool.dart';
import 'text_editor.dart';
import 'text_format_bar.dart';
import 'text_layer.dart';
import 'text_overlay.dart';
import 'text_tool.dart';

export 'image_source.dart' show ImagePicker, PickedImage, imagePickerProvider;

/// Overrides how stored pictures are read (tests serve bytes from memory).
/// Null reads the file the repository's `assetPath` names.
final assetBytesLoaderProvider = Provider<AssetBytesLoader?>((ref) => null);

/// Text boxes and pictures: the text tool, the image tool, the layers that
/// paint both on pages and thumbnails, and their page overlays.
final EditorIntegration textImagesIntegration = _install;

void _install(EditorController controller, WidgetRef ref) {
  final textEditor = TextBoxEditor(controller);
  final imageEditor = ImageEditor(controller, ref.read(imagePickerProvider));

  final customLoader = ref.read(assetBytesLoaderProvider);
  Future<Uint8List?> loadFromRepository(String notebookId, String asset) async {
    final file = File(controller.repository.assetPath(notebookId, asset));
    return await file.exists() ? await file.readAsBytes() : null;
  }

  final imageLayer = ImageLayerPainter(
    loadBytes: customLoader ?? loadFromRepository,
    onReady: controller.invalidatePageRender,
    hiddenId: imageEditor.draggedIdOn,
  );

  final ext = controller.extensions;
  ext.textLayer = TextLayerPainter(
    hiddenId: textEditor.editingIdOn,
    showCorrections: () => controller.settings.autocorrect,
  );
  ext.imageLayer = imageLayer;
  ext.toolHandlers[EditorTool.text] = TextToolHandler(controller, textEditor);
  // The lasso menu's Edit: the text tool, editing that box.
  ext.editText = (pageId, item) {
    controller.selectTool(EditorTool.text);
    textEditor.begin(pageId, item);
  };
  ext.toolHandlers[EditorTool.image] = ImageToolHandler(controller, imageEditor);
  ext.toolOptions[EditorTool.text] =
      (context, c) => TextFormatBar(editor: textEditor, controller: c);
  ext.toolOptions[EditorTool.image] =
      (context, c) => ImageOptions(editor: imageEditor);
  ext.pageOverlays
    ..add(imagePageOverlay(imageEditor, imageLayer))
    ..add(textPageOverlay(textEditor));

  controller.addDisposeCallback(() {
    textEditor.dispose();
    imageEditor.dispose();
    imageLayer.dispose();
  });
}

/// Tool-row options of the image tool: insert a picture, delete the
/// selected one.
class ImageOptions extends StatelessWidget {
  const ImageOptions({super.key, required this.editor});

  final ImageEditor editor;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: editor,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.tonalIcon(
              key: const ValueKey('image-insert'),
              onPressed: editor.busy ? null : () => _insert(context),
              icon: editor.busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Insert picture'),
            ),
            if (editor.selection != null) ...[
              const SizedBox(width: 8),
              IconButton(
                key: const ValueKey('image-delete'),
                tooltip: 'Delete picture',
                onPressed: editor.deleteSelected,
                icon: Icon(Icons.delete_outline, color: scheme.error),
              ),
            ] else
              const Padding(
                padding: EdgeInsets.only(left: 12),
                child: Text('Tap a picture to move or resize it'),
              ),
          ],
        );
      },
    );
  }

  Future<void> _insert(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final message = await editor.insert();
    if (message != null) {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
