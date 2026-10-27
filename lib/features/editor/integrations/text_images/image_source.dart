import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../lock/auto_lock_suspension.dart';

/// A picture chosen by the user, as raw file bytes.
class PickedImage {
  const PickedImage(this.bytes, {this.name = ''});
  final Uint8List bytes;
  final String name;
}

/// Lets the user choose a picture; null when they cancel. Behind
/// [imagePickerProvider] so tests can supply bytes without a system dialog.
typedef ImagePicker = Future<PickedImage?> Function();

/// Opens the system picker filtered to pictures. The app lock is relaxed
/// while it is open (the picker moves NeatInk to the background).
Future<PickedImage?> pickImageWithSystemPicker() async {
  final file = await AutoLockSuspension.during<PlatformFile?>(
    () => FilePicker.pickFile(type: FileType.image),
  );
  if (file == null) return null;
  try {
    final path = file.path;
    final bytes = path != null
        ? await File(path).readAsBytes()
        : await file.readAsBytes();
    return PickedImage(bytes, name: file.name);
  } finally {
    try {
      await FilePicker.clearTemporaryFiles();
    } catch (e) {
      debugPrint('NeatInk: could not clear picker cache: $e');
    }
  }
}

final imagePickerProvider =
    Provider<ImagePicker>((ref) => pickImageWithSystemPicker);

/// Loads the bytes of a stored picture (`null` when missing); the image
/// layer decodes them. Behind a provider so tests need no files.
typedef AssetBytesLoader = Future<Uint8List?> Function(
    String notebookId, String asset);
