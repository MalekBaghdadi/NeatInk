import '../document/notebook_meta.dart';

/// Parses `library.json`, migrating older versions first.
LibraryIndex libraryFromJson(Map<String, dynamic> json) =>
    LibraryIndex.fromJson(migrateLibraryJson(json));

/// Upgrades a `library.json` map to [LibraryIndex.currentVersion].
///
/// Version 1 is the first format, so this only checks the version today.
/// Add a `case` per future version bump; never drop folders that
/// notebooks still point at.
Map<String, dynamic> migrateLibraryJson(Map<String, dynamic> j) {
  final version = (j['version'] as num?)?.toInt() ?? 1;
  if (version > LibraryIndex.currentVersion) {
    throw FormatException(
        'Library file version $version is newer than this app supports');
  }
  return j;
}
