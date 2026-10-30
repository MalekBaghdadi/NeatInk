import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/settings/app_settings.dart';
import 'package:neatink/ink/ink_point.dart';
import 'package:neatink/ink/stroke.dart';
import 'package:neatink/recognition/text_polish.dart';

import 'harness.dart';

// v1.13.0: the writing bar of a text box reads its strip through the
// convert feature's recogniser.

/// A short word written left to right at x [x0], id prefix [id].
Stroke word(String id, double x0) => Stroke(
      id: '$id-0',
      tool: StrokeTool.pen,
      color: 0xFF1E1E1E,
      size: 2.6,
      raw: [
        for (var i = 0; i <= 12; i++) InkPoint(x0 + i * 5, 60 + (i.isEven ? -10 : 10), 0.5, i * 10),
      ],
    );

void main() {
  testWidgets('reads the strip as one line, with the text before the cursor for capitals', (tester) async {
    final fake = FakeRecognizer({'w': ('many', 0.9)});
    final h = await ConvertHarness.open(tester, recognizer: fake);
    final read = h.controller.extensions.readHandwriting!;
    expect(await read([word('w', 20)], before: 'The brain has'), 'many');
    expect(fake.previousTexts.last, 'The brain has');
    expect(await read(const []), '', reason: 'nothing written');
  });

  const fix = PolishSuggestion(
    original: 'nuerons',
    replacement: 'neurons',
    kind: PolishKind.spelling,
    reason: 'Spelling',
    start: 0,
    end: 7,
  );
  FakeRecognizer misspelt() => FakeRecognizer({'w': ('nuerons', 0.9)})..suggestions['w'] = const [fix];

  testWidgets("autocorrect's own fixes apply when it is on", (tester) async {
    final h = await ConvertHarness.open(tester, recognizer: misspelt(), prefsValues: {
      AppSettings.prefsKey: jsonEncode({'autocorrect': true}),
    });
    expect(await h.controller.extensions.readHandwriting!([word('w', 20)]), 'neurons');
  });

  testWidgets('with autocorrect off the words come as read', (tester) async {
    final h = await ConvertHarness.open(tester, recognizer: misspelt());
    expect(await h.controller.extensions.readHandwriting!([word('w', 20)]), 'nuerons');
  });
}
