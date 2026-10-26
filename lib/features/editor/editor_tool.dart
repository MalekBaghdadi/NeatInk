/// The tools of the editor's tool row.
///
/// Pen and highlighter are built into the editor core. The other tools are
/// enabled when an integration registers a `CanvasToolHandler` for them (see
/// `EditorExtensions.toolHandlers`); until then the toolbar shows them
/// disabled.
enum EditorTool {
  pen('Pen'),
  highlighter('Highlighter'),
  eraser('Eraser'),
  lasso('Lasso'),
  text('Text'),
  image('Image'),
  shape('Shapes');

  const EditorTool(this.label);

  /// User-facing name (tooltips, menus).
  final String label;

  /// Tools that lay down ink strokes through the live layer.
  bool get drawsInk => this == pen || this == highlighter;
}

/// How the eraser removes ink.
enum EraserMode {
  /// Removes every stroke it touches, whole.
  stroke('Stroke eraser'),

  /// Cuts away only the touched part of strokes.
  pixel('Partial eraser');

  const EraserMode(this.label);
  final String label;
}
