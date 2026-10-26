import 'package:flutter/material.dart';

import '../features/debug/pointer_debug_screen.dart';
import '../features/editor/editor_screen.dart';
import '../features/library/search_screen.dart';
import '../features/settings/settings_screen.dart';

/// The app's navigation entry points. Screens call these instead of building
/// routes themselves, so navigation stays in one place.
///
/// Every method returns a future that completes when the pushed screen is
/// closed (e.g. the library refreshes its grid after the editor returns).
abstract final class AppRoutes {
  static const String editorRoute = '/editor';
  static const String settingsRoute = '/settings';
  static const String searchRoute = '/search';
  static const String pointerDebugRoute = PointerDebugScreen.routeName;

  /// Opens the editor for [notebookId], optionally scrolled to [pageIndex].
  static Future<void> openEditor(
    BuildContext context,
    String notebookId, {
    int? pageIndex,
  }) =>
      _push(
        context,
        editorRoute,
        (_) => EditorScreen(
          notebookId: notebookId,
          initialPageIndex: pageIndex,
        ),
      );

  static Future<void> openSettings(BuildContext context) =>
      _push(context, settingsRoute, (_) => const SettingsScreen());

  static Future<void> openSearch(BuildContext context) =>
      _push(context, searchRoute, (_) => const SearchScreen());

  /// Developer screen that shows raw pointer data (pen kind, pressure, tilt).
  static Future<void> openPointerDebug(BuildContext context) =>
      PointerDebugScreen.open(context);

  static Future<void> _push(
    BuildContext context,
    String name,
    WidgetBuilder builder,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: builder,
        settings: RouteSettings(name: name),
      ),
    );
  }
}
