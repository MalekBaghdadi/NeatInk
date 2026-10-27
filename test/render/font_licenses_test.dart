import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/page_items.dart';
import 'package:neatink/render/font_licenses.dart';

class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.files);
  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final text = files[key];
    if (text == null) throw FlutterError('Unable to load asset: $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
  }
}

void main() {
  test('every bundled font family gets one licence entry', () async {
    final bundle = _FakeBundle({
      for (final f in FontKind.values)
        f.licenseAsset: 'Copyright ${f.label}\nSIL OPEN FONT LICENSE',
    });
    final entries = await fontLicenseEntries(bundle).toList();
    expect(entries, hasLength(FontKind.values.length));
    final names = entries.expand((e) => e.packages).toSet();
    for (final f in FontKind.values) {
      expect(names, contains('${f.label} (font)'));
    }
    expect(entries.first.paragraphs.first.text, startsWith('Copyright'));
  });

  test('a missing licence file is skipped, not fatal', () async {
    final bundle = _FakeBundle({FontKind.lora.licenseAsset: 'Lora licence'});
    final entries = await fontLicenseEntries(bundle).toList();
    expect(entries, hasLength(1));
    expect(entries.single.packages, ['Lora (font)']);
  });
}
