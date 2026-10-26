/// Public surface of the "tidy as you write" engine (docs/beautify-spec.md).
library;

export 'features.dart' show StrokeClass, WordAnalysis, analyzeWord;
export 'line_context.dart';
export 'smoothing.dart';
export 'tidy_config.dart';
export 'tidy_pipeline.dart';
export 'transform.dart' show WordTransform;
export 'word_segmenter.dart';
