import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/settings/my_words_screen.dart';
import 'package:neatink/recognition/user_lexicon.dart';

void main() {
  late UserLexicon lexicon;

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [myWordsLexiconProvider.overrideWithValue(lexicon)],
      child: const MaterialApp(home: MyWordsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() => lexicon = UserLexicon());

  testWidgets('shows an empty state, then the words that are added',
      (tester) async {
    await pumpScreen(tester);
    expect(find.byKey(const ValueKey('my-words-empty')), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('my-words-field')), 'Malek Mariam');
    await tester.tap(find.byKey(const ValueKey('my-words-add')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('my-words-empty')), findsNothing);
    expect(find.byKey(const ValueKey('my-word-Malek')), findsOneWidget);
    expect(find.byKey(const ValueKey('my-word-Mariam')), findsOneWidget);
    expect(lexicon.words, containsAll(['Malek', 'Mariam']));
  });

  testWidgets('a word can be removed', (tester) async {
    lexicon.add('Baghdadi');
    await pumpScreen(tester);
    expect(find.byKey(const ValueKey('my-word-Baghdadi')), findsOneWidget);

    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('my-word-Baghdadi')),
        matching: find.byTooltip('Delete')));
    await tester.pumpAndSettle();

    expect(lexicon.contains('baghdadi'), isFalse);
    expect(find.byKey(const ValueKey('my-word-Baghdadi')), findsNothing);
  });

  testWidgets('rejects text that is not a word and says why', (tester) async {
    await pumpScreen(tester);
    await tester.enterText(find.byKey(const ValueKey('my-words-field')), '123');
    await tester.tap(find.byKey(const ValueKey('my-words-add')));
    await tester.pumpAndSettle();
    expect(find.text('Use letters only (A-Z, a-z).'), findsOneWidget);
    expect(lexicon.isEmpty, isTrue);
  });

  testWidgets('says so when the word is already there', (tester) async {
    lexicon.add('Malek');
    await pumpScreen(tester);
    await tester.enterText(find.byKey(const ValueKey('my-words-field')), 'Malek');
    await tester.tap(find.byKey(const ValueKey('my-words-add')));
    await tester.pumpAndSettle();
    expect(find.text('Already in your words.'), findsOneWidget);
  });
}
