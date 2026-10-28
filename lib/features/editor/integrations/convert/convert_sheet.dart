import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../document/font_kind.dart';
import '../../../../recognition/htr_channel.dart';
import '../../../../recognition/text_polish.dart';
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
import '../../../../app/insets.dart';

/// Opens the "Convert to text" sheet and, when the user converts, shows the
/// confirmation with an Undo action. Resolves when the sheet is gone.
///
/// The sheet starts with [initialStyle] (the look last used) and reports the
/// look used through [onStyleChosen] when the user converts; corrected words
/// go to [learner]; [sampleShare] sends the "Share samples" file. With
/// [autoFix] (the setting "Fix spelling automatically") the suggested spelling
/// and grammar fixes are already in the text, each with an Undo chip; without,
/// they are offered as chips.
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
  bool autoFix = false,
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
    autoFix: autoFix,
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

/// What the "Show what the recognizer saw" section lists: a block per line
/// (the pictures the model read), each followed by a row per word.
sealed class _DebugEntry {}

class _DebugLine extends _DebugEntry {
  _DebugLine(this.lineIndex, this.line);
  final int lineIndex;
  final PlannedLine line;
}

class _DebugWord extends _DebugEntry {
  _DebugWord(this.index, this.line, this.wordIndex);

  /// Counted over the words of all lines.
  final int index;
  final PlannedLine line;
  final int wordIndex;
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

  /// A suggestion was accepted or an automatic fix undone: rebuild the rows
  /// (their text fields follow the lines) and the "Fix all" button.
  void _changed() => setState(() {});

