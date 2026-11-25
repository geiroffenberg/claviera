import 'dart:math' as math;

import '../models/score.dart';

class EditException implements Exception {
  const EditException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One logical event may be rendered as several tied notation segments.
class VoiceEvent {
  VoiceEvent({
    required this.id,
    required this.start,
    required this.duration,
    required this.voice,
    required this.staff,
    List<Pitch> pitches = const [],
    this.generatedRest = false,
    Set<Articulation> articulations = const {},
    this.tieFromPrevious = false,
    this.tieToNext = false,
    this.tuplet,
  }) : pitches = List.unmodifiable(pitches),
       articulations = Set.unmodifiable(articulations);

  final int id;
  final int start;
  final int duration;
  final Voice voice;
  final Staff staff;
  final List<Pitch> pitches;
  final bool generatedRest;
  final Set<Articulation> articulations;
  final bool tieFromPrevious;
  final bool tieToNext;
  final Tuplet? tuplet;
  bool get isRest => pitches.isEmpty;
  int get end => start + duration;

  VoiceEvent copyWith({
    int? start,
    int? duration,
    Staff? staff,
    List<Pitch>? pitches,
    bool? generatedRest,
    Set<Articulation>? articulations,
    bool? tieFromPrevious,
    bool? tieToNext,
  }) => VoiceEvent(
    id: id,
    start: start ?? this.start,
    duration: duration ?? this.duration,
    voice: voice,
    staff: staff ?? this.staff,
    pitches: pitches ?? this.pitches,
    generatedRest: generatedRest ?? this.generatedRest,
    articulations: articulations ?? this.articulations,
    tieFromPrevious: tieFromPrevious ?? this.tieFromPrevious,
    tieToNext: tieToNext ?? this.tieToNext,
    tuplet: tuplet,
  );
}

class _Snapshot {
  _Snapshot(
    this.events,
    this.measureCount,
    this.nextId,
    this.beats,
    this.unit,
    this.key,
    this.tempos,
    this.times,
    this.keys,
    this.repeatStarts,
    this.repeatEnds,
    this.dynamics,
    this.hairpins,
    this.arpeggios,
    this.notes,
  );
  final List<VoiceEvent> events;
  final int measureCount;
  final int nextId;
  final int beats;
  final int unit;
  final int key;
  final Map<int, int> tempos;
  final Map<int, TimeSignature> times;
  final Map<int, int> keys;
  final Set<int> repeatStarts;
  final Set<int> repeatEnds;
  final Map<int, DynamicMark> dynamics;
  final List<Hairpin> hairpins;
  final Map<int, ArpeggioDirection> arpeggios;
  final Map<int, String> notes;
}

class _BarData {
  const _BarData({
    required this.time,
    required this.key,
    required this.tempo,
    this.explicitTime = false,
    this.explicitKey = false,
    this.explicitTempo = false,
    this.repeatStart = false,
    this.repeatEnd = false,
    this.note = '',
  });

  final TimeSignature time;
  final int key;
  final int tempo;
  final bool explicitTime;
  final bool explicitKey;
  final bool explicitTempo;
  final bool repeatStart;
  final bool repeatEnd;
  final String note;
}

class BarClipboard {
  BarClipboard._(
    this._bars,
    this._events,
    this._dynamics,
    this._hairpins,
    this._arpeggios,
  );

  final List<_BarData> _bars;
  final List<VoiceEvent> _events;
  final Map<int, DynamicMark> _dynamics;
  final List<Hairpin> _hairpins;
  final Map<int, ArpeggioDirection> _arpeggios;

  int get count => _bars.length;
}

class ScoreEditor {
  ScoreEditor(Score source)
    : _source = source,
      _beats = source.beatsPerMeasure,
      _unit = source.beatUnit,
      _key = source.keySignature,
      _tempos = {
        for (var i = 0; i < source.measures.length; i++)
          if (source.measures[i].tempo != null) i: source.measures[i].tempo!,
      },
      _times = {
        for (var i = 0; i < source.measures.length; i++)
          if (source.measures[i].timeSignature != null)
            i: source.measures[i].timeSignature!,
      },
      _keys = {
        for (var i = 0; i < source.measures.length; i++)
          if (source.measures[i].keySignature != null)
            i: source.measures[i].keySignature!,
      },
      _repeatStarts = {
        for (var i = 0; i < source.measures.length; i++)
          if (source.measures[i].repeatStart) i,
      },
      _repeatEnds = {
        for (var i = 0; i < source.measures.length; i++)
          if (source.measures[i].repeatEnd) i,
      },
      _dynamics = {
        for (var i = 0; i < source.measures.length; i++)
          for (final entry in source.measures[i].dynamics.entries)
            source.measureStart(i) + entry.key: entry.value,
      },
      _hairpins = List.of(source.hairpins),
      _arpeggios = {
        for (var i = 0; i < source.measures.length; i++)
          for (final entry in source.measures[i].arpeggios.entries)
            source.measureStart(i) + entry.key: entry.value,
      },
      _notes = {
        for (var i = 0; i < source.measures.length; i++)
          if (source.measures[i].note.isNotEmpty) i: source.measures[i].note,
      },
      _measureCount = source.measures.length {
    for (var measure = 0; measure < source.measures.length; measure++) {
      for (final event in source.measures[measure].events) {
        if (!validArticulations(event.articulations, isRest: event.isRest)) {
          throw ArgumentError('Invalid note articulations.');
        }
        _events.add(
          VoiceEvent(
            id: _nextId++,
            start: source.measureStart(measure) + event.startTick,
            duration: event.durationTicks,
            voice: event.voice,
            staff: event.staff,
            pitches: event.pitches,
            articulations: event.articulations,
            tieFromPrevious: event.tieFromPrevious,
            tieToNext: event.tieToNext,
            tuplet: event.tuplet,
          ),
        );
      }
    }
    for (final voice in Voice.values) {
      var end = 0;
      for (final event in storedEventsFor(voice)) {
        if (event.start < end) {
          throw ArgumentError(
            'The source score has overlapping events in ${voice.name}.',
          );
        }
        end = event.end;
      }
    }
    _normalizeRests();
    try {
      _validateTies();
      _validateTuplets();
      _resolvedEvents();
    } on EditException catch (error) {
      throw ArgumentError(error.message);
    }
    for (var measure = 0; measure < source.measures.length; measure++) {
      for (final offset in source.measures[measure].arpeggios.keys) {
        if (offset < 0 ||
            offset >= source.timeAt(measure).ticks ||
            offset % 60 != 0 ||
            pitchCountAt(source.measureStart(measure) + offset) < 2) {
          throw ArgumentError('Invalid arpeggio.');
        }
      }
    }
  }

