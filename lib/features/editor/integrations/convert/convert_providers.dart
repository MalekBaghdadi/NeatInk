import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../recognition/htr_channel.dart';
import '../../../../recognition/word_image.dart';

/// The handwriting recogniser the convert feature uses. Tests override it
/// with a fake that returns canned readings.
final htrRecognizerProvider =
    Provider<HtrRecognizer>((ref) => HtrRecognizer.instance);

/// Renders the 128x32 word crops shown in "Show what the recognizer saw".
/// The default draws with `dart:ui`; `Picture.toImage` never completes under
/// `flutter_tester`, so widget tests override it with
/// `PolylineWordImageRenderer`.
final wordImageRendererProvider =
    Provider<WordImageRenderer>((ref) => const UiWordImageRenderer());
