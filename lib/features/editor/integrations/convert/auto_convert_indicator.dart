import 'dart:async';

import 'package:flutter/material.dart';

import 'auto_convert_session.dart';

/// The small unobtrusive feedback of auto-convert, stacked over the pages:
/// a "Converting..." chip while the model reads (never blocks the pen: it
/// ignores pointers) and, once per failure, a SnackBar with why.
class AutoConvertIndicator extends StatefulWidget {
  const AutoConvertIndicator({super.key, required this.session});

  final AutoConvertSession session;

  @override
  State<AutoConvertIndicator> createState() => _AutoConvertIndicatorState();
}

class _AutoConvertIndicatorState extends State<AutoConvertIndicator> {
  StreamSubscription<String>? _failures;

  @override
  void initState() {
    super.initState();
    _failures = widget.session.failures.listen(_showFailure);
  }

  @override
  void didUpdateWidget(AutoConvertIndicator old) {
    super.didUpdateWidget(old);
    if (!identical(old.session, widget.session)) {
      unawaited(_failures?.cancel());
      _failures = widget.session.failures.listen(_showFailure);
    }
  }

  @override
  void dispose() {
    unawaited(_failures?.cancel());
    super.dispose();
  }

  void _showFailure(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      key: const ValueKey('auto-convert-error'),
      content: Text(
          'Auto-convert paused: $message It tries again with your next stroke.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.session.working,
      builder: (context, working, _) {
        if (!working) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return IgnorePointer(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Material(
                key: const ValueKey('auto-convert-working'),
                elevation: 2,
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: scheme.onSecondaryContainer),
                      ),
                      const SizedBox(width: 8),
                      Text('Converting...',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(color: scheme.onSecondaryContainer)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