  /// Accepts every pending suggestion of [lines].
  void _fixAll(List<PlannedLine> lines) {
    for (final line in lines) {
      for (final s in _pendingFixes(line)) {
        _acceptFix(_s, line, s);
      }
    }
    _changed();
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
    final lines = [
      for (final e in entries)
        if (e is _LineEntry) e.line,
    ];
    final debug = <_DebugEntry>[];
    if (_showWords) {
      var wordIndex = 0;
      for (final e in entries) {
        if (e is! _LineEntry) continue;
        debug.add(_DebugLine(e.index, e.line));
        for (var i = 0; i < e.line.words.length; i++) {
          debug.add(_DebugWord(wordIndex++, e.line, i));
        }
      }
    }
    final convertCount = _s.includedCount;
    final stay = _s.stayCount;
    final pending = lines.fold<int>(0, (n, l) => n + _pendingFixes(l).length);

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _Controls(session: _s)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          stay == 0
                              ? 'Every line will be converted.'
                              : '$stay ${stay == 1 ? 'line' : 'lines'} will stay as handwriting',
                          key: const ValueKey('convert-stay-count'),
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      if (pending > 0)
                        TextButton.icon(
                          key: const ValueKey('convert-fix-all'),
                          icon: const Icon(Icons.auto_fix_high, size: 18),
                          label: Text('Fix all ($pending)'),
                          onPressed: () => _fixAll(lines),
                        ),
                    ],
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
                        onChanged: _changed,
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
                  itemCount: debug.length,
                  itemBuilder: (context, i) {
                    final e = debug[i];
                    return switch (e) {
                      _DebugLine() => _LineDebug(
                          key: ValueKey('convert-line-${e.lineIndex}'),
                          lineIndex: e.lineIndex,
                          line: e.line,
                        ),
                      _DebugWord() => _WordRow(
                          key: ValueKey('convert-word-${e.index}'),
                          index: e.index,
                          word: e.line.words[e.wordIndex],
                          onPick: (alt) =>
                              _s.replaceWord(e.line, e.wordIndex, alt),
                        ),
                    };
                  },
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
          // Clear of the system navigation bar (the app is drawn edge to edge).
          padding: withBottomSafeSpace(context, const EdgeInsets.all(12), extra: 4),
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

// -----------------------------------------------------------------------------
// Suggested fixes

/// What a word is made of: letters, digits and apostrophes.
final RegExp _wordChar = RegExp("[\\p{L}\\p{N}'’]", unicode: true);

/// True when [word] is in [text] as a whole word (not inside a longer one).
/// The same rule as `PlannedLine.acceptSuggestion` uses to find it, so a chip
/// is only shown when tapping it can work.
bool _hasWholeWord(String text, String word) {
  if (word.isEmpty) return false;
  var from = 0;
  while (true) {
    final at = text.indexOf(word, from);
    if (at < 0) return false;
    final end = at + word.length;
    final joinedBefore = at > 0 &&
        _wordChar.hasMatch(word[0]) &&
        _wordChar.hasMatch(text[at - 1]);
    final joinedAfter = end < text.length &&
        _wordChar.hasMatch(word[word.length - 1]) &&
        _wordChar.hasMatch(text[end]);
    if (!joinedBefore && !joinedAfter) return true;
    from = at + 1;
  }
}

/// The pending suggestions of [line] that still apply to its text. Typing
/// the fix by hand makes the suggestion go away.
List<PolishSuggestion> _pendingFixes(PlannedLine line) => [
      for (final s in line.suggestions)
        if (_hasWholeWord(line.text, s.original)) s,
    ];

/// The automatic fixes of [line] that can still be undone: the fixed word is
/// still in the text.
List<PolishSuggestion> _undoableFixes(PlannedLine line) => [
      for (final s in line.autoApplied)
        if (_hasWholeWord(line.text, s.replacement)) s,
    ];

/// Accepts [s] in [line]'s text. A suggestion that no longer fits (the user
/// changed the text) is dropped.
void _acceptFix(ConvertSession session, PlannedLine line, PolishSuggestion s) {
  if (!session.acceptSuggestion(line, s)) line.suggestions.remove(s);
}

/// Undoes the automatic fix [s] in [line]'s text; it becomes a pending
/// suggestion again. A fix that no longer fits is dropped.
void _undoFix(ConvertSession session, PlannedLine line, PolishSuggestion s) {
  if (!session.revertAutoFix(line, s)) line.autoApplied.remove(s);
}

/// "Nuerons → Neurons"; a suggestion that removes a word says so.
String _swapLabel(PolishSuggestion s) =>
    '${s.original} → ${s.replacement.isEmpty ? '(remove)' : s.replacement}';

IconData _kindIcon(PolishKind kind) => switch (kind) {
      PolishKind.spelling => Icons.spellcheck,
      PolishKind.contraction => Icons.format_quote_outlined,
      PolishKind.capitalization => Icons.text_fields,
      PolishKind.grammar => Icons.rule,
    };

/// One recognised line: include checkbox, editable text in the chosen look,
/// "Not sure" badge for doubtful readings, and under the text the spelling
/// fixes: chips to accept the suggested ones, and to undo the ones that were
/// applied automatically.
class _LineRow extends StatefulWidget {
  const _LineRow({
    super.key,
    required this.session,
    required this.line,
    required this.index,
    required this.onChanged,
  });

  final ConvertSession session;
  final PlannedLine line;
  final int index;

  /// A fix was accepted or undone (the line's text changed).
  final VoidCallback onChanged;

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

