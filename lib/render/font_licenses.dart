import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../document/font_kind.dart';

/// Lists the licence text of every bundled font on Flutter's licence page
/// (Settings > Open-source licenses).
///
/// Each family's `OFL.txt` (declared as an asset in `pubspec.yaml`) becomes
/// one entry named "<label> (font)". The texts are read lazily, only when
/// the licence page is opened. A missing file is skipped rather than
/// failing the whole page.
///
/// Call once at startup; repeated calls (without a custom [bundle]) are
/// ignored so the licences are never listed twice.
void registerFontLicenses({AssetBundle? bundle}) {
  if (bundle == null) {
    if (_registered) return;
    _registered = true;
  }
  LicenseRegistry.addLicense(() => fontLicenseEntries(bundle ?? rootBundle));
}

bool _registered = false;

/// One licence entry per bundled font family, read from [bundle].
Stream<LicenseEntry> fontLicenseEntries(AssetBundle bundle) async* {
  // Several registry entries can share a directory (none today, but the
  // licence file is per directory); list each file once.
  final seen = <String>{};
  for (final font in FontKind.values) {
    if (!seen.add(font.licenseAsset)) continue;
    String text;
    try {
      text = await bundle.loadString(font.licenseAsset);
    } catch (_) {
      continue;
    }
    yield LicenseEntryWithLineBreaks(['${font.label} (font)'], text);
  }
}
