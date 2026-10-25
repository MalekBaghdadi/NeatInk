import '../ink/stroke.dart';
import 'page_items.dart';

/// Everything drawn or placed on one page. Stored as `pages/<pageId>.json`.
///
/// Paint order (bottom to top): paper / PDF background → [images] →
/// highlighter strokes → [texts] → pen strokes. Within each group, list order
/// is paint order.
///
/// The lists are mutable, but only [EditCommand]s may change them (the UI
/// never mutates directly). Every mutation must call [touch] so renderers and
/// autosave notice.
class PageContent {
  PageContent({
    List<Stroke>? strokes,
    List<TextItem>? texts,
    List<ImageItem>? images,
  })  : strokes = strokes ?? [],
        texts = texts ?? [],
        images = images ?? [];

  /// Parses a page file. Older versions are migrated by [migratePageJson].
  factory PageContent.fromJson(Map<String, dynamic> json) {
    final j = migratePageJson(json);
    return PageContent(
      strokes: [
        for (final s in (j['strokes'] as List<dynamic>? ?? const []))
          Stroke.fromJson(s as Map<String, dynamic>),
      ],
      texts: [
        for (final t in (j['texts'] as List<dynamic>? ?? const []))
          TextItem.fromJson(t as Map<String, dynamic>),
      ],
      images: [
        for (final i in (j['images'] as List<dynamic>? ?? const []))
          ImageItem.fromJson(i as Map<String, dynamic>),
      ],
    );
  }

  static const int currentVersion = 1;

  final List<Stroke> strokes;
  final List<TextItem> texts;
  final List<ImageItem> images;

  /// Bumped on every change. Renderers compare it to decide when to rebuild
  /// cached pictures; autosave uses it to find dirty pages.
  int revision = 0;

  void touch() => revision++;

  bool get isEmpty => strokes.isEmpty && texts.isEmpty && images.isEmpty;

  int indexOfStroke(String id) => strokes.indexWhere((s) => s.id == id);

  Stroke? strokeById(String id) {
    final i = indexOfStroke(id);
    return i < 0 ? null : strokes[i];
  }

  TextItem? textById(String id) {
    for (final t in texts) {
      if (t.id == id) return t;
    }
    return null;
  }

  ImageItem? imageById(String id) {
    for (final i in images) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// A deep-enough copy: the lists are new, the immutable items are shared.
  PageContent copy() => PageContent(
        strokes: List.of(strokes),
        texts: List.of(texts),
        images: List.of(images),
      );

  Map<String, dynamic> toJson() => {
        'version': currentVersion,
        'strokes': [for (final s in strokes) s.toJson()],
        'texts': [for (final t in texts) t.toJson()],
        'images': [for (final i in images) i.toJson()],
      };
}

/// Upgrades a page JSON map to [PageContent.currentVersion].
///
/// Version 1 is the first format, so this only fills in a missing version
/// today. Add a `case` per future version bump; never drop old fields that
/// still hold user ink.
Map<String, dynamic> migratePageJson(Map<String, dynamic> j) {
  final version = (j['version'] as num?)?.toInt() ?? 1;
  if (version > PageContent.currentVersion) {
    throw FormatException(
        'Page file version $version is newer than this app supports');
  }
  return j;
}
