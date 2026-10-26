/// Validation for every name the storage layer turns into a file path.
///
/// Ids come from JSON files and other code; a crafted id such as `../x`
/// must never escape the notebook folder. Only the character set of a UUID
/// (plus `_`) is accepted, so ids can never contain path separators, dots
/// or drive letters.
library;

final RegExp _idPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$');
final RegExp _assetPattern =
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}(\.[a-z0-9]{1,8})?$');

/// True when [id] is safe to use as a file or folder name: 1–64 characters
/// of `[A-Za-z0-9_-]`, starting with a letter or digit. UUIDs qualify.
bool isValidStorageId(String id) => _idPattern.hasMatch(id);

/// Returns [id] unchanged, or throws [ArgumentError] if it is not a valid
/// storage id (see [isValidStorageId]).
String checkStorageId(String id, [String name = 'id']) {
  if (!isValidStorageId(id)) {
    throw ArgumentError.value(id, name, 'Not a valid storage id');
  }
  return id;
}

/// True when [name] is a valid asset file name: a storage id optionally
/// followed by a short lowercase extension, e.g. `3f2a…c1.png`.
bool isValidAssetName(String name) => _assetPattern.hasMatch(name);

/// Returns [name] unchanged, or throws [ArgumentError] if it is not a valid
/// asset file name.
String checkAssetName(String name) {
  if (!isValidAssetName(name)) {
    throw ArgumentError.value(name, 'asset', 'Not a valid asset name');
  }
  return name;
}

/// Turns a user-supplied extension (`.JPG`, `png`, `tar.gz`, ``) into a
/// safe lowercase one of at most 8 characters, or `bin` if nothing usable
/// is left.
String sanitizeExtension(String extension) {
  var e = extension.trim().toLowerCase();
  final dot = e.lastIndexOf('.');
  if (dot >= 0) e = e.substring(dot + 1);
  e = e.replaceAll(RegExp('[^a-z0-9]'), '');
  if (e.length > 8) e = e.substring(0, 8);
  return e.isEmpty ? 'bin' : e;
}
