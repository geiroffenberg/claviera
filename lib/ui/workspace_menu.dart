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
              onTap: () {
                Navigator.pop(sheetContext);
                item.$3();
              },
            ),
          for (final item in const [
            (Icons.tune, 'Time and measures'),
            (Icons.settings_outlined, 'Settings / ad-free'),
          ])
            ListTile(
              leading: Icon(item.$1),
              title: Text(item.$2),
              enabled: false,
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
              for (final (heading, description) in const [
                (
                  'Write notes',
                  'In Write mode, choose a voice and note length. Touch the '
                      'staff and drag up or down to choose a pitch; release '
                      'to add it at the green cursor. Switch Note to Rest '
                      'to enter rests.',
                ),
                (
                  'Move around',
                  'Drag the score with two fingers to scroll. Use the Bar '
                      'arrows to choose where to write.',
                ),
                (
                  'Edit',
                  'Switch to Edit mode and tap a bar or a note in the active '
                      'voice. Drag a note vertically to change its pitch, '
                      'change its length, or use Delete. Undo is on the right; '
                      'Redo is in the menu.',
                ),
                (
                  'Play',
                  'Play starts at the selected bar. Use Go to start beside '
                      'Play to return to the beginning. Tap BPM to set tempo.',
                ),
                (
                  'Score settings',
                  'Tap the clefs or time signature to set the initial key '
                      'and meter. Tap the Bar label or a bar number for bar '
                      'settings and to add or edit bars.',
                ),
                (
                  'Save and back up',
                  'Use Menu > Save to save your project. Back up project saves '
                      'an editable copy outside the app; Restore project '
                      'backup opens it as a new project.',
                ),
              ]) ...[
                Text(
                  heading,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
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
