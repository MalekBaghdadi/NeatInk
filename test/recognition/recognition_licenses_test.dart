import 'package:flutter/foundation.dart' show LicenseEntry;
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/recognition/recognition_licenses.dart';

String _text(LicenseEntry e) => e.paragraphs.map((p) => p.text).join('\n');

void main() {
  test('credits the model, the runtime and the word list', () async {
    final entries = await recognitionLicenseEntries().toList();
    final names = [for (final e in entries) e.packages.join()];
    expect(names, hasLength(3));
    expect(names[0], contains('PaddleOCR'));
    expect(names[1], 'ONNX Runtime');
    expect(names[2], contains('word list'));
    final words = _text(entries.last);
    expect(words, contains('CC BY 3.0'));
  });

  test('the model is credited under Apache-2.0 with the standard notice', () async {
    final model = _text((await recognitionLicenseEntries().toList()).first);
    expect(model, contains('PaddlePaddle'));
    expect(model, contains('PP-OCRv5'));
    expect(model, contains('https://huggingface.co/PaddlePaddle/en_PP-OCRv5_mobile_rec_onnx'));
    expect(model, contains('Apache License, Version 2.0'));
    expect(model, contains('https://www.apache.org/licenses/LICENSE-2.0'));
    expect(model, contains('WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND'));
    // The old model is gone from the credits.
    expect(model, isNot(contains('SimpleHTR')));
    expect(model, isNot(contains('IAM')));
  });
}
