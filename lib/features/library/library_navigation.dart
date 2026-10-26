import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';

/// The screen changes the library and search screens trigger.
///
/// The default implementation forwards to [AppRoutes]. It sits behind
/// [libraryNavigatorProvider] so widget tests can record navigation instead
/// of opening the real editor.
class LibraryNavigator {
  const LibraryNavigator();

  /// Completes when the editor closes.
  Future<void> openEditor(BuildContext context, String notebookId,
          {int? pageIndex}) =>
      AppRoutes.openEditor(context, notebookId, pageIndex: pageIndex);

  Future<void> openSearch(BuildContext context) =>
      AppRoutes.openSearch(context);

  Future<void> openSettings(BuildContext context) =>
      AppRoutes.openSettings(context);
}

final libraryNavigatorProvider =
    Provider<LibraryNavigator>((ref) => const LibraryNavigator());
