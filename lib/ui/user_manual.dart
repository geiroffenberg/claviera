import 'package:flutter/material.dart';

import 'workspace_screen.dart' show ChordStackIcon, TieIcon;

typedef _ManualEntry = (List<Widget>, String, String);
typedef _ManualSection = (String, List<_ManualEntry>);

Widget _icon(IconData icon) => Icon(icon, size: 20);
Widget _symbol(String text, {bool music = false}) => Text(
  text,
  style: TextStyle(
    fontFamily: music ? 'Bravura' : null,
    fontSize: music ? 23 : 15,
    fontWeight: music ? FontWeight.normal : FontWeight.bold,
  ),
);

void showUserManual(BuildContext context) {
  final sections = <_ManualSection>[
    (
      'Getting around',
      [
        (
          [
            Image.asset(
              'assets/icons/claviera_icon.png',
              width: 24,
              height: 24,
            ),
          ],
          'Claviera icon',
          'Open information about the app and its licenses.',
        ),
        (
          [_symbol('4/4'), _symbol('\uE050', music: true)],
          'Score settings',
          'Tap the clefs or time signature on the score to set its initial '
              'key and time signature.',
        ),
        (
          [
            _symbol('Bar 1'),
            _icon(Icons.chevron_left),
            _icon(Icons.chevron_right),
          ],
          'Bar navigation',
          'The arrows select the previous or next bar. Tap the Bar label or '
              'a bar number on the score to open bar settings.',
        ),
        (
          [],
          'Scrolling and selection',
          'Scroll the side rails to see all controls. Drag the score with '
              'two fingers to scroll. In Edit mode, tap a bar or note to '
              'select it.',
        ),
      ],
    ),
    (
      'Writing and notation',
      [
        (
          [_icon(Icons.edit), _icon(Icons.touch_app)],
          'Write mode / Edit mode',
          'Switch modes. In Write mode, touch the staff and drag vertically '
              'to preview a pitch, then release to enter it. In Edit mode, '
              'tap a note or rest to select it; drag a note to change pitch.',
        ),
        (
          [_icon(Icons.music_note), _icon(Icons.hotel)],
          'Note / Rest',
          'Choose whether the next entry is a note or a rest.',
        ),
        (
          [
            for (final glyph in [
              '\uE1D2',
              '\uE1D3',
              '\uE1D5',
              '\uE1D7',
              '\uE1D9',
              '\uE1DB',
              '\uE1DD',
            ])
              _symbol(glyph, music: true),
          ],
          'Note lengths',
          'Choose whole, half, quarter, eighth, 16th, 32nd or 64th. '
              'In Edit mode the length changes the selected event.',
        ),
        (
          [
            for (final glyph in [
              '\uE4E3',
              '\uE4E4',
              '\uE4E5',
              '\uE4E6',
              '\uE4E7',
              '\uE4E8',
              '\uE4E9',
            ])
              _symbol(glyph, music: true),
          ],
          'Rest lengths',
          'In Rest mode the same length buttons display rest symbols, from '
              'whole through 64th.',
        ),
        (
          [_symbol('•'), _symbol('••')],
          'Dots',
          'Cycle through no dot, one dot and two dots where the chosen '
              'length permits them.',
        ),
        (
          [_symbol('3'), _symbol('5')],
          'Tuplet',
          'In Write mode, cycle through triplet, quintuplet and off.',
        ),
        (
          [const TieIcon()],
          'Tie',
          'In Write mode, arm a tie for the next note. In Edit mode, tie '
              'the selected note to a matching previous note.',
        ),
        (
          [_symbol('♯'), _symbol('♭'), _symbol('♮')],
          'Accidentals',
          'Choose sharp, flat or natural. In Write mode it applies to entered '
              'notes; tap it again to turn it off. In Edit mode it changes '
              'the selected pitch.',
        ),
        (
          [const ChordStackIcon()],
          'Chord stack',
          'Add pitches to the selected note instead of advancing the cursor. '
              'Turn it off to append notes again.',
        ),
        (
          [_symbol('\uE4B0', music: true)],
          'Articulations and ornaments (Pro)',
          'Select a note or rest and open the palette to add or remove '
              'marks. Available marks depend on the selection.',
        ),
        (
          [_icon(Icons.graphic_eq)],
          'Dynamics and hairpins (Pro)',
          'Select a note or rest to add a dynamic, or start a crescendo or '
              'diminuendo. Select a later event and choose Set end to finish '
              'a hairpin. Tap a marking or hairpin to change or remove it.',
        ),
      ],
    ),
    (
      'Articulation palette (Pro)',
      [
        ([_symbol('\uE4A2', music: true)], 'Staccato', 'Shorten the note.'),
        (
          [_symbol('\uE4A6', music: true)],
          'Staccatissimo',
          'Shorten the note more.',
        ),
        (
          [_symbol('\uE4A4', music: true)],
          'Tenuto',
          'Hold the note for its full length.',
        ),
        (
          [_symbol('\uE4B2', music: true)],
          'Portato',
          'Combine staccato and tenuto.',
        ),
        ([_symbol('\uE4A0', music: true)], 'Accent', 'Emphasize the note.'),
        (
          [_symbol('\uE4AC', music: true)],
          'Marcato',
          'Emphasize the note strongly.',
        ),
        (
          [_symbol('\uE4C0', music: true)],
          'Fermata',
          'Hold the note or rest longer.',
        ),
        (
          [_symbol('\uE566', music: true)],
          'Trill',
          'Alternate rapidly with the upper neighbor.',
        ),
        (
          [_symbol('\uE56C', music: true)],
          'Upper mordent',
          'Briefly alternate with the upper neighbor.',
        ),
        (
          [_symbol('\uE56D', music: true)],
          'Lower mordent',
          'Briefly alternate with the lower neighbor.',
        ),
        (
          [_symbol('\uE567', music: true)],
          'Turn',
          'Play a figure around the note.',
        ),
        (
          [_symbol('\uE568', music: true)],
          'Inverted turn',
          'Play an inverted figure around the note.',
        ),
        (
          [_icon(Icons.arrow_upward), _icon(Icons.arrow_downward)],
          'Arpeggio up / down',
          'Spread simultaneous note attacks upward or downward. At least '
              'two notes must start together.',
        ),
      ],
    ),
    (
      'Playback',
      [
        (
          [_icon(Icons.skip_previous), _icon(Icons.skip_next)],
          'Go to start / Go to end',
          'Select the first or last bar.',
        ),
        (
          [_icon(Icons.play_arrow), _icon(Icons.stop)],
          'Play / Stop',
          'Play from the selected bar, following repeats. Stop immediately '
              'and select the current bar. Score playback is available on Android.',
        ),
        (
          [_symbol('BPM')],
          'Tempo',
          'Set the initial tempo in quarter notes per minute. Bar settings '
              'can add later tempo changes.',
        ),
        (
          [_icon(Icons.volume_up), _icon(Icons.volume_off)],
          'Piano preview',
          'Mute or enable the note-entry preview. This does not mute score playback.',
        ),
        (
          [_icon(Icons.graphic_eq)],
          'Reverb',
          'Use Menu > Reverb to enable or adjust the score playback reverb. '
              'Changes apply the next time you play; note-entry previews stay dry.',
        ),
      ],
    ),
    (
      'Right rail',
      [
        (
          [_symbol('V1'), _symbol('V2'), _symbol('V3'), _symbol('V4')],
          'Voices',
          'Choose the active voice. Each voice advances independently.',
        ),
        (
          [_icon(Icons.chevron_left), _icon(Icons.chevron_right)],
          'Previous / Next event',
          'Select the previous or next note or rest in the active voice.',
        ),
        (
          [_icon(Icons.keyboard_arrow_up), _icon(Icons.keyboard_arrow_down)],
          'Higher / Lower chord note',
          'Choose a pitch within the selected chord for editing.',
        ),
        (
          [_icon(Icons.undo)],
          'Undo',
          'Undo the most recent score edit. Redo is in the menu.',
        ),
        (
          [_icon(Icons.delete_outline)],
          'Delete',
          'In Edit mode, delete the selected pitch or rest. Deleting the '
              'last pitch removes the note.',
        ),
        (
          [_icon(Icons.music_note), _icon(Icons.swap_vert)],
          'Transpose score',
          'Move all voices by semitones or octaves, changing key signatures '
              'to match.',
        ),
        (
          [_icon(Icons.menu)],
          'Menu',
          'Open project actions, help and Pro options.',
        ),
      ],
    ),
    (
      'Bar settings',
      [
        ([_icon(Icons.search)], 'Go to bar', 'Select a bar by number.'),
        (
          [_icon(Icons.speed)],
          'Tempo',
          'Set or remove a tempo change at this bar.',
        ),
        (
          [_icon(Icons.music_note)],
          'Key and time signature',
          'Set the initial key and meter, or changes starting at a later bar.',
        ),
        (
          [_icon(Icons.repeat)],
          'Repeats',
          'Add or remove repeat signs. Each end sign repeats its passage once.',
        ),
        (
          [_icon(Icons.swap_horiz)],
          'Voice switch',
          'Swap two voices in this bar.',
        ),
        (
          [_icon(Icons.unfold_more)],
          'Voice transpose',
          'Move the active voice in this bar by staff steps or octaves.',
        ),
        (
          [_icon(Icons.notes)],
          'Bar note',
          'Add text below the bar, such as lyrics or a reminder.',
        ),
        (
          [_icon(Icons.view_week_outlined)],
          'Edit bars',
          'Add, insert, delete, cut, copy or paste bars. Paste inserts bars; '
              'the clipboard lasts for the current app session.',
        ),
      ],
    ),
    (
      'Project menu',
      [
        (
          [_icon(Icons.workspace_premium_outlined)],
          'Upgrade / Pro',
          'View Pro features and purchase options.',
        ),
        (
          [_icon(Icons.help_outline)],
          'Getting started',
          'Open the short introduction to the editor.',
        ),
        ([_icon(Icons.menu_book_outlined)], 'User manual', 'Open this guide.'),
        ([_icon(Icons.redo)], 'Redo', 'Redo an undone score edit.'),
        ([_icon(Icons.note_add_outlined)], 'New score', 'Start a blank score.'),
        ([_icon(Icons.folder_open)], 'Open project', 'Open a saved project.'),
        (
          [_icon(Icons.save_outlined)],
          'Save',
          'Save the current project on the device.',
        ),
        (
          [_icon(Icons.save_as_outlined)],
          'Save as',
          'Save a separate copy of the project.',
        ),
        (
          [_icon(Icons.drive_file_rename_outline)],
          'Rename',
          'Change the project name.',
        ),
        (
          [_icon(Icons.backup_outlined), _icon(Icons.restore)],
          'Back up / Restore project backup',
          'Save an editable copy outside the app or import a backup as a new '
              'project. Backups and exports use the Android file picker.',
        ),
        (
          [_icon(Icons.picture_as_pdf_outlined)],
          'Export PDF (Pro)',
          'Save the score for viewing or printing.',
        ),
        (
          [_icon(Icons.piano)],
          'Export MIDI (Pro)',
          'Save a MIDI file for playback or use in compatible music software.',
        ),
        (
          [_icon(Icons.music_note)],
          'Export MusicXML (Pro)',
          'Save notation for use in compatible score software.',
        ),
        (
          [_icon(Icons.lock_outline)],
          'Lock',
          'This feature requires the optional Pro unlock.',
        ),
      ],
    ),
  ];

  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('User manual'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (heading, entries) in sections) ...[
                Text(heading, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final (icons, title, description) in entries) ...[
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    children: [
                      ...icons,
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(description),
                  const SizedBox(height: 12),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
