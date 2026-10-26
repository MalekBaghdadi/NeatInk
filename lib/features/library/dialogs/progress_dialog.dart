import 'dart:async';

import 'package:flutter/material.dart';

/// Runs [task] while a modal progress dialog shows [message]. The dialog
/// can't be dismissed and closes when the task finishes, whether it
/// succeeds or throws. Returns the task's result (errors are rethrown).
Future<T> runWithProgress<T>(
  BuildContext context,
  String message,
  Future<T> Function() task,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
  unawaited(navigator.push(route));
  try {
    return await task();
  } finally {
    // removeRoute (not pop) so we close exactly this dialog even if
    // something else was pushed on top meanwhile.
    if (route.isActive) navigator.removeRoute(route);
  }
}
