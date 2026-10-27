/// The fonts a typed text box can use: a small registry of bundled, static
/// TrueType families (Regular / Bold / Italic / Bold Italic where the family
/// has them). The same files are used on screen (declared in `pubspec.yaml`)
/// and embedded in exported PDFs (loaded by the Kotlin exporter from the
/// Flutter assets), so the page looks the same in both.
///
/// Files live in `assets/fonts/<directory>/` with the family's SIL OFL
/// licence text next to them.
///
/// Ids ([FontKind.name]) are what the notebook JSON stores. The three
/// original ids keep working: `sans` is Roboto, `serif` is Tinos and `mono`
/// is Roboto Mono. An unknown id resolves to `sans` ([FontKind.byName]).
library;

/// How the font picker groups families.
enum FontCategory {
  sans('Sans'),
  serif('Serif'),
  mono('Mono'),
  school('School & easy reading'),
  handwriting('Handwriting');

  const FontCategory(this.label);

  /// Heading shown in the font picker.
  final String label;
}

/// Which files a family ships.
enum FontStyles {
  /// Regular only.
  regularOnly([('Regular', false, false)]),

  /// Regular and Bold.
  regularBold([('Regular', false, false), ('Bold', true, false)]),

  /// Regular, Bold, Italic and Bold Italic.
  all([
    ('Regular', false, false),
    ('Bold', true, false),
    ('Italic', false, true),
    ('BoldItalic', true, true),
  ]);

  const FontStyles(this._variants);
  final List<(String, bool, bool)> _variants;
}

/// One font file of a family: a weight/slant combination.
class FontFile {
  const FontFile(this.asset, {this.bold = false, this.italic = false});

  /// Flutter asset path, e.g. `assets/fonts/Roboto/Roboto-Bold.ttf`.
  final String asset;
  final bool bold;
  final bool italic;

  /// CSS-style weight number (400 or 700).
  int get weight => bold ? 700 : 400;

  @override
  String toString() => 'FontFile($asset)';
}

/// A bundled font family. Instances are compile-time constants, so they can
/// be compared with `==` / `identical`; resolve a stored id with [byName].
class FontKind {
  const FontKind._(
    this.name,
    this.label,
    this.category,
    this.family,
    this.directory,
    this.styles,
  );

  /// Stable id stored in notebook JSON and sent to the PDF exporter.
  final String name;

  /// Name shown in the font picker.
  final String label;
  final FontCategory category;

  /// The family name declared in `pubspec.yaml` (`TextStyle.fontFamily`).
  final String family;

  /// Folder under `assets/fonts/` holding the files and `OFL.txt`.
  final String directory;

  /// Which weights/slants the family ships.
  final FontStyles styles;

  /// Available files (Regular first), named `<directory>-<Style>.ttf`.
  List<FontFile> get files => [
        for (final (suffix, bold, italic) in styles._variants)
          FontFile('assets/fonts/$directory/$directory-$suffix.ttf',
              bold: bold, italic: italic),
      ];

  /// Licence name (all bundled fonts are SIL OFL 1.1).
  String get license => 'SIL Open Font License 1.1';

  /// Asset path of the family's licence text.
  String get licenseAsset => 'assets/fonts/$directory/OFL.txt';

  bool get hasBold => files.any((f) => f.bold);
  bool get hasItalic => files.any((f) => f.italic);

  /// The file with exactly this weight and slant, or null.
  FontFile? exactFile({bool bold = false, bool italic = false}) {
    for (final f in files) {
      if (f.bold == bold && f.italic == italic) return f;
    }
    return null;
  }

  /// The best available file for the requested style: the exact one if the
  /// family has it, otherwise the closest (keeping bold in preference to
  /// italic, then the other way, then Regular). The caller can compare the
  /// result's [FontFile.bold] / [FontFile.italic] with what it asked for to
  /// know whether the style has to be faked.
  FontFile resolveFile({bool bold = false, bool italic = false}) =>
      exactFile(bold: bold, italic: italic) ??
      (bold ? exactFile(bold: true, italic: false) : null) ??
      (italic ? exactFile(bold: false, italic: true) : null) ??
      exactFile() ??
      files.first;

