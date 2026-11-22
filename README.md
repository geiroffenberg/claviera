# Claviera

Claviera is an Android landscape-first piano score sketchpad. The current
prototype opens a blank four-bar score in 4/4. Projects can be saved on the
device; unsaved changes are held in memory.

## Run

With Flutter and the Android SDK installed, connect an Android device or start an
emulator, then run `flutter pub get` and `flutter run` from this directory.
The app requests both landscape orientations at startup.

## Using the editor

- Select a voice, note/rest and duration on the rails. Scroll a rail if its
  controls don't fit on screen. Values run from whole through 64th; dots are
  available through the 32nd.
- Tap the clefs or time signature at the beginning of the staff to open
  **Score settings**. Choose the initial key signature and time signature.
  Key signatures change the sounding pitch of existing notes
  without explicit accidentals as well as newly entered notes. Explicit
  accidentals override the key on their individual note; accidental carry
  through the rest of the bar is not yet implemented.
- Changing the meter keeps each event in its existing bar. A shorter meter is
  rejected if a note or explicit rest no longer fits. A meter change is also
  blocked if it changes the length of a bar crossed by an existing tied note;
  edit that tie first. Undo and Redo include score settings.
- Use the **Bar** arrows in the header to choose the bar to write in. The
  selected bar is shaded and the green cursor marks the next entry point for
  the active voice in that bar. Each bar is numbered above its starting
  barline. Changing bars does not modify the score.
- In Write mode, touch and drag vertically to preview a pitch, then release to
  append it at the green cursor, regardless of horizontal touch position. In
  Rest mode, touch the staff to append a rest. Drag with two fingers to scroll
  the score. An entry cannot overlap a later note or an explicit rest; a note
  crossing a barline may consume generated rests in the next bar.
  Dragging between the treble and bass staves switches the note to that staff;
  chord stack keeps the selected chord's staff.
- On Android, the piano preview plays the pitch while entering or dragging a
  note. Use the speaker button in the header to mute it. It is an experimental
  single-note preview; device latency may vary.
- Press **Play** to play the whole score from the beginning, or **Stop** to
  stop immediately. Playback includes all voices and chord pitches; empty space
  and rests are silent. Tap the BPM value to set a score-wide tempo from 30 to
  240 quarter notes per minute (default 120). Editing is disabled while
  playing, and playback stops at the last event or when the app is backgrounded.
  The speaker button mutes note-entry preview only, not score playback.
- Tap a bar number to open **Bar settings**, then choose **Tempo** or
  **Key and time signature**. Tempo changes apply until the next tempo
  marking, including during tied notes; the header BPM is the initial tempo.
  In the first bar, key and time opens the initial score settings. For later
  bars, use the switches to add or remove changes. Each change applies from that bar
  until the next change of the same kind. Key changes affect existing notes
  that begin under the new key; a note tied across a key change retains the
  pitch from its start. Changes are saved with the project and can be undone.
- Choose **Repeats** in Bar settings to add a start sign at the beginning or an
  end sign at the end of that bar. An end sign plays the passage one additional
  time, then continues; without an unmatched start sign it repeats from the
  beginning. Each end sign repeats once, and separate consecutive repeats are
  supported. Tempo on a jump returns to the tempo in effect at its destination.
  Repeat signs are saved and support Undo and Redo.
  Nested repeats are not yet supported; playback reports an error for nested
  start signs. Playback also reports an error if a tied note crosses a repeat
  jump or destination boundary; edit the tie before playing.
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
- Choose **Export PDF** in the menu, then select a destination in Android's
  file picker. The score is arranged into systems on A4 portrait pages.
  PDF pages are rendered as images; dense passages may need manual review
  before printing. PDF is for sharing/printing, not reopening for editing.
- The menu contains **New score**, **Open project**, **Save**, **Save as** and
  **Rename**. The first save asks for a name; Save updates that project, while
  Save as creates a separate copy. New and Open ask whether to save or discard
  unsaved changes. Android Back also warns about unsaved changes. Project files
  are stored privately by the app and can be removed when the app is
  uninstalled or its data is cleared. Save manually; sudden process termination
  or force-closing the app can lose unsaved changes.

Each voice advances independently in each bar. Editing leaves later notes in
place: gaps before later events **in the same bar** are filled with generated
rests. The unfinished end of a bar is left empty, even when later bars contain
notes. Explicitly entered rests remain; an empty bar for one voice does not
affect the other voices. Lengthening a note can consume following rests but
cannot overlap a later note.

Notes crossing a barline are one logical event shown as tied segments; editing
or deleting a tied note (or a pitch in its chord) affects the entire tied
event, including its continuation in the next bar. Measures are added as
needed.

V1 and V3 use up-stems; V2 and V4 use down-stems on both staves. Consecutive
eighth notes and shorter notes in the same voice, staff and beat are beamed,
with additional beams or beamlets for shorter values. Rests, gaps, staff
changes, beats and barlines break groups. Compound eighth-note meters such as
6/8 use dotted-quarter beats; manual beam overrides are not yet available.

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
  audio/
    piano_preview.dart         Android preview and playback controller
    score_playback.dart        Playback timing from logical voice events
  storage/
    projects.dart              Versioned local project storage
  notation/
    score_viewport.dart        Touch input and two-finger scrolling
    score_painter.dart         SMuFL grand-staff rendering
    print_layout.dart          Paginated score rendering for PDF export
    beaming.dart               Voice stem directions and rhythmic beam grouping
  ui/
    workspace_screen.dart      Rails and editing interactions
    workspace_menu.dart        Redo and future actions
assets/fonts/                  Bravura font and its SIL OFL license
android/app/src/main/assets/piano/  CC0 piano samples and provenance
```

Timing uses 960 ticks per quarter. Logical events use absolute ticks in the
editor; rendered segments use measure-relative ticks. A chord is one logical
event with multiple pitches sharing its duration. Pitch positions use C0 = 0,
D0 = 1, …, C4 = 28, independent of accidentals.

MusicXML/MIDI export, ads, and clef changes per bar are not implemented. The remaining disabled menu
items are placeholders. Bravura is distributed under the license in
`assets/fonts/LICENSE-Bravura.txt`.

The Android preview and experimental playback use SoundPool and a small set of CC0 Steinway B samples
derived from the Versilian Community Sample Library. See the accompanying
`android/app/src/main/assets/piano/README.txt` for sources and processing.
Samples are at most three seconds long, so longer held notes decay or end before
their notated duration. SoundPool timing and pitch-shifted samples are
provisional; playback supports at most 64 simultaneous notes and does not yet
provide a playhead. The sample engine supports MIDI
notes 10–127.
