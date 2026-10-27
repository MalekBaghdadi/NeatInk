import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../document/font_kind.dart';
import '../../../../recognition/htr_channel.dart';
import '../../../../recognition/word_image.dart';
import '../../../settings/convert_style_prefs.dart';
import '../../editor_controller.dart';
import '../../tools/selection.dart';
import '../text_images/text_format_bar.dart';
import 'convert_apply.dart';
import 'convert_config.dart';
import 'convert_plan.dart';
import 'convert_session.dart';
import 'sample_share.dart';
import 'user_lexicon.dart';
import 'word_crop.dart';

/// Opens the "Convert to text" sheet and, when the user converts, shows the
/// confirmation with an Undo action. Resolves when the sheet is gone.
///
/// The sheet starts with [initialStyle] (the look last used) and reports the
/// look used through [onStyleChosen] when the user converts; corrected words
/// go to [learner]; [sampleShare] sends the "Share samples" file.
Future<void> showConvertSheet(
  BuildContext context,
  EditorController controller, {
  required HtrRecognizer recognizer,
  required WordImageRenderer renderer,
  Selection? selection,
  ConvertStylePrefs initialStyle = const ConvertStylePrefs(),
  void Function(ConvertStylePrefs style)? onStyleChosen,
  WordLearner? learner,
  SampleShareService sampleShare = const DefaultSampleShareService(),
  String appVersion = 'unknown',
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final session = ConvertSession(
    controller: controller,
    recognizer: recognizer,
    selection: selection,
    initialStyle: initialStyle,
    onStyleChosen: onStyleChosen,
    learner: learner,
    appVersion: appVersion,
  );
  unawaited(session.start());
  final outcome = await showModalBottomSheet<ConvertOutcome>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: false,
    constraints: const BoxConstraints(maxWidth: 860),
    builder: (_) => ConvertSheet(
        session: session, renderer: renderer, sampleShare: sampleShare),
  );
  session.cancel();
  if (outcome == null) return;
  final n = outcome.lines;
  messenger.showSnackBar(SnackBar(
    content: Text(
        'Converted $n ${n == 1 ? 'line' : 'lines'}. Undo to get your handwriting back.'),
    action: SnackBarAction(
      label: 'Undo',
      onPressed: () {
        // Only undo our own step, not something done since.
        if (controller.isReady && controller.undoLabel == convertCommandLabel) {
          controller.undo();
        }
      },
    ),
  ));
}

/// The full-height sheet: progress, then the review of the recognised lines.
class ConvertSheet extends StatelessWidget {
  const ConvertSheet({
    super.key,
    required this.session,
    required this.renderer,
    this.sampleShare = const DefaultSampleShareService(),
  });

  final ConvertSession session;
  final WordImageRenderer renderer;
  final SampleShareService sampleShare;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return SizedBox(
      key: const ValueKey('convert-sheet'),
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text('Convert to text',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton(
                  key: const ValueKey('convert-close'),
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    session.cancel();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListenableBuilder(
              listenable: session,
              builder: (context, _) => switch (session.phase) {
                ConvertPhase.reading => _Reading(session: session),
                ConvertPhase.failed => _Failed(session: session),
                ConvertPhase.empty => _Empty(session: session),
                ConvertPhase.review => _Review(
                    session: session,
                    renderer: renderer,
                    sampleShare: sampleShare),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading({required this.session});

  final ConvertSession session;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Reading your handwriting...',
                    key: ValueKey('convert-reading')),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  key: const ValueKey('convert-progress'),
                  value: session.progress,
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  key: const ValueKey('convert-cancel'),
                  onPressed: () {
                    session.cancel();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      );
}

class _Failed extends StatelessWidget {
  const _Failed({required this.session});

  final ConvertSession session;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              Text(
                session.errorMessage ?? 'Reading the handwriting failed.',
                key: const ValueKey('convert-error'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      session.cancel();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Close'),
                  ),
                  FilledButton(
                    key: const ValueKey('convert-retry'),
                    onPressed: session.retry,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.session});

  final ConvertSession session;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.edit_note, size: 44),
              const SizedBox(height: 12),
              const Text('Nothing to convert here yet',
                  key: ValueKey('convert-empty')),
              const SizedBox(height: 4),
              Text('Write something with the pen first.',
                  style: Theme.of(context).textTheme.bodySmall),
              if (session.canChooseScope) ...[
                const SizedBox(height: 20),
                _ScopeSwitch(session: session),
              ],
            ],
          ),
        ),
      );
}

