import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../audio/piano_preview.dart';
import '../audio/midi_export.dart';
import '../audio/score_playback.dart';
import '../billing/pro_purchase_controller.dart';
import '../billing/pro_purchase_service.dart';
import '../editor/score_editor.dart';
import '../models/blank_score.dart';
import '../models/score.dart';
import '../notation/score_painter.dart';
import '../notation/musicxml_export.dart';
import '../notation/print_layout.dart';
import '../notation/score_viewport.dart';
import '../storage/projects.dart';
import 'workspace_menu.dart';
import 'pro_upgrade_dialog.dart';

enum WorkspaceMode { write, edit }

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({
    super.key,
    this.pianoPreview,
    this.projectStore,
    this.proPurchaseController,
  });

  final PianoPreview? pianoPreview;
  final ProjectStore? projectStore;
  final ProPurchaseController? proPurchaseController;
  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  ScoreEditor editor = ScoreEditor(blankScore);
  late final ProjectStore projectStore;
  String projectName = 'Untitled score';
  String? projectId;
  late String savedState;
  late final PianoPreview piano;
  late final ProPurchaseController proPurchases;
  late final bool ownsProPurchases;
  Voice voice = Voice.v1;
  NoteValue noteValue = NoteValue.quarter;
  WorkspaceMode mode = WorkspaceMode.write;
  bool rest = false;
  bool tieArmed = false;
  int dots = 0;
  Accidental writeAccidental = Accidental.none;
  int tupletSize = 0;
  bool chordStack = false;
  int? selectedId;
  int selectedMeasure = 0;
  int revealRevision = 0;
  bool replaceSelectedRest = false;
  int pitchIndex = 0;
  Pitch? preview;
  Staff? previewStaff;
  Offset? gestureStart;
  bool settingsGesture = false;
  int? tempoGesture;
  int? dynamicGesture;
  int? hairpinGesture;
  int? barGesture;
  bool playing = false;
  bool saving = false;
  bool exportingPdf = false;
  bool exportingMidi = false;
  bool exportingMusicXml = false;
  bool transferringProject = false;
  bool checkingRecovery = false;
  bool recoveryAvailable = false;
  Future<void> recoveryWrites = Future.value();
  int playbackRevision = 0;
  late final Ticker playbackTicker;
  PlaybackPlan? playbackPlan;
  PlaybackFrame? playbackFrame;
  int tempo = 120;
  BarClipboard? barClipboard;
  bool get hasPro => proPurchases.isPro;

  VoiceEvent? get selected => editor.eventById(selectedId);
  int get duration => noteValue.duration(dots: dots);
  int get entryMeasure {
    final event = selected;
    if (event != null &&
        ((replaceSelectedRest && event.isRest) ||
            (chordStack && !event.isRest) ||
            mode == WorkspaceMode.edit)) {
      return editor.measureAtTick(event.start);
    }
    return editor.measureAtTick(
      editor.nextTick(voice, measure: selectedMeasure),
    );
  }

  Project get project =>
      Project(name: projectName, tempo: tempo, editor: editor);
  bool get dirty => ProjectCodec.encode(project) != savedState;

  void _toggleTie() {
    if (mode == WorkspaceMode.edit) {
      final event = selected;
      if (event == null || event.isRest) return;
      _perform(() => editor.toggleTieToPrevious(event.id));
    } else {
      setState(() => tieArmed = !tieArmed);
    }
  }

  Future<void> _exportMusicXml() async {
    if (!await _requirePro()) return;
    if (exportingMusicXml) return;
    setState(() => exportingMusicXml = true);
    try {
      final bytes = MusicXmlExport.encode(editor, tempo, projectName);
      final safeName = projectName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final saved = await const MethodChannel('claviera/musicxml')
          .invokeMethod<bool>('save', {
            'name': '$safeName.musicxml',
            'bytes': bytes,
          });
      if (mounted && saved == true) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('MusicXML saved.')));
      }
    } on PlatformException catch (error) {
      _musicXmlError(error.message ?? error.code);
    } on MissingPluginException {
      _musicXmlError('MusicXML export is available on Android only.');
    } on StateError catch (error) {
      _musicXmlError(error.message);
    } finally {
      if (mounted) setState(() => exportingMusicXml = false);
    }
  }

  void _musicXmlError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('MusicXML export error: $error')));
  }

  Future<void> _exportMidi() async {
    if (!await _requirePro()) return;
    if (exportingMidi) return;
    setState(() => exportingMidi = true);
    try {
      final bytes = MidiExport.encode(editor, tempo);
      final safeName = projectName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final saved = await const MethodChannel(
        'claviera/midi',
      ).invokeMethod<bool>('save', {'name': '$safeName.mid', 'bytes': bytes});
      if (mounted && saved == true) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('MIDI saved.')));
      }
    } on PlatformException catch (error) {
      _midiError(error.message ?? error.code);
    } on MissingPluginException {
      _midiError('MIDI export is available on Android only.');
    } on StateError catch (error) {
      _midiError(error.message);
    } finally {
      if (mounted) setState(() => exportingMidi = false);
    }
  }

  void _midiError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('MIDI export error: $error')));
  }

  Future<void> _exportPdf() async {
    if (!await _requirePro()) return;
    if (exportingPdf) return;
    setState(() => exportingPdf = true);
    try {
      final pages = await PrintLayout.render(
        editor.score,
        projectName,
        initialTempo: tempo,
      );
      final safeName = projectName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final saved = await const MethodChannel(
        'claviera/pdf',
      ).invokeMethod<bool>('save', {'name': '$safeName.pdf', 'pages': pages});
      if (mounted && saved == true) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('PDF saved.')));
      }
    } on PlatformException catch (error) {
      _storageError(error.message ?? error.code);
    } on MissingPluginException {
      _storageError('PDF export is available on Android only.');
    } on StateError catch (error) {
      _storageError(error.message);
    } finally {
      if (mounted) setState(() => exportingPdf = false);
    }
  }

  Future<void> _backupProject() async {
    if (transferringProject) return;
    final contents = ProjectCodec.encode(project);
    final safeName = projectName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    setState(() => transferringProject = true);
    try {
      final saved = await const MethodChannel('claviera/projects')
          .invokeMethod<bool>('backup', {
            'name': '$safeName.claviera',
            'bytes': Uint8List.fromList(utf8.encode(contents)),
          });
      if (mounted && saved == true) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Project backup saved.')));
      }
    } on PlatformException catch (error) {
      _storageError(error.message ?? error.code);
    } on MissingPluginException {
      _storageError('Project backup is available on Android only.');
    } finally {
      if (mounted) setState(() => transferringProject = false);
    }
  }

  Future<void> _restoreProjectBackup() async {
    if (transferringProject) return;
    setState(() => transferringProject = true);
    try {
      final bytes = await const MethodChannel(
        'claviera/projects',
      ).invokeMethod<Uint8List>('restore');
      if (bytes == null || !mounted) return;
      final restored = ProjectCodec.decode(utf8.decode(bytes));
      setState(() => transferringProject = false);
      if (!await _confirmDiscard() || !mounted) return;
      setState(() => transferringProject = true);
      final id = await projectStore.save(restored);
      if (!mounted) return;
      _replaceProject(restored, id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Project backup restored as a new project.'),
        ),
      );
    } on PlatformException catch (error) {
      _storageError(error.message ?? error.code);
    } on MissingPluginException {
      _storageError('Project restore is available on Android only.');
    } on FileSystemException catch (error) {
      _storageError(error);
    } on FormatException catch (error) {
      _storageError('Invalid project backup: ${error.message}');
    } finally {
      if (mounted) setState(() => transferringProject = false);
    }
  }

  @override
  void initState() {
    super.initState();
    ownsProPurchases = widget.proPurchaseController == null;
    proPurchases = widget.proPurchaseController ?? ProPurchaseService();
    proPurchases.addListener(_onProPurchaseChanged);
    if (proPurchases.isAndroid) unawaited(proPurchases.initialize());
    playbackTicker = createTicker(_updatePlayback);
    projectStore = widget.projectStore ?? ProjectStore();
    savedState = ProjectCodec.encode(project);
    checkingRecovery = Platform.isAndroid || widget.projectStore != null;
    WidgetsBinding.instance.addObserver(this);
    piano =
        widget.pianoPreview ??
        PianoPreview(
          onError: (message) {
            if (!mounted) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(message)));
          },
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        piano.warmUp();
        if (checkingRecovery) _initializeRecovery();
      }
    });
  }

  void _onProPurchaseChanged() {
    if (mounted) setState(() {});
  }

  Future<bool> _requirePro() async {
    if (hasPro) return true;
    await showProUpgradeDialog(context, proPurchases);
    return false;
  }

  Future<void> _showProUpgrade() => showProUpgradeDialog(context, proPurchases);

  Future<void> _initializeRecovery() async {
    try {
      if (Platform.isAndroid && widget.projectStore == null) {
        final contents = await rootBundle.loadString(
          'assets/demo/Dream.claviera',
        );
        final dream = ProjectCodec.decode(contents);
        await projectStore.ensureDemoProject(
          Project(name: 'Dream', tempo: dream.tempo, editor: dream.editor),
        );
      }
      final draft = await projectStore.readRecovery();
      if (!mounted) return;
      if (draft != null) {
        final restore = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text('Recover unsaved work?'),
              content: Text(
                'A recovery draft for "${ProjectCodec.decode(draft.contents).name}" was found.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Discard draft'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Restore draft'),
                ),
              ],
            ),
          ),
        );
        if (!mounted) return;
        if (restore == null) return;
        if (restore) {
          _replaceProject(ProjectCodec.decode(draft.contents), draft.projectId);
          savedState = draft.savedState;
        } else {
          await projectStore.clearRecovery();
        }
      }
      if (mounted) setState(() => recoveryAvailable = true);
      if (mounted && Platform.isAndroid && widget.projectStore == null) {
        unawaited(showGettingStartedOnFirstRun(context));
      }
    } on FileSystemException catch (error) {
      _storageError('Recovery unavailable: $error');
    } on PlatformException catch (error) {
      _storageError('Recovery unavailable: ${error.message ?? error.code}');
    } on MissingPluginException {
      _storageError('Recovery storage is unavailable.');
    } on FlutterError catch (error) {
      _storageError('Bundled demo project could not be read: $error');
    } on FormatException catch (error) {
      _storageError('Project data could not be read: ${error.message}');
    } finally {
      if (mounted) setState(() => checkingRecovery = false);
    }
  }

  Future<bool> _queueRecovery({bool discard = false}) {
    if (!recoveryAvailable) return Future.value(false);
    final contents = ProjectCodec.encode(project);
    final draft = discard || contents == savedState
        ? null
        : RecoveryDraft(
            contents: contents,
            savedState: savedState,
            projectId: projectId,
          );
    final result = Completer<bool>();
    recoveryWrites = recoveryWrites.then((_) async {
      try {
        if (draft == null) {
          await projectStore.clearRecovery();
        } else {
          await projectStore.writeRecovery(draft);
        }
        result.complete(true);
      } on FileSystemException catch (error) {
        _storageError('Recovery could not be saved: $error');
        result.complete(false);
      } on PlatformException catch (error) {
        _storageError(
          'Recovery could not be saved: ${error.message ?? error.code}',
        );
        result.complete(false);
      } on MissingPluginException {
        _storageError('Recovery storage is unavailable.');
        result.complete(false);
      }
    });
    return result.future;
  }

  void _storageError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Project storage error: $error')));
  }

  Future<String?> _askName(String title, String initial) async {
    var name = initial;
    String? error;
    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(title),
          content: TextFormField(
            initialValue: initial,
            autofocus: true,
            maxLength: 100,
            onChanged: (value) => name = value,
            decoration: InputDecoration(
              labelText: 'Project name',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (name.trim().isEmpty) {
                  update(() => error = 'Enter a project name.');
                } else {
                  Navigator.pop(context, name.trim());
                }
              },
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _saveProject({bool saveAs = false, bool rename = false}) async {
    if (saving) return false;
    var name = projectName;
    if (projectId == null || saveAs || rename) {
      final result = await _askName(
        rename ? 'Rename project' : 'Save project',
        name,
      );
      if (result == null || !mounted) return false;
      name = result;
    }
    final snapshot = Project(name: name, tempo: tempo, editor: editor);
    final encoded = ProjectCodec.encode(snapshot);
    setState(() => saving = true);
    try {
      final id = await projectStore.save(
        snapshot,
        id: saveAs ? null : projectId,
      );
      if (!mounted) return false;
      setState(() {
        projectId = id;
        projectName = name;
        savedState = encoded;
      });
      _queueRecovery();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Project saved.')));
      return true;
    } on FileSystemException catch (error) {
      _storageError(error);
    } on PlatformException catch (error) {
      _storageError(error.message ?? error.code);
    } on MissingPluginException catch (error) {
      _storageError(error.message ?? 'App storage is unavailable.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
    return false;
  }

  Future<bool> _confirmDiscard() async {
    if (!dirty) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text('Save your changes before continuing?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (choice == 'discard') return true;
    if (choice == 'save' && mounted) {
      final saved = await _saveProject();
      if (saved && mounted && dirty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The project changed while saving. Save again before continuing.',
            ),
          ),
        );
        return false;
      }
      return saved;
    }
    return false;
  }

  void _replaceProject(Project value, String? id) {
    piano.stop();
    setState(() {
      editor = value.editor;
      tempo = value.tempo;
      projectName = value.name;
      projectId = id;
      selectedId = null;
      selectedMeasure = 0;
      pitchIndex = 0;
      replaceSelectedRest = false;
      preview = null;
      gestureStart = null;
      savedState = ProjectCodec.encode(project);
    });
    _queueRecovery();
  }

  Future<void> _newProject() async {
    if (!await _confirmDiscard() || !mounted) return;
    _replaceProject(
      Project(
        name: 'Untitled score',
        tempo: 120,
        editor: ScoreEditor(blankScore),
      ),
      null,
    );
  }

  Future<void> _openProject() async {
    try {
      final projects = await projectStore.list();
      if (!mounted) return;
      final id = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Open project'),
          content: SizedBox(
            width: 400,
            child: projects.isEmpty
                ? const Text('No saved projects yet.')
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final item in projects)
                        ListTile(
                          title: Text(item.name),
                          subtitle: Text('Saved ${item.modified.toLocal()}'),
                          onTap: () => Navigator.pop(context, item.id),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      if (id == null || !mounted) return;
      if (!await _confirmDiscard() || !mounted) return;
      setState(() => saving = true);
      try {
        final loaded = await projectStore.load(id);
        if (!mounted) return;
        _replaceProject(loaded, id);
      } finally {
        if (mounted) setState(() => saving = false);
      }
    } on FileSystemException catch (error) {
      _storageError(error);
    } on PlatformException catch (error) {
      _storageError(error.message ?? error.code);
    } on MissingPluginException catch (error) {
      _storageError(error.message ?? 'App storage is unavailable.');
    } on FormatException catch (error) {
      _storageError(error.message);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _queueRecovery();
      piano.stop();
      if (playing) {
        _stopScore();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    playbackTicker.dispose();
    piano.dispose();
    proPurchases.removeListener(_onProPurchaseChanged);
    if (ownsProPurchases) proPurchases.dispose();
    super.dispose();
  }

  void _previewPitch(Pitch pitch, {Accidental accidental = Accidental.none}) {
    final event = selected;
    final tick =
        event != null &&
            (mode == WorkspaceMode.edit ||
                (replaceSelectedRest && event.isRest) ||
                (chordStack && !event.isRest))
        ? event.start
        : editor.nextTick(voice, measure: selectedMeasure);
    final midi = editor.previewMidi(
      pitch.diatonicStep,
      accidental,
      previewStaff ?? event?.staff ?? Staff.treble,
      tick,
    );
    if (midi >= 0 && midi <= 127) {
      piano.play(midi);
    } else {
      piano.stop();
    }
  }

  Pitch _writePitchAt(Offset position, Staff staff) {
    final pitch = ScorePainter.pitchAt(position.dy, staff, 10);
    return Pitch(
      diatonicStep: pitch.diatonicStep,
      midiNote: pitch.midiNote,
      accidental: writeAccidental,
    );
  }

  Future<void> _scoreSettings({int? measure}) async {
    piano.stop();
    final score = editor.score;
    final time = measure == null
        ? TimeSignature(score.beatsPerMeasure, score.beatUnit)
        : editor.timeAt(measure);
    var beats = time.beats;
    var unit = time.unit;
    var key = measure == null ? score.keySignature : editor.keyAt(measure);
    var explicitTime =
        measure != null && editor.timeChanges.containsKey(measure);
    var explicitKey = measure != null && editor.keyChanges.containsKey(measure);
    String? error;
    const keys = [
      'C♭ major / A♭ minor (7 flats)',
      'G♭ major / E♭ minor (6 flats)',
      'D♭ major / B♭ minor (5 flats)',
      'A♭ major / F minor (4 flats)',
      'E♭ major / C minor (3 flats)',
      'B♭ major / G minor (2 flats)',
      'F major / D minor (1 flat)',
      'C major / A minor (no sharps or flats)',
      'G major / E minor (1 sharp)',
      'D major / B minor (2 sharps)',
      'A major / F♯ minor (3 sharps)',
      'E major / C♯ minor (4 sharps)',
      'B major / G♯ minor (5 sharps)',
      'F♯ major / D♯ minor (6 sharps)',
      'C♯ major / A♯ minor (7 sharps)',
    ];
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            measure == null
                ? 'Score settings'
                : 'Bar ${measure + 1} key and time',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (measure != null)
                  SwitchListTile(
                    title: const Text('Change key at this bar'),
                    value: explicitKey,
                    onChanged: (value) => update(() => explicitKey = value),
                  ),
                DropdownButtonFormField<int>(
                  key: const ValueKey('score-key-signature'),
                  initialValue: key,
                  decoration: const InputDecoration(labelText: 'Key signature'),
                  isExpanded: true,
                  items: [
                    for (var i = 0; i < keys.length; i++)
                      DropdownMenuItem(value: i - 7, child: Text(keys[i])),
                  ],
                  onChanged: measure != null && !explicitKey
                      ? null
                      : (value) => update(() => key = value!),
                ),
                if (measure != null)
                  SwitchListTile(
                    title: const Text('Change time at this bar'),
                    value: explicitTime,
                    onChanged: (value) => update(() => explicitTime = value),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        key: const ValueKey('score-beats-per-bar'),
                        initialValue: beats,
                        decoration: const InputDecoration(
                          labelText: 'Beats per bar',
                        ),
                        items: [
                          for (var i = 1; i <= 32; i++)
                            DropdownMenuItem(value: i, child: Text('$i')),
                        ],
                        onChanged: measure != null && !explicitTime
                            ? null
                            : (value) => update(() => beats = value!),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        key: const ValueKey('score-beat-unit'),
                        initialValue: unit,
                        decoration: const InputDecoration(
                          labelText: 'Beat unit',
                        ),
                        items: [
                          for (final i in [1, 2, 4, 8, 16])
                            DropdownMenuItem(value: i, child: Text('$i')),
                        ],
                        onChanged: measure != null && !explicitTime
                            ? null
                            : (value) => update(() => unit = value!),
                      ),
                    ),
                  ],
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                try {
                  if (measure == null) {
                    editor.setScoreSettings(beats: beats, unit: unit, key: key);
                  } else {
                    editor.setMeasureSignatures(
                      measure,
                      time: explicitTime ? TimeSignature(beats, unit) : null,
                      key: explicitKey ? key : null,
                    );
                  }
                  setState(() {});
                  _queueRecovery();
                  Navigator.pop(context);
                } on EditException catch (exception) {
                  update(() => error = exception.message);
                }
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _playScore() async {
    try {
      final plan = PlaybackPlan(editor, tempo, startMeasure: selectedMeasure);
      if (plan.durationMs == 0 && selectedMeasure > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No notes or rests at or after this bar.'),
          ),
        );
        return;
      }
      piano.stop();
      final revision = ++playbackRevision;
      setState(() => playing = true);
      final started = await piano.playScore(
        plan,
        onFinished: () {
          if (mounted && revision == playbackRevision) {
            _finishPlayback();
          }
        },
      );
      if (mounted && revision == playbackRevision) {
        if (started) {
          setState(() {
            playbackPlan = plan;
            playbackFrame = plan.frameAt(0);
          });
          playbackTicker.start();
        } else {
          _finishPlayback();
        }
      }
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  void _stopScore() {
    piano.stopScore();
    final measure = playbackFrame?.measure;
    if (measure != null && measure != selectedMeasure) {
      _selectMeasure(measure);
    }
    _finishPlayback();
  }

  void _finishPlayback() {
    playbackRevision++;
    playbackTicker.stop();
    setState(() {
      playing = false;
      playbackPlan = null;
      playbackFrame = null;
    });
  }

  void _updatePlayback(Duration elapsed) {
    final frame = playbackPlan?.frameAt(elapsed.inMilliseconds);
    if (frame != playbackFrame) {
      setState(() => playbackFrame = frame);
    }
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'Claviera',
      applicationIcon: Image.asset(
        'assets/icons/claviera_icon.png',
        width: 48,
        height: 48,
        excludeFromSemantics: true,
      ),
      children: const [
        SizedBox(height: 16),
        Text('A piano score sketchpad for writing and playing music.'),
      ],
    );
  }

  Future<void> _setTempo() async {
    var input = '$tempo';
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tempo (quarter notes per minute)'),
        content: TextFormField(
          initialValue: input,
          onChanged: (value) => input = value,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'BPM (30–240)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final bpm = int.tryParse(input);
              if (bpm == null || bpm < 30 || bpm > 240) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Enter a tempo between 30 and 240 BPM.'),
                  ),
                );
                return;
              }
              Navigator.pop(context, bpm);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
    if (mounted && value != null) {
      setState(() => tempo = value);
      _queueRecovery();
    }
  }

  Future<void> _barSettings(int measure) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Bar ${measure + 1} settings'),
        content: SingleChildScrollView(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.search),
                label: const Text('Go to bar'),
                onPressed: () => Navigator.pop(context, 'goTo'),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.speed),
                label: const Text('Tempo'),
                onPressed: () => Navigator.pop(context, 'tempo'),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.music_note),
                label: const Text('Key and time signature'),
                onPressed: () => Navigator.pop(context, 'signatures'),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.repeat),
                label: const Text('Repeats'),
                onPressed: () => Navigator.pop(context, 'repeats'),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Voice switch'),
                onPressed: () => Navigator.pop(context, 'voiceSwitch'),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.unfold_more),
                label: const Text('Voice transpose'),
                onPressed: () => Navigator.pop(context, 'voiceTranspose'),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.notes),
                label: const Text('Bar note'),
                onPressed: () => Navigator.pop(context, 'note'),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.view_week_outlined),
                label: const Text('Edit bars'),
                onPressed: () => Navigator.pop(context, 'edit'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'goTo') {
      await _goToBar();
    } else if (choice == 'tempo') {
      await _setBarTempo(measure);
    } else if (choice == 'signatures') {
      await _scoreSettings(measure: measure == 0 ? null : measure);
    } else if (choice == 'repeats') {
      await _setBarRepeats(measure);
    } else if (choice == 'voiceSwitch') {
      await _voiceSwitch(measure);
    } else if (choice == 'voiceTranspose') {
      await _voiceTranspose(measure);
    } else if (choice == 'note') {
      await _setBarNote(measure);
    } else if (choice == 'edit') {
      await _editBars(measure);
    }
  }

  Future<void> _goToBar() async {
    var input = '${selectedMeasure + 1}';
    String? error;
    final bar = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          void go() {
            final number = int.tryParse(input);
            if (number == null || number < 1 || number > editor.measureCount) {
              update(
                () => error = 'Enter a bar from 1 to ${editor.measureCount}.',
              );
              return;
            }
            Navigator.pop(context, number - 1);
          }

          return AlertDialog(
            title: const Text('Go to bar'),
            content: TextFormField(
              initialValue: input,
              autofocus: true,
              keyboardType: TextInputType.number,
              onChanged: (value) => input = value,
              onFieldSubmitted: (_) => go(),
              decoration: InputDecoration(
                labelText: 'Bar number (1–${editor.measureCount})',
                errorText: error,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(onPressed: go, child: const Text('Go')),
            ],
          );
        },
      ),
    );
    if (mounted && bar != null) _selectMeasure(bar, reveal: true);
  }

  Future<void> _voiceSwitch(int measure) async {
    final pair = await showDialog<(Voice, Voice)>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Bar ${measure + 1} voice switch'),
        content: SingleChildScrollView(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in Voice.values)
                for (final b in Voice.values.where((b) => b.index > a.index))
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context, (a, b)),
                    child: Text('V${a.index + 1} ⇄ V${b.index + 1}'),
                  ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (pair == null || !mounted) return;
    _perform(() => editor.swapVoices(measure, pair.$1, pair.$2));
  }

  Future<void> _transposeScore() async {
    String? error;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          void move(int semitones) {
            try {
              setState(() => editor.transposeScore(semitones));
              _queueRecovery();
              update(() => error = null);
            } on EditException catch (exception) {
              update(() => error = exception.message);
            }
          }

          return AlertDialog(
            title: const Text('Transpose score'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (label, semitones) in const [
                        ('+1', 1),
                        ('-1', -1),
                        ('+12', 12),
                        ('-12', -12),
                      ])
                        OutlinedButton(
                          onPressed: () => move(semitones),
                          child: Text(label),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Moves all voices in all bars by semitones and changes '
                    'the key signatures to match, for example C major +1 '
                    'becomes D♭ major. ±12 is one octave.',
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _voiceTranspose(int measure) async {
    final target = voice;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          void move(int steps) {
            try {
              setState(() => editor.transposeVoice(measure, target, steps));
              _queueRecovery();
              update(() => error = null);
            } on EditException catch (exception) {
              update(() => error = exception.message);
            }
          }

          return AlertDialog(
            title: Text(
              'Bar ${measure + 1} voice transpose (V${target.index + 1})',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (label, steps) in const [
                        ('+1', 1),
                        ('-1', -1),
                        ('+12', 7),
                        ('-12', -7),
                      ])
                        OutlinedButton(
                          onPressed: () => move(steps),
                          child: Text(label),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '±1 moves one step on the staff; ±12 moves one octave. '
                    'Change the voice in the right sidebar.',
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _setBarNote(int measure) async {
    var input = editor.barNotes[measure] ?? '';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Bar ${measure + 1} note'),
        content: TextFormField(
          initialValue: input,
          autofocus: true,
          maxLength: ScoreEditor.maxBarNoteLength,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (value) => input = value,
          decoration: const InputDecoration(
            labelText: 'Text under the bar (lyrics, chords, reminders)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _perform(() => editor.setBarNote(measure, input));
              Navigator.pop(context);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Future<void> _editBars(int measure) async {
    var input = '1';
    String? error;
    final choice = await showDialog<(String, int)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          void choose(String action) {
            final count = int.tryParse(input);
            if (action != 'pasteBefore' &&
                action != 'pasteAfter' &&
                (count == null || count < 1 || count > 100000)) {
              update(() => error = 'Enter a number from 1 to 100000.');
              return;
            }
            Navigator.pop(context, (action, count ?? 1));
          }

          return AlertDialog(
            title: Text('Edit bars from ${measure + 1}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    initialValue: input,
                    keyboardType: TextInputType.number,
                    onChanged: (value) => input = value,
                    decoration: InputDecoration(
                      labelText: 'Number of consecutive bars',
                      errorText: error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => choose('append'),
                        child: const Text('Add at end'),
                      ),
                      OutlinedButton(
                        onPressed: () => choose('before'),
                        child: const Text('Insert before'),
                      ),
                      OutlinedButton(
                        onPressed: () => choose('after'),
                        child: const Text('Insert after'),
                      ),
                      OutlinedButton(
                        onPressed: () => choose('delete'),
                        child: const Text('Delete'),
                      ),
                      OutlinedButton(
                        onPressed: () => choose('cut'),
                        child: const Text('Cut'),
                      ),
                      OutlinedButton(
                        onPressed: () => choose('copy'),
                        child: const Text('Copy'),
                      ),
                      OutlinedButton(
                        onPressed: barClipboard == null
                            ? null
                            : () => choose('pasteBefore'),
                        child: const Text('Paste before'),
                      ),
                      OutlinedButton(
                        onPressed: barClipboard == null
                            ? null
                            : () => choose('pasteAfter'),
                        child: const Text('Paste after'),
                      ),
                    ],
                  ),
                  if (barClipboard != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('${barClipboard!.count} bar(s) copied.'),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
    if (choice == null || !mounted) return;
    final (action, count) = choice;
    if (action == 'delete' || action == 'cut') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(action == 'cut' ? 'Cut bars?' : 'Delete bars?'),
          content: Text(
            'Remove $count bar(s) starting at bar ${measure + 1}, including '
            'their notes and markings? You can undo this.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action == 'cut' ? 'Cut' : 'Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    var copied = false;
    _perform(() {
      switch (action) {
        case 'append':
          final index = editor.measureCount;
          editor.insertBars(index, count, initialTempo: tempo);
          selectedMeasure = index;
        case 'before':
          editor.insertBars(measure, count, initialTempo: tempo);
          selectedMeasure = measure;
        case 'after':
          editor.insertBars(measure + 1, count, initialTempo: tempo);
          selectedMeasure = measure + 1;
        case 'copy':
          barClipboard = editor.copyBars(measure, count, initialTempo: tempo);
          copied = true;
        case 'cut':
          final clipboard = editor.copyBars(
            measure,
            count,
            initialTempo: tempo,
          );
          editor.deleteBars(measure, count, initialTempo: tempo);
          barClipboard = clipboard;
          copied = true;
          selectedMeasure = measure.clamp(0, editor.measureCount - 1);
        case 'delete':
          editor.deleteBars(measure, count, initialTempo: tempo);
          selectedMeasure = measure.clamp(0, editor.measureCount - 1);
        case 'pasteBefore':
        case 'pasteAfter':
          final index = action == 'pasteBefore' ? measure : measure + 1;
          editor.pasteBars(index, barClipboard!, initialTempo: tempo);
          selectedMeasure = index;
      }
      if (action != 'copy') {
        selectedId = null;
        pitchIndex = 0;
        replaceSelectedRest = false;
      }
    });
    if (copied && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$count bar(s) copied.')));
    }
  }

  Future<void> _setBarRepeats(int measure) async {
    var start = editor.repeatStarts.contains(measure);
    var end = editor.repeatEnds.contains(measure);
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('Bar ${measure + 1} repeats'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('Start repeat'),
                  subtitle: const Text('At the beginning of this bar'),
                  value: start,
                  onChanged: (value) => update(() => start = value),
                ),
                SwitchListTile(
                  title: const Text('End repeat'),
                  subtitle: const Text('At the end of this bar'),
                  value: end,
                  onChanged: (value) => update(() => end = value),
                ),
                const Text(
                  'Repeat once; without a start sign, repeat from the beginning.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                _perform(
                  () =>
                      editor.setMeasureRepeats(measure, start: start, end: end),
                );
                Navigator.pop(context);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setBarTempo(int measure) async {
    final changes = editor.tempoChanges;
    var effective = tempo;
    for (final entry
        in (changes.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) {
      if (entry.key > measure) break;
      effective = entry.value;
    }
    var input = '${changes[measure] ?? effective}';
    String? error;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('Bar ${measure + 1} tempo'),
          content: TextFormField(
            initialValue: input,
            keyboardType: TextInputType.number,
            onChanged: (value) => input = value,
            decoration: InputDecoration(
              labelText: 'Quarter notes per minute (30–240)',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            if (changes.containsKey(measure))
              TextButton(
                onPressed: () {
                  _perform(() => editor.setMeasureTempo(measure, null));
                  Navigator.pop(context);
                },
                child: const Text('Remove change'),
              ),
            TextButton(
              onPressed: () {
                final bpm = int.tryParse(input);
                if (bpm == null || bpm < 30 || bpm > 240) {
                  update(() => error = 'Enter a tempo between 30 and 240.');
                  return;
                }
                _perform(() => editor.setMeasureTempo(measure, bpm));
                Navigator.pop(context);
              },
              child: const Text('Set'),
            ),
          ],
        ),
      ),
    );
  }

  void _perform(void Function() operation) {
    try {
      setState(operation);
      _queueRecovery();
    } on EditException catch (error) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  void _select(int? id, {int pitch = 0, int? measure}) => setState(() {
    selectedId = id;
    pitchIndex = pitch;
    final event = editor.eventById(id);
    if (measure != null) {
      selectedMeasure = measure;
    } else if (event != null) {
      selectedMeasure = editor.measureAtTick(event.start);
    }
    replaceSelectedRest = event?.isRest ?? false;
    if (event != null) {
      final notation = notationForDuration(
        event.duration,
        tuplet: event.tuplet,
      );
      if (notation != null) {
        noteValue = notation.value;
        dots = notation.dots;
      }
    }
  });

  void _selectMeasure(int measure, {bool reveal = false}) => setState(() {
    piano.stop();
    selectedMeasure = measure;
    if (reveal) revealRevision++;
    selectedId = null;
    pitchIndex = 0;
    replaceSelectedRest = false;
    preview = null;
  });

  Future<void> _articulationPalette(int id) async {
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AnimatedBuilder(
          animation: proPurchases,
          builder: (context, _) {
            final event = editor.eventById(id)!;
            final marks = event.articulations;
            final proUnlocked = hasPro;
            final portato =
                marks.contains(Articulation.staccato) &&
                marks.contains(Articulation.tenuto);
            void toggle(Articulation? mark) {
              final next = Set<Articulation>.of(marks);
              if (mark == null) {
                next.remove(Articulation.staccatissimo);
                if (portato) {
                  next.removeAll({Articulation.staccato, Articulation.tenuto});
                } else {
                  next.addAll({Articulation.staccato, Articulation.tenuto});
                }
              } else if (!next.remove(mark)) {
                if (mark == Articulation.staccatissimo) {
                  next.removeAll({Articulation.staccato, Articulation.tenuto});
                } else if (mark == Articulation.staccato ||
                    mark == Articulation.tenuto) {
                  next.remove(Articulation.staccatissimo);
                } else if (mark == Articulation.accent) {
                  next.remove(Articulation.marcato);
                } else if (mark == Articulation.marcato) {
                  next.remove(Articulation.accent);
                } else if (mark.isOrnament) {
                  next.removeWhere((item) => item.isOrnament);
                }
                next.add(mark);
              }
              _perform(() => editor.setArticulations(id, next));
              update(() {});
            }

            final options = [
              if (!event.isRest) ...[
                (Articulation.staccato, 'Staccato', '\uE4A2'),
                (Articulation.staccatissimo, 'Staccatissimo', '\uE4A6'),
                (Articulation.tenuto, 'Tenuto', '\uE4A4'),
                (null, 'Portato', '\uE4B2'),
                (Articulation.accent, 'Accent', '\uE4A0'),
                (Articulation.marcato, 'Marcato', '\uE4AC'),
                (Articulation.trill, 'Trill', '\uE566'),
                (Articulation.upperMordent, 'Upper mordent', '\uE56C'),
                (Articulation.lowerMordent, 'Lower mordent', '\uE56D'),
                (Articulation.turn, 'Turn', '\uE567'),
                (Articulation.invertedTurn, 'Inverted turn', '\uE568'),
              ],
              (Articulation.fermata, 'Fermata', '\uE4C0'),
            ];
            return AlertDialog(
              title: const Text('Articulations'),
              titlePadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final (mark, label, glyph) in options)
                          SizedBox(
                            width: (constraints.maxWidth - 8) / 2,
                            child: FilterChip(
                              label: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: glyph,
                                      style: const TextStyle(
                                        fontFamily: 'Bravura',
                                        fontSize: 22,
                                      ),
                                    ),
                                    TextSpan(text: ' $label'),
                                    if (!proUnlocked)
                                      const WidgetSpan(
                                        alignment: PlaceholderAlignment.middle,
                                        child: Icon(
                                          Icons.lock_outline,
                                          size: 13,
                                        ),
                                      ),
                                  ],
                                ),
                                style: const TextStyle(fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              selected: mark == null
                                  ? portato
                                  : marks.contains(mark),
                              showCheckmark: false,
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              onSelected: (_) {
                                if (!proUnlocked) {
                                  _showProUpgrade();
                                } else {
                                  toggle(mark);
                                }
                              },
                            ),
                          ),
                        if (!event.isRest)
                          for (final direction in ArpeggioDirection.values)
                            SizedBox(
                              width: (constraints.maxWidth - 8) / 2,
                              child: FilterChip(
                                avatar: Icon(
                                  direction == ArpeggioDirection.up
                                      ? Icons.arrow_upward
                                      : Icons.arrow_downward,
                                  size: 16,
                                ),
                                label: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: 'Arpeggio ${direction.name}',
                                      ),
                                      if (!proUnlocked)
                                        const WidgetSpan(
                                          alignment:
                                              PlaceholderAlignment.middle,
                                          child: Icon(
                                            Icons.lock_outline,
                                            size: 13,
                                          ),
                                        ),
                                    ],
                                  ),
                                  style: const TextStyle(fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                selected:
                                    editor.arpeggios[event.start] == direction,
                                showCheckmark: false,
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                onSelected:
                                    !proUnlocked ||
                                        editor.pitchCountAt(event.start) >= 2
                                    ? (_) {
                                        if (!proUnlocked) {
                                          _showProUpgrade();
                                          return;
                                        }
                                        _perform(
                                          () => editor.setArpeggio(
                                            event.start,
                                            editor.arpeggios[event.start] ==
                                                    direction
                                                ? null
                                                : direction,
                                          ),
                                        );
                                        update(() {});
                                      }
                                    : null,
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                if (!hasPro)
                  TextButton.icon(
                    onPressed: _showProUpgrade,
                    icon: const Icon(Icons.workspace_premium_outlined),
                    label: const Text('Upgrade to Pro'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _dynamicPalette(int tick) async {
    final pending = editor.pendingHairpin;
    if (pending != null && hasPro) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Finish hairpin'),
          content: const Text('Set the end at the selected note or rest.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _perform(() => editor.endHairpin(tick));
              },
              child: const Text('Set end'),
            ),
          ],
        ),
      );
      return;
    }
    final current = editor.dynamicChanges[tick];
    final chosen = await showDialog<DynamicMark?>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: proPurchases,
        builder: (context, _) {
          final proUnlocked = hasPro;
          return AlertDialog(
            title: const Text('Dynamics (both staves)'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!proUnlocked) ...[
                      const Text(
                        'Dynamics and hairpins are included with Pro.',
                      ),
                      const SizedBox(height: 8),
                    ],
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final mark in DynamicMark.values)
                          SizedBox(
                            width: proUnlocked ? 48 : 64,
                            height: 48,
                            child: ChoiceChip(
                              avatar: proUnlocked
                                  ? null
                                  : const Icon(Icons.lock_outline, size: 12),
                              label: Text(mark.name),
                              selected: current == mark,
                              showCheckmark: false,
                              visualDensity: VisualDensity.compact,
                              labelPadding: EdgeInsets.zero,
                              onSelected: (_) {
                                if (!proUnlocked) {
                                  _showProUpgrade();
                                } else {
                                  Navigator.pop(context, mark);
                                }
                              },
                            ),
                          ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final (kind, label) in [
                          (HairpinKind.crescendo, 'Crescendo start'),
                          (HairpinKind.diminuendo, 'Diminuendo start'),
                        ])
                          OutlinedButton.icon(
                            onPressed: () {
                              if (!proUnlocked) {
                                _showProUpgrade();
                              } else {
                                Navigator.pop(context);
                                _perform(() => editor.startHairpin(tick, kind));
                              }
                            },
                            icon: proUnlocked
                                ? const Icon(Icons.show_chart)
                                : const Icon(Icons.lock_outline, size: 16),
                            label: Text(label),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              if (current != null)
                TextButton(
                  onPressed: () {
                    if (!proUnlocked) {
                      _showProUpgrade();
                    } else {
                      Navigator.pop(context);
                      _perform(() => editor.setDynamic(tick, null));
                    }
                  },
                  child: const Text('Remove'),
                ),
              if (!proUnlocked)
                TextButton.icon(
                  onPressed: _showProUpgrade,
                  icon: const Icon(Icons.workspace_premium_outlined),
                  label: const Text('Upgrade to Pro'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || chosen == null) return;
    _perform(() => editor.setDynamic(tick, chosen));
  }

  Future<void> _hairpinOptions(int start) async {
    if (!hasPro) {
      await _showProUpgrade();
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hairpin'),
        content: const Text('Delete this hairpin?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _perform(() => editor.deleteHairpin(start));
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _selectVoice(Voice value) => setState(() {
    piano.stop();
    voice = value;
    selectedId = null;
    replaceSelectedRest = false;
    pitchIndex = 0;
    preview = null;
  });

  int? _pitchInDirection(VoiceEvent? event, {required bool up}) {
    if (event == null || event.pitches.isEmpty) return null;
    final order = List<int>.generate(event.pitches.length, (i) => i)
      ..sort((a, b) {
        final byStep = event.pitches[a].diatonicStep.compareTo(
          event.pitches[b].diatonicStep,
        );
        return byStep != 0 ? byStep : a.compareTo(b);
      });
    final position = order.indexOf(pitchIndex) + (up ? 1 : -1);
    return position >= 0 && position < order.length ? order[position] : null;
  }

  NotationEvent? _hitEvent(Score score, Offset position) {
    NotationEvent? closest;
    var distance = double.infinity;
    for (var m = 0; m < score.measures.length; m++) {
      for (final event in score.measures[m].events.where(
        (e) => e.voice == voice,
      )) {
        final x = ScorePainter.eventXFor(score, m, event.startTick, 10);
        final ys = event.isRest
            ? [ScorePainter.restY(event.voice, 10)]
            : event.pitches.map(
                (pitch) => ScorePainter.pitchY(pitch, event.staff, 10),
              );
        if (!ys.any((y) => (position.dy - y).abs() < 30)) continue;
        final dx = (position.dx - x).abs();
        if (dx < 18 && dx < distance) {
          closest = event;
          distance = dx;
        }
      }
    }
    return closest;
  }

  int _nearestPitch(VoiceEvent event, double y) {
    if (event.isRest) return 0;
    final target = ScorePainter.pitchAt(y, event.staff, 10).diatonicStep;
    var index = 0;
    for (var i = 1; i < event.pitches.length; i++) {
      if ((event.pitches[i].diatonicStep - target).abs() <
          (event.pitches[index].diatonicStep - target).abs()) {
        index = i;
      }
    }
    return index;
  }

  void _startGesture(Offset position, Score score) {
    gestureStart = position;
    for (var measure = 0; measure < score.measures.length; measure++) {
      for (final tick in score.measures[measure].dynamics.keys) {
        if (ScorePainter.dynamicBounds(
          score,
          measure,
          tick,
          10,
        ).inflate(6).contains(position)) {
          dynamicGesture = score.measureStart(measure) + tick;
          return;
        }
      }
      for (final hairpin in score.hairpins) {
        if (ScorePainter.hairpinBounds(
          score,
          hairpin,
          10,
        ).inflate(6).contains(position)) {
          hairpinGesture = hairpin.start;
          return;
        }
      }
    }
    if (position.dy >= 45 && position.dy <= 75) {
      for (var index = 0; index < score.measures.length; index++) {
        if ((position.dx - ScorePainter.barX(score, index, 10)).abs() <= 20) {
          tempoGesture = index;
          return;
        }
      }
    }
    settingsGesture = position.dx < ScorePainter.startFor(score, 10);
    if (settingsGesture) return;
    if (mode == WorkspaceMode.edit) {
      final hit = _hitEvent(score, position);
      if (hit != null) {
        final event = editor.eventById(hit.eventId);
        _select(
          hit.eventId,
          pitch: event == null ? 0 : _nearestPitch(event, position.dy),
          measure: score.measures.indexWhere((m) => m.events.contains(hit)),
        );
      } else {
        if (position.dy >= 50 && position.dy < 300) {
          for (var measure = 0; measure < score.measures.length; measure++) {
            if (position.dx >= ScorePainter.barX(score, measure, 10) &&
                position.dx < ScorePainter.barX(score, measure + 1, 10)) {
              barGesture = measure;
              break;
            }
          }
        }
        _select(null);
      }
    } else if (!rest) {
      previewStaff = chordStack && selected != null && !selected!.isRest
          ? selected!.staff
          : ScorePainter.staffAt(position.dy, 10);
      setState(() => preview = _writePitchAt(position, previewStaff!));
      _previewPitch(preview!, accidental: writeAccidental);
    }
  }

  void _updateGesture(Offset position) {
    if (gestureStart == null ||
        settingsGesture ||
        tempoGesture != null ||
        dynamicGesture != null ||
        hairpinGesture != null) {
      return;
    }
    if (mode == WorkspaceMode.write && !rest && previewStaff != null) {
      setState(() {
        if (!(chordStack && selected != null && !selected!.isRest)) {
          previewStaff = ScorePainter.staffAt(position.dy, 10);
        }
        preview = _writePitchAt(position, previewStaff!);
      });
      _previewPitch(preview!, accidental: writeAccidental);
    } else if (mode == WorkspaceMode.edit &&
        selected != null &&
        !selected!.isRest &&
        (preview != null || (position.dy - gestureStart!.dy).abs() > 5)) {
      previewStaff = selected!.staff;
      setState(
        () => preview = ScorePainter.pitchAt(position.dy, previewStaff!, 10),
      );
      _previewPitch(
        preview!,
        accidental: selected!.pitches[pitchIndex].accidental,
      );
    }
  }

  void _cancelGesture() => setState(() {
    piano.stop();
    gestureStart = null;
    settingsGesture = false;
    tempoGesture = null;
    dynamicGesture = null;
    hairpinGesture = null;
    barGesture = null;
    preview = null;
    previewStaff = null;
  });

  void _endGesture(Offset position) {
    if (gestureStart == null) return;
    if (hairpinGesture != null) {
      final start = hairpinGesture!;
      final isTap = (position - gestureStart!).distance < 15;
      _cancelGesture();
      if (isTap) _hairpinOptions(start);
      return;
    }
    if (dynamicGesture != null) {
      final tick = dynamicGesture!;
      final isTap = (position - gestureStart!).distance < 15;
      _cancelGesture();
      if (isTap) _dynamicPalette(tick);
      return;
    }
    if (tempoGesture != null) {
      final measure = tempoGesture!;
      final isTap = (position - gestureStart!).distance < 15;
      _cancelGesture();
      if (isTap) _barSettings(measure);
      return;
    }
    if (settingsGesture) {
      final isTap = (position - gestureStart!).distance < 15;
      _cancelGesture();
      if (isTap) _scoreSettings();
      return;
    }
    final staff = previewStaff ?? ScorePainter.staffAt(position.dy, 10);
    final pitch =
        preview ??
        (mode == WorkspaceMode.write
            ? _writePitchAt(position, staff)
            : ScorePainter.pitchAt(position.dy, staff, 10));
    final moved = (position.dy - gestureStart!.dy).abs() > 5;
    final bar = barGesture;
    final isTap = (position - gestureStart!).distance < 15;
    _cancelGesture();
    if (mode == WorkspaceMode.edit) {
      if (bar != null && isTap) {
        _selectMeasure(bar);
        return;
      }
      if (moved && selected != null && !selected!.isRest) {
        final accidental = selected!.pitches[pitchIndex].accidental;
        final midi = soundingMidi(
          pitch.diatonicStep,
          accidental,
          editor.keyAt(editor.measureAtTick(selected!.start)),
        );
        if (midi < 0 || midi > 127) {
          _perform(
            () => throw const EditException(
              'That pitch is outside the MIDI range.',
            ),
          );
        } else {
          _perform(
            () => editor.changePitch(
              selectedId!,
              pitchIndex,
              Pitch(
                diatonicStep: pitch.diatonicStep,
                midiNote: midi,
                accidental: accidental,
              ),
            ),
          );
        }
      }
      return;
    }
    _perform(() {
      final midi = soundingMidi(
        pitch.diatonicStep,
        pitch.accidental,
        editor.keyAt(entryMeasure),
      );
      if (!rest && (midi < 0 || midi > 127)) {
        throw const EditException('That pitch is outside the MIDI range.');
      }
      final writtenPitch = !rest
          ? Pitch(
              diatonicStep: pitch.diatonicStep,
              midiNote: midi,
              accidental: pitch.accidental,
            )
          : pitch;
      if (tieArmed && (rest || chordStack)) {
        throw const EditException(
          'Tie mode applies to single note entry, not rests or chord stacking.',
        );
      }
      if (tupletSize > 0 &&
          !chordStack &&
          !(replaceSelectedRest && selected?.tuplet != null)) {
        _startTuplet(staff);
      }
      if (chordStack) {
        if (rest) {
          throw const EditException('Turn off Rest to add a chord pitch.');
        }
        if (selected == null || selected!.isRest) {
          throw const EditException(
            'Select a note in Edit mode before adding chord pitches.',
          );
        }
        editor.addPitch(selectedId!, writtenPitch);
        pitchIndex = selected!.pitches.length - 1;
      } else if (!rest &&
          replaceSelectedRest &&
          selected != null &&
          selected!.isRest) {
        selectedId = editor.replaceRest(
          selectedId!,
          duration,
          writtenPitch,
          staff,
          tieToPrevious: tieArmed,
        );
        tieArmed = false;
        pitchIndex = 0;
        _advanceInTuplet();
      } else if (rest &&
          replaceSelectedRest &&
          selected != null &&
          selected!.isRest &&
          selected!.tuplet != null) {
        // The slot already is a rest; just move on to the next one.
        _advanceInTuplet();
      } else {
        selectedId = editor.append(
          voice: voice,
          staff: rest ? restStaffForVoice(voice) : staff,
          duration: duration,
          pitch: rest ? null : writtenPitch,
          measure: selectedMeasure,
          tieToPrevious: tieArmed,
        );
        tieArmed = false;
        selectedMeasure = editor.measureAtTick(
          editor.eventById(selectedId)!.end - 1,
        );
        replaceSelectedRest = false;
        pitchIndex = 0;
      }
    });
  }

  /// After filling a tuplet slot, select the next empty slot of the group.
  void _advanceInTuplet() {
    final next = editor.nextInTuplet(selectedId!);
    replaceSelectedRest = next != null && next.isRest;
    if (replaceSelectedRest) selectedId = next!.id;
  }

  void _startTuplet(Staff staff) {
    if (dots > 0) {
      throw const EditException('Tuplets cannot use dotted notes.');
    }
    selectedId = editor.insertTuplet(
      voice: voice,
      staff: staff,
      tuplet: tupletSize == 5
          ? const Tuplet.quintuplet()
          : const Tuplet.triplet(),
      value: noteValue,
      measure: selectedMeasure,
    );
    selectedMeasure = editor.measureAtTick(selected!.start);
    replaceSelectedRest = true;
    tieArmed = false;
    pitchIndex = 0;
  }

  void _changeDuration(NoteValue value, int dotCount) {
    if (mode == WorkspaceMode.edit && selected != null) {
      _perform(() {
        editor.resize(selectedId!, value.duration(dots: dotCount));
        noteValue = value;
        dots = dotCount;
      });
    } else {
      setState(() {
        noteValue = value;
        dots = dotCount;
      });
    }
  }

  void _accidental(Accidental accidental) {
    if (mode == WorkspaceMode.write) {
      setState(() {
        writeAccidental = writeAccidental == accidental
            ? Accidental.none
            : accidental;
      });
      return;
    }
    final event = selected;
    if (event == null || event.isRest) {
      _perform(
        () => throw const EditException('Select a note in Edit mode first.'),
      );
      return;
    }
    final old = event.pitches[pitchIndex];
    const semitones = [0, 2, 4, 5, 7, 9, 11];
    final natural =
        12 + old.diatonicStep ~/ 7 * 12 + semitones[old.diatonicStep % 7];
    final midi =
        natural +
        (accidental == Accidental.sharp
            ? 1
            : accidental == Accidental.flat
            ? -1
            : 0);
    if (midi < 0 || midi > 127) {
      _perform(
        () => throw const EditException(
          'That accidental is outside the MIDI pitch range.',
        ),
      );
      return;
    }
    _perform(
      () => editor.changePitch(
        event.id,
        pitchIndex,
        Pitch(
          diatonicStep: old.diatonicStep,
          midiNote: midi,
          accidental: accidental,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final score = editor.score;
    final events = editor.eventsFor(voice);
    final event = selected;
    final index = events.indexWhere((e) => e.id == selectedId);
    final above = _pitchInDirection(event, up: true);
    final below = _pitchInDirection(event, up: false);
    NotationEvent? renderedSelection;
    for (final measure in score.measures) {
      for (final item in measure.events) {
        if (item.eventId == selectedId) {
          renderedSelection = item;
          break;
        }
      }
      if (renderedSelection != null) break;
    }
    final cursor = mode == WorkspaceMode.write
        ? (event != null &&
                  ((event.isRest && !rest && replaceSelectedRest) ||
                      (chordStack && !event.isRest))
              ? event.start
              : editor.nextTick(voice, measure: selectedMeasure))
        : (preview != null ? event?.start : null);

    return PopScope(
      canPop:
          !checkingRecovery &&
          !saving &&
          !transferringProject &&
          !recoveryAvailable &&
          !dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop &&
            !checkingRecovery &&
            !saving &&
            !transferringProject &&
            await _confirmDiscard() &&
            mounted) {
          if (!recoveryAvailable || await _queueRecovery(discard: true)) {
            await SystemNavigator.pop();
          }
        }
      },
      child: IgnorePointer(
        ignoring:
            checkingRecovery ||
            saving ||
            transferringProject ||
            exportingPdf ||
            exportingMidi ||
            exportingMusicXml,
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 0, key: ValueKey('ad-slot')),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      IgnorePointer(
                        ignoring: playing,
                        child: _rail(64, [
                          _button(
                            mode == WorkspaceMode.write
                                ? 'Write mode'
                                : 'Edit mode',
                            mode == WorkspaceMode.write
                                ? Icons.edit
                                : Icons.touch_app,
                            () => setState(() {
                              piano.stop();
                              mode = mode == WorkspaceMode.write
                                  ? WorkspaceMode.edit
                                  : WorkspaceMode.write;
                              tieArmed = false;
                              preview = null;
                            }),
                            selected: mode == WorkspaceMode.edit,
                          ),
                          _button(
                            rest ? 'Rest' : 'Note',
                            rest ? Icons.hotel : Icons.music_note,
                            () => setState(() {
                              rest = !rest;
                              if (rest) tieArmed = false;
                            }),
                            selected: rest,
                          ),
                          const Divider(),
                          _button(
                            'Dynamics',
                            Icons.graphic_eq,
                            event == null
                                ? null
                                : () => _dynamicPalette(event.start),
                          ),
                          for (final value in NoteValue.values)
                            _durationButton(value),
                          _textButton(
                            dots == 2 ? '\u2022 \u2022' : '\u2022',
                            'Dot',
                            noteValue.maxDots == 0
                                ? null
                                : () => _changeDuration(
                                    noteValue,
                                    (dots + 1) % (noteValue.maxDots + 1),
                                  ),
                            selected: dots > 0,
                            semanticValue: switch (dots) {
                              1 => 'One dot',
                              2 => 'Two dots',
                              _ => 'No dots',
                            },
                          ),
                          _textButton(
                            tupletSize == 0 ? '3' : '$tupletSize',
                            'Tuplet',
                            mode == WorkspaceMode.write
                                ? () => setState(
                                    () => tupletSize = switch (tupletSize) {
                                      0 => 3,
                                      3 => 5,
                                      _ => 0,
                                    },
                                  )
                                : null,
                            selected: tupletSize > 0,
                            semanticValue: switch (tupletSize) {
                              3 => 'Triplet',
                              5 => 'Quintuplet',
                              _ => 'Off',
                            },
                          ),
                          _glyphButton(
                            mode == WorkspaceMode.write
                                ? 'Tie next note'
                                : 'Tie to previous note',
                            const TieIcon(),
                            mode == WorkspaceMode.edit
                                ? event == null || event.isRest
                                      ? null
                                      : _toggleTie
                                : rest || chordStack
                                ? null
                                : _toggleTie,
                            selected: mode == WorkspaceMode.write
                                ? tieArmed
                                : event?.tieFromPrevious ?? false,
                          ),
                          for (final item in [
                            (Accidental.sharp, '♯'),
                            (Accidental.flat, '♭'),
                            (Accidental.natural, '♮'),
                          ])
                            _textButton(
                              item.$2,
                              '${item.$2} accidental',
                              mode == WorkspaceMode.write ||
                                      (event != null && !event.isRest)
                                  ? () => _accidental(item.$1)
                                  : null,
                              selected:
                                  mode == WorkspaceMode.write &&
                                  writeAccidental == item.$1,
                            ),
                          const Divider(),
                          _glyphButton(
                            'Chord stack',
                            const ChordStackIcon(),
                            () => setState(() {
                              chordStack = !chordStack;
                              tieArmed = false;
                            }),
                            selected: chordStack,
                          ),
                          _textButton(
                            '\uE4B0',
                            'Articulations',
                            event == null
                                ? null
                                : () => _articulationPalette(event.id),
                            selected:
                                event != null &&
                                (event.articulations.isNotEmpty ||
                                    editor.arpeggios.containsKey(event.start)),
                            music: true,
                          ),
                        ]),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Container(
                              height: 40,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              color: const Color(0xffedf1ed),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final density = constraints.maxWidth < 520
                                      ? const VisualDensity(
                                          horizontal: -4,
                                          vertical: -2,
                                        )
                                      : VisualDensity.compact;
                                  final iconPadding = constraints.maxWidth < 520
                                      ? const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 8,
                                        )
                                      : null;
                                  return Row(
                                    children: [
                                      Tooltip(
                                        message: 'About Claviera',
                                        child: InkWell(
                                          onTap: _showAbout,
                                          child: Image.asset(
                                            'assets/icons/claviera_icon.png',
                                            width: 28,
                                            height: 28,
                                            excludeFromSemantics: true,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          projectName,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Go to start',
                                        visualDensity: density,
                                        padding: iconPadding,
                                        icon: const Icon(Icons.skip_previous),
                                        onPressed:
                                            !playing && selectedMeasure > 0
                                            ? () => _selectMeasure(0)
                                            : null,
                                      ),
                                      IconButton(
                                        tooltip: playing
                                            ? 'Stop playback'
                                            : 'Play score',
                                        visualDensity: density,
                                        padding: iconPadding,
                                        icon: Icon(
                                          playing
                                              ? Icons.stop
                                              : Icons.play_arrow,
                                        ),
                                        onPressed: playing
                                            ? _stopScore
                                            : _playScore,
                                      ),
                                      IconButton(
                                        tooltip: 'Go to end',
                                        visualDensity: density,
                                        padding: iconPadding,
                                        icon: const Icon(Icons.skip_next),
                                        onPressed:
                                            !playing &&
                                                selectedMeasure + 1 <
                                                    score.measures.length
                                            ? () => _selectMeasure(
                                                score.measures.length - 1,
                                              )
                                            : null,
                                      ),
                                      TextButton(
                                        onPressed: playing ? null : _setTempo,
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: const Size(55, 36),
                                        ),
                                        child: Text('$tempo BPM'),
                                      ),
                                      IconButton(
                                        tooltip: piano.enabled
                                            ? 'Mute piano preview'
                                            : 'Enable piano preview',
                                        visualDensity: density,
                                        padding: iconPadding,
                                        icon: Icon(
                                          piano.enabled
                                              ? Icons.volume_up
                                              : Icons.volume_off,
                                        ),
                                        onPressed: () => setState(
                                          () =>
                                              piano.setEnabled(!piano.enabled),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Previous bar',
                                        visualDensity: density,
                                        padding: iconPadding,
                                        icon: const Icon(Icons.chevron_left),
                                        onPressed:
                                            !playing && selectedMeasure > 0
                                            ? () => _selectMeasure(
                                                selectedMeasure - 1,
                                              )
                                            : null,
                                      ),
                                      Tooltip(
                                        message: 'Bar menu',
                                        child: TextButton(
                                          onPressed: playing
                                              ? null
                                              : () => _barSettings(
                                                  selectedMeasure,
                                                ),
                                          style: TextButton.styleFrom(
                                            minimumSize: Size.zero,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 2,
                                              vertical: 8,
                                            ),
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'Bar ${(playbackFrame?.measure ?? selectedMeasure) + 1}',
                                                style:
                                                    constraints.maxWidth < 520
                                                    ? const TextStyle(
                                                        fontSize: 12,
                                                      )
                                                    : null,
                                              ),
                                              const Icon(
                                                Icons.arrow_drop_down,
                                                size: 16,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Next bar',
                                        visualDensity: density,
                                        padding: iconPadding,
                                        icon: const Icon(Icons.chevron_right),
                                        onPressed:
                                            !playing &&
                                                selectedMeasure + 1 <
                                                    score.measures.length
                                            ? () => _selectMeasure(
                                                selectedMeasure + 1,
                                              )
                                            : null,
                                      ),
                                      if (constraints.maxWidth >= 900)
                                        Text(
                                          mode == WorkspaceMode.write
                                              ? 'WRITE · 2 FINGERS TO SCROLL'
                                              : 'EDIT · TAP TO SELECT',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            Expanded(
                              child: IgnorePointer(
                                ignoring: playing,
                                child: ScoreViewport(
                                  score: score,
                                  selectedEvent: playing
                                      ? null
                                      : renderedSelection,
                                  selectedPitch: pitchIndex,
                                  selectedMeasure:
                                      playbackFrame?.measure ?? selectedMeasure,
                                  revealRevision: revealRevision,
                                  cursorTick: playing ? null : cursor,
                                  playingSegments:
                                      playbackFrame?.segments ?? const {},
                                  playingPitches:
                                      playbackFrame?.playingPitches ?? const {},
                                  previewPitch: playing ? null : preview,
                                  previewStaff: previewStaff,
                                  previewDuration: duration,
                                  previewVoice: voice,
                                  onStart: (position) =>
                                      _startGesture(position, score),
                                  onUpdate: _updateGesture,
                                  onEnd: _endGesture,
                                  onCancel: _cancelGesture,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IgnorePointer(
                        ignoring: playing,
                        child: _rail(68, [
                          for (final value in Voice.values)
                            _textButton(
                              value.name.toUpperCase(),
                              'Voice ${value.index + 1}',
                              () => _selectVoice(value),
                              selected: voice == value,
                            ),
                          const Divider(),
                          _button(
                            'Previous event',
                            Icons.chevron_left,
                            index > 0
                                ? () => _select(events[index - 1].id)
                                : null,
                          ),
                          _button(
                            'Next event',
                            Icons.chevron_right,
                            events.isNotEmpty && index + 1 < events.length
                                ? () => _select(events[index + 1].id)
                                : null,
                          ),
                          _button(
                            'Higher chord note',
                            Icons.keyboard_arrow_up,
                            above == null
                                ? null
                                : () => setState(() => pitchIndex = above),
                          ),
                          _button(
                            'Lower chord note',
                            Icons.keyboard_arrow_down,
                            below == null
                                ? null
                                : () => setState(() => pitchIndex = below),
                          ),
                          _button(
                            'Undo',
                            Icons.undo,
                            editor.canUndo
                                ? () => _perform(() {
                                    editor.undo();
                                    selectedMeasure = selectedMeasure.clamp(
                                      0,
                                      editor.measureCount - 1,
                                    );
                                    selectedId = null;
                                    pitchIndex = 0;
                                  })
                                : null,
                          ),
                          _button(
                            'Delete',
                            Icons.delete_outline,
                            mode == WorkspaceMode.edit && event != null
                                ? () => _perform(() {
                                    editor.delete(
                                      event.id,
                                      pitchIndex: pitchIndex,
                                    );
                                    pitchIndex = 0;
                                    if (editor.eventById(event.id) == null) {
                                      selectedId = null;
                                    }
                                  })
                                : null,
                          ),
                          _glyphButton(
                            'Transpose score',
                            const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.music_note, size: 14),
                                Icon(Icons.swap_vert, size: 14),
                              ],
                            ),
                            _transposeScore,
                          ),
                          _button(
                            'Menu',
                            Icons.menu,
                            () => showWorkspaceMenu(
                              context,
                              canRedo: editor.canRedo,
                              onNew: _newProject,
                              onOpen: _openProject,
                              onSave: _saveProject,
                              onSaveAs: () => _saveProject(saveAs: true),
                              onRename: () => _saveProject(rename: true),
                              onExportPdf: _exportPdf,
                              onExportMidi: _exportMidi,
                              onExportMusicXml: _exportMusicXml,
                              isPro: hasPro,
                              onUpgrade: _showProUpgrade,
                              onBackup: _backupProject,
                              onRestoreBackup: _restoreProjectBackup,
                              onReverb: () => showReverbSettings(context),
                              onRedo: () => _perform(() {
                                editor.redo();
                                selectedMeasure = selectedMeasure.clamp(
                                  0,
                                  editor.measureCount - 1,
                                );
                                selectedId = null;
                                pitchIndex = 0;
                              }),
                            ),
                          ),
                        ]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _rail(double width, List<Widget> children) => Container(
    width: width,
    color: const Color(0xffe6ece8),
    child: ListView(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 5),
      children: children,
    ),
  );

  Widget _button(
    String label,
    IconData icon,
    VoidCallback? onPressed, {
    bool selected = false,
  }) => _glyphButton(label, Icon(icon), onPressed, selected: selected);

  Widget _glyphButton(
    String label,
    Widget icon,
    VoidCallback? onPressed, {
    bool selected = false,
  }) => Tooltip(
    message: label,
    child: IconButton(
      visualDensity: VisualDensity.compact,
      iconSize: 21,
      onPressed: onPressed,
      isSelected: selected,
      style: IconButton.styleFrom(
        backgroundColor: selected ? const Color(0xffc7dfd5) : null,
      ),
      icon: icon,
    ),
  );

  Widget _textButton(
    String text,
    String label,
    VoidCallback? onPressed, {
    bool selected = false,
    bool music = false,
    String? semanticValue,
  }) => Tooltip(
    message: label,
    child: Semantics(
      label: label,
      value: semanticValue,
      button: true,
      selected: selected,
      child: ExcludeSemantics(
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(40, 36),
            backgroundColor: selected ? const Color(0xffc7dfd5) : null,
            foregroundColor: const Color(0xff244d45),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontFamily: music ? 'Bravura' : null,
              fontSize: music ? 26 : 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _durationButton(NoteValue value) {
    final notes = [
      '\uE1D2',
      '\uE1D3',
      '\uE1D5',
      '\uE1D7',
      '\uE1D9',
      '\uE1DB',
      '\uE1DD',
    ];
    final rests = [
      '\uE4E3',
      '\uE4E4',
      '\uE4E5',
      '\uE4E6',
      '\uE4E7',
      '\uE4E8',
      '\uE4E9',
    ];
    return _textButton(
      (rest ? rests : notes)[value.index],
      '${value.name} ${rest ? 'rest' : 'note'}',
      () => _changeDuration(value, dots.clamp(0, value.maxDots)),
      selected: value == noteValue,
      music: true,
    );
  }
}

class TieIcon extends StatelessWidget {
  const TieIcon({super.key});

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(26, 24),
    painter: _TiePainter(IconTheme.of(context).color ?? Colors.black),
  );
}

class _TiePainter extends CustomPainter {
  const _TiePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final y = size.height * 0.4;
    final head = Paint()..color = color;
    canvas.drawOval(Rect.fromLTWH(0, y, 7, 5.5), head);
    canvas.drawOval(Rect.fromLTWH(w - 7, y, 7, 5.5), head);
    final arc = Path()
      ..moveTo(3.5, y + 8)
      ..quadraticBezierTo(w / 2, y + 18, w - 3.5, y + 8)
      ..quadraticBezierTo(w / 2, y + 14, 3.5, y + 8);
    canvas.drawPath(arc, head);
  }

  @override
  bool shouldRepaint(_TiePainter old) => old.color != color;
}

class ChordStackIcon extends StatelessWidget {
  const ChordStackIcon({super.key});

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(24, 24),
    painter: StackPainter(IconTheme.of(context).color ?? Colors.black),
  );
}

class StackPainter extends CustomPainter {
  const StackPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final stem = Paint()
      ..color = color
      ..strokeWidth = 1.6;
    const heads = [Offset(8, 18), Offset(8, 12), Offset(8, 6)];
    for (final c in heads) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(-0.35);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 10, height: 6.5),
        paint,
      );
      canvas.restore();
    }
    canvas.drawLine(const Offset(12.6, 17), const Offset(12.6, 1), stem);
  }

  @override
  bool shouldRepaint(StackPainter old) => old.color != color;
}
