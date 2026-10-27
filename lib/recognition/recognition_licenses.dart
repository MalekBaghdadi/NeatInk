import 'package:flutter/foundation.dart';

/// Credits for the handwriting recognition on Flutter's licence page
/// (Settings > Open-source licenses): the model, the runtime that executes it
/// and the word list that corrects its output.
///
/// Call once at startup; repeated calls are ignored.
void registerRecognitionLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(recognitionLicenseEntries);
}

bool _registered = false;

const String _apacheNotice = '''
Copyright (c) PaddlePaddle Authors. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
''';

const String _mitBody = '''
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
''';

/// The credit entries, in display order. Public for tests.
Stream<LicenseEntry> recognitionLicenseEntries() async* {
  yield const LicenseEntryWithLineBreaks(
    ['PaddleOCR PP-OCRv5 text recognition model (handwriting to text)'],
    '''
The on-device handwriting recognizer is the English mobile text recognition
model of PP-OCRv5 from the PaddleOCR project of PaddlePaddle / Baidu
(https://github.com/PaddlePaddle/PaddleOCR), in the ONNX export published at
https://huggingface.co/PaddlePaddle/en_PP-OCRv5_mobile_rec_onnx. It runs
entirely on the device and no handwriting ever leaves it.

$_apacheNotice''',
  );
  yield const LicenseEntryWithLineBreaks(
    ['ONNX Runtime'],
    'Copyright (c) Microsoft Corporation. MIT licence.\n\n$_mitBody',
  );
  yield const LicenseEntryWithLineBreaks(
    ['English word list (SymSpell frequency dictionary)'],
    '''
The list of common English words used to correct the recognized text comes
from the SymSpell project by Wolf Garbe
(https://github.com/wolfgarbe/SymSpell), MIT licence. Its word counts derive
from the Google Books Ngram data (https://storage.googleapis.com/books/ngrams/books/datasetsv3.html),
licensed CC BY 3.0 (https://creativecommons.org/licenses/by/3.0/).

$_mitBody''',
  );
}
