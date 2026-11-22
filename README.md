# Claviera

Claviera is an Android landscape-first piano score sketchpad. The current
prototype opens a blank four-bar score in 4/4; changes are held in memory and
lost when the app closes.

## Run

With Flutter and the Android SDK installed, connect an Android device or start an
emulator, then run `flutter pub get` and `flutter run` from this directory.
The app requests both landscape orientations at startup.

## Using the editor

- Select a voice, note/rest and duration on the rails. Scroll a rail if its
  controls don't fit on screen. Values run from whole through 64th; dots are
  available through the 32nd.
- Use the **Bar** arrows in the header to choose the bar to write in. The
  selected bar is shaded and the green cursor marks the next entry point for
  the active voice in that bar. Changing bars does not modify the score.
- In Write mode, touch and drag vertically to preview a pitch, then release to
  append it at the green cursor, regardless of horizontal touch position. In
  Rest mode, touch the staff to append a rest. Drag with two fingers to scroll
  the score. An entry cannot overlap a later note or an explicit rest; a note
  crossing a barline may consume generated rests in the next bar.
- Switch to Edit mode and tap an event in the active voice, or use the
  left/right arrows to select one. Drag a selected note vertically to change
  its pitch. The up/down arrows select a pitch in a chord; accidentals and Delete
  apply to that pitch. Changing a duration in Edit mode changes the selected
  event. Deleting the only pitch deletes the event.
- To fill a rest, select it in Edit mode, switch to Write mode, choose a note
  of no longer than that rest, and enter its pitch. The leftover space remains
  rest. To add a chord pitch, select a note, switch to Write mode, enable Chord
  Stack, and enter a pitch. Switch Chord Stack off to append again.
- Undo is on the right rail; Redo is in the menu.

Each voice advances independently in each bar. Editing leaves later notes in
place: gaps before later events **in the same bar** are filled with generated
rests. The unfinished end of a bar is left empty, even when later bars contain
notes. Explicitly entered rests remain; an empty bar for one voice does not
affect the other voices. Lengthening a note can consume following rests but
cannot overlap a later note.

Notes crossing a barline are one logical event shown as tied segments; editing
or deleting a tied note (or a pitch in its chord) affects the entire tied
event, including its continuation in the next bar. Measures are added as
needed. Bar selection is independent of the future barline signature controls.

V1 and V3 use up-stems; V2 and V4 use down-stems on both staves. Consecutive
eighth notes and shorter notes in the same voice, staff and beat are beamed,
with additional beams or beamlets for shorter values. Rests, gaps, staff
changes, beats and barlines break groups. Compound eighth-note meters such as
6/8 use dotted-quarter beats; manual beam overrides and per-bar time
signatures are not yet available.

## Structure and limitations

```text
lib/
  main.dart                    App entry and landscape orientation
  models/
    score.dart                 Tick-based notation models
    blank_score.dart           Empty startup score
    demo_score.dart            Sample events
  editor/
    score_editor.dart          Voice timelines, rest handling and undo/redo
  notation/
    score_viewport.dart        Touch input and two-finger scrolling
    score_painter.dart         SMuFL grand-staff rendering
    beaming.dart               Voice stem directions and rhythmic beam grouping
  ui/
    workspace_screen.dart      Rails and editing interactions
    workspace_menu.dart        Redo and future actions
assets/fonts/                  Bravura font and its SIL OFL license
```

Timing uses 960 ticks per quarter. Logical events use absolute ticks in the
editor; rendered segments use measure-relative ticks. A chord is one logical
event with multiple pitches sharing its duration. Pitch positions use C0 = 0,
D0 = 1, …, C4 = 28, independent of accidentals.

Local JSON persistence, PDF/MusicXML/MIDI export, audio, ads, and tempo, key and
time-signature changes per bar are not implemented. The remaining disabled menu
items are placeholders. Bravura is distributed under the license in
`assets/fonts/LICENSE-Bravura.txt`.