  final Score _source;
  int _beats;
  int _unit;
  int _key;
  Map<int, int> _tempos;
  Map<int, TimeSignature> _times;
  Map<int, int> _keys;
  Set<int> _repeatStarts;
  Map<int, String> _notes;
  Set<int> _repeatEnds;
  Map<int, DynamicMark> _dynamics;
  List<Hairpin> _hairpins;
  Map<int, ArpeggioDirection> _arpeggios;
  Set<int> get repeatStarts => Set.unmodifiable(_repeatStarts);
  Set<int> get repeatEnds => Set.unmodifiable(_repeatEnds);
  Map<int, int> get tempoChanges => Map.unmodifiable(_tempos);
  Map<int, TimeSignature> get timeChanges => Map.unmodifiable(_times);
  Map<int, int> get keyChanges => Map.unmodifiable(_keys);
  Map<int, DynamicMark> get dynamicChanges => Map.unmodifiable(_dynamics);
  List<Hairpin> get hairpins => List.unmodifiable(_hairpins);
  Map<int, ArpeggioDirection> get arpeggios => Map.unmodifiable(_arpeggios);

  int pitchCountAt(int tick) => _events
      .where((event) => event.start == tick)
      .fold(0, (total, event) => total + event.pitches.length);
  Hairpin? get pendingHairpin =>
      _hairpins.where((hairpin) => hairpin.end == null).firstOrNull;

  DynamicMark? dynamicAt(int tick) {
    DynamicMark? result;
    var latest = -1;
    for (final entry in _dynamics.entries) {
      if (entry.key <= tick && entry.key > latest) {
        latest = entry.key;
        result = entry.value;
      }
    }
    return result;
  }

  int get ticksPerMeasure => _beats * ticksPerQuarter * 4 ~/ _unit;
  TimeSignature timeAt(int measure) {
    var time = TimeSignature(_beats, _unit);
    for (var i = 0; i <= measure; i++) {
      time = _times[i] ?? time;
    }
    return time;
  }

  int keyAt(int measure) {
    var key = _key;
    for (var i = 0; i <= measure; i++) {
      key = _keys[i] ?? key;
    }
    return key;
  }

  int measureStart(int measure) {
    var start = 0;
    var time = TimeSignature(_beats, _unit);
    for (var i = 0; i < measure; i++) {
      time = _times[i] ?? time;
      start += time.ticks;
    }
    return start;
  }

  int measureAtTick(int tick) {
    if (tick < 0) throw RangeError.value(tick, 'tick');
    var start = 0;
    var time = TimeSignature(_beats, _unit);
    for (var i = 0; i < _measureCount; i++) {
      time = _times[i] ?? time;
      if (tick < start + time.ticks) return i;
      start += time.ticks;
    }
    return _measureCount + (tick - start) ~/ time.ticks;
  }

  List<VoiceEvent> _events = [];
  List<VoiceEvent>? _resolvedCache;
  int _measureCount;
  int _nextId = 1;
  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  // Persist the underlying pitches, not the derived in-bar alterations.
  List<VoiceEvent> storedEventsFor(Voice voice) =>
      _events.where((e) => e.voice == voice).toList()
        ..sort((a, b) => a.start.compareTo(b.start));

  List<VoiceEvent> eventsFor(Voice voice) =>
      _resolvedEvents().where((e) => e.voice == voice).toList()
        ..sort((a, b) => a.start.compareTo(b.start));

  VoiceEvent? eventById(int? id) {
    for (final event in _resolvedEvents()) {
      if (event.id == id) return event;
    }
    return null;
  }

  VoiceEvent? _storedEventById(int? id) {
    for (final event in _events) {
      if (event.id == id) return event;
    }
    return null;
  }

  List<VoiceEvent> _resolvedEvents() {
    final cached = _resolvedCache;
    if (cached != null) return cached;
    final events = List<VoiceEvent>.of(_events)
      ..sort((a, b) => a.start.compareTo(b.start));
    final result = <VoiceEvent>[];
    // A null value means simultaneous accidentals left this pitch ambiguous.
    final carried = <(Staff, int), Accidental?>{};
    var measure = -1;
    for (var first = 0; first < events.length;) {
      final tick = events[first].start;
      final currentMeasure = measureAtTick(tick);
      if (currentMeasure != measure) {
        carried.clear();
        measure = currentMeasure;
      }
      var end = first + 1;
      while (end < events.length && events[end].start == tick) {
        end++;
      }
      final explicit = <(Staff, int), Set<Accidental>>{};
      for (final event in events.sublist(first, end)) {
        for (final pitch in event.pitches) {
          if (pitch.accidental != Accidental.none) {
            explicit
                .putIfAbsent((event.staff, pitch.diatonicStep), () => {})
                .add(pitch.accidental);
          }
        }
      }
      // Resolve a whole onset together, independent of voice ordering.
      final changes = <(Staff, int), Set<Accidental>>{
        for (final entry in explicit.entries) entry.key: {...entry.value},
      };
      for (final event in events.sublist(first, end)) {
        final pitches = <Pitch>[];
        var changed = false;
        for (final pitch in event.pitches) {
          final key = (event.staff, pitch.diatonicStep);
          var midi = pitch.midiNote;
          var accidental = pitch.accidental;
          if (accidental == Accidental.none) {
            final previous = carried[key];
            if (previous != null) {
              midi = soundingMidi(pitch.diatonicStep, previous, 0);
            }
            final simultaneous = explicit[key];
            final ambiguous = carried.containsKey(key) && previous == null;
            final conflicting =
                simultaneous != null &&
                simultaneous.any(
                  (mark) => soundingMidi(pitch.diatonicStep, mark, 0) != midi,
                );
            if (ambiguous || conflicting) {
              final natural = soundingMidi(
                pitch.diatonicStep,
                Accidental.natural,
                0,
              );
              accidental = switch (midi - natural) {
                -1 => Accidental.flat,
                0 => Accidental.natural,
                1 => Accidental.sharp,
                _ => throw const EditException(
                  'A conflicting accidental cannot be represented.',
                ),
              };
              changes.putIfAbsent(key, () => {}).add(accidental);
            }
          }
          if (midi < 0 || midi > 127) {
            throw const EditException(
              'An accidental would put a note outside the MIDI range.',
            );
          }
          if (midi == pitch.midiNote && accidental == pitch.accidental) {
            pitches.add(pitch);
          } else {
            changed = true;
            pitches.add(
              Pitch(
                diatonicStep: pitch.diatonicStep,
                midiNote: midi,
                accidental: accidental,
              ),
            );
          }
        }
        result.add(changed ? event.copyWith(pitches: pitches) : event);
      }
      for (final entry in changes.entries) {
        carried[entry.key] = entry.value.length == 1
            ? entry.value.single
            : null;
      }
      first = end;
    }
    return _resolvedCache = result;
  }

