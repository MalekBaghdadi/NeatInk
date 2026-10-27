/// Public surface of the handwriting geometry helpers (baseline, x-height,
/// deskew, robust statistics, resampling) shared by the recognition code.
///
/// The auto-tidy pipeline that used to live here was removed in v1.1; see
/// docs/beautify-spec.md (kept for reference).
library;

export 'features.dart' show StrokeClass, WordAnalysis, analyzeWord;
export 'tidy_config.dart';
