/// Static facts about the app shown in Settings › About and the license page.
///
/// Keep [version] and [buildNumber] in sync with `version:` in pubspec.yaml
/// (`1.2.0+3` → version `1.2.0`, build `3`).
abstract final class AppInfo {
  static const String name = "Mariam's Notes";
  static const String version = '1.2.0';
  static const int buildNumber = 3;

  /// Version as shown to the user, e.g. "1.2.0 (build 3)".
  static const String displayVersion = '$version (build $buildNumber)';

  static const String tagline = 'Handwritten notes, typed up beautifully.';

  static const String offlineStatement =
      '100% offline: no internet permission, no accounts, no tracking';

  static const String legalese =
      'Your notebooks never leave this device. '
      "Mariam's Notes is built with open-source software; see the licenses below.";
}
