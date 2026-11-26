# Claviera

Claviera is an Android landscape-first piano score sketchpad. The current
prototype opens a blank four-bar score in 4/4. Projects and recovery drafts are
stored on the device.

## Run

With Flutter and the Android SDK installed, connect an Android device or start an
emulator, then run `flutter pub get` and `flutter run` from this directory.
The app requests both landscape orientations at startup.

### Google Play review access

The Android Pro dialog includes a **Review access code** field. Supply a private,
non-empty code at build time (replace the placeholder; do not commit the code):

```sh
flutter run --release --dart-define=CLAVIERA_REVIEW_CODE=YOUR_PRIVATE_CODE
flutter build appbundle --release --dart-define=CLAVIERA_REVIEW_CODE=YOUR_PRIVATE_CODE
```

In Play Console's App content access instructions, provide the code and these
steps: open **Menu > Upgrade to Pro**, enter the review access code, and tap
**Activate review access**. The uploaded bundle must include the define.
Without it, the field reports that review access is not configured.

Review access works without billing availability and persists on that device
separately from purchases. It is not a Google Play entitlement and is lost when
app data is cleared. This offline code is embedded in the build and can be
extracted or shared; it is not strong protection against payment bypass.

## Using the editor

- On Android, open **Menu > Open project > Dream** to load the included demo
  composition. It is installed as an editable project on first launch.
- Open **Menu > Getting started** for a short guide to the basic controls.
- Open **Menu > User manual** for an offline guide to the controls and icons.
- Tap the Claviera icon in the top bar for app information and licenses,
  including the Bravura font license and piano sample notice.
- The top two controls on the left rail toggle Write/Edit and Note/Rest.
  Select a voice and duration on the rails. Scroll a rail if its controls
  don't fit on screen. Values run from whole through 64th. Tap **Dot** to
  cycle between no dot, one dot and two dots; double dots are available through
  the 16th and single dots through the 32nd.
- Tap the clefs or time signature at the beginning of the staff to open
  **Score settings**. Choose the initial key signature and time signature.
  Key signatures change the sounding pitch of existing notes
  without explicit accidentals as well as newly entered notes. A sharp, flat or
  natural applies to subsequent notes at the same pitch and octave on that
  staff, including other voices, until another accidental or the next bar.
  Tied notes retain their pitch across barlines. Conflicting simultaneous
  pitches are given explicit signs when necessary to avoid ambiguity.
  Existing projects may sound different if they previously relied on the
  missing accidental carry.
- Changing the meter keeps each event in its existing bar. A shorter meter is
  rejected if a note or explicit rest no longer fits. A meter change is also
  blocked if it changes the length of a bar crossed by an existing tied note;
  edit that tie first. Undo and Redo include score settings.
- Use the **Bar** arrows in the header to choose the bar to write in. The
  selected bar is shaded and the green cursor marks the next entry point for
  the active voice in that bar. Each bar is numbered above its starting
  barline. In Edit mode, tap inside a bar to select it; tapping a note selects
  both the note and its bar. Changing bars does not modify the score.
- Tap the **Bar** label and choose **Go to bar** to jump directly to an
  existing bar. Enter its number and tap **Go**.
- In Write mode, touch and drag vertically to preview a pitch, then release to
  append it at the green cursor, regardless of horizontal touch position. In
  Rest mode, touch the staff to append a rest. Drag with two fingers to scroll
  the score; a quick swipe continues scrolling after release. Touch the score
  to stop it. An entry cannot overlap a later note or an explicit rest; a note
  crossing a barline may consume generated rests in the next bar.
  Dragging between the treble and bass staves switches the note to that staff;
  chord stack keeps the selected chord's staff.
- Rests for voices 1 and 2 appear on the treble staff, and rests for voices 3
  and 4 on the bass staff, regardless of where you tap. Voices 1 and 3 sit
  above the staff center; voices 2 and 4 sit below it. Notes can still be
  entered on either staff.
- In Write mode, select sharp, flat or natural to apply it to each entered
  pitch. Tap the selected accidental again to turn it off, or choose another.
  With none selected, normal key-signature and in-bar accidental rules apply.
  In Edit mode, select a note first, then tap an accidental to change it.
- On Android, the piano preview plays the pitch while entering or dragging a
  note. Use the speaker button in the header to mute it. It is an experimental
  single-note preview; device latency may vary.
- Press **Play** to play from the selected bar, or **Stop** to stop immediately.
  Use **Go to start** or **Go to end** beside Play to select the first or last
  bar. Notes tied in from an earlier bar are silent until their next attack.
  Playback follows written
  repeats, which can jump back before the selected bar.
  Playback includes all voices and chord pitches; empty space
  and rests are silent. Tap the BPM value to set a score-wide tempo from 30 to
  240 quarter notes per minute (default 120). Editing is disabled while
  playing, and playback stops at the last event or when the app is backgrounded.
  The current bar is shaded and sounding notes are highlighted. Stopping
  playback selects the current bar; the previous editing selection is retained
  if playback is stopped in its starting bar.
  The speaker button mutes note-entry preview only, not score playback.
