import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../audio/reverb_settings.dart';
import 'user_manual.dart';
import 'workspace_screen.dart' show ChordStackIcon;

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
  required VoidCallback onReverb,
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
                const SizedBox(width: 16),
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
                    showGettingStarted(context);
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
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('User manual'),
            onTap: () {
              Navigator.pop(sheetContext);
              showUserManual(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.graphic_eq),
            title: const Text('Reverb'),
            onTap: () {
              Navigator.pop(sheetContext);
              onReverb();
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> showReverbSettings(BuildContext context) async {
  try {
    var settings = await ReverbSettings.load();
    if (!context.mounted) return;
    final chosen = await showDialog<ReverbSettings>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          Widget slider(
            String label,
            String description,
            double value,
            double min,
            double max,
            int divisions,
            String display,
            ValueChanged<double> onChanged,
          ) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$label: $display'),
              Text(description, style: Theme.of(context).textTheme.bodySmall),
              Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                label: display,
                onChanged: settings.enabled
                    ? (value) => update(() => onChanged(value))
                    : null,
              ),
            ],
          );
          return AlertDialog(
            title: const Text('Reverb'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Score playback only. Changes apply next time you play.',
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable reverb'),
                      value: settings.enabled,
                      onChanged: (value) => update(
                        () => settings = settings.copyWith(enabled: value),
                      ),
                    ),
                    slider(
                      'Reverb level',
                      'Amount of reverb mixed with the piano.',
                      settings.wet,
                      0,
                      1,
                      100,
                      '${(settings.wet * 100).round()}%',
                      (value) => settings = settings.copyWith(wet: value),
                    ),
                    slider(
                      'Feedback / decay',
                      'Higher values make the reverb decay more slowly.',
                      settings.feedback,
                      0.5,
                      0.9,
                      40,
                      '${(settings.feedback * 100).round()}%',
                      (value) => settings = settings.copyWith(feedback: value),
                    ),
                    slider(
                      'Damping',
                      'Higher values soften the reverb’s high frequencies.',
                      settings.damping,
                      0,
                      0.8,
                      80,
                      '${(settings.damping * 100).round()}%',
                      (value) => settings = settings.copyWith(damping: value),
                    ),
                    slider(
                      'Tail length',
                      'Maximum time the reverb rings after the last note.',
                      settings.tailMs.toDouble(),
                      500,
                      4000,
                      14,
                      '${(settings.tailMs / 1000).toStringAsFixed(2)} s',
                      (value) =>
                          settings = settings.copyWith(tailMs: value.round()),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    update(() => settings = const ReverbSettings()),
                child: const Text('Reset'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, settings),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    if (chosen != null) await chosen.save();
  } on PlatformException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message ?? 'Could not access reverb settings.'),
        ),
      );
    }
  } on MissingPluginException {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reverb settings are unavailable.')),
      );
    }
  } on FormatException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  } on StateError catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

Widget _chip(Widget child) => Container(
  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
  padding: const EdgeInsets.symmetric(horizontal: 4),
  alignment: Alignment.center,
  decoration: BoxDecoration(
    color: const Color(0xffe6f0eb),
    borderRadius: BorderRadius.circular(6),
  ),
  child: IconTheme(
    data: const IconThemeData(size: 18, color: Color(0xff244d45)),
    child: child,
  ),
);

Widget _iconChip(IconData icon) => _chip(Icon(icon));

Widget _labelChip(String text, {bool music = false}) => _chip(
  Text(
    text,
    style: TextStyle(
      fontFamily: music ? 'Bravura' : null,
      fontSize: music ? 22 : 13,
      fontWeight: FontWeight.w700,
      color: const Color(0xff244d45),
    ),
  ),
);

Widget _separator(String text) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 4),
  child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
);

const _hideGettingStartedKey = 'claviera.gettingStarted.hidden';

Future<SharedPreferences?> _preferences() async {
  try {
    return await SharedPreferences.getInstance();
  } catch (_) {
    return null;
  }
}

Future<void> showGettingStartedOnFirstRun(BuildContext context) async {
  final preferences = await _preferences();
  if (preferences == null ||
      preferences.getBool(_hideGettingStartedKey) == true) {
    return;
  }
  if (context.mounted) await showGettingStarted(context);
}

Future<void> showGettingStarted(BuildContext context) async {
  final preferences = await _preferences();
  if (!context.mounted) return;
  var hidden = preferences?.getBool(_hideGettingStartedKey) ?? false;
  final sections = <(List<Widget>, String, String)>[
    (
      [_iconChip(Icons.edit), _separator('/'), _iconChip(Icons.touch_app)],
      'Write mode / Edit mode',
      'The top button switches between the two modes. The pencil is Write '
          'mode: touch the staff and drag up or down to choose a pitch, then '
          'release to add the note at the green cursor. The pointing hand is '
          'Edit mode: tap a bar or a note, drag a note vertically to change '
          'its pitch, change its length, or use Delete. Undo is on the '
          'right; Redo is in the menu.',
    ),
    (
      [_iconChip(Icons.music_note), _separator('/'), _iconChip(Icons.hotel)],
      'Note / Rest',
      'This button switches between writing notes and writing rests. The '
          'note icon means the next entry is a note; the bed icon means it '
          'is a rest.',
    ),
    (
      [
        _labelChip('V1'),
        _labelChip('V2'),
        _labelChip('V3'),
        _labelChip('V4'),
        _separator('+'),
        _iconChip(Icons.chevron_left),
        _iconChip(Icons.chevron_right),
      ],
      'Voices and moving around',
      'V1 to V4 choose the voice you write in. Use the arrows to move '
          'between notes, and the Bar arrows to choose where to write. Tap '
          'Bar and choose Go to bar to jump directly to a bar. Drag or swipe '
          'the score with two fingers to scroll.',
    ),
    (
      [_chip(const ChordStackIcon())],
      'Chord stack',
      'Turn on Chord stack to add several notes on top of each other at '
          'the same position, building a chord.',
    ),
    (
      [
        _iconChip(Icons.play_arrow),
        _iconChip(Icons.skip_previous),
        _iconChip(Icons.skip_next),
        _iconChip(Icons.speed),
      ],
      'Play',
      'Play starts at the selected bar. Use Go to start beside Play to '
          'return to the beginning or Go to end to select the last bar. '
          'Tap BPM to set tempo.',
    ),
    (
      [_labelChip('\uE050', music: true), _labelChip('4/4')],
      'Score settings',
      'Tap the clefs or time signature to set the initial key and meter. '
          'Tap the Bar label or a bar number for bar settings and to add or '
          'edit bars.',
    ),
    (
      [_iconChip(Icons.menu)],
      'Save and back up',
      'Use Menu > Save to save your project. Back up project saves an '
          'editable copy outside the app; Restore project backup opens it as '
          'a new project.',
    ),
  ];
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Getting started'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (chips, heading, description) in sections) ...[
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          heading,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ...chips,
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
          if (preferences != null)
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              value: hidden,
              title: const Text("Don't show this at startup"),
              onChanged: (value) {
                hidden = value ?? false;
                unawaited(preferences.setBool(_hideGettingStartedKey, hidden));
                setDialogState(() {});
              },
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    ),
  );
}
