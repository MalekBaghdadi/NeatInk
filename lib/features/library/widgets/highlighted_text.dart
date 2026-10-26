import 'package:flutter/material.dart';

import '../search_results.dart';

/// [text] with every case-insensitive occurrence of [query] emphasised
/// (bold, on the theme's highlight colour).
class HighlightedText extends StatelessWidget {
  const HighlightedText(
    this.text, {
    super.key,
    required this.query,
    this.style,
    this.maxLines,
  });

  final String text;
  final String query;
  final TextStyle? style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final highlight = TextStyle(
      fontWeight: FontWeight.w700,
      backgroundColor: scheme.tertiaryContainer,
      color: scheme.onTertiaryContainer,
    );
    final spans = <TextSpan>[];
    var at = 0;
    for (final m in findMatches(text, query)) {
      if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
      spans.add(TextSpan(text: text.substring(m.start, m.end), style: highlight));
      at = m.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return Text.rich(
      TextSpan(children: spans),
      style: style,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}
