import 'package:flutter/material.dart';

import 'app_info.dart';
import 'theme.dart';

/// Shown instead of the app when startup fails (e.g. the documents folder
/// can't be opened), so the user sees what happened rather than a blank
/// screen. Nothing is sent anywhere; the details are only shown here.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({
    super.key,
    required this.error,
    this.stackTrace,
    this.onRetry,
  });

  final Object error;
  final StackTrace? stackTrace;

  /// Runs startup again. Hidden when null.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppInfo.name,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline_rounded,
                            size: 48, color: scheme.error),
                        const SizedBox(height: 16),
                        Text("NeatInk couldn't start",
                            style: theme.textTheme.headlineSmall),
                        const SizedBox(height: 8),
                        Text(
                          'Your notebooks are stored on this device and were '
                          'not changed. Try again, or restart the tablet if '
                          'this keeps happening.',
                          style: theme.textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 20),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SelectableText(
                            '$error',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontFamily: 'monospace'),
                          ),
                        ),
                        if (onRetry != null) ...[
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: onRetry,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Try again'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Replacement for the grey box Flutter shows in release builds when a
/// widget fails to build: a small, readable notice. Debug builds keep the
/// detailed red error screen.
Widget releaseErrorWidget(FlutterErrorDetails details) {
  return const Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(
      color: Color(0x14B3261E),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Something went wrong showing this part of the screen.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFB3261E), fontSize: 14),
          ),
        ),
      ),
    ),
  );
}
