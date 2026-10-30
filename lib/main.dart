import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'app/diagnostics.dart';
import 'app/error_views.dart';
import 'features/editor/default_integrations.dart';
import 'features/tour/tours.dart';
import 'features/editor/editor_integrations.dart';
import 'recognition/recognition_licenses.dart';
import 'render/font_licenses.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installDiagnostics();
  installErrorHandlers();
  registerFontLicenses();
  registerRecognitionLicenses();
  await _start();
}

/// Opens storage and settings, then runs the app. If that fails, shows a
/// readable error screen with a retry button instead of a blank app.
Future<void> _start() async {
  try {
    // Tablets are used both ways; allow every orientation.
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    final services = await AppServices.load();
    runApp(ProviderScope(
      overrides: [
        ...services.overrides,
        editorIntegrationsProvider
            .overrideWithValue(defaultEditorIntegrations),
        // Guided tours start by themselves in the app (not in tests).
        autoToursProvider.overrideWithValue(true),
      ],
      child: const NeatInkApp(),
    ));
  } catch (error, stack) {
    debugPrint('NeatInk: startup failed: $error\n$stack');
    runApp(StartupErrorApp(
      error: error,
      stackTrace: stack,
      onRetry: () => unawaited(_start()),
    ));
  }
}
