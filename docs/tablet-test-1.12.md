# Tablet test run for v1.12.0

New in this version (session 14): **record a lecture** while writing and
play it back, alone or with the notes appearing as they were written, and a
**guided tour** of each screen, plus a short description on every button
(hold a finger on it, or hover the pen over it). Report each step as
"N. title: ✅ Works / ❌ Problem / ⏭️ Skipped" plus a note.

## The steps

1. **Get the new version.** Install `releases/latest/download/MariamsNotes.apk`
   over the old app. Expect "Version 1.12.0" at the bottom of Settings.
2. **The library tour.** When the app opens, a tour starts by itself: the
   screen dims and one button at a time is lit, with a card saying what it
   does. Tap Next through it. Expect the lit ring around the right button
   each time (New, a notebook, Folders, Search, Sort, Settings).
3. **The notebook tour.** Open a notebook: a second tour shows the writing
   tools. Open a PDF notebook: two more cards about the PDF. Later,
   ⋮ › Show me around shows it again; Settings › Show me around again brings
   all tours back.
4. **What is this button?** Hold a finger on any button (pen, lasso, the
   microphone, undo...) and, separately, hover the M-Pencil just above one
   without touching. Expect a dark label saying what it does.
5. **Record.** In a notebook, tap the microphone at the top. Read the
   explanation, tap Start recording, and tap Allow when the tablet asks for
   the microphone (and for notifications). Expect a red bar with the time
   running and a small level meter that moves when someone talks.
6. **Keep recording in the background.** While recording, write a few lines,
   tap Pause and Go on, then switch to another app for a minute and turn the
   screen off for a minute. Expect "Recording your lecture" in the
   notifications and the time still running when you come back. If it
   stopped by itself, tell us (Huawei's battery manager may close it:
   Settings › Battery › App launch › Mariam's Notes › Manage manually, all
   three on).
7. **Leave the notebook while recording.** Go back to the library. Expect a
   question: Keep recording keeps it on and shows a red banner at the top of
   the library; Open notebook goes back to it, Stop ends it. Expect "Recording
   saved".
8. **Play.** Tap the headphones button, then Play. Expect the sound, with
   Back 10 s / Ahead 10 s, the slider and the speed button (1×, 1.25×,
   1.5×, 2×, 0.75×) working.
9. **Play with notes.** Tap the headphones, then Play with notes. Expect the
   notes faint at first, each one turning dark when the sound reaches the
   moment you wrote it, and the page following the newest note. Tap a faint
   or dark note: it plays from just before you wrote it. "Notes as written"
   off shows all the notes again.
10. **Rename and delete.** In the recordings list, ⋮ › Rename, then
    ⋮ › Delete. Expect the notes untouched.
11. **A real lecture.** Record one whole lecture (an hour or more). Tell us
    whether it kept recording to the end, how the battery did, and whether
    Play with notes matched the notes to the right moments.

## Where each step lives in the code

| Step | Code to look at first |
|---|---|
| 2-3 tours | `features/tour/tour.dart` (`showTour`, `findTourTarget`, `TourOverlay`), `features/tour/tours.dart` (`startTourWhenOnTop`, `libraryTour`, `notebookTour`, `pdfTour`, `TourMemory`), `library_screen.dart`, `editor_screen.dart` (`menu-tour`), `settings_screen.dart` (`settings-tour`) |
| 4 tooltips | `app/theme.dart` (`tooltipTheme`), `editor_tool.dart` (`EditorTool.hint`), `toolbar_widgets.dart`, `library_screen.dart` |
| 5-7 recording | `AudioPlugin.kt`, `RecordingService.kt`, `audio/audio_channel.dart`, `features/recording/recording_controller.dart`, `recording_banner.dart`, `integrations/recordings/recording_widgets.dart` (`RecordButton`, `RecordingBar`, the intro and leave dialogs) |
| 8-10 playback | `integrations/recordings/playback_controller.dart` (`PlaybackController`, `leadInMs`), `recording_widgets.dart` (`PlayerBar`, the recordings sheet), `document/recording.dart` (`audioPositionOf`, `wallTimeAt`) |
| 9 notes appearing | `canvas/ink_reveal.dart` (`aheadOpacity`), `page_painting.dart`, `text_layer.dart`, `render/text_style.dart` (`faintFrom`), `Stroke.writtenAt`, `TextItem.times` |