  int previewMidi(int step, Accidental accidental, Staff staff, int tick) {
    if (accidental != Accidental.none) {
      return soundingMidi(step, accidental, keyAt(measureAtTick(tick)));
    }
    final measure = measureAtTick(tick);
    final start = measureStart(measure);
    var latest = -1;
    final marks = <Accidental>{};
    for (final event in _resolvedEvents()) {
      if (event.staff != staff || event.start < start || event.start >= tick) {
        continue;
      }
      for (final pitch in event.pitches) {
        if (pitch.diatonicStep != step || pitch.accidental == Accidental.none) {
          continue;
        }
        if (event.start > latest) {
          latest = event.start;
          marks.clear();
        }
        if (event.start == latest) marks.add(pitch.accidental);
      }
    }
    return soundingMidi(
      step,
      marks.length == 1 ? marks.single : Accidental.none,
      keyAt(measure),
    );
  }

  int get measureCount => _measureCount;

  int nextTick(Voice voice, {int? measure}) {
    if (measure == null) {
      final events = storedEventsFor(voice);
      return events.isEmpty ? 0 : events.last.end;
    }
    if (measure < 0 || measure >= _measureCount) {
      throw RangeError.range(measure, 0, _measureCount - 1, 'measure');
    }
    final start = measureStart(measure);
    final end = start + timeAt(measure).ticks;
    var cursor = start;
    for (final event in storedEventsFor(voice)) {
      if (event.start < end && event.end > start) {
        cursor = math.max(cursor, math.min(event.end, end));
      }
    }
    return cursor;
  }

  _Snapshot _snapshot() => _Snapshot(
    List.of(_events),
    _measureCount,
    _nextId,
    _beats,
    _unit,
    _key,
    Map.of(_tempos),
    Map.of(_times),
    Map.of(_keys),
    Set.of(_repeatStarts),
    Set.of(_repeatEnds),
    Map.of(_dynamics),
    List.of(_hairpins),
    Map.of(_arpeggios),
    Map.of(_notes),
  );
  void _restore(_Snapshot snapshot) {
    _resolvedCache = null;
    _events = List.of(snapshot.events);
    _measureCount = snapshot.measureCount;
    _nextId = snapshot.nextId;
    _beats = snapshot.beats;
    _unit = snapshot.unit;
    _key = snapshot.key;
    _tempos = Map.of(snapshot.tempos);
    _times = Map.of(snapshot.times);
    _keys = Map.of(snapshot.keys);
    _repeatStarts = Set.of(snapshot.repeatStarts);
    _repeatEnds = Set.of(snapshot.repeatEnds);
    _dynamics = Map.of(snapshot.dynamics);
    _hairpins = List.of(snapshot.hairpins);
    _arpeggios = Map.of(snapshot.arpeggios);
    _notes = Map.of(snapshot.notes);
  }

  void _commit(void Function() change) {
    final before = _snapshot();
    _resolvedCache = null;
    try {
      change();
      _normalizeRests();
      _validateTies();
      _validateTuplets();
      _arpeggios.removeWhere((tick, _) => pitchCountAt(tick) < 2);
      _resolvedEvents();
    } on EditException {
      _restore(before);
      rethrow;
    }
    _undo.add(before);
    _redo.clear();
  }

  void undo() {
    if (!canUndo) return;
    _redo.add(_snapshot());
    _restore(_undo.removeLast());
  }

  void redo() {
    if (!canRedo) return;
    _undo.add(_snapshot());
    _restore(_redo.removeLast());
  }

  void setMeasureTempo(int measure, int? bpm) {
    if (measure < 0 ||
        measure >= _measureCount ||
        (bpm != null && (bpm < 30 || bpm > 240))) {
      throw const EditException('Invalid bar or tempo.');
    }
    if (_tempos[measure] == bpm) return;
    _commit(() {
      if (bpm == null) {
        _tempos.remove(measure);
      } else {
        _tempos[measure] = bpm;
      }
    });
  }

  void setDynamic(int tick, DynamicMark? mark) {
    if (tick < 0 || tick >= measureStart(_measureCount) || tick % 60 != 0) {
      throw const EditException('Invalid dynamic position.');
    }
    if (_dynamics[tick] == mark) return;
    _commit(() {
      if (mark == null) {
        _dynamics.remove(tick);
      } else {
        _dynamics[tick] = mark;
      }
    });
  }

  void setArpeggio(int tick, ArpeggioDirection? direction) {
    if (direction != null && pitchCountAt(tick) < 2) {
      throw const EditException('Select at least two simultaneous notes.');
    }
    if (direction != null && tick % 60 != 0) {
      throw const EditException('Arpeggios are not supported on tuplet notes.');
    }
    if (_arpeggios[tick] == direction) return;
    _commit(() {
      if (direction == null) {
        _arpeggios.remove(tick);
      } else {
        _arpeggios[tick] = direction;
      }
    });
  }

  void startHairpin(int tick, HairpinKind kind) {
    if (pendingHairpin != null) {
      throw const EditException(
        'Finish or remove the unfinished hairpin first.',
      );
    }
    if (tick < 0 || tick >= measureStart(_measureCount) || tick % 60 != 0) {
      throw const EditException('Invalid hairpin position.');
    }
    if (_hairpins.any((h) => tick >= h.start && tick < h.end!)) {
      throw const EditException('Hairpins cannot overlap.');
    }
    _commit(() => _hairpins.add(Hairpin(start: tick, kind: kind)));
  }

  void endHairpin(int tick) {
    final pending = pendingHairpin;
    if (pending == null) {
      throw const EditException('No hairpin is being started.');
    }
    if (tick <= pending.start ||
        tick >= measureStart(_measureCount) ||
        tick % 60 != 0) {
      throw const EditException('Choose an end after the hairpin start.');
    }
    if (_hairpins.any(
      (h) => h.end != null && pending.start < h.end! && tick > h.start,
    )) {
      throw const EditException('Hairpins cannot overlap.');
    }
    _commit(() {
      final index = _hairpins.indexOf(pending);
      _hairpins[index] = Hairpin(
        start: pending.start,
        end: tick,
        kind: pending.kind,
      );
    });
  }