class _ScopeSwitch extends StatelessWidget {
  const _ScopeSwitch({required this.session});

  final ConvertSession session;

  @override
  Widget build(BuildContext context) => SegmentedButton<bool>(
        key: const ValueKey('convert-scope'),
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: false, label: Text('This page')),
          ButtonSegment(value: true, label: Text('All pages')),
        ],
        selected: {session.allPages},
        onSelectionChanged: (v) => unawaited(session.setAllPages(v.first)),
      );
}

// -----------------------------------------------------------------------------
// Review

sealed class _Entry {}

class _PageHeader extends _Entry {
  _PageHeader(this.pageIndex);
  final int pageIndex;
}

class _LineEntry extends _Entry {
  _LineEntry(this.index, this.line);
  final int index;
  final PlannedLine line;
}

class _Review extends StatefulWidget {
  const _Review({
    required this.session,
    required this.renderer,
    required this.sampleShare,
  });

  final ConvertSession session;
  final WordImageRenderer renderer;
  final SampleShareService sampleShare;

  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  bool _showWords = false;
  bool _sharing = false;
  String? _shareStatus;

  ConvertSession get _s => widget.session;

  /// Builds the samples file (words, corrected text, pen data, the pictures
  /// the model saw) and opens the share sheet. The user decides where it goes.
  Future<void> _shareSamples() async {
    setState(() {
      _sharing = true;
      _shareStatus = null;
    });
    String? status;
    try {
      final json = await _s.buildSamples(widget.renderer);
      final shared = await widget.sampleShare
          .share(fileName: _s.sampleFileName, json: json);
      if (shared) status = 'Thank you! The samples file was shared.';
    } catch (e) {
      debugPrint('NeatInk: could not share samples: $e');
      status = "Couldn't prepare the samples. Please try again.";
    }
    if (!mounted) return;
    setState(() {
      _sharing = false;
      _shareStatus = status;
    });
  }

  @override
  Widget build(BuildContext context) {
    final plans = _s.plans;
    final multiPage = plans.length > 1 || _s.allPages;
    final entries = <_Entry>[];
    var index = 0;
    for (final plan in plans) {
      if (multiPage) entries.add(_PageHeader(plan.pageIndex));
      for (final line in plan.lines) {
        entries.add(_LineEntry(index++, line));
      }
    }
    final words = <(int, PlannedLine, int)>[
      for (final e in entries)
        if (e is _LineEntry)
          for (var i = 0; i < e.line.words.length; i++) (e.index, e.line, i),
    ];
    final convertCount = _s.includedCount;
    final stay = _s.stayCount;

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _Controls(session: _s)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Text(
                    stay == 0
                        ? 'Every line will be converted.'
                        : '$stay ${stay == 1 ? 'line' : 'lines'} will stay as handwriting',
                    key: const ValueKey('convert-stay-count'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: entries.length,
                itemBuilder: (context, i) {
                  final e = entries[i];
                  return switch (e) {
                    _PageHeader() => Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: Text('Page ${e.pageIndex + 1}',
                            style: Theme.of(context).textTheme.titleSmall),
                      ),
                    _LineEntry() => _LineRow(
                        key: ValueKey('convert-row-${e.line.id}'),
                        session: _s,
                        line: e.line,
                        index: e.index,
                      ),
                  };
                },
              ),
              SliverToBoxAdapter(
                child: ListTile(
                  key: const ValueKey('convert-debug-toggle'),
                  title: const Text('Show what the recognizer saw'),
                  trailing:
                      Icon(_showWords ? Icons.expand_less : Icons.expand_more),
                  onTap: () => setState(() => _showWords = !_showWords),
                ),
              ),
              if (_showWords)
                SliverList.builder(
                  itemCount: words.length,
                  itemBuilder: (context, i) => _WordRow(
                    key: ValueKey('convert-word-$i'),
                    index: i,
                    lineIndex: words[i].$1,
                    word: words[i].$2.words[words[i].$3],
                    renderer: widget.renderer,
                    onPick: (alt) =>
                        _s.replaceWord(words[i].$2, words[i].$3, alt),
                  ),
                ),
              SliverToBoxAdapter(
                child: _ShareSamples(
                  busy: _sharing,
                  status: _shareStatus,
                  onShare: _shareSamples,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const ValueKey('convert-apply'),
              onPressed: convertCount == 0
                  ? null
                  : () {
                      final outcome = _s.apply();
                      Navigator.of(context).pop(outcome);
                    },
              child: Text(
                  'Convert $convertCount ${convertCount == 1 ? 'line' : 'lines'}'),
            ),
          ),
        ),
      ],
    );
  }
}

