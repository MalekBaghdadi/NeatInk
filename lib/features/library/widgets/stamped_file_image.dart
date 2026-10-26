import 'package:flutter/painting.dart';

/// A [FileImage] whose cache identity includes a [stamp] (e.g. derived from
/// the file's modification time).
///
/// A plain [FileImage] is cached by path, so after the editor rewrites
/// `thumb.png` the library would keep showing the old cover. With the stamp
/// in the key, a rewritten file is a new cache entry; the stale one ages out
/// of the image cache on its own.
class StampedFileImage extends FileImage {
  const StampedFileImage(super.file, this.stamp, {super.scale});

  final int stamp;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is StampedFileImage &&
      other.file.path == file.path &&
      other.scale == scale &&
      other.stamp == stamp;

  @override
  int get hashCode => Object.hash(file.path, scale, stamp);

  @override
  String toString() => 'StampedFileImage("${file.path}", stamp: $stamp)';
}
