/// Static facts about the app shown in Settings › About and the license page.
///
/// Keep [version] and [buildNumber] in sync with `version:` in pubspec.yaml
/// (`1.14.0+17` → version `1.14.0`, build `17`).
abstract final class AppInfo {
  static const String name = "Mariam's Notes";
  static const String version = '1.14.0';
  static const int buildNumber = 17;

  /// Version as shown to the user, e.g. "1.4.0 (build 6)".
  static const String displayVersion = '$version (build $buildNumber)';

  static const String tagline = 'Handwritten notes, typed up beautifully.';

  /// The newest release's APK (arm64, the MatePad's). Settings › About ›
  /// Get the newest version opens it in the browser; the app itself never
  /// goes online.
  static const String downloadUrl =
      'https://github.com/MalekBaghdadi/NeatInk/releases/latest/download/MariamsNotes.apk';

  static const String offlineStatement =
      '100% offline: no internet permission, no accounts, no tracking';

  static const String legalese =
      'Your notebooks, kept corrections and diagnostics never leave this '
      'device unless you export, back up or share them yourself. '
      "Mariam's Notes is built with open-source software; see the licenses below.";
}
