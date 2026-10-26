import '../../document/notebook_meta.dart';

/// Colour of a new folder (matches the [Folder] default).
const int defaultFolderColor = 0xFF90A4AE;

/// Colours offered for folders: the default grey, then the cover colours.
const List<int> folderColors = [defaultFolderColor, ...NotebookMeta.coverColors];

/// Human names for the palette colours, used for tooltips and screen
/// readers. Unknown colours fall back to their hex value.
const Map<int, String> _colorNames = {
  0xFF90A4AE: 'Grey',
  0xFF3F51B5: 'Indigo',
  0xFF1E88E5: 'Blue',
  0xFF00897B: 'Teal',
  0xFF43A047: 'Green',
  0xFFF9A825: 'Yellow',
  0xFFEF6C00: 'Orange',
  0xFFE53935: 'Red',
  0xFFD81B60: 'Pink',
  0xFF8E24AA: 'Purple',
  0xFF6D4C41: 'Brown',
  0xFF546E7A: 'Blue grey',
  0xFF263238: 'Charcoal',
  0xFFFFFFFF: 'White',
  0xFFFAF5E8: 'Cream',
  0xFF1F2124: 'Dark',
};

String colorName(int argb) =>
    _colorNames[argb] ??
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
