import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/page_items.dart';

/// The project root, also when the tests run from the mirror project whose
/// `lib` is a link to the real one.
Directory projectRoot() {
  final dir = Directory.current;
  if (Directory('${dir.path}/assets/fonts').existsSync()) return dir;
  final lib = Link('${dir.path}/lib');
  if (lib.existsSync()) {
    return Directory(lib.resolveSymbolicLinksSync()).parent;
  }
  return dir;
}

void main() {
  group('FontKind registry', () {
    test('ids are unique and every id resolves to its font', () {
      final ids = FontKind.values.map((f) => f.name).toList();
      expect(ids.toSet().length, ids.length);
      for (final f in FontKind.values) {
        expect(FontKind.byName(f.name), same(f));
      }
      expect(FontKind.values.length, greaterThanOrEqualTo(18));
    });

    test('the old ids map to Roboto, Tinos and Roboto Mono', () {
      expect(FontKind.byName('sans'), same(FontKind.sans));
      expect(FontKind.byName('serif'), same(FontKind.serif));
      expect(FontKind.byName('mono'), same(FontKind.mono));
      expect(FontKind.sans.label, 'Roboto');
      expect(FontKind.serif.label, startsWith('Tinos'));
      expect(FontKind.mono.label, 'Roboto Mono');
      expect(FontKind.sans.name, 'sans');
    });

    test('unknown or missing ids fall back to sans', () {
      expect(FontKind.byName(null), same(FontKind.sans));
      expect(FontKind.byName(''), same(FontKind.sans));
      expect(FontKind.byName('comic sans ms'), same(FontKind.sans));
    });

    test('families and labels are unique and every category is used', () {
      expect(FontKind.values.map((f) => f.family).toSet().length,
          FontKind.values.length);
      expect(FontKind.values.map((f) => f.label).toSet().length,
          FontKind.values.length);
      for (final c in FontCategory.values) {
        expect(FontKind.inCategory(c), isNotEmpty, reason: c.label);
      }
      // values are grouped by category, in category order.
      final order = [for (final f in FontKind.values) f.category.index];
      expect(order, [...order]..sort());
      expect(FontCategory.school.label, 'School & easy reading');
    });

    test('resolveFile picks the exact style, else the closest', () {
      final bi = FontKind.sans.resolveFile(bold: true, italic: true);
      expect(bi.bold && bi.italic, isTrue);
      expect(bi.asset, 'assets/fonts/Roboto/Roboto-BoldItalic.ttf');
      // Lexend has Regular and Bold only: italic falls back to upright.
      final lexItalic = FontKind.lexend.resolveFile(italic: true);
      expect(lexItalic.asset, endsWith('Lexend-Regular.ttf'));
      final lexBoldItalic =
          FontKind.lexend.resolveFile(bold: true, italic: true);
      expect(lexBoldItalic.bold, isTrue);
      expect(lexBoldItalic.italic, isFalse);
      // Patrick Hand only has Regular.
      expect(FontKind.patrickHand.resolveFile(bold: true).asset,
          endsWith('PatrickHand-Regular.ttf'));
      expect(FontKind.patrickHand.hasBold, isFalse);
      expect(FontKind.sans.hasBold && FontKind.sans.hasItalic, isTrue);
    });

    test('every font file and licence exists and is declared in pubspec', () {
      final root = projectRoot();
      final pubspecFile = File('${root.path}/pubspec.yaml');
      if (!pubspecFile.existsSync() ||
          !Directory('${root.path}/assets/fonts').existsSync()) {
        markTestSkipped('project root not found from ${Directory.current}');
        return;
      }
      final pubspec = pubspecFile.readAsStringSync();
      for (final f in FontKind.values) {
        expect(pubspec, contains('family: ${f.family}'), reason: f.name);
        expect(File('${root.path}/${f.licenseAsset}').existsSync(), isTrue,
            reason: f.licenseAsset);
        expect(pubspec, contains(f.licenseAsset));
        for (final file in f.files) {
          final disk = File('${root.path}/${file.asset}');
          expect(disk.existsSync(), isTrue, reason: file.asset);
          // A real TrueType file (not a variable font stub).
          final head = disk.openSync().readSync(4);
          expect(head, [0, 1, 0, 0], reason: file.asset);
          expect(pubspec, contains('asset: ${file.asset}'));
        }
      }
    });

    test('total font payload stays small', () {
      final root = projectRoot();
      if (!Directory('${root.path}/assets/fonts').existsSync()) {
        markTestSkipped('project root not found');
        return;
      }
      var bytes = 0;
      for (final e in Directory('${root.path}/assets/fonts')
          .listSync(recursive: true)
          .whereType<File>()) {
        bytes += e.lengthSync();
      }
      expect(bytes, lessThan(12 * 1024 * 1024));
    });
  });

  group('TextItem font JSON', () {
    TextItem item(FontKind f) => TextItem(
        id: 't', x: 1, y: 2, width: 100, height: 20, text: 'x', font: f);

    test('every font survives a JSON round trip', () {
      for (final f in FontKind.values) {
        final json = jsonDecode(jsonEncode(item(f).toJson()))
            as Map<String, dynamic>;
        expect(json['font'], f.name);
        expect(TextItem.fromJson(json).font, same(f));
      }
    });

    test('old documents with sans, serif and mono keep their fonts', () {
      for (final (id, kind) in [
        ('sans', FontKind.sans),
        ('serif', FontKind.serif),
        ('mono', FontKind.mono),
      ]) {
        final j = item(FontKind.sans).toJson()..['font'] = id;
        expect(TextItem.fromJson(j).font, same(kind));
      }
    });

    test('unknown, missing or malformed font ids load as sans', () {
      final base = item(FontKind.lora).toJson();
      expect(
          TextItem.fromJson(base..['font'] = 'wingdings').font, FontKind.sans);
      expect(TextItem.fromJson(base..remove('font')).font, FontKind.sans);
      expect(TextItem.fromJson(base..['font'] = 42).font, FontKind.sans);
    });
  });
}