/// Font, bold / italic, size and colour, and the page scope.
class _Controls extends StatelessWidget {
  const _Controls({required this.session});

  final ConvertSession session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final label = Theme.of(context).textTheme.labelLarge;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (s.canChooseScope) ...[
            _ScopeSwitch(session: s),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PopupMenuButton<FontKind>(
                key: const ValueKey('convert-font'),
                tooltip: 'Font',
                initialValue: s.font,
                onSelected: s.setFont,
                itemBuilder: (_) => TextFormatBar.fontPickerItems(s.font),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: Theme.of(context).colorScheme.outline),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(s.font.label,
                          key: const ValueKey('convert-font-label'),
                          style: TextStyle(fontFamily: s.font.family)),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
              FilterChip(
                key: const ValueKey('convert-bold'),
                label: const Text('Bold'),
                selected: s.bold,
                onSelected: s.setBold,
              ),
              FilterChip(
                key: const ValueKey('convert-italic'),
                label: const Text('Italic'),
                selected: s.italic,
                onSelected: s.setItalic,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Size', style: label),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                key: const ValueKey('convert-size-auto'),
                label: const Text('Auto (match my handwriting)'),
                selected: s.autoSize,
                onSelected: (_) => s.setFixedSize(null),
              ),
              SizedBox(
                width: 260,
                child: Row(
                  children: [
                    Expanded(
                      child: Slider(
                        key: const ValueKey('convert-size-slider'),
                        min: ConvertConfig.minFixedSize,
                        max: ConvertConfig.maxFixedSize,
                        divisions: (ConvertConfig.maxFixedSize -
                                ConvertConfig.minFixedSize)
                            .round(),
                        value: (s.fixedSize ?? ConvertConfig.defaultFixedSize),
                        onChanged: s.setFixedSize,
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        s.autoSize ? '' : '${s.fixedSize!.round()} pt',
                        key: const ValueKey('convert-size-label'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Text('Colour', style: label),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                key: const ValueKey('convert-colour-keep'),
                label: const Text('Keep my ink colour'),
                selected: s.colorOverride == null,
                onSelected: (_) => s.setColorOverride(null),
              ),
              for (final c in ConvertConfig.colorChoices)
                GestureDetector(
                  key: ValueKey('convert-colour-${c.toRadixString(16)}'),
                  onTap: () => s.setColorOverride(c),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                        width: s.colorOverride == c ? 3 : 1,
                        color: s.colorOverride == c
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One recognised line: include checkbox, editable text in the chosen look,
/// "Not sure" badge for doubtful readings.
class _LineRow extends StatefulWidget {
  const _LineRow({
    super.key,
    required this.session,
    required this.line,
    required this.index,
  });

  final ConvertSession session;
  final PlannedLine line;
  final int index;

  @override
  State<_LineRow> createState() => _LineRowState();
}

class _LineRowState extends State<_LineRow> {
  late final TextEditingController _text =
      TextEditingController(text: widget.line.text);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final line = widget.line;
    // The text can change from outside the field (an alternative reading was
    // picked in "what the recognizer saw").
    if (_text.text != line.text) {
      _text.value = TextEditingValue(
          text: line.text,
          selection: TextSelection.collapsed(offset: line.text.length));
    }
    final scheme = Theme.of(context).colorScheme;
    final ink = Color(line.dominantColor);
    final color = s.colorOverride != null
        ? Color(s.colorOverride!)
        : (ink.computeLuminance() < 0.6 ? ink : scheme.onSurface);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 20, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            key: ValueKey('convert-include-${widget.index}'),
            value: line.include,
            onChanged: (v) => s.setInclude(line, v ?? false),
          ),
          Expanded(
            child: TextField(
              key: ValueKey('convert-text-${widget.index}'),
              controller: _text,
              onChanged: (v) => s.setText(line, v),
              minLines: 1,
              maxLines: 4,
              style: TextStyle(
                fontFamily: s.font.family,
                fontSize: 17,
                fontWeight: s.bold ? FontWeight.w700 : FontWeight.w400,
                fontStyle: s.italic ? FontStyle.italic : FontStyle.normal,
                color: line.include ? color : color.withValues(alpha: 0.55),
              ),
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: line.lowConfidence
                    ? Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Chip(
                          key: ValueKey('convert-notsure-${widget.index}'),
                          label: const Text('Not sure'),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: scheme.tertiaryContainer,
                        ),
                      )
                    : null,
                suffixIconConstraints: const BoxConstraints(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One word of the "what the recognizer saw" section: the 128x32 crop and
/// the raw and corrected reading with its confidence.
class _WordRow extends StatefulWidget {
  const _WordRow({
    super.key,
    required this.index,
    required this.lineIndex,
    required this.word,
    required this.renderer,
    required this.onPick,
  });

  final int index;
  final int lineIndex;
  final WordResult word;
  final WordImageRenderer renderer;

  /// An alternative reading was tapped: use it in the line's text.
  final void Function(String alternative) onPick;

  @override
  State<_WordRow> createState() => _WordRowState();
}

class _WordRowState extends State<_WordRow> {
  late final Future<WordImage> _image =
      renderWordImage(widget.word.group, renderer: widget.renderer);

  /// Up to [maxAlternatives] other readings of the word (best first), without
  /// the one already used or repeats.
  List<String> get alternatives {
    final w = widget.word;
    final out = <String>[];
    for (final a in w.alternatives) {
      final t = a.trim();
      if (t.isEmpty || t == w.text.trim() || out.contains(t)) continue;
      out.add(t);
      if (out.length == maxAlternatives) break;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.word;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          FutureBuilder<WordImage>(
            future: _image,
            builder: (context, snap) {
              final img = snap.data;
              if (img == null) {
                return const SizedBox(width: 96, height: wordImageHeight * 1.5);
              }
              // Word images are as wide as the word; wide ones are shown
              // smaller so a row never gets too wide.
              final scale = math.min(1.5, 240 / img.width);
              return Container(
                width: img.width * scale + 2,
                height: img.height * scale + 2,
                decoration: BoxDecoration(
                  border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: CustomPaint(
                  key: ValueKey('convert-crop-${widget.index}'),
                  painter: WordCropPainter.of(img, scale: scale),
                ),
              );
            },
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'line ${widget.lineIndex + 1}  raw "${w.raw}"  read "${w.text}"  '
                  'confidence ${w.confidence.toStringAsFixed(2)}',
                  key: ValueKey('convert-word-text-${widget.index}'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (alternatives.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 6,
                      children: [
                        for (var a = 0; a < alternatives.length; a++)
                          ActionChip(
                            key: ValueKey('convert-alt-${widget.index}-$a'),
                            label: Text(alternatives[a]),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => widget.onPick(alternatives[a]),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Alternative reading chips shown per word.
const int maxAlternatives = 4;

/// The unobtrusive "Share samples for improving recognition" button with its
/// one-line promise and the outcome of the last try.
class _ShareSamples extends StatelessWidget {
  const _ShareSamples({
    required this.busy,
    required this.status,
    required this.onShare,
  });

  final bool busy;
  final String? status;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            key: const ValueKey('convert-share-samples'),
            style: TextButton.styleFrom(
              textStyle: theme.textTheme.bodySmall,
              foregroundColor: theme.colorScheme.onSurfaceVariant,
            ),
            icon: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.ios_share, size: 16),
            label: const Text('Share samples for improving recognition'),
            onPressed: busy ? null : onShare,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
            child: Text(
              status ??
                  'Makes one file with your handwriting and the text above. '
                      'Nothing is sent unless you pick where to share it.',
              key: const ValueKey('convert-share-status'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
