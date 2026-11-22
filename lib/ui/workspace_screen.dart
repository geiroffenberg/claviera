import 'package:flutter/material.dart';

import '../editor/score_editor.dart';
import '../models/blank_score.dart';
import '../models/score.dart';
import '../notation/score_painter.dart';
import '../notation/score_viewport.dart';
import 'workspace_menu.dart';

enum WorkspaceMode { write, edit }

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});
  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final editor = ScoreEditor(blankScore);
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

  VoiceEvent? get selected => editor.eventById(selectedId);
  int get duration => noteValue.duration(dotted: dotted);

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
      selectedMeasure = event.start ~/ blankScore.ticksPerMeasure;
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
    selectedMeasure = measure;
    selectedId = null;
    pitchIndex = 0;
    replaceSelectedRest = false;
    preview = null;
  });

  void _selectVoice(Voice value) => setState(() {
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
        final x = ScorePainter.eventX(
          m,
          event.startTick,
          score.ticksPerMeasure,
          10,
        );
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
    if (mode == WorkspaceMode.edit) {
      final hit = _hitEvent(score, position);
      if (hit != null) {
        final event = editor.eventById(hit.eventId);
        _select(
          hit.eventId,
          pitch: event == null ? 0 : _nearestPitch(event, position.dy),
          measure: ((position.dx / 10 - 13) / 28).floor().clamp(
            0,
            score.measures.length - 1,
          ),
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
    }
  }

  void _updateGesture(Offset position) {
    if (gestureStart == null) return;
    if (mode == WorkspaceMode.write && !rest && previewStaff != null) {
      setState(
        () => preview = ScorePainter.pitchAt(position.dy, previewStaff!, 10),
      );
    } else if (mode == WorkspaceMode.edit &&
        selected != null &&
        !selected!.isRest &&
        (preview != null || (position.dy - gestureStart!.dy).abs() > 5)) {
      previewStaff = selected!.staff;
      setState(
        () => preview = ScorePainter.pitchAt(position.dy, previewStaff!, 10),
      );
    }
  }

  void _cancelGesture() => setState(() {
    gestureStart = null;
    preview = null;
    previewStaff = null;
  });

  void _endGesture(Offset position) {
    if (gestureStart == null) return;
    final staff = previewStaff ?? ScorePainter.staffAt(position.dy, 10);
    final pitch = preview ?? ScorePainter.pitchAt(position.dy, staff, 10);
    final moved = (position.dy - gestureStart!.dy).abs() > 5;
    _cancelGesture();
    if (mode == WorkspaceMode.edit) {
      if (moved && selected != null && !selected!.isRest) {
        final accidental = selected!.pitches[pitchIndex].accidental;
        final alteration = accidental == Accidental.sharp
            ? 1
            : accidental == Accidental.flat
            ? -1
            : 0;
        final midi = pitch.midiNote + alteration;
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
      if (chordStack) {
        if (rest) {
          throw const EditException('Turn off Rest to add a chord pitch.');
        }
        if (selected == null || selected!.isRest) {
          throw const EditException(
            'Select a note in Edit mode before adding chord pitches.',
          );
        }
        editor.addPitch(selectedId!, pitch);
        pitchIndex = selected!.pitches.length - 1;
      } else if (!rest &&
          replaceSelectedRest &&
          selected != null &&
          selected!.isRest) {
        selectedId = editor.replaceRest(selectedId!, duration, pitch, staff);
        replaceSelectedRest = false;
        pitchIndex = 0;
      } else {
        selectedId = editor.append(
          voice: voice,
          staff: staff,
          duration: duration,
          pitch: rest ? null : pitch,
          measure: selectedMeasure,
        );
        selectedMeasure =
            (editor.eventById(selectedId)!.end - 1) ~/
            blankScore.ticksPerMeasure;
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

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 0, key: ValueKey('ad-slot')),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _rail(64, [
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
                      mode == WorkspaceMode.write ? 'Write mode' : 'Edit mode',
                      mode == WorkspaceMode.write
                          ? Icons.edit
                          : Icons.touch_app,
                      () => setState(() {
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
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          color: const Color(0xffedf1ed),
                          child: Row(
                            children: [
                              const Text(
                                'CLAVIERA',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.4,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  score.title,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Previous bar',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.chevron_left),
                                onPressed: selectedMeasure > 0
                                    ? () => _selectMeasure(selectedMeasure - 1)
                                    : null,
                              ),
                              Text('Bar ${selectedMeasure + 1}'),
                              IconButton(
                                tooltip: 'Next bar',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.chevron_right),
                                onPressed:
                                    selectedMeasure + 1 < score.measures.length
                                    ? () => _selectMeasure(selectedMeasure + 1)
                                    : null,
                              ),
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
                        Expanded(
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
                      ],
                    ),
                  ),
                  _rail(68, [
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
                      index > 0 ? () => _select(events[index - 1].id) : null,
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
                              editor.delete(event.id, pitchIndex: pitchIndex);
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
                ],
              ),
            ),
          ],
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
