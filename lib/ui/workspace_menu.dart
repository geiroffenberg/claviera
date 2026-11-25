import 'package:flutter/material.dart';

void showWorkspaceMenu(
  BuildContext context, {
  required bool canRedo,
  required VoidCallback onRedo,
  required VoidCallback onNew,
  required VoidCallback onOpen,
  required VoidCallback onSave,
  required VoidCallback onSaveAs,
  required VoidCallback onRename,
  required VoidCallback onExportPdf,
  required VoidCallback onExportMidi,
  required VoidCallback onExportMusicXml,
  required bool isPro,
  required VoidCallback onUpgrade,
  required VoidCallback onBackup,
  required VoidCallback onRestoreBackup,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const Text(
                  'Menu',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Tooltip(
                  message: 'Upgrade to Pro',
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(
                      Icons.workspace_premium_outlined,
                      size: 18,
                    ),
                    label: Text(isPro ? 'Pro' : 'Upgrade'),
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      onUpgrade();
                    },
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.help_outline, size: 18),
                  label: const Text('Getting started'),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _showGettingStarted(context);
                  },
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.redo),
            title: const Text('Redo'),
            enabled: canRedo,
            onTap: canRedo
                ? () {
                    Navigator.pop(sheetContext);
                    onRedo();
                  }
                : null,
          ),
          for (final item in [
            (Icons.note_add_outlined, 'New score', onNew),
            (Icons.folder_open, 'Open project', onOpen),
            (Icons.save_outlined, 'Save', onSave),
            (Icons.save_as_outlined, 'Save as', onSaveAs),
            (Icons.drive_file_rename_outline, 'Rename', onRename),
            (Icons.backup_outlined, 'Back up project', onBackup),
            (Icons.restore, 'Restore project backup', onRestoreBackup),
            (Icons.picture_as_pdf_outlined, 'Export PDF', onExportPdf),
            (Icons.piano, 'Export MIDI', onExportMidi),
            (Icons.music_note, 'Export MusicXML', onExportMusicXml),
          ])
            ListTile(
              leading: Icon(item.$1),
              title: Text(item.$2),
              trailing:
                  !isPro &&
                      (item.$2 == 'Export PDF' ||
                          item.$2 == 'Export MIDI' ||
                          item.$2 == 'Export MusicXML')
                  ? const Icon(Icons.lock_outline, size: 18)
                  : null,
              onTap: () {
                Navigator.pop(sheetContext);
                item.$3();
              },
            ),
        ],
      ),
    ),
  );
}

void _showGettingStarted(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Getting started'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (heading, icons, description) in const [
                (
                  'Write notes',
                  [Icons.edit, Icons.music_note, Icons.hotel],
                  'The pencil button is Write mode; tap it to switch to Edit '
                      '(the pointing hand). In Write mode, choose a voice and '
                      'note length. Touch the '
                      'staff and drag up or down to choose a pitch; release '
                      'to add it at the green cursor. The note button switches '
                      'to the bed icon to enter rests.',
                ),
                (
                  'Move around',
                  [Icons.chevron_left, Icons.chevron_right],
                  'Drag the score with two fingers to scroll. Use the Bar '
                      'arrows to choose where to write.',
                ),
                (
                  'Edit',
                  [Icons.touch_app, Icons.delete_outline, Icons.undo],
                  'Switch to Edit mode and tap a bar or a note in the active '
                      'voice. Drag a note vertically to change its pitch, '
                      'change its length, or use Delete. Undo is on the right; '
                      'Redo is in the menu.',
                ),
                (
                  'Play',
                  [Icons.play_arrow, Icons.skip_previous, Icons.speed],
                  'Play starts at the selected bar. Use Go to start beside '
                      'Play to return to the beginning. Tap BPM to set tempo.',
                ),
                (
                  'Score settings',
                  [Icons.view_week_outlined],
                  'Tap the clefs or time signature to set the initial key '
                      'and meter. Tap the Bar label or a bar number for bar '
                      'settings and to add or edit bars.',
                ),
                (
                  'Save and back up',
                  [Icons.menu],
                  'Use Menu > Save to save your project. Back up project saves '
                      'an editable copy outside the app; Restore project '
                      'backup opens it as a new project.',
                ),
              ]) ...[
                Row(
                  children: [
                    for (final icon in icons) ...[
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: const Color(0xffe6f0eb),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          icon,
                          size: 18,
                          color: const Color(0xff244d45),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        heading,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(description),
                const SizedBox(height: 12),
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