  void deleteHairpin(int start) {
    if (!_hairpins.any((h) => h.start == start)) return;
    _commit(() => _hairpins.removeWhere((h) => h.start == start));
  }

  void setMeasureRepeats(
    int measure, {
    required bool start,
    required bool end,
  }) {
    if (measure < 0 || measure >= _measureCount) {
      throw const EditException('Invalid bar.');
    }
    if (_repeatStarts.contains(measure) == start &&
        _repeatEnds.contains(measure) == end) {
      return;
    }
    _commit(() {
      if (start) {
        _repeatStarts.add(measure);
      } else {
        _repeatStarts.remove(measure);
      }
      if (end) {
        _repeatEnds.add(measure);
      } else {
        _repeatEnds.remove(measure);
      }
    });
  }

  static const maxBarNoteLength = 60;

  Map<int, String> get barNotes => Map.unmodifiable(_notes);

  void setBarNote(int measure, String text) {
    if (measure < 0 || measure >= _measureCount) {
      throw const EditException('Invalid bar.');
    }
    final value = text.trim();
    if (value.length > maxBarNoteLength) {
      throw const EditException(
        'A bar note can have at most $maxBarNoteLength characters.',
      );
    }
    if ((_notes[measure] ?? '') == value) return;
    _commit(() {
      if (value.isEmpty) {
        _notes.remove(measure);
      } else {
        _notes[measure] = value;
      }
    });
  }

  List<_BarData> _barData(int initialTempo) {
    var time = TimeSignature(_beats, _unit);
    var key = _key;
    var tempo = initialTempo;
    return [
      for (var i = 0; i < _measureCount; i++)
        _BarData(
          time: time = _times[i] ?? time,
          key: key = _keys[i] ?? key,
          tempo: tempo = _tempos[i] ?? tempo,
          explicitTime: _times.containsKey(i),
          explicitKey: _keys.containsKey(i),
          explicitTempo: _tempos.containsKey(i),
          repeatStart: _repeatStarts.contains(i),
          repeatEnd: _repeatEnds.contains(i),
          note: _notes[i] ?? '',
        ),
    ];
  }

  void _checkBarRange(int start, int count) {
    if (count < 1 || start < 0 || start + count > _measureCount) {
      throw const EditException('Choose a valid range of bars.');
    }
  }

  void _checkBoundary(int tick) {
    if (_events.any(
      (event) => !event.isRest && event.start < tick && event.end > tick,
    )) {
      throw const EditException(
        'Edit the tied note crossing this bar boundary first.',
      );
    }
    if (_hairpins.any(
      (hairpin) =>
          hairpin.start < tick &&
          (hairpin.end == null
              ? tick < measureStart(_measureCount)
              : hairpin.end! >= tick),
    )) {
      throw const EditException(
        'Finish or edit the hairpin crossing this bar boundary first.',
      );
    }
  }

  BarClipboard copyBars(int start, int count, {required int initialTempo}) {
    _checkBarRange(start, count);
    final firstTick = measureStart(start);
    final endTick = measureStart(start + count);
    _checkBoundary(firstTick);
    _checkBoundary(endTick);
    if (_hairpins.any(
      (hairpin) =>
          hairpin.end == null &&
          hairpin.start >= firstTick &&
          hairpin.start < endTick,
    )) {
      throw const EditException(
        'Finish or remove the unfinished hairpin first.',
      );
    }
    return BarClipboard._(
      _barData(initialTempo).sublist(start, start + count),
      [
        for (final event in _events)
          if (!event.generatedRest &&
              event.start >= firstTick &&
              event.start < endTick)
            event.copyWith(start: event.start - firstTick),
      ],
      {
        for (final entry in _dynamics.entries)
          if (entry.key >= firstTick && entry.key < endTick)
            entry.key - firstTick: entry.value,
      },
      [
        for (final hairpin in _hairpins)
          if (hairpin.start >= firstTick && hairpin.start < endTick)
            Hairpin(
              start: hairpin.start - firstTick,
              end: hairpin.end! - firstTick,
              kind: hairpin.kind,
            ),
      ],
      {
        for (final entry in _arpeggios.entries)
          if (entry.key >= firstTick && entry.key < endTick)
            entry.key - firstTick: entry.value,
      },
    );
  }

  void insertBars(int index, int count, {required int initialTempo}) {
    if (index < 0 || index > _measureCount || count < 1) {
      throw const EditException('Choose a valid number of bars.');
    }
    final bars = _barData(initialTempo);
    final context = bars[index == 0 ? 0 : index - 1];
    final blank = _BarData(
      time: context.time,
      key: context.key,
      tempo: context.tempo,
    );
    _spliceBars(
      index,
      0,
      BarClipboard._(List.filled(count, blank), [], {}, [], {}),
      initialTempo,
    );
  }

  void pasteBars(
    int index,
    BarClipboard clipboard, {
    required int initialTempo,
  }) {
    if (index < 0 || index > _measureCount) {
      throw const EditException('Choose a valid insertion point.');
    }
    _spliceBars(index, 0, clipboard, initialTempo);
  }

  void deleteBars(int start, int count, {required int initialTempo}) {
    _checkBarRange(start, count);
    if (count == _measureCount) {
      throw const EditException('Keep at least one bar in the score.');
    }
    _spliceBars(start, count, BarClipboard._([], [], {}, [], {}), initialTempo);
  }

