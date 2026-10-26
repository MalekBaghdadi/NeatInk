/// Static facts about the app shown in Settings › About and the license page.
///
/// Keep [version] and [buildNumber] in sync with `version:` in pubspec.yaml
/// (`1.0.0+1` → version `1.0.0`, build `1`).
abstract final class AppInfo {
  static const String name = 'NeatInk';
  static const String version = '1.0.0';
  static const int buildNumber = 1;

  /// Version as shown to the user, e.g. "1.0.0 (build 1)".
  static const String displayVersion = '$version (build $buildNumber)';

  static const String tagline = 'Handwritten notes, tidy as you write.';

  static const String offlineStatement =
      '100% offline: no internet permission, no accounts, no tracking';

  static const String legalese =
      'Your notebooks never leave this device. '
      'NeatInk is built with open-source software; see the licenses below.';
}
