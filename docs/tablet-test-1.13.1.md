# Tablet test run for v1.13.1

A fix release (session 15): **the keyboard closed again right after it
opened** whenever Mariam tapped a text box to type. Only these steps are
new; the 1.13, 1.12 and 1.11 steps on the checklist page stay open. Report
each step as "N. title: ✅ Works / ❌ Problem / ⏭️ Skipped" plus a note.

## The steps

1. **Get the new version.** Install `releases/latest/download/MariamsNotes.apk`
   over the old app. Expect "Version 1.13.1" at the bottom of Settings.
2. **Type in a new text box.** In a notebook with a few pages, scroll to
   page 2 or later, choose the text tool (T) and tap empty paper with a
   finger. Expect the keyboard to come up **and stay up**; type a sentence.
3. **Type in an old text box.** Tap Done, then tap that box again (finger
   or pen). Expect the keyboard to stay up again. Do it three or four
   times, also with a box near the bottom of the screen: expect the page to
   move up so the box is above the keyboard, where you can see what you type.
4. **From the lasso.** Lasso typed text, tap the keyboard button (Edit text
   with the keyboard). Expect the keyboard to stay up while you type.
5. **Scroll a little while typing.** With the keyboard up, move the page a
   little with one finger. Expect the keyboard to stay up.

## Where each step lives in the code

| Step | Code to look at first |
|---|---|
| 2-5 keyboard closing | `canvas/document_view.dart` (`_buildPages`: the `Positioned.fromRect` key), `canvas/viewport_controller.dart` (`applyViewportSize`, `keepInViewOnResize`), `integrations/text_images/text_editor.dart` (`docRect`), `text_images_integration.dart`; test `test/editor/integrations/text_images/text_keyboard_test.dart` |
