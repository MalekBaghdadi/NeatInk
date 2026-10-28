import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/insets.dart';
import 'package:neatink/app/theme.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/features/library/dialogs/new_notebook_sheet.dart';

import '../editor/integrations/convert/convert_sheet_test.dart' show reader, threeLines, settle;
import '../editor/integrations/convert/harness.dart';

// Android draws the app edge to edge: the system navigation bar lies over
// the bottom of the window. Buttons at the bottom must stay above it.
const double navBar = 48;

void withNavBar(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(bottom: navBar);
  tester.view.viewPadding = const FakeViewPadding(bottom: navBar);
  addTearDown(tester.view.reset);
}

void main() {
  group('bottomSafeSpace', () {
    Future<double> spaceWith(WidgetTester tester, MediaQueryData data, {double extra = 0}) async {
      late double space;
      await tester.pumpWidget(MediaQuery(
        data: data,
        child: Builder(builder: (context) {
          space = bottomSafeSpace(context, extra: extra);
          return const SizedBox();
        }),
      ));
      return space;
    }

    testWidgets('the navigation bar, or the keyboard when it is open', (tester) async {
      expect(await spaceWith(tester, const MediaQueryData(padding: EdgeInsets.only(bottom: 48))), 48);
      // With the keyboard up, Flutter moves the bar's room into the insets.
      expect(await spaceWith(tester, const MediaQueryData(viewInsets: EdgeInsets.only(bottom: 300))), 300);
      expect(await spaceWith(tester, const MediaQueryData(padding: EdgeInsets.only(bottom: 48)), extra: 8), 56);
    });
  });

  testWidgets('the new-notebook sheet keeps Create above the navigation bar', (tester) async {
    const size = Size(800, 1000);
    withNavBar(tester, size);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showNewNotebookSheet(context,
                  defaultTitle: 'Physics', defaultPaper: const Paper()),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final create = tester.getRect(find.widgetWithText(FilledButton, 'Create'));
    expect(create.bottom, lessThanOrEqualTo(size.height - navBar - 8));
  });

  testWidgets('the Convert sheet keeps its Convert button above the navigation bar',
      (tester) async {
    final h = await ConvertHarness.open(tester, pages: [threeLines()], recognizer: reader());
    withNavBar(tester, const Size(1000, 1400));
    await tester.pump();
    await h.tapConvert();
    await settle(tester);
    final button = tester.getRect(find.byKey(const ValueKey('convert-apply')));
    expect(button.bottom, lessThanOrEqualTo(1400 - navBar));
  });
}
