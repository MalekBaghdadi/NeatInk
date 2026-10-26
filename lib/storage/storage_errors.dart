/// Errors thrown by the storage layer. They carry enough context for the UI
/// to show a clear message ("This page could not be read") without exposing
/// file system details.
library;

/// A JSON document (and its `.bak` copy, if any) could not be parsed.
///
/// The files are left untouched on disk so nothing is lost; the next
/// successful write keeps the unreadable file as `<name>.corrupt`.
class CorruptFileException implements Exception {
  const CorruptFileException(this.path, this.cause);

  /// The main file that failed to parse.
  final String path;

  /// The underlying parse or I/O error.
  final Object cause;

  @override
  String toString() => 'CorruptFileException($path): $cause';
}

/// The notebook does not exist (it was never created, or was deleted).
class NotebookNotFoundException implements Exception {
  const NotebookNotFoundException(this.notebookId);

  final String notebookId;

  @override
  String toString() => 'NotebookNotFoundException($notebookId)';
}
