import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/piano_preview.dart';
import '../audio/score_playback.dart';
import '../editor/score_editor.dart';
import '../models/blank_score.dart';
import '../models/score.dart';
import '../notation/score_painter.dart';
import '../notation/score_viewport.dart';
import '../storage/projects.dart';
import 'workspace_menu.dart';

enum WorkspaceMode { write, edit }

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key, this.pianoPreview, this.projectStore});

  final PianoPreview? pianoPreview;
  final ProjectStore? projectStore;
  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen>
    with WidgetsBindingObserver {
  ScoreEditor editor = ScoreEditor(blankScore);
  late final ProjectStore projectStore;
  String projectName = 'Untitled score';
  String? projectId;
  late String savedState;
  late final PianoPreview piano;
  Voice voice = Voice.v1;
  NoteValue noteValue = NoteValue.quarter;
  WorkspaceMode mode = WorkspaceMode.write;
  bool rest = false;
  bool dotted = false;
  bool chordStack = false;
  int? selectedId;
  int selectedMeasure = 0;
  bool replaceSelectedRest = false;
  int pitchIndex = 0;
  Pitch? preview;
  Staff? previewStaff;
  Offset? gestureStart;
  bool settingsGesture = false;
  int? tempoGesture;
  bool playing = false;
  bool saving = false;
  int playbackRevision = 0;
  int tempo = 120;

  VoiceEvent? get selected => editor.eventById(selectedId);
  int get duration => noteValue.duration(dotted: dotted);
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

  @override
  void initState() {
    super.initState();
    projectStore = widget.projectStore ?? ProjectStore();
    savedState = ProjectCodec.encode(project);
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
      if (mounted) piano.warmUp();
    });
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
      piano.stop();
      if (playing) {
        piano.stopScore();
        setState(() {
          playbackRevision++;
          playing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    piano.dispose();
    super.dispose();
  }

  void _previewPitch(Pitch pitch, {Accidental accidental = Accidental.none}) {
    final midi = soundingMidi(
      pitch.diatonicStep,
      accidental,
      editor.keyAt(entryMeasure),
    );
    if (midi >= 0 && midi <= 127) {
      piano.play(midi);
    } else {
      piano.stop();
    }
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
      final plan = PlaybackPlan(editor, tempo);
      piano.stop();
      final revision = ++playbackRevision;
      setState(() => playing = true);
      final started = await piano.playScore(
        plan,
        onFinished: () {
          if (mounted && revision == playbackRevision) {
            setState(() => playing = false);
          }
        },
      );
      if (!started && mounted && revision == playbackRevision) {
        setState(() => playing = false);
      }
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  void _stopScore() {
    playbackRevision++;
    piano.stopScore();
    setState(() => playing = false);
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
    if (mounted && value != null) setState(() => tempo = value);
  }

  Future<void> _barSettings(int measure) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Bar ${measure + 1} settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.speed),
              title: const Text('Tempo'),
              onTap: () => Navigator.pop(context, 'tempo'),
            ),
            ListTile(
              leading: const Icon(Icons.music_note),
              title: const Text('Key and time signature'),
              onTap: () => Navigator.pop(context, 'signatures'),
            ),
            ListTile(
              leading: const Icon(Icons.repeat),
              title: const Text('Repeats'),
              onTap: () => Navigator.pop(context, 'repeats'),
            ),
          ],
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
    if (choice == 'tempo') {
      await _setBarTempo(measure);
    } else if (choice == 'signatures') {
      await _scoreSettings(measure: measure == 0 ? null : measure);
    } else if (choice == 'repeats') {
      await _setBarRepeats(measure);
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
      for (final value in NoteValue.values) {
        if (event.duration == value.ticks) {
          noteValue = value;
          dotted = false;
          break;
        }
        if (value != NoteValue.sixtyFourth &&
            event.duration == value.duration(dotted: true)) {
          noteValue = value;
          dotted = true;
          break;
        }
      }
    }
  });

  void _selectMeasure(int measure) => setState(() {
    piano.stop();
    selectedMeasure = measure;
    selectedId = null;
    pitchIndex = 0;
    replaceSelectedRest = false;
    preview = null;
  });

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
            ? [(event.staff == Staff.treble ? 10 : 22) * 10.0]
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
        _select(null);
      }
    } else if (!rest) {
      previewStaff = chordStack && selected != null && !selected!.isRest
          ? selected!.staff
          : ScorePainter.staffAt(position.dy, 10);
      setState(
        () => preview = ScorePainter.pitchAt(position.dy, previewStaff!, 10),
      );
      _previewPitch(preview!);
    }
  }

  void _updateGesture(Offset position) {
    if (gestureStart == null || settingsGesture || tempoGesture != null) return;
    if (mode == WorkspaceMode.write && !rest && previewStaff != null) {
      setState(() {
        if (!(chordStack && selected != null && !selected!.isRest)) {
          previewStaff = ScorePainter.staffAt(position.dy, 10);
        }
        preview = ScorePainter.pitchAt(position.dy, previewStaff!, 10);
      });
      _previewPitch(preview!);
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
    preview = null;
    previewStaff = null;
  });

  void _endGesture(Offset position) {
    if (gestureStart == null) return;
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
    final pitch = preview ?? ScorePainter.pitchAt(position.dy, staff, 10);
    final moved = (position.dy - gestureStart!.dy).abs() > 5;
    _cancelGesture();
    if (mode == WorkspaceMode.edit) {
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
        );
        replaceSelectedRest = false;
        pitchIndex = 0;
      } else {
        selectedId = editor.append(
          voice: voice,
          staff: staff,
          duration: duration,
          pitch: rest ? null : writtenPitch,
          measure: selectedMeasure,
        );
        selectedMeasure = editor.measureAtTick(
          editor.eventById(selectedId)!.end - 1,
        );
        replaceSelectedRest = false;
        pitchIndex = 0;
      }
    });
  }

  void _changeDuration(NoteValue value, bool dot) {
    if (mode == WorkspaceMode.edit && selected != null) {
      _perform(() {
        editor.resize(selectedId!, value.duration(dotted: dot));
        noteValue = value;
        dotted = dot;
      });
    } else {
      setState(() {
        noteValue = value;
        dotted = dot;
      });
    }
  }

  void _accidental(Accidental accidental) {
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
      canPop: !saving && !dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && !saving && await _confirmDiscard() && mounted) {
          await SystemNavigator.pop();
        }
      },
      child: IgnorePointer(
        ignoring: saving,
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
                            rest ? 'Rest' : 'Note',
                            rest ? Icons.hotel : Icons.music_note,
                            () => setState(() => rest = !rest),
                            selected: rest,
                          ),
                          for (final value in NoteValue.values)
                            _durationButton(value),
                          _button(
                            'Dot',
                            Icons.circle,
                            noteValue == NoteValue.sixtyFourth
                                ? null
                                : () => _changeDuration(noteValue, !dotted),
                            selected: dotted,
                          ),
                          const Divider(),
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
                              preview = null;
                            }),
                            selected: mode == WorkspaceMode.edit,
                          ),
                          _button(
                            'Chord stack',
                            Icons.library_add,
                            () => setState(() => chordStack = !chordStack),
                            selected: chordStack,
                          ),
                        ]),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Container(
                              height: 40,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              color: const Color(0xffedf1ed),
                              child: LayoutBuilder(
                                builder: (context, constraints) => Row(
                                  children: [
                                    if (constraints.maxWidth >= 450) ...[
                                      const Text(
                                        'CLAVIERA',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.4,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                    ],
                                    Expanded(
                                      child: Text(
                                        projectName,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: playing
                                          ? 'Stop playback'
                                          : 'Play score',
                                      visualDensity: VisualDensity.compact,
                                      icon: Icon(
                                        playing ? Icons.stop : Icons.play_arrow,
                                      ),
                                      onPressed: playing
                                          ? _stopScore
                                          : _playScore,
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
                                      visualDensity: VisualDensity.compact,
                                      icon: Icon(
                                        piano.enabled
                                            ? Icons.volume_up
                                            : Icons.volume_off,
                                      ),
                                      onPressed: () => setState(
                                        () => piano.setEnabled(!piano.enabled),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Previous bar',
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(Icons.chevron_left),
                                      onPressed: selectedMeasure > 0
                                          ? () => _selectMeasure(
                                              selectedMeasure - 1,
                                            )
                                          : null,
                                    ),
                                    Text('Bar ${selectedMeasure + 1}'),
                                    IconButton(
                                      tooltip: 'Next bar',
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(Icons.chevron_right),
                                      onPressed:
                                          selectedMeasure + 1 <
                                              score.measures.length
                                          ? () => _selectMeasure(
                                              selectedMeasure + 1,
                                            )
                                          : null,
                                    ),
                                    if (constraints.maxWidth >= 800)
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
                                ),
                              ),
                            ),
                            Expanded(
                              child: IgnorePointer(
                                ignoring: playing,
                                child: ScoreViewport(
                                  score: score,
                                  selectedEvent: renderedSelection,
                                  selectedPitch: pitchIndex,
                                  selectedMeasure: selectedMeasure,
                                  cursorTick: cursor,
                                  previewPitch: preview,
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
                          const Divider(),
                          for (final item in [
                            (Accidental.sharp, '♯'),
                            (Accidental.flat, '♭'),
                            (Accidental.natural, '♮'),
                          ])
                            _textButton(
                              item.$2,
                              '${item.$2} accidental',
                              mode == WorkspaceMode.edit &&
                                      event != null &&
                                      !event.isRest
                                  ? () => _accidental(item.$1)
                                  : null,
                            ),
                          _button(
                            'Undo',
                            Icons.undo,
                            editor.canUndo
                                ? () => setState(() {
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
                              onRedo: () => setState(() {
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
      icon: Icon(icon),
    ),
  );

  Widget _textButton(
    String text,
    String label,
    VoidCallback? onPressed, {
    bool selected = false,
    bool music = false,
  }) => Tooltip(
    message: label,
    child: Semantics(
      label: label,
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
      () => _changeDuration(
        value,
        value == NoteValue.sixtyFourth ? false : dotted,
      ),
      selected: value == noteValue,
      music: true,
    );
  }
}
