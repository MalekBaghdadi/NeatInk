import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/theme.dart';
import 'package:neatink/features/editor/editor_controller.dart';
import 'package:neatink/features/editor/tool_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../fakes/in_memory_repository.dart';

/// An [EditorController] that was never opened: enough for the tool prefs,
/// the tool selection and the extension registry (tests of the tool row and
/// the settings panel), without loading a notebook.
Future<EditorController> toolbarController({
  Map<String, Object> storedPrefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(storedPrefs);
  final prefs = await SharedPreferences.getInstance();
  final controller = EditorController(
    repository: InMemoryNotebookRepository(),
    notebookId: 'toolbar-test',
    toolPrefsStore: ToolPrefsStore(prefs),
  );
  addTearDown(controller.dispose);
  return controller;
}

/// Sets the test window to [size] logical pixels (device pixel ratio 1).
void useScreen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// [child] in the app's own light or dark theme, on a page.
Widget themedApp(
  Widget child, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) =>
    MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: app!,
      ),
      home: Scaffold(body: child),
    );
