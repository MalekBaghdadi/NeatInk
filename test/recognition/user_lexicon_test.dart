import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/recognition/user_lexicon.dart';

class _FailingStore implements UserLexiconStore {
  int attempts = 0;

  @override
  Future<List<String>> load() async => throw StateError('no disk');

  @override
  Future<void> save(List<String> words) async {
    attempts++;
    throw StateError('disk full');
  }
}

void main() {
  group('UserLexicon', () {
    test('normalize accepts plain words only', () {
      expect(UserLexicon.normalize('Malek'), 'Malek');
      expect(UserLexicon.normalize('  malek. '), 'malek');
      expect(UserLexicon.normalize('"Baghdadi",'), 'Baghdadi');
      expect(UserLexicon.normalize('O\u2019Brien'), "O'Brien");
      expect(UserLexicon.normalize("Malek's"), 'Malek');
      expect(UserLexicon.normalize('caf\u00e9'), isNull);
      expect(UserLexicon.normalize('a'), isNull);
      expect(UserLexicon.normalize('x1'), isNull);
      expect(UserLexicon.normalize('2025'), isNull);
      expect(UserLexicon.normalize('well-known'), isNull);
      expect(UserLexicon.normalize(''), isNull);
      expect(UserLexicon.normalize('a' * 41), isNull);
    });

    test('add keeps the capitalisation the user typed', () {
      final u = UserLexicon();
      expect(u.add('Malek'), isTrue);
      expect(u.add('Malek'), isFalse);
      expect(u.add('1'), isFalse);
      expect(u.contains('malek'), isTrue);
      expect(u.contains('MALEK'), isTrue);
      expect(u.formOf('malek'), 'Malek');
      expect(u.formOf('nobody'), isNull);
      expect(u.words, ['Malek']);
      // a new spelling of a known word replaces it
      expect(u.add('MALEK'), isTrue);
      expect(u.words, ['MALEK']);
      expect(u.length, 1);
    });

    test('learn takes the plain words of what the user typed', () {
      final u = UserLexicon();
      expect(u.learn('Malek Baghdadi'), 2);
      expect(u.learn('Hello, Mariam! Call 555 now.'), 4); // hello, mariam, call, now
      expect(u.words, containsAll(['Malek', 'Baghdadi', 'Mariam']));
      expect(u.learn('Malek'), 0);
      expect(u.learn("O\u2019Brien's"), 1); // O'Brien (the 's is dropped)
      expect(u.learn('Jean-Luc caf\u00e9 x2'), 2); // Jean, Luc
    });

    test('learn skips words the word list already knows', () {
      final u = UserLexicon();
      const known = {'the', 'hello'};
      expect(u.learn('The Hello Mariam', isKnownWord: known.contains), 1);
      expect(u.words, ['Mariam']);
    });

    test('remove and clear', () {
      final u = UserLexicon()
        ..add('Malek')
        ..add('Mariam');
      expect(u.remove('malek'), isTrue);
      expect(u.remove('malek'), isFalse);
      expect(u.words, ['Mariam']);
      u.clear();
      expect(u.isEmpty, isTrue);
    });

    test('the oldest entries go first beyond maxWords', () {
      final u = UserLexicon(maxWords: 3);
      for (final w in ['Aa', 'Bb', 'Cc', 'Dd']) {
        u.add(w);
      }
      expect(u.words, ['Bb', 'Cc', 'Dd']);
      u.add('Bb'); // unchanged: stays where it is
      u.add('BB'); // changed: moves to the end
      expect(u.words, ['Cc', 'Dd', 'BB']);
    });

    test('nearby finds words within the edit distance', () {
      final u = UserLexicon()
        ..add('Malek')
        ..add('Mariam')
        ..add('Baghdadi');
      expect(u.nearby('malck', 1), ['Malek']);
      expect(u.nearby('masion', 2), isEmpty);
      expect(u.nearby('masion', 3), ['Mariam']);
      expect(u.nearby('baghbadi', 1), ['Baghdadi']);
    });
  });

  group('persistence', () {
    test('changes are saved through the store', () async {
      final store = InMemoryUserLexiconStore();
      final u = UserLexicon(store: store)
        ..add('Malek')
        ..add('Mariam');
      await u.flush();
      expect(store.saved, ['Malek', 'Mariam']);
      u.remove('Malek');
      await u.flush();
      expect(store.saved, ['Mariam']);
    });

    test('a new dictionary loads what was saved', () async {
      final store = InMemoryUserLexiconStore(['Malek', 'bad word!', 'Baghdadi']);
      final u = UserLexicon(store: store);
      await u.load();
      expect(u.words, ['Malek', 'Baghdadi']);
      expect(u.contains('baghdadi'), isTrue);
    });

    test('words added before the load finished are kept, not overwritten', () async {
      final store = InMemoryUserLexiconStore(['Malek']);
      final u = UserLexicon(store: store)..add('Mariam');
      await u.flush(); // the save waits for the load
      expect(store.saved, ['Malek', 'Mariam']);
      expect(u.words, ['Malek', 'Mariam']);
    });

    test('a failing store never throws', () async {
      final store = _FailingStore();
      final u = UserLexicon(store: store);
      await u.load();
      expect(u.add('Malek'), isTrue);
      await u.flush();
      expect(store.attempts, 1);
      expect(u.contains('Malek'), isTrue); // still in memory
    });

    group('JsonFileUserLexiconStore', () {
      late Directory dir;
      setUp(() => dir = Directory.systemTemp.createTempSync('neatink_lexicon_'));
      tearDown(() => dir.deleteSync(recursive: true));

      JsonFileUserLexiconStore store() => JsonFileUserLexiconStore(directory: () async => dir);
      File file() => File('${dir.path}/recognition/user_lexicon.json');

      test('round trip through a JSON file, written atomically', () async {
        final u = UserLexicon(store: store())
          ..add('Malek')
          ..add('Baghdadi');
        await u.flush();
        final json = jsonDecode(file().readAsStringSync()) as Map<String, dynamic>;
        expect(json['version'], 1);
        expect(json['words'], ['Malek', 'Baghdadi']);
        expect(file().parent.listSync().map((e) => e.uri.pathSegments.last), ['user_lexicon.json']); // no temp files

        final again = UserLexicon(store: store());
        await again.load();
        expect(again.words, ['Malek', 'Baghdadi']);
      });

      test('a missing or corrupt file is an empty dictionary', () async {
        expect(await store().load(), isEmpty);
        file().createSync(recursive: true);
        file().writeAsStringSync('{"words": [');
        expect(await store().load(), isEmpty);
        file().writeAsStringSync('{"words": "nope"}');
        expect(await store().load(), isEmpty);
        file().writeAsStringSync('{"words": ["Malek", 3, null]}');
        expect(await store().load(), ['Malek']);
      });

      test('non-ASCII text in the file is not a problem', () async {
        file().createSync(recursive: true);
        file().writeAsBytesSync(utf8.encode('{"words": ["Malek", "caf\u00e9"]}'));
        final u = UserLexicon(store: store());
        await u.load();
        expect(u.words, ['Malek']); // caf\u00e9 is not a plain Latin word
      });
    });
  });
}
