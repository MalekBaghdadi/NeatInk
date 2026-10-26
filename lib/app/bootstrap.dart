import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show ErrorWidget;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/file_notebook_repository.dart';
import '../storage/notebook_repository.dart';
import 'error_views.dart';
import 'providers.dart';

/// The app-wide singletons that must exist before the first frame.
class AppServices {
  const AppServices({required this.preferences, required this.repository});

  /// Name of NeatInk's folder inside the app documents directory.
  static const String storageFolder = 'neatink';

  final SharedPreferences preferences;
  final NotebookRepository repository;

  /// Opens shared_preferences and the notebook storage under
  /// `<app documents>/neatink`.
  ///
  /// The storage folder is created here so a broken or full storage shows
  /// up as a readable startup error instead of failing on the first save.
  static Future<AppServices> load({
    Future<SharedPreferences> Function()? openPreferences,
    Future<Directory> Function()? documentsDirectory,
  }) async {
    final preferences =
        await (openPreferences ?? SharedPreferences.getInstance)();
    final docs =
        await (documentsDirectory ?? getApplicationDocumentsDirectory)();
    final root = Directory(p.join(docs.path, storageFolder));
    await root.create(recursive: true);
    return AppServices(
      preferences: preferences,
      repository: FileNotebookRepository(root),
    );
  }

  /// Provider overrides that inject these services into the app.
  List<Override> get overrides => [
        sharedPreferencesProvider.overrideWithValue(preferences),
        notebookRepositoryProvider.overrideWithValue(repository),
      ];
}

/// Routes uncaught errors to the debug log only. Nothing is reported
/// anywhere: NeatInk has no crash reporting and nothing leaves the device.
///
/// In release builds a widget that fails to build shows a short notice
/// ([releaseErrorWidget]) instead of a grey box.
void installErrorHandlers() {
  FlutterError.onError = FlutterError.dumpErrorToConsole;
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('NeatInk: uncaught error: $error\n$stack');
    // Handled: keep the app running rather than letting the engine treat
    // it as fatal.
    return true;
  };
  if (kReleaseMode) ErrorWidget.builder = releaseErrorWidget;
}
