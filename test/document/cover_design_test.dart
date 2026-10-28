import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/cover_design.dart';
import 'package:neatink/document/notebook_meta.dart';

void main() {
  test('every design survives a JSON round trip', () {
    final designs = [
      const CoverDesign.preview(),
      for (final p in CoverPattern.values) CoverDesign.pattern(p),
      for (final a in CoverArt.values) CoverDesign.art(a),
      const CoverDesign.photo('1b2c.jpg'),
    ];
    for (final d in designs) {
      expect(CoverDesign.fromJson(d.toJson()), d, reason: '$d');
    }
  });

  test('anything unknown or unsafe reads as the page-preview cover', () {
    const preview = CoverDesign.preview();
    expect(CoverDesign.fromJson(null), preview);
    expect(CoverDesign.fromJson('art'), preview);
    expect(CoverDesign.fromJson(const {'kind': 'hologram'}), preview);
    expect(CoverDesign.fromJson(const {'kind': 'art', 'art': 'unicorn'}), preview);
    expect(CoverDesign.fromJson(const {'kind': 'photo'}), preview);
    expect(CoverDesign.fromJson(const {'kind': 'photo', 'photo': '../../secret.png'}), preview);
    expect(CoverDesign.fromJson(const {'kind': 'photo', 'photo': r'a\b.png'}), preview);
    // An unknown pattern keeps the colour cover, plain.
    expect(CoverDesign.fromJson(const {'kind': 'pattern', 'pattern': 'plaid'}),
        const CoverDesign.pattern(CoverPattern.plain));
  });

  test('every subject has pictures, and every picture a subject', () {
    for (final s in CoverSubject.values) {
      expect(s.arts, isNotEmpty, reason: s.label);
    }
    expect([for (final s in CoverSubject.values) ...s.arts], unorderedEquals(CoverArt.values));
  });

  test('notebook.json keeps the cover, and omits the default one', () {
    final meta = NotebookMeta(
        id: 'n',
        title: 'Bio',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        cover: const CoverDesign.art(CoverArt.dna));
    final json = meta.toJson();
    expect(json['cover'], {'kind': 'art', 'art': 'dna'});
    expect(NotebookMeta.fromJson(json).cover, const CoverDesign.art(CoverArt.dna));
    expect(meta.copyWith(title: 'Biology').cover, const CoverDesign.art(CoverArt.dna));

    final plain = meta.copyWith(cover: const CoverDesign.preview()).toJson();
    expect(plain.containsKey('cover'), isFalse);
    // Notebooks saved before covers existed load with the preview cover.
    expect(NotebookMeta.fromJson(plain).cover, const CoverDesign.preview());
  });

  test('a photo hides the colour', () {
    expect(const CoverDesign.photo('a.png').usesColor, isFalse);
    expect(const CoverDesign.art(CoverArt.atom).usesColor, isTrue);
    expect(const CoverDesign.preview().usesColor, isTrue);
  });
}
