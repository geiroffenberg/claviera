import 'package:flutter/material.dart';

void showWorkspaceMenu(
  BuildContext context, {
  required bool canRedo,
  required VoidCallback onRedo,
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
            child: Text(
              'Menu · coming in a later milestone',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
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
          for (final item in const [
            (Icons.note_add_outlined, 'New score'),
            (Icons.folder_open, 'Open JSON'),
            (Icons.picture_as_pdf_outlined, 'Export PDF'),
            (Icons.music_note, 'Export MusicXML'),
            (Icons.piano, 'Export MIDI'),
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