  // --- registry ----------------------------------------------------------

  /// Roboto (the original `sans`).
  static const sans = FontKind._('sans', 'Roboto', FontCategory.sans,
      'NI-Roboto', 'Roboto', FontStyles.all);
  static const openSans = FontKind._('open_sans', 'Open Sans',
      FontCategory.sans, 'NI-OpenSans', 'OpenSans',
      FontStyles.all);
  static const lato = FontKind._('lato', 'Lato', FontCategory.sans, 'NI-Lato',
      'Lato', FontStyles.all);
  static const nunito = FontKind._('nunito', 'Nunito', FontCategory.sans,
      'NI-Nunito', 'Nunito', FontStyles.all);
  static const arimo = FontKind._('arimo', 'Arimo (Arial-like)',
      FontCategory.sans, 'NI-Arimo', 'Arimo', FontStyles.all);

  /// Tinos, metric-compatible with Times New Roman (the original `serif`).
  static const serif = FontKind._('serif', 'Tinos (Times-like)',
      FontCategory.serif, 'NI-Tinos', 'Tinos', FontStyles.all);
  static const merriweather = FontKind._('merriweather', 'Merriweather',
      FontCategory.serif, 'NI-Merriweather', 'Merriweather',
      FontStyles.all);
  static const lora = FontKind._('lora', 'Lora', FontCategory.serif,
      'NI-Lora', 'Lora', FontStyles.all);
  static const libreBaskerville = FontKind._(
      'libre_baskerville',
      'Libre Baskerville',
      FontCategory.serif,
      'NI-LibreBaskerville',
      'LibreBaskerville',
      FontStyles.all);

  /// Roboto Mono (the original `mono`).
  static const mono = FontKind._('mono', 'Roboto Mono', FontCategory.mono,
      'NI-RobotoMono', 'RobotoMono', FontStyles.all);

  static const lexend = FontKind._('lexend', 'Lexend', FontCategory.school,
      'NI-Lexend', 'Lexend', FontStyles.regularBold);
  static const atkinson = FontKind._(
      'atkinson',
      'Atkinson Hyperlegible',
      FontCategory.school,
      'NI-AtkinsonHyperlegible',
      'AtkinsonHyperlegible',
      FontStyles.all);
  static const comicNeue = FontKind._('comic_neue', 'Comic Neue',
      FontCategory.school, 'NI-ComicNeue', 'ComicNeue',
      FontStyles.all);

  static const caveat = FontKind._('caveat', 'Caveat',
      FontCategory.handwriting, 'NI-Caveat', 'Caveat',
      FontStyles.regularBold);
  static const patrickHand = FontKind._('patrick_hand', 'Patrick Hand',
      FontCategory.handwriting, 'NI-PatrickHand', 'PatrickHand',
      FontStyles.regularOnly);
  static const kalam = FontKind._('kalam', 'Kalam', FontCategory.handwriting,
      'NI-Kalam', 'Kalam', FontStyles.regularBold);
  static const indieFlower = FontKind._('indie_flower', 'Indie Flower',
      FontCategory.handwriting, 'NI-IndieFlower', 'IndieFlower',
      FontStyles.regularOnly);
  static const dancingScript = FontKind._('dancing_script', 'Dancing Script',
      FontCategory.handwriting, 'NI-DancingScript', 'DancingScript',
      FontStyles.regularBold);

  /// Every font, grouped by category in picker order.
  static const List<FontKind> values = [
    sans, openSans, lato, nunito, arimo, //
    serif, merriweather, lora, libreBaskerville, //
    mono, //
    lexend, atkinson, comicNeue, //
    caveat, patrickHand, kalam, indieFlower, dancingScript,
  ];

  /// The font with id [name]; `sans` for null or unknown ids.
  static FontKind byName(String? name) {
    for (final f in values) {
      if (f.name == name) return f;
    }
    return sans;
  }

  /// The fonts of [category], in picker order.
  static List<FontKind> inCategory(FontCategory category) =>
      [for (final f in values) if (f.category == category) f];

  @override
  String toString() => 'FontKind($name)';
}

