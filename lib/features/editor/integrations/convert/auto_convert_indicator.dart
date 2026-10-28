import 'dart:async';

import 'package:flutter/material.dart';

import 'auto_convert_session.dart';

/// The small unobtrusive feedback of auto-convert, stacked over the pages:
/// a "Converting..." chip while the model reads (never blocks the pen: it
/// ignores pointers), once per failure a SnackBar with why, and, when a line
/// was kept as handwriting because auto-convert was not sure what it says, a
/// "Kept as handwriting · Review" chip for [shownFor] that opens the review
/// sheet ([onReview]).
class AutoConvertIndicator extends StatefulWidget {
  const AutoConvertIndicator({
    super.key,
    required this.session,
    this.onReview,
    this.shownFor = const Duration(seconds: 6),
  });

  final AutoConvertSession session;

  /// Opens the Convert review sheet for the page in view. Without it the
  /// kept-lines chip is not shown.
  final void Function(BuildContext context)? onReview;

  /// How long the kept-lines chip stays after a line was kept. It must not
  /// sit over the page for good: a pen stroke that starts on it is lost.
  final Duration shownFor;

  @override
  State<AutoConvertIndicator> createState() => _AutoConvertIndicatorState();
}

class _AutoConvertIndicatorState extends State<AutoConvertIndicator> {
  StreamSubscription<String>? _failures;
  Timer? _hide;
  bool _showKept = false;
  int _lastKept = 0;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(AutoConvertIndicator old) {
    super.didUpdateWidget(old);
    if (!identical(old.session, widget.session)) {
      _unlisten(old.session);
      _listen();
    }
  }

  @override
  void dispose() {
    _unlisten(widget.session);
    _hide?.cancel();
    super.dispose();
  }

  void _listen() {
    _failures = widget.session.failures.listen(_showFailure);
    _lastKept = widget.session.keptLines.value;
    widget.session.keptLines.addListener(_onKept);
  }

  void _unlisten(AutoConvertSession session) {
    unawaited(_failures?.cancel());
    session.keptLines.removeListener(_onKept);
  }

  void _onKept() {
    final n = widget.session.keptLines.value;
    final grew = n > _lastKept;
    _lastKept = n;
    if (!mounted) return;
    if (n == 0) {
      _hide?.cancel();
      setState(() => _showKept = false);
    } else if (grew) {
      _hide?.cancel();
      _hide = Timer(widget.shownFor, () {
        if (mounted) setState(() => _showKept = false);
      });
      setState(() => _showKept = true);
    }
  }

  void _showFailure(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      key: const ValueKey('auto-convert-error'),
      content: Text(
          'Auto-convert paused: $message It tries again with your next stroke.'),
    ));
  }

  void _review() {
    _hide?.cancel();
    setState(() => _showKept = false);
    widget.session.clearKept();
    widget.onReview?.call(context);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.session.working,
      builder: (context, working, _) {
        final scheme = Theme.of(context).colorScheme;
        final Widget chip;
        if (working) {
          chip = IgnorePointer(
            child: _Chip(
              key: const ValueKey('auto-convert-working'),
              color: scheme.secondaryContainer,
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: scheme.onSecondaryContainer),
                ),
                const SizedBox(width: 8),
                _label(context, 'Converting...', scheme.onSecondaryContainer),
              ],
            ),
          );
        } else if (_showKept && widget.onReview != null && widget.session.keptLines.value > 0) {
          final n = widget.session.keptLines.value;
          chip = _Chip(
            key: const ValueKey('auto-convert-kept'),
            color: scheme.tertiaryContainer,
            onTap: _review,
            children: [
              Icon(Icons.gesture, size: 16, color: scheme.onTertiaryContainer),
              const SizedBox(width: 8),
              _label(
                context,
                n == 1 ? 'Not sure about 1 line: kept as handwriting' : 'Not sure about $n lines: kept as handwriting',
                scheme.onTertiaryContainer,
              ),
              const SizedBox(width: 10),
              _label(context, 'Review', scheme.onTertiaryContainer, bold: true),
            ],
          );
        } else {
          return const SizedBox.shrink();
        }
        return Align(
          alignment: Alignment.topCenter,
          child: Padding(padding: const EdgeInsets.only(top: 10), child: chip),
        );
      },
    );
  }

  Widget _label(BuildContext context, String text, Color color, {bool bold = false}) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: color, fontWeight: bold ? FontWeight.w700 : null),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.color, required this.children, this.onTap});

  final Color color;
  final List<Widget> children;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}
