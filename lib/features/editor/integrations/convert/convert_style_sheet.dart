import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/insets.dart';
import '../../../../document/notebook_meta.dart';
import '../../../../document/page_items.dart';
import '../../../../document/paper.dart';
import '../../../../render/text_style.dart';
import '../../../settings/app_settings.dart';
import '../../../settings/convert_style_prefs.dart';
import '../../../settings/settings_controller.dart';
import '../../../settings/settings_screen.dart' show formatSeconds;
import '../../../settings/widgets/settings_section.dart';
import 'convert_layout.dart';
import 'convert_style_controls.dart';

/// The "Typed text" sheet: how converted handwriting looks (the look the
/// Convert sheet and auto-convert use), and auto-convert's own switches.
/// It opens any time, also when there is nothing to convert yet, from the
/// button next to Auto in the editor and from the settings. [page] (the
/// page in view) decides the even size shown; without it, the default
/// paper does.
Future<void> showConvertStyleSheet(BuildContext context, {PageMeta? page}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (_) => ConvertStyleSheet(page: page),
    );

class ConvertStyleSheet extends ConsumerWidget {
  const ConvertStyleSheet({super.key, this.page});

  final PageMeta? page;

  /// The sentence shown in the preview.
  static const String sample = 'Neurons fire when they reach threshold.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(convertStylePrefsProvider);
    final settings = ref.watch(settingsProvider);
    final p = page;
    final ruling = p != null
        ? PageRuling.of(p.paper, p.width, p.height, isPdf: p.isPdf)
        : PageRuling.of(settings.defaultPaper, a4WidthPt, a4HeightPt);
    final even = evenFontSize(ruling);
    void change(AppSettings Function(AppSettings) f) => ref.read(settingsProvider.notifier).update(f);
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            children: [
              Text('Typed text', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text('How handwriting looks once it is converted, by the Convert '
                  'button or by Auto.', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
              _Preview(prefs: prefs, ruling: ruling, evenSize: even, paper: p?.paper ?? settings.defaultPaper),
              const SizedBox(height: 12),
              ConvertStyleControls(
                value: prefs,
                onChange: (change) => ref
                    .read(convertStylePrefsProvider.notifier)
                    .save(change(ref.read(convertStylePrefsProvider))),
                evenSize: even,
              ),
              const Divider(height: 24),
              SwitchListTile(
                key: const ValueKey('style-auto-convert'),
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.auto_awesome_outlined),
                title: const Text('Auto-convert'),
                subtitle: const Text('Handwriting turns into text by itself after you lift the pen.'),
                value: settings.autoConvert,
                onChanged: (v) => change((s) => s.copyWith(autoConvert: v)),
              ),
              SettingsSliderTile(
                key: const ValueKey('style-auto-convert-delay'),
                title: 'Wait before converting',
                value: settings.autoConvertDelayMs / 1000,
                min: AppSettings.minAutoConvertDelayMs / 1000,
                max: AppSettings.maxAutoConvertDelayMs / 1000,
                divisions: (AppSettings.maxAutoConvertDelayMs - AppSettings.minAutoConvertDelayMs) ~/ 500,
                label: formatSeconds,
                enabled: settings.autoConvert,
                onChanged: (v) => change((s) => s.copyWith(autoConvertDelayMs: (v * 1000).round())),
              ),
              SwitchListTile(
                key: const ValueKey('style-autocorrect'),
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.auto_fix_high_outlined),
                title: const Text('Autocorrect'),
                subtitle: const Text('Fix spelling and small grammar slips. Tap an underlined word '
                    'to get yours back.'),
                value: settings.autocorrect,
                onChanged: (v) => change((s) => s.copyWith(autocorrect: v)),
              ),
            ],
          ),
        ),
        Padding(
          padding: withBottomSafeSpace(context, const EdgeInsets.fromLTRB(20, 4, 20, 12), extra: 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const ValueKey('style-done'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ),
        ),
      ],
    );
  }
}

/// The sample sentence on a strip of the page's paper, in the chosen look
/// (the even size stands in for "match my handwriting").
class _Preview extends StatelessWidget {
  const _Preview({required this.prefs, required this.ruling, required this.evenSize, required this.paper});

  final ConvertStylePrefs prefs;
  final PageRuling? ruling;
  final double evenSize;
  final Paper paper;

  @override
  Widget build(BuildContext context) {
    final style = ConvertStyle.fromPrefs(prefs);
    final size = style.fixedSize ?? evenSize;
    final item = TextItem(
      id: 'preview',
      x: 0,
      y: 0,
      width: 1e6,
      height: 0,
      text: ConvertStyleSheet.sample,
      fontSize: size,
      color: prefs.colorOverride ?? 0xFF1E1E1E,
      bold: prefs.bold,
      italic: prefs.italic,
      font: prefs.font,
    );
    return ClipRRect(
      key: const ValueKey('style-preview'),
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 64,
        width: double.infinity,
        child: CustomPaint(painter: _PreviewPainter(item, ruling?.spacing ?? 26, Color(paper.color), Color(paper.lineColor))),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.item, this.spacing, this.background, this.line);

  final TextItem item;
  final double spacing;
  final Color background;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    // Page points at a comfortable scale: two ruled lines fill the strip.
    final scale = size.height / (spacing * 2);
    final baseline = spacing * 1.5;
    canvas.save();
    canvas.scale(scale);
    final rule = Paint()
      ..color = line
      ..strokeWidth = 0.6;
    for (var y = spacing * 0.5; y < size.height / scale; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width / scale, y), rule);
    }
    final painter = layoutTextItem(item);
    final first = painter.computeLineMetrics().firstOrNull;
    painter.paint(canvas, Offset(12, baseline - (first?.ascent ?? item.fontSize * 0.8)));
    painter.dispose();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PreviewPainter old) =>
      old.item.fontSize != item.fontSize ||
      old.item.font != item.font ||
      old.item.bold != item.bold ||
      old.item.italic != item.italic ||
      old.item.color != item.color ||
      old.spacing != spacing ||
      old.background != background;
}
