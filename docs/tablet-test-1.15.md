# Tablet test run for v1.15.0

New in this version (session 16): a **ruler**, **line styles** (dashed, dotted,
wavy, zigzag, double) and a **pen settings panel**, made from a TikTok video
the owner sent. Nothing here has been tried on a tablet yet: please go through
it. The 1.14 steps (`docs/tablet-test-1.14.md`) and the older open checklists
stay open. Report each step as "N. title: ✅ Works / ❌ Problem /
⏭️ Skipped" plus a note.

## The steps

1. **Get the new version.** Install `releases/latest/download/MariamsNotes.apk`
   (or Settings › About › Get the newest version). Expect "Version 1.15.0" at
   the bottom of Settings.
2. **The ruler.** In a notebook, tap the ruler button in the tool row (after
   the tools). Expect a see-through ruler across the page with centimetre
   marks and "0°" in the middle. Drag it with one finger; turn it with two
   fingers (it clicks at every 15°, the middle shows the angle).
3. **Straight lines.** With the pen, draw along either long edge of the ruler
   (start within a finger's width of the edge). Expect a perfectly straight
   line along the edge, from where the pen landed to where it lifted, even
   when the hand wobbles. Draw away from the ruler: normal ink. One undo
   removes the whole line.
4. **The ruler stays put.** Scroll and zoom the page with the ruler out.
   Expect the ruler to stay where it is on the screen. Tap the ruler button
   again: it goes away. Rest the pen hand on the screen while writing: the
   ruler must not move.
5. **The pen settings.** Tap the little pill at the end of the pen's row (or
   tap the selected pen again). Expect a panel like the one in the video:
   Reset, Thickness, Concentration, Line Style, Horizontal drawing, Color.
   Tap outside it to close it.
6. **Line styles.** Pick Dashed, Dotted, Wavy, Zigzag and Double in turn and
   draw a line along the ruler each time. Expect each look. With Wavy or
   Zigzag the "Wavy Line Height" and "Wavy Line Width" sliders appear: try
   them.
7. **Thickness and concentration.** Make the line thicker, then fainter.
   Expect the line to follow, and the waves and dashes to grow with the
   thickness. Reset puts the pen back (the colour stays).
8. **Horizontal drawing.** Switch it on and draw a rough line without the
   ruler. Expect a perfectly horizontal line. Switch it off again.
9. **The highlighter too.** Select the highlighter, open its settings, pick
   Dashed or Wavy and draw. Expect a see-through dashed or wavy highlight.
   Shapes drawn with the shape tool follow the line style too.
10. **Erase and select.** Rub a wavy line with the partial eraser and lasso a
    dashed one. Expect the eraser to cut it where you rub and the lasso to
    move and resize it.
11. **PDF.** Export a page with all the line styles as PDF. Expect the same
    lines in the PDF.
12. **Old notes.** Open a notebook from before the update. Expect everything
    as it was.

## Where each step lives in the code

| Step | Code to look at first |
|---|---|
| 2, 4 ruler | `features/editor/integrations/ruler/` (`ruler_geometry.dart`, `ruler_gesture.dart`, `ruler_painter.dart`, `ruler_touch_interceptor.dart`), `canvas/document_view.dart` (`_interceptTouch`) |
| 3 straight lines | `canvas/ink_tool_handler.dart` (`_constrainedLine`), `ruler/ruler_edge_constraint.dart`, `canvas/stroke_constraint.dart` |
| 5, 7 panel | `toolbar/ink_settings_panel.dart`, `ink_settings_model.dart`, `ink_sliders.dart`, `line_style_widgets.dart` |
| 6 line styles | `ink/line_style.dart` (the lengths), `ink/line_pattern.dart`, `render/stroke_outline.dart` (`strokeOutlines`) |
| 8 horizontal | `canvas/stroke_constraint.dart` (`HorizontalConstraint`), `tool_prefs.dart` |
| 11 PDF | `pdf/export_builder.dart` |
