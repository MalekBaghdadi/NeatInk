import 'dart:typed_data';

import '../ink/stroke.dart' show enumByName;

/// What a notebook's cover shows in the library.
enum CoverKind {
  /// The cover colour as a frame around a preview of the first page (the
  /// look before covers could be designed; the default).
  preview,

  /// The cover colour, plain or with a [CoverPattern].
  pattern,

  /// The cover colour with a science illustration ([CoverArt]).
  art,

  /// A picture from the device, stored as a notebook asset.
  photo,
}

/// Patterns drawn over the cover colour.
enum CoverPattern {
  plain('Plain'),
  stripes('Stripes'),
  dots('Dots'),
  grid('Grid'),
  chevron('Chevron'),
  waves('Waves'),
  diamonds('Diamonds'),
  hexagons('Hexagons'),
  linen('Linen');

  const CoverPattern(this.label);
  final String label;
}

/// The subjects the science covers are grouped by.
enum CoverSubject {
  neuroscience('Neuroscience & psychology'),
  biology('Biology & medicine'),
  chemistryPhysics('Chemistry & physics'),
  spaceMaths('Space & maths');

  const CoverSubject(this.label);
  final String label;

  List<CoverArt> get arts => [for (final a in CoverArt.values) if (a.subject == this) a];
}

/// Science illustrations, drawn in code (`lib/render/cover_painter.dart`).
enum CoverArt {
  brain(CoverSubject.neuroscience, 'Brain'),
  neuron(CoverSubject.neuroscience, 'Neuron'),
  synapse(CoverSubject.neuroscience, 'Synapse'),
  network(CoverSubject.neuroscience, 'Neural network'),
  dna(CoverSubject.biology, 'DNA'),
  cell(CoverSubject.biology, 'Cell'),
  heartbeat(CoverSubject.biology, 'Heartbeat'),
  microbes(CoverSubject.biology, 'Microscope view'),
  atom(CoverSubject.chemistryPhysics, 'Atom'),
  molecules(CoverSubject.chemistryPhysics, 'Molecules'),
  periodic(CoverSubject.chemistryPhysics, 'Periodic table'),
  waves(CoverSubject.chemistryPhysics, 'Waves'),
  planets(CoverSubject.spaceMaths, 'Planets'),
  galaxy(CoverSubject.spaceMaths, 'Galaxy'),
  geometry(CoverSubject.spaceMaths, 'Geometry'),
  equations(CoverSubject.spaceMaths, 'Equations');

  const CoverArt(this.subject, this.label);
  final CoverSubject subject;
  final String label;
}

/// The design of a notebook cover (`cover` in `notebook.json`); the colour
/// is `NotebookMeta.coverColor`. Immutable.
class CoverDesign {
  const CoverDesign.preview()
      : kind = CoverKind.preview,
        pattern = null,
        art = null,
        photo = null;

  const CoverDesign.pattern(CoverPattern this.pattern)
      : kind = CoverKind.pattern,
        art = null,
        photo = null;

  const CoverDesign.art(CoverArt this.art)
      : kind = CoverKind.art,
        pattern = null,
        photo = null;

  /// [photo] is the asset file name of the picture in the notebook folder.
  const CoverDesign.photo(String this.photo)
      : kind = CoverKind.photo,
        pattern = null,
        art = null;

  /// Reads `cover`; anything unknown or broken gives [CoverDesign.preview].
  factory CoverDesign.fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return const CoverDesign.preview();
    switch (j['kind']) {
      case 'pattern':
        return CoverDesign.pattern(enumByName(CoverPattern.values, j['pattern'], CoverPattern.plain));
      case 'art':
        for (final a in CoverArt.values) {
          if (a.name == j['art']) return CoverDesign.art(a);
        }
        return const CoverDesign.preview();
      case 'photo':
        final photo = j['photo'];
        return photo is String && photo.isNotEmpty && !photo.contains('/') && !photo.contains('\\')
            ? CoverDesign.photo(photo)
            : const CoverDesign.preview();
      default:
        return const CoverDesign.preview();
    }
  }

  final CoverKind kind;
  final CoverPattern? pattern;
  final CoverArt? art;
  final String? photo;

  /// The colour shows (everything but a photo).
  bool get usesColor => kind != CoverKind.photo;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        if (pattern != null) 'pattern': pattern!.name,
        if (art != null) 'art': art!.name,
        if (photo != null) 'photo': photo,
      };

  @override
  bool operator ==(Object other) =>
      other is CoverDesign && other.kind == kind && other.pattern == pattern && other.art == art && other.photo == photo;

  @override
  int get hashCode => Object.hash(kind, pattern, art, photo);

  @override
  String toString() => 'CoverDesign(${toJson()})';
}

/// A cover picked in the cover sheet: the design and colour, plus a photo
/// the user just chose ([photoBytes], not stored yet; [design] is then a
/// photo design whose asset name is filled in when the bytes are stored).
class CoverChoice {
  const CoverChoice({required this.design, required this.color, this.photoBytes, this.photoExtension = 'png'});

  final CoverDesign design;
  final int color;
  final Uint8List? photoBytes;
  final String photoExtension;
}