  void _spliceBars(
    int start,
    int removeCount,
    BarClipboard inserted,
    int initialTempo,
  ) {
    if (_measureCount - removeCount + inserted.count > 100000) {
      throw const EditException('The score cannot exceed 100000 bars.');
    }
    final firstTick = measureStart(start);
    final endTick = measureStart(start + removeCount);
    _checkBoundary(firstTick);
    _checkBoundary(endTick);
    if (_hairpins.any(
      (hairpin) =>
          hairpin.end == null &&
          hairpin.start >= firstTick &&
          hairpin.start < endTick,
    )) {
      throw const EditException(
        'Finish or remove the unfinished hairpin first.',
      );
    }
    final bars = _barData(initialTempo)
      ..replaceRange(start, start + removeCount, inserted._bars);
    final insertedTicks = inserted._bars.fold<int>(
      0,
      (total, bar) => total + bar.time.ticks,
    );
    final shift = insertedTicks - (endTick - firstTick);
    int? remap(int tick) {
      if (tick < firstTick) return tick;
      if (tick >= endTick) return tick + shift;
      return null;
    }

    _commit(() {
      _events = [
        for (final event in _events)
          if (!event.generatedRest && remap(event.start) != null)
            event.copyWith(start: remap(event.start)!),
        for (final event in inserted._events)
          VoiceEvent(
            id: _nextId++,
            start: firstTick + event.start,
            duration: event.duration,
            voice: event.voice,
            staff: event.staff,
            pitches: event.pitches,
            articulations: event.articulations,
            tuplet: event.tuplet,
          ),
      ];
      _dynamics = {
        for (final entry in _dynamics.entries)
          if (remap(entry.key) != null) remap(entry.key)!: entry.value,
        for (final entry in inserted._dynamics.entries)
          firstTick + entry.key: entry.value,
      };
      _arpeggios = {
        for (final entry in _arpeggios.entries)
          if (remap(entry.key) != null) remap(entry.key)!: entry.value,
        for (final entry in inserted._arpeggios.entries)
          firstTick + entry.key: entry.value,
      };
      _hairpins = [
        for (final hairpin in _hairpins)
          if (remap(hairpin.start) != null)
            Hairpin(
              start: remap(hairpin.start)!,
              end: hairpin.end == null ? null : remap(hairpin.end!),
              kind: hairpin.kind,
            ),
        for (final hairpin in inserted._hairpins)
          Hairpin(
            start: firstTick + hairpin.start,
            end: firstTick + hairpin.end!,
            kind: hairpin.kind,
          ),
      ];
      _measureCount = bars.length;
      _beats = bars.first.time.beats;
      _unit = bars.first.time.unit;
      _key = bars.first.key;
      _times = {
        for (var i = 1; i < bars.length; i++)
          if (bars[i].explicitTime || bars[i].time != bars[i - 1].time)
            i: bars[i].time,
      };
      _keys = {
        for (var i = 1; i < bars.length; i++)
          if (bars[i].explicitKey || bars[i].key != bars[i - 1].key)
            i: bars[i].key,
      };
      _tempos = {
        for (var i = 0; i < bars.length; i++)
          if (bars[i].explicitTempo ||
              bars[i].tempo != (i == 0 ? initialTempo : bars[i - 1].tempo))
            i: bars[i].tempo,
      };
      _repeatStarts = {
        for (var i = 0; i < bars.length; i++)
          if (bars[i].repeatStart) i,
      };
      _repeatEnds = {
        for (var i = 0; i < bars.length; i++)
          if (bars[i].repeatEnd) i,
      };
      _notes = {
        for (var i = 0; i < bars.length; i++)
          if (bars[i].note.isNotEmpty) i: bars[i].note,
      };
    });
  }

  void setScoreSettings({
    required int beats,
    required int unit,
    required int key,
  }) {
    _changeSignatures(beats, unit, key, _times, _keys);
  }

  void setMeasureSignatures(int measure, {TimeSignature? time, int? key}) {
    if (measure <= 0 || measure >= _measureCount) {
      throw const EditException('Invalid bar.');
    }
    final times = Map<int, TimeSignature>.of(_times);
    final keys = Map<int, int>.of(_keys);
    if (time == null) {
      times.remove(measure);
    } else {
      times[measure] = time;
    }
    if (key == null) {
      keys.remove(measure);
    } else {
      keys[measure] = key;
    }
    _changeSignatures(_beats, _unit, _key, times, keys);
  }

  void _changeSignatures(
    int beats,
    int unit,
    int key,
    Map<int, TimeSignature> times,
    Map<int, int> keys,
  ) {
    if (beats < 1 ||
        beats > 32 ||
        ![1, 2, 4, 8, 16].contains(unit) ||
        key < -7 ||
        key > 7 ||
        times.values.any(
          (time) =>
              time.beats < 1 ||
              time.beats > 32 ||
              ![1, 2, 4, 8, 16].contains(time.unit),
        ) ||
        keys.values.any((k) => k < -7 || k > 7)) {
      throw const EditException('Invalid score settings.');
    }
    bool sameMap<K, V>(Map<K, V> a, Map<K, V> b) =>
        a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
    if (beats == _beats &&
        unit == _unit &&
        key == _key &&
        sameMap(times, _times) &&
        sameMap(keys, _keys)) {
      return;
    }
    final oldStarts = [
      for (var i = 0; i <= _measureCount; i++) measureStart(i),
    ];
    final newStarts = <int>[0];
    final newKeys = <int>[];
    var currentTime = TimeSignature(beats, unit);
    var currentKey = key;
    for (var i = 0; i < _measureCount; i++) {
      currentTime = times[i] ?? currentTime;
      currentKey = keys[i] ?? currentKey;
      newStarts.add(newStarts.last + currentTime.ticks);
      newKeys.add(currentKey);
    }
    final events = _events.where((event) => !event.generatedRest).toList();
    for (final event in events) {
      final first = measureAtTick(event.start);
      final last = measureAtTick(event.end - 1);
      for (var i = first; i <= last; i++) {
        final oldLength = oldStarts[i + 1] - oldStarts[i];
        final newLength = newStarts[i + 1] - newStarts[i];
        if (oldLength == newLength) continue;
        if (first != last) {
          throw const EditException(
            'Edit tied notes spanning barlines before changing the time signature.',
          );
        }
        if (event.end - oldStarts[i] > newLength) {
          throw const EditException(
            'Existing notes or rests do not fit in the shorter bars. Edit them first.',
          );
        }
      }
    }
    final updated = <VoiceEvent>[];
    final dynamics = <int, DynamicMark>{};
    for (final entry in _dynamics.entries) {
      final measure = measureAtTick(entry.key);
      final offset = entry.key - oldStarts[measure];
      if (offset >= newStarts[measure + 1] - newStarts[measure]) {
        throw const EditException(
          'A dynamic marking does not fit in the shorter bar. Move or remove it first.',
        );
      }
      dynamics[newStarts[measure] + offset] = entry.value;
    }
    int remapHairpinTick(int tick) {
      final measure = measureAtTick(tick);
      final offset = tick - oldStarts[measure];
      if (offset >= newStarts[measure + 1] - newStarts[measure]) {
        throw const EditException(
          'A hairpin endpoint does not fit in the shorter bar. Remove it first.',
        );
      }
      return newStarts[measure] + offset;
    }

    final hairpins = [
      for (final h in _hairpins)
        Hairpin(
          start: remapHairpinTick(h.start),
          end: h.end == null ? null : remapHairpinTick(h.end!),
          kind: h.kind,
        ),
    ];
    final arpeggios = <int, ArpeggioDirection>{};
    for (final entry in _arpeggios.entries) {
      final measure = measureAtTick(entry.key);
      arpeggios[newStarts[measure] + entry.key - oldStarts[measure]] =
          entry.value;
    }
    for (final event in events) {
      final measure = measureAtTick(event.start);
      final pitches = <Pitch>[];
      for (final pitch in event.pitches) {
        final midi = newKeys[measure] == keyAt(measure)
            ? pitch.midiNote
            : soundingMidi(
                pitch.diatonicStep,
                pitch.accidental,
                newKeys[measure],
              );
        if (midi < 0 || midi > 127) {
          throw const EditException(
            'The key would put a note outside the MIDI range.',
          );
        }
        pitches.add(
          Pitch(
            diatonicStep: pitch.diatonicStep,
            midiNote: midi,
            accidental: pitch.accidental,
          ),
        );
      }
      final start = newStarts[measure] + event.start - oldStarts[measure];
      updated.add(event.copyWith(start: start, pitches: pitches));
    }
    _commit(() {
      _beats = beats;
      _unit = unit;
      _key = key;
      _times = Map.of(times);
      _keys = Map.of(keys);
      _events = updated;
      _dynamics = dynamics;
      _hairpins = hairpins;
      _arpeggios = arpeggios;
    });
  }

