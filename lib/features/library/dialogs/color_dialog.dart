import 'package:flutter/material.dart';

import '../widgets/color_swatch_button.dart';

/// Lets the user pick one of [colors]. Returns the chosen ARGB colour, or
/// null when cancelled. Tapping a swatch confirms right away.
Future<int?> showColorDialog(
  BuildContext context, {
  required String title,
  required List<int> colors,
  int? selected,
}) =>
    showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 320,
          child: ColorSwatchPicker(
            colors: colors,
            selected: selected,
            size: 44,
            onSelected: (c) => Navigator.of(context).pop(c),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
