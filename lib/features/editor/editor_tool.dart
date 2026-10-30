/// The tools of the editor's tool row.
///
/// Pen and highlighter are built into the editor core. The other tools are
/// enabled when an integration registers a `CanvasToolHandler` for them (see
/// `EditorExtensions.toolHandlers`); until then the toolbar shows them
/// disabled.
enum EditorTool {
  pen('Pen', 'write and draw. Scribble over writing to delete it'),
  highlighter('Highlighter', 'mark important words in colour'),
  eraser('Eraser', 'rub over ink or typed words to erase them'),
  lasso('Lasso', 'draw a loop around notes to move, copy, convert or restyle them'),
  text('Text', 'tap the page to type a text box'),
  image('Image', 'add a picture from the tablet'),
  shape('Shapes', 'draw straight lines, arrows, boxes and circles');

  const EditorTool(this.label, this.hint);

  /// User-facing name (tooltips, menus).
  final String label;

  /// What the tool does, in a few words (the tooltip after the name, shown
  /// on a long press or when the pen hovers over it).
  final String hint;

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