- Android score playback mixes all voices and pitch shifts into one music audio
  stream before output, so internal-audio screen recorders receive the combined
  score rather than separate pitched sample streams. Note-entry preview still
  uses SoundPool. The score mix reserves headroom for simultaneous notes; its
  overall level can differ from earlier builds, while relative dynamics remain.
- Tap a bar number to open **Bar settings**, then choose **Tempo** or
  **Key and time signature**. Tempo changes apply until the next tempo
  marking, including during tied notes; the header BPM is the initial tempo.
  In the first bar, key and time opens the initial score settings. For later
  bars, use the switches to add or remove changes. Each change applies from that bar
  until the next change of the same kind. Key changes affect existing notes
  that begin under the new key; a note tied across a key change retains the
  pitch from its start. Changes are saved with the project and can be undone.
- Tap the **Bar** label between the header arrows, or a bar number on the
  score, and choose **Edit bars** to add bars at the end, insert before or
  after a bar, delete, cut or copy consecutive bars, and paste copied bars
  before or after a bar. Paste inserts rather than replaces bars. The bar
  clipboard lasts for the current app session. These actions include all
  voices and markings, support Undo and Redo, and preserve the effective key,
  meter and tempo of existing and copied bars. Extra change markings may be
  added where needed to preserve those settings.
- Bars are added manually; add enough bars before entering or extending a
  note past the end. Deleting or cutting asks for confirmation, and at least
  one bar must remain. Operations that would split a tied note or a hairpin
  across a bar boundary are blocked; edit the tie or hairpin first.
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
- Select or enter a note, then use **Articulations** below Chord Stack to
  toggle staccato, staccatissimo, tenuto, portato, accent and marcato.
  Portato combines staccato and tenuto; a chord's marks apply to the whole
  chord. Marks appear on the attack of a tied note, are saved with the project,
  support Undo and Redo, and are included in PDF and MusicXML.
  Playback and MIDI approximate the duration and intensity of these marks.
  When a score has accents but no dynamics, playback uses an mf baseline
  instead of maximum volume so accents can be heard; scores without accents
  retain their previous volume.
- Select a note, chord or rest and use **Articulations** to add a fermata.
  It appears on the final segment of a tied note and is included in PDF and
  MusicXML. Playback and MIDI pause the entire score at its end for half its
  written duration; simultaneous fermatas ending together use the longest
  hold. Shortened articulations may stop sounding before the pause.
- The same menu offers trill, upper and lower mordents, turn and inverted
  turn. Choose one ornament per note or chord; selecting another replaces it.
  Ornaments apply to every pitch in a chord, appear on the attack of a tied
  note, and are saved and exported to PDF and MusicXML. Playback and MIDI
  approximate them using diatonic neighbors from the current key signature and
  earlier accidentals on the same staff; they do not add separately notated
  accidental overrides for those neighbors.
  Playback reports an error if an ornament is too short to schedule or its
  neighbor is outside the available piano-sample range.
- In **Articulations**, choose **Arpeggio up** or **Arpeggio down** when at
  least two notes start together. The mark combines those notes across voices
  and staves; selecting it again removes it. Playback and MIDI spread the
  attacks briefly without delaying later events, and PDF and MusicXML include
  the mark. If editing leaves fewer than two notes, the mark is removed.
- Select a note or rest, or enter one in Write mode, then use **Dynamics** on
  the left rail to add or change a marking from ppp to fff. A marking applies
  to the whole piano from that score position until the next marking, regardless
  of voice or staff. Tap a displayed marking to change or remove it, even if
  its original note is deleted. Dynamics support Undo and Redo and are saved
  with the project. Changing to a shorter meter is blocked if a marking would
  no longer fit in its bar.
  Playback and MIDI use approximate levels for new note attacks; an already
  sounding piano note does not change volume. Unmarked scores retain the
  original playback volume. MusicXML and PDF include the markings.
- To add a crescendo or diminuendo, select or enter its first note or rest and
  choose **Crescendo start** or **Diminuendo start** in Dynamics. The short red
  hairpin is unfinished; select a later note or rest and choose **Set end** in
  Dynamics. Only one hairpin can be unfinished at a time; completed hairpins
  may not overlap. Tap a hairpin to delete it. Hairpins are saved, support
  Undo and Redo, and apply to the whole piano. Finish or remove an unfinished
  hairpin before playback or export.
  Playback and MIDI interpolate the volume of new note attacks to a dynamic
  at the end, or by one dynamic level if there is no ending mark; that level
  remains in effect until another dynamic or hairpin. Dynamics inside a
  hairpin act as intermediate targets. MusicXML and PDF contain the hairpin.
