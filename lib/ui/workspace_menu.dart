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
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text('Menu', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.redo),
            title: const Text('Redo'),
            enabled: canRedo,
            onTap: canRedo
                ? () {
                    Navigator.pop(context);
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
                Navigator.pop(context);
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
