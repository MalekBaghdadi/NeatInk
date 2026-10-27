import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/recognition/recognition_licenses.dart';

void main() {
  test('credits the model, the runtime and the word list', () async {
    final entries = await recognitionLicenseEntries().toList();
    final names = [for (final e in entries) e.packages.join()];
    expect(names, hasLength(3));
    expect(names[0], contains('SimpleHTR'));
    expect(names[1], 'ONNX Runtime');
    expect(names[2], contains('word list'));

    final model = entries.first.paragraphs.map((p) => p.text).join('\n');
    expect(model, contains('IAM'));
    expect(model, contains('non-commercial'));
    final words = entries.last.paragraphs.map((p) => p.text).join('\n');
    expect(words, contains('CC BY 3.0'));
  });
}
