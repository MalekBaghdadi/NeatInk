/// Static facts about the app shown in Settings › About and the license page.
///
/// Keep [version] and [buildNumber] in sync with `version:` in pubspec.yaml
/// (`1.10.0+12` → version `1.10.0`, build `12`).
abstract final class AppInfo {
  static const String name = "Mariam's Notes";
  static const String version = '1.10.0';
  static const int buildNumber = 12;

  /// Version as shown to the user, e.g. "1.4.0 (build 6)".
  static const String displayVersion = '$version (build $buildNumber)';

  static const String tagline = 'Handwritten notes, typed up beautifully.';

  static const String offlineStatement =
      '100% offline: no internet permission, no accounts, no tracking';

  static const String legalese =
      'Your notebooks, kept corrections and diagnostics never leave this '
      'device unless you export, back up or share them yourself. '
      "Mariam's Notes is built with open-source software; see the licenses below.";
}