  List<int> get _notationValues => <int>[
    for (final value in NoteValue.values)
      for (var dots = 0; dots <= value.maxDots; dots++)
        value.duration(dots: dots),
  ]..sort((a, b) => b.compareTo(a));

  void _normalizeRests() {
    final previous = _events.where((e) => e.isRest && e.generatedRest).toList();
    _events.removeWhere((e) => e.isRest && e.generatedRest);
    for (final voice in Voice.values) {
      final events = storedEventsFor(voice);
      for (var measure = 0; measure < _measureCount; measure++) {
        final start = measureStart(measure);
        final end = start + timeAt(measure).ticks;
        var cursor = start;
        for (final event in events) {
          if (event.end <= start || event.start >= end) continue;
          final eventStart = math.max(event.start, start);
          if (eventStart > cursor) {
            _addGeneratedRests(
              voice,
              event.staff,
              cursor,
              eventStart,
              previous,
            );
          }
          cursor = math.max(cursor, math.min(event.end, end));
        }
      }
    }
    // Explicit rests can also span bars or need multiple notation values.
    final explicit = _events
        .where((e) => e.isRest && !e.generatedRest && e.tuplet == null)
        .toList();
    for (final rest in explicit) {
      _events.remove(rest);
      var position = rest.start;
      var remaining = rest.duration;
      var first = true;
      while (remaining > 0) {
        final available = math.min(
          remaining,
          measureStart(measureAtTick(position) + 1) - position,
        );
        final part = _notationValues.firstWhere((value) => value <= available);
        _events.add(
          VoiceEvent(
            id: first ? rest.id : _nextId++,
            start: position,
            duration: part,
            voice: rest.voice,
            staff: rest.staff,
            articulations: remaining == part ? rest.articulations : const {},
          ),
        );
        first = false;
        position += part;
        remaining -= part;
      }
    }
  }

  void _addGeneratedRests(
    Voice voice,
    Staff staff,
    int start,
    int end,
    List<VoiceEvent> previous,
  ) {
    while (start < end) {
      final duration = _notationValues.firstWhere(
        (value) => value <= end - start,
      );
      final existing = previous
          .where(
            (e) =>
                e.voice == voice && e.start == start && e.duration == duration,
          )
          .firstOrNull;
      if (existing != null) previous.remove(existing);
      _events.add(
        VoiceEvent(
          id: existing?.id ?? _nextId++,
          start: start,
          duration: duration,
          voice: voice,
          staff: staff,
          generatedRest: true,
        ),
      );
      start += duration;
    }
  }

  void _replace(VoiceEvent old, VoiceEvent replacement) {
    _events[_events.indexOf(old)] = replacement;
  }

  VoiceEvent? _previousEvent(VoiceEvent event) => storedEventsFor(
    event.voice,
  ).where((candidate) => candidate.end == event.start).lastOrNull;

  VoiceEvent? _nextEvent(VoiceEvent event) => storedEventsFor(
    event.voice,
  ).where((candidate) => candidate.start == event.end).firstOrNull;

  bool _samePitches(List<Pitch> first, List<Pitch> second) {
    if (first.length != second.length) return false;
    final left = List<Pitch>.of(first)
      ..sort((a, b) {
        final step = a.diatonicStep.compareTo(b.diatonicStep);
        return step != 0 ? step : a.midiNote.compareTo(b.midiNote);
      });
    final right = List<Pitch>.of(second)
      ..sort((a, b) {
        final step = a.diatonicStep.compareTo(b.diatonicStep);
        return step != 0 ? step : a.midiNote.compareTo(b.midiNote);
      });
    for (var i = 0; i < left.length; i++) {
      if (left[i].diatonicStep != right[i].diatonicStep ||
          left[i].midiNote != right[i].midiNote) {
        return false;
      }
    }
    return true;
  }

  void _requireTieable(
    VoiceEvent? previous, {
    required Voice voice,
    required int start,
    required List<Pitch> pitches,
  }) {
    if (previous == null ||
        previous.voice != voice ||
        previous.end != start ||
        previous.isRest ||
        pitches.isEmpty) {
      throw const EditException(
        'A tie needs a previous note in the same voice.',
      );
    }
    if (!_samePitches(previous.pitches, pitches)) {
      throw const EditException(
        'A tie requires the same pitch as the previous note.',
      );
    }
  }

  void _validateTies() {
    for (final voice in Voice.values) {
      for (final event in storedEventsFor(voice)) {
        if (event.tieFromPrevious) {
          final previous = _previousEvent(event);
          if (previous == null || !previous.tieToNext) {
            throw const EditException(
              'Tied notes must be consecutive and linked.',
            );
          }
          _requireTieable(
            previous,
            voice: event.voice,
            start: event.start,
            pitches: event.pitches,
          );
        }
        if (event.tieToNext) {
          final next = _nextEvent(event);
          if (next == null || !next.tieFromPrevious) {
            throw const EditException(
              'Tied notes must be consecutive and linked.',
            );
          }
          _requireTieable(
            event,
            voice: next.voice,
            start: next.start,
            pitches: next.pitches,
          );
        }
      }
    }
  }

  void _validateTuplets() {
    for (final event in _events) {
      if (event.tuplet != null &&
          measureAtTick(event.start) != measureAtTick(event.end - 1)) {
        throw const EditException('A tuplet cannot cross a bar line.');
      }
    }
  }

