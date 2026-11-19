import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/app/app_info.dart';
import 'package:neatink/app/providers.dart';
import 'package:neatink/app/theme.dart';
import 'package:neatink/features/settings/settings_screen.dart';
import 'package:neatink/features/settings/widgets/update_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

// v1.14.0: a button that takes Mariam to the newest version, so updates no
// longer need someone to send her the link.

void main() {
  late SharedPreferences prefs;
  late List<Uri> opened;
  late bool browserAnswers;
  String? clipboard;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    opened = [];
    browserAnswers = true;
    clipboard = null;
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        linkOpenerProvider.overrideWithValue((link) async {
          opened.add(link);
          return browserAnswers;
        }),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const SettingsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  test('the link is the newest release of the arm64 app', () {
    expect(AppInfo.downloadUrl,
        'https://github.com/MalekBaghdadi/NeatInk/releases/latest/download/MariamsNotes.apk');
  });

  testWidgets('About has the button; Download opens the link in the browser', (tester) async {
    await pumpSettings(tester);
    expect(key('settings-update'), findsOneWidget);
    expect(find.text('Get the newest version'), findsOneWidget);
    expect(find.textContaining('You have version ${AppInfo.version}'), findsOneWidget);

    await tester.tap(key('settings-update'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('Your notebooks stay as they are'), findsOneWidget);

    await tester.tap(key('update-download'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(opened, [Uri.parse(AppInfo.downloadUrl)]);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Not now opens nothing', (tester) async {
    await pumpSettings(tester);
    await tester.tap(key('settings-update'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
  });

  testWidgets('no browser: the link is copied and she is told', (tester) async {
    browserAnswers = false;
    await pumpSettings(tester);
    await tester.tap(key('settings-update'));
    await tester.pumpAndSettle();
    await tester.tap(key('update-download'));
    await tester.pumpAndSettle();
    expect(opened, hasLength(1));
    expect(clipboard, AppInfo.downloadUrl);
    expect(find.textContaining('The download link is copied'), findsOneWidget);
  });
}