  Widget _fixes(BuildContext context, List<PolishSuggestion> pending,
      List<PolishSuggestion> applied) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        key: ValueKey('convert-fixes-${widget.index}'),
        spacing: 6,
        runSpacing: 2,
        children: [
          for (var k = 0; k < pending.length; k++)
            ActionChip(
              key: ValueKey('convert-suggest-${widget.index}-$k'),
              tooltip: pending[k].reason,
              avatar: Icon(_kindIcon(pending[k].kind), size: 16),
              label: Text(_swapLabel(pending[k])),
              visualDensity: VisualDensity.compact,
              onPressed: () {
                _acceptFix(widget.session, widget.line, pending[k]);
                widget.onChanged();
              },
            ),
          for (var k = 0; k < applied.length; k++)
            ActionChip(
              key: ValueKey('convert-undo-${widget.index}-$k'),
              tooltip: 'Undo: ${applied[k].reason}',
              avatar: const Icon(Icons.undo, size: 16),
              label: Text('Fixed: ${_swapLabel(applied[k])} · Undo'),
              backgroundColor: scheme.surfaceContainerHighest,
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
              onPressed: () {
                _undoFix(widget.session, widget.line, applied[k]);
                widget.onChanged();
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final line = widget.line;
    // The text can change from outside the field (an alternative reading was
    // picked in "what the recognizer saw", or a fix was accepted).
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
    final pending = _pendingFixes(line);
    final applied = _undoableFixes(line);
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: ValueKey('convert-text-${widget.index}'),
                  controller: _text,
                  // Typing a fix by hand also dismisses its chip: the
                  // session notifies and the row is built again.
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
                              key:
                                  ValueKey('convert-notsure-${widget.index}'),
                              label: const Text('Not sure'),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: scheme.tertiaryContainer,
                            ),
                          )
                        : null,
                    suffixIconConstraints: const BoxConstraints(),
                  ),
                ),
                if (pending.isNotEmpty || applied.isNotEmpty)
                  _fixes(context, pending, applied),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// What the recognizer saw

/// One line of the "what the recognizer saw" section: its number, how sure
/// the reading is, and the picture(s) the model was given (more than one only
/// for a very wide line, cut into parts).
class _LineDebug extends StatelessWidget {
  const _LineDebug({super.key, required this.lineIndex, required this.line});

  final int lineIndex;
  final PlannedLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final images = line.images;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Line ${lineIndex + 1}  ·  ${(line.confidence * 100).round()}% sure',
              key: ValueKey('convert-line-text-$lineIndex'),
              style: theme.textTheme.titleSmall,
            ),
            for (var k = 0; k < images.length; k++) ...[
              const SizedBox(height: 6),
              if (images.length > 1)
                Text('part ${k + 1} of ${images.length}',
                    style: theme.textTheme.bodySmall),
              _LineImageStrip(
                cropKey: ValueKey('convert-crop-$lineIndex-$k'),
                image: images[k],
                available: constraints.maxWidth,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The grey picture the model read, scaled up a little and scrolling
/// sideways when it is wider than the sheet.
class _LineImageStrip extends StatelessWidget {
  const _LineImageStrip({
    required this.cropKey,
    required this.image,
    required this.available,
  });

  final Key cropKey;
  final WordImage image;
  final double available;

  /// Shown at most this much larger than the model's pixels, and never
  /// smaller than they are (a wide line scrolls instead).
  static const double maxScale = 1.5;

  @override
  Widget build(BuildContext context) {
    final scale = image.width <= 0
        ? 1.0
        : (available / image.width).clamp(1.0, maxScale).toDouble();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: RepaintBoundary(
        child: Container(
          width: image.width * scale + 2,
          height: image.height * scale + 2,
          decoration: BoxDecoration(
            border:
                Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: CustomPaint(
            key: cropKey,
            painter: WordCropPainter.of(image, scale: scale),
          ),
        ),
      ),
    );
  }
}

/// One word of the "what the recognizer saw" section: the model's raw
/// reading, the word as read, its confidence and the other readings to pick.
class _WordRow extends StatelessWidget {
  const _WordRow({
    super.key,
    required this.index,
    required this.word,
    required this.onPick,
  });

  final int index;
  final WordResult word;

  /// An alternative reading was tapped: use it in the line's text.
  final void Function(String alternative) onPick;

  /// Up to [maxAlternatives] other readings of the word (best first), without
  /// the one already used or repeats.
  List<String> get alternatives {
    final out = <String>[];
    for (final a in word.alternatives) {
      final t = a.trim();
      if (t.isEmpty || t == word.text.trim() || out.contains(t)) continue;
      out.add(t);
      if (out.length == maxAlternatives) break;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final w = word;
    final alts = alternatives;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'raw "${w.raw}"  read "${w.text}"  '
            'confidence ${w.confidence.toStringAsFixed(2)}',
            key: ValueKey('convert-word-text-$index'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (alts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 6,
                children: [
                  for (var a = 0; a < alts.length; a++)
                    ActionChip(
                      key: ValueKey('convert-alt-$index-$a'),
                      label: Text(alts[a]),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onPick(alts[a]),
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