  /// Writes a tuplet as placeholder rests (one per slot) to be replaced by
  /// notes. [value] is the written length of each slot: a triplet of eighths
  /// fills the time of two eighths. Returns the id of the first slot.
  int insertTuplet({
    required Voice voice,
    required Staff staff,
    required Tuplet tuplet,
    required NoteValue value,
    int? measure,
  }) {
    final slot = tuplet.scale(value.ticks);
    if (slot == null) {
      throw const EditException('That tuplet does not fit this note value.');
    }
    var firstId = 0;
    _commit(() {
      final start = nextTick(voice, measure: measure);
      final end = start + slot * tuplet.actual;
      if (end > measureStart(_measureCount) ||
          measureAtTick(start) != measureAtTick(end - 1)) {
        throw const EditException('The tuplet does not fit in this bar.');
      }
      if (storedEventsFor(voice).any((e) => e.start < end && e.end > start)) {
        throw const EditException(
          'The tuplet would overlap an existing event.',
        );
      }
      final groupId =
          _events.fold<int>(
            0,
            (top, e) => math.max(top, e.tuplet?.groupId ?? 0),
          ) +
          1;
      final grouped = Tuplet(
        actual: tuplet.actual,
        normal: tuplet.normal,
        groupId: groupId,
      );
      for (var i = 0; i < tuplet.actual; i++) {
        final id = _nextId++;
        if (i == 0) firstId = id;
        _events.add(
          VoiceEvent(
            id: id,
            start: start + i * slot,
            duration: slot,
            voice: voice,
            staff: staff,
            tuplet: grouped,
          ),
        );
      }
    });
    return firstId;
  }

  /// The slot after [id] in the same tuplet, or null at the end of the group.
  VoiceEvent? nextInTuplet(int id) {
    final event = _storedEventById(id);
    final tuplet = event?.tuplet;
    if (event == null || tuplet == null) return null;
    final next = _nextEvent(event);
    return next?.tuplet?.groupId == tuplet.groupId ? next : null;
  }

  VoiceEvent _removeTieLinks(VoiceEvent event) {
    if (!event.tieFromPrevious && !event.tieToNext) return event;
    if (event.tieFromPrevious) {
      final previous = _previousEvent(event);
      if (previous != null) {
        _replace(previous, previous.copyWith(tieToNext: false));
      }
    }
    if (event.tieToNext) {
      final next = _nextEvent(event);
      if (next != null) {
        _replace(next, next.copyWith(tieFromPrevious: false));
      }
    }
    final untied = event.copyWith(tieFromPrevious: false, tieToNext: false);
    if (event.tieFromPrevious || event.tieToNext) _replace(event, untied);
    return untied;
  }

  int append({
    required Voice voice,
    required Staff staff,
    required int duration,
    Pitch? pitch,
    int? measure,
    bool tieToPrevious = false,
  }) {
    if (duration <= 0 || duration % 60 != 0) {
      throw const EditException('Unsupported duration.');
    }
    var id = 0;
    _commit(() {
      final start = nextTick(voice, measure: measure);
      VoiceEvent? previous;
      if (tieToPrevious) {
        previous = storedEventsFor(
          voice,
        ).where((event) => event.end == start).lastOrNull;
        _requireTieable(
          previous,
          voice: voice,
          start: start,
          pitches: pitch == null ? const [] : [pitch],
        );
      }
      if (start + duration > measureStart(_measureCount)) {
        throw const EditException('Add more bars before writing past the end.');
      }
      if (storedEventsFor(voice).any(
        (e) =>
            e.start < start + duration &&
            e.end > start &&
            !(pitch != null && e.isRest && e.generatedRest),
      )) {
        throw const EditException(
          'The note or rest would overlap an existing event in a later bar.',
        );
      }
      id = _nextId++;
      if (previous != null) {
        _replace(previous, previous.copyWith(tieToNext: true));
      }
      _events.add(
        VoiceEvent(
          id: id,
          start: start,
          duration: duration,
          voice: voice,
          staff: staff,
          pitches: pitch == null ? [] : [pitch],
          tieFromPrevious: tieToPrevious,
        ),
      );
    });
    return id;
  }

  int replaceRest(
    int id,
    int duration,
    Pitch pitch,
    Staff staff, {
    bool tieToPrevious = false,
  }) {
    final rest = _storedEventById(id);
    if (rest == null || !rest.isRest) {
      throw const EditException('Select a rest first.');
    }
    if (rest.tuplet != null) {
      // A tuplet slot is always filled completely.
      duration = rest.duration;
    } else if (duration <= 0 || duration % 60 != 0) {
      throw const EditException('Unsupported duration.');
    }
    if (duration > rest.duration) {
      throw const EditException('The note is longer than the selected rest.');
    }
    final previous = tieToPrevious ? _previousEvent(rest) : null;
    if (tieToPrevious) {
      _requireTieable(
        previous,
        voice: rest.voice,
        start: rest.start,
        pitches: [pitch],
      );
    }
    _commit(() {
      if (previous != null) {
        _replace(previous, previous.copyWith(tieToNext: true));
      }
      _replace(
        rest,
        rest.copyWith(
          duration: duration,
          staff: staff,
          pitches: [pitch],
          generatedRest: false,
          tieFromPrevious: tieToPrevious,
        ),
      );
      if (duration < rest.duration) {
        _events.add(
          VoiceEvent(
            id: _nextId++,
            start: rest.start + duration,
            duration: rest.duration - duration,
            voice: rest.voice,
            staff: rest.staff,
            generatedRest: rest.generatedRest,
          ),
        );
      }
    });
    return id;
  }

  void toggleTieToPrevious(int id) {
    final event = _storedEventById(id);
    if (event == null || event.isRest) {
      throw const EditException('Select a note to tie.');
    }
    final previous = _previousEvent(event);
    if (event.tieFromPrevious) {
      if (previous == null || !previous.tieToNext) {
        throw const EditException('The previous tie could not be found.');
      }
      _commit(() {
        _replace(previous, previous.copyWith(tieToNext: false));
        _replace(event, event.copyWith(tieFromPrevious: false));
      });
      return;
    }
    _requireTieable(
      previous,
      voice: event.voice,
      start: event.start,
      pitches: event.pitches,
    );
    final prior = previous!;
    _commit(() {
      _replace(prior, prior.copyWith(tieToNext: true));
      _replace(event, event.copyWith(tieFromPrevious: true));
    });
  }

  void addPitch(int id, Pitch pitch) {
    final event = _storedEventById(id);
    if (event == null || event.isRest) {
      throw const EditException('Select a note to add a chord pitch.');
    }
    _commit(
      () => _replace(event, event.copyWith(pitches: [...event.pitches, pitch])),
    );
  }

