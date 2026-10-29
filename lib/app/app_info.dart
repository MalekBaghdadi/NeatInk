/// Static facts about the app shown in Settings › About and the license page.
///
/// Keep [version] and [buildNumber] in sync with `version:` in pubspec.yaml
/// (`1.7.0+9` → version `1.7.0`, build `9`).
abstract final class AppInfo {
  static const String name = "Mariam's Notes";
  static const String version = '1.7.0';
  static const int buildNumber = 9;

  /// Version as shown to the user, e.g. "1.4.0 (build 6)".
  static const String displayVersion = '$version (build $buildNumber)';

  static const String tagline = 'Handwritten notes, typed up beautifully.';

  static const String offlineStatement =
      '100% offline: no internet permission, no accounts, no tracking';

  static const String legalese =
      'Your notebooks never leave this device unless you export or back them '
      'up yourself. '
      "Mariam's Notes is built with open-source software; see the licenses below.";
}