- Choose **Export PDF** in the menu, then select a destination in Android's
  file picker. The score is arranged into systems on A4 portrait pages.
  PDF pages are rendered as images; dense passages may need manual review
  before printing. PDF is for sharing/printing, not reopening for editing.
- Choose **Export MIDI** to save a standard `.mid` file with Android's file
  picker. It includes all voices, chords, rests as silence, sustained ties,
  tempo, time and key changes. Repeat passages are written out twice; the
  same unsupported repeat structures and ties as playback are reported.
  MIDI exports use piano sounds and are not editable Claviera projects.
  Because the editor stores key signatures but not major/minor mode, MIDI key
  signature metadata is marked major. Pitches are unchanged.
- Choose **Export MusicXML** to save a `.musicxml` score using Android's file
  picker. It contains both staves, voices, notes, rests, chords, ties, tempo,
  key and time changes, and repeat signs. Unlike MIDI, repeat passages remain
  written as repeats rather than being expanded. The export can be opened in
  compatible notation software, but is not a Claviera project file.
- The menu contains **New score**, **Open project**, **Save**, **Save as** and
  **Rename**. The first save asks for a name; Save updates that project, while
  Save as creates a separate copy. New and Open ask whether to save or discard
  unsaved changes. Android Back also warns about unsaved changes. Project files
  are stored privately by the app and can be removed when the app is
  uninstalled or its data is cleared.
- Unsaved changes are also written to a separate local recovery draft. When the
  app reopens, choose whether to restore or discard that draft. Recovery does
  not overwrite a saved project; use Save to keep the restored work. Continue
  to save regularly: a sudden termination may occur before the latest draft
  write finishes, and the draft is also lost if app data is removed.
- Use **Back up project** to save an editable `.claviera` file for the current
  score, including unsaved edits, to a location outside the app. **Restore
  project backup** imports the selected file as a new project without
  overwriting an existing one. Keep backups in a safe location outside the
  device if you want protection from device loss.

Each voice advances independently in each bar. Editing leaves later notes in
place: gaps before later events **in the same bar** are filled with generated
rests. The unfinished end of a bar is left empty, even when later bars contain
notes. Explicitly entered rests remain; an empty bar for one voice does not
affect the other voices. Lengthening a note can consume following rests but
cannot overlap a later note.

Notes crossing a barline are one logical event shown as tied segments; editing
or deleting a tied note (or a pitch in its chord) affects the entire tied
event, including its continuation in the next bar. The final bar has a
closing barline.

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
    score_timeline.dart        Shared repeat traversal and validation
    midi_export.dart           Standard MIDI file encoding
  storage/
    projects.dart              Versioned local project storage
  notation/
    score_viewport.dart        Touch input and two-finger scrolling
    score_painter.dart         SMuFL grand-staff rendering
    print_layout.dart          Paginated score rendering for PDF export
    beaming.dart               Voice stem directions and rhythmic beam grouping
    musicxml_export.dart       MusicXML score encoding
  ui/
    workspace_screen.dart      Rails and editing interactions
    workspace_menu.dart        Project menu and getting-started guide
    user_manual.dart           Offline guide to the controls
assets/fonts/                  Bravura font and its SIL OFL license
android/app/src/main/assets/piano/  CC0 piano samples and provenance
```

Timing uses 960 ticks per quarter. Logical events use absolute ticks in the
editor; rendered segments use measure-relative ticks. A chord is one logical
event with multiple pitches sharing its duration. Pitch positions use C0 = 0,
D0 = 1, …, C4 = 28, independent of accidentals.

Ads and clef changes per bar are not implemented. The remaining disabled menu
items are placeholders. Bravura is distributed under the license in
`assets/fonts/LICENSE-Bravura.txt`.

The Android preview and experimental playback use SoundPool and a small set of CC0 Meta Piano samples
(an upright piano). See the accompanying
`android/app/src/main/assets/piano/README.txt` for sources and processing.
Samples are at most four seconds long, so longer held notes decay or end before
their notated duration; highlighting follows the notated duration. SoundPool
timing and pitch-shifted samples are provisional; playback supports at most 64
simultaneous notes. The sample engine supports MIDI notes 10–127.
Score playback briefly prepares the audio output before starting, to reduce
first-note delays on Android. Short release fades reduce clicks when preview
and score notes stop; score notes fade during their final 10 ms.
Menu > Reverb controls the score playback room reverb:
enable it or adjust its level, feedback/decay, damping and maximum tail length.
Settings are saved for future playback. The single-note preview remains dry.