  void setArticulations(int id, Set<Articulation> articulations) {
    final event = _storedEventById(id);
    if (event == null) {
      throw const EditException('Select a note or rest first.');
    }
    if (!validArticulations(articulations, isRest: event.isRest)) {
      throw const EditException('Those articulations cannot be combined.');
    }
    if (event.articulations.length == articulations.length &&
        event.articulations.containsAll(articulations)) {
      return;
    }
    _commit(
      () => _replace(
        event,
        event.copyWith(
          articulations: articulations,
          generatedRest: event.isRest && articulations.isNotEmpty
              ? false
              : event.generatedRest,
        ),
      ),
    );
  }

  void changePitch(int id, int index, Pitch pitch) {
    final event = _storedEventById(id);
    if (event == null || index < 0 || index >= event.pitches.length) {
      throw const EditException('Select a note first.');
    }
    _commit(() {
      final pitches = List<Pitch>.of(event.pitches)..[index] = pitch;
      _replace(event, event.copyWith(pitches: pitches));
    });
  }

  void resize(int id, int duration) {
    final event = _storedEventById(id);
    if (event == null) throw const EditException('Select an event first.');
    if (event.tuplet != null) {
      throw const EditException('Tuplet notes cannot be resized.');
    }
    if (duration <= 0 || duration % 60 != 0) {
      throw const EditException('Unsupported duration.');
    }
    if (duration == event.duration) return;
    final events = storedEventsFor(event.voice);
    final following = events.skipWhile((e) => e.id != id).skip(1).toList();
    if (following.any(
      (e) => e.tuplet != null && e.start < event.start + duration,
    )) {
      throw const EditException('The duration would overlap a tuplet.');
    }
    final nextNote = following.where((e) => !e.isRest).firstOrNull;
    final newEnd = event.start + duration;
    if (newEnd > measureStart(_measureCount)) {
      throw const EditException('Add more bars before writing past the end.');
    }
    if (nextNote != null && newEnd > nextNote.start) {
      throw const EditException('The duration would overlap a later note.');
    }
    if (event.isRest &&
        duration > event.duration &&
        following.any((e) => e.start < newEnd)) {
      throw const EditException(
        'Rests cannot be lengthened over another event.',
      );
    }
    final eventBarEnd = measureStart(measureAtTick(event.start) + 1);
    if (event.isRest &&
        duration < event.duration &&
        following.any((e) => e.start < eventBarEnd)) {
      throw const EditException(
        'An internal rest must fill the gap before the next event.',
      );
    }
    _commit(() {
      _replace(event, event.copyWith(duration: duration));
      if (newEnd > event.end) {
        for (final rest in following) {
          if (!rest.isRest || rest.start >= newEnd) break;
          _events.remove(rest);
          if (rest.end > newEnd) {
            _events.add(
              rest.copyWith(start: newEnd, duration: rest.end - newEnd),
            );
            break;
          }
        }
      }
    });
  }

  void delete(int id, {int? pitchIndex}) {
    final event = _storedEventById(id);
    if (event == null) throw const EditException('Select an event first.');
    final tuplet = event.tuplet;
    if (tuplet != null && event.isRest) {
      final group = _events
          .where(
            (e) =>
                e.voice == event.voice &&
                e.tuplet?.groupId == tuplet.groupId &&
                measureAtTick(e.start) == measureAtTick(event.start),
          )
          .toList();
      if (group.any((e) => !e.isRest)) {
        throw const EditException(
          'Delete the notes of the tuplet first, then delete a rest to remove it.',
        );
      }
      _commit(() => _events.removeWhere(group.contains));
      return;
    }
    final barEnd = measureStart(measureAtTick(event.start) + 1);
    if (event.isRest &&
        storedEventsFor(
          event.voice,
        ).any((e) => e.start >= event.end && e.start < barEnd)) {
      throw const EditException(
        'Rests between events cannot be deleted; replace them with a note.',
      );
    }
    _commit(() {
      final editable = _removeTieLinks(event);
      if (event.isRest) {
        _events.remove(editable);
      } else if (pitchIndex != null && event.pitches.length > 1) {
        final pitches = List<Pitch>.of(editable.pitches)..removeAt(pitchIndex);
        _replace(editable, editable.copyWith(pitches: pitches));
      } else {
        _replace(
          editable,
          editable.copyWith(
            pitches: [],
            generatedRest: tuplet == null,
            articulations: {},
          ),
        );
      }
    });
  }

  Score get score {
    final measures = List.generate(_measureCount, (_) => <NotationEvent>[]);
    final values = _notationValues;
    for (final event in _resolvedEvents()) {
      var position = event.start;
      var remaining = event.duration;
      while (remaining > 0) {
        final measure = measureAtTick(position);
        final available = math.min(
          remaining,
          measureStart(measure + 1) - position,
        );
        final part = event.tuplet != null
            ? available
            : values.firstWhere((value) => value <= available);
        measures[measure].add(
          NotationEvent(
            startTick: position - measureStart(measure),
            durationTicks: part,
            voice: event.voice,
            staff: event.staff,
            pitches: event.pitches,
            eventId: event.id,
            tuplet: event.tuplet,
            tieFromPrevious:
                !event.isRest &&
                (position > event.start ||
                    (position == event.start && event.tieFromPrevious)),
            tieToNext:
                !event.isRest &&
                (remaining > part || (remaining == part && event.tieToNext)),
            articulations: {
              if (position == event.start)
                ...event.articulations.where(
                  (mark) => mark != Articulation.fermata,
                ),
              if (remaining == part &&
                  event.articulations.contains(Articulation.fermata))
                Articulation.fermata,
            },
          ),
        );
        position += part;
        remaining -= part;
      }
    }
    return Score(
      title: _source.title,
      beatsPerMeasure: _beats,
      beatUnit: _unit,
      keySignature: _key,
      hairpins: List.unmodifiable(_hairpins),
      measures: [
        for (var i = 0; i < measures.length; i++)
          Measure(
            events: measures[i],
            tempo: _tempos[i],
            timeSignature: _times[i],
            keySignature: _keys[i],
            repeatStart: _repeatStarts.contains(i),
            repeatEnd: _repeatEnds.contains(i),
            note: _notes[i] ?? '',
            dynamics: {
              for (final entry in _dynamics.entries)
                if (entry.key >= measureStart(i) &&
                    entry.key < measureStart(i + 1))
                  entry.key - measureStart(i): entry.value,
            },
            arpeggios: {
              for (final entry in _arpeggios.entries)
                if (measureAtTick(entry.key) == i)
                  entry.key - measureStart(i): entry.value,
            },
          ),
      ],
    );
  }
}
