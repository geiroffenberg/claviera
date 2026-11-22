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
  }) : pitches = List.unmodifiable(pitches);

  final int id;
  final int start;
  final int duration;
  final Voice voice;
  final Staff staff;
  final List<Pitch> pitches;
  final bool generatedRest;
  bool get isRest => pitches.isEmpty;
  int get end => start + duration;

  VoiceEvent copyWith({
    int? start,
    int? duration,
    Staff? staff,
    List<Pitch>? pitches,
    bool? generatedRest,
  }) => VoiceEvent(
    id: id,
    start: start ?? this.start,
    duration: duration ?? this.duration,
    voice: voice,
    staff: staff ?? this.staff,
    pitches: pitches ?? this.pitches,
    generatedRest: generatedRest ?? this.generatedRest,
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
      _measureCount = source.measures.length {
    for (var measure = 0; measure < source.measures.length; measure++) {
      for (final event in source.measures[measure].events) {
        _events.add(
          VoiceEvent(
            id: _nextId++,
            start: source.measureStart(measure) + event.startTick,
            duration: event.durationTicks,
            voice: event.voice,
            staff: event.staff,
            pitches: event.pitches,
          ),
        );
      }
    }
    for (final voice in Voice.values) {
      var end = 0;
      for (final event in eventsFor(voice)) {
        if (event.start < end) {
          throw ArgumentError(
            'The source score has overlapping events in ${voice.name}.',
          );
        }
        end = event.end;
      }
    }
    _normalizeRests();
  }

  final Score _source;
  int _beats;
  int _unit;
  int _key;
  Map<int, int> _tempos;
  Map<int, TimeSignature> _times;
  Map<int, int> _keys;
  Map<int, int> get tempoChanges => Map.unmodifiable(_tempos);
  Map<int, TimeSignature> get timeChanges => Map.unmodifiable(_times);
  Map<int, int> get keyChanges => Map.unmodifiable(_keys);
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
  int _measureCount;
  int _nextId = 1;
  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  List<VoiceEvent> eventsFor(Voice voice) =>
      _events.where((e) => e.voice == voice).toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  VoiceEvent? eventById(int? id) {
    for (final event in _events) {
      if (event.id == id) return event;
    }
    return null;
  }

  int get measureCount => _measureCount;

  int nextTick(Voice voice, {int? measure}) {
    if (measure == null) {
      final events = eventsFor(voice);
      return events.isEmpty ? 0 : events.last.end;
    }
    if (measure < 0 || measure >= _measureCount) {
      throw RangeError.range(measure, 0, _measureCount - 1, 'measure');
    }
    final start = measureStart(measure);
    final end = start + timeAt(measure).ticks;
    var cursor = start;
    for (final event in eventsFor(voice)) {
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
  );
  void _restore(_Snapshot snapshot) {
    _events = List.of(snapshot.events);
    _measureCount = snapshot.measureCount;
    _nextId = snapshot.nextId;
    _beats = snapshot.beats;
    _unit = snapshot.unit;
    _key = snapshot.key;
    _tempos = Map.of(snapshot.tempos);
    _times = Map.of(snapshot.times);
    _keys = Map.of(snapshot.keys);
  }

  void _commit(void Function() change) {
    final before = _snapshot();
    try {
      change();
      _normalizeRests();
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
    });
  }

  void _ensureMeasures(int end) {
    if (end > 0) {
      _measureCount = math.max(_measureCount, measureAtTick(end - 1) + 1);
    }
  }

  List<int> get _notationValues => <int>[
    for (final value in NoteValue.values) ...[
      if (value != NoteValue.sixtyFourth) value.duration(dotted: true),
      value.ticks,
    ],
  ]..sort((a, b) => b.compareTo(a));

  void _normalizeRests() {
    final previous = _events.where((e) => e.isRest && e.generatedRest).toList();
    _events.removeWhere((e) => e.isRest && e.generatedRest);
    for (final voice in Voice.values) {
      final events = eventsFor(voice);
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
        .where((e) => e.isRest && !e.generatedRest)
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

  int append({
    required Voice voice,
    required Staff staff,
    required int duration,
    Pitch? pitch,
    int? measure,
  }) {
    if (duration <= 0 || duration % 60 != 0) {
      throw const EditException('Unsupported duration.');
    }
    var id = 0;
    _commit(() {
      final start = nextTick(voice, measure: measure);
      if (eventsFor(voice).any(
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
      _events.add(
        VoiceEvent(
          id: id,
          start: start,
          duration: duration,
          voice: voice,
          staff: staff,
          pitches: pitch == null ? [] : [pitch],
        ),
      );
      _ensureMeasures(start + duration);
    });
    return id;
  }

  int replaceRest(int id, int duration, Pitch pitch, Staff staff) {
    final rest = eventById(id);
    if (rest == null || !rest.isRest) {
      throw const EditException('Select a rest first.');
    }
    if (duration <= 0 || duration % 60 != 0) {
      throw const EditException('Unsupported duration.');
    }
    if (duration > rest.duration) {
      throw const EditException('The note is longer than the selected rest.');
    }
    _commit(() {
      _replace(
        rest,
        rest.copyWith(
          duration: duration,
          staff: staff,
          pitches: [pitch],
          generatedRest: false,
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

  void addPitch(int id, Pitch pitch) {
    final event = eventById(id);
    if (event == null || event.isRest) {
      throw const EditException('Select a note to add a chord pitch.');
    }
    _commit(
      () => _replace(event, event.copyWith(pitches: [...event.pitches, pitch])),
    );
  }

  void changePitch(int id, int index, Pitch pitch) {
    final event = eventById(id);
    if (event == null || index < 0 || index >= event.pitches.length) {
      throw const EditException('Select a note first.');
    }
    _commit(() {
      final pitches = List<Pitch>.of(event.pitches)..[index] = pitch;
      _replace(event, event.copyWith(pitches: pitches));
    });
  }

  void resize(int id, int duration) {
    final event = eventById(id);
    if (event == null) throw const EditException('Select an event first.');
    if (duration <= 0 || duration % 60 != 0) {
      throw const EditException('Unsupported duration.');
    }
    if (duration == event.duration) return;
    final events = eventsFor(event.voice);
    final following = events.skipWhile((e) => e.id != id).skip(1).toList();
    final nextNote = following.where((e) => !e.isRest).firstOrNull;
    final newEnd = event.start + duration;
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
      _ensureMeasures(newEnd);
    });
  }

  void delete(int id, {int? pitchIndex}) {
    final event = eventById(id);
    if (event == null) throw const EditException('Select an event first.');
    final barEnd = measureStart(measureAtTick(event.start) + 1);
    if (event.isRest &&
        eventsFor(
          event.voice,
        ).any((e) => e.start >= event.end && e.start < barEnd)) {
      throw const EditException(
        'Rests between events cannot be deleted; replace them with a note.',
      );
    }
    _commit(() {
      if (event.isRest) {
        _events.remove(event);
      } else if (pitchIndex != null && event.pitches.length > 1) {
        final pitches = List<Pitch>.of(event.pitches)..removeAt(pitchIndex);
        _replace(event, event.copyWith(pitches: pitches));
      } else {
        _replace(event, event.copyWith(pitches: [], generatedRest: true));
      }
    });
  }

  Score get score {
    final measures = List.generate(_measureCount, (_) => <NotationEvent>[]);
    final values = _notationValues;
    for (final event in _events) {
      var position = event.start;
      var remaining = event.duration;
      while (remaining > 0) {
        final measure = measureAtTick(position);
        final available = math.min(
          remaining,
          measureStart(measure + 1) - position,
        );
        final part = values.firstWhere((value) => value <= available);
        measures[measure].add(
          NotationEvent(
            startTick: position - measureStart(measure),
            durationTicks: part,
            voice: event.voice,
            staff: event.staff,
            pitches: event.pitches,
            eventId: event.id,
            tieFromPrevious: !event.isRest && position > event.start,
            tieToNext: !event.isRest && remaining > part,
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
      measures: [
        for (var i = 0; i < measures.length; i++)
          Measure(
            events: measures[i],
            tempo: _tempos[i],
            timeSignature: _times[i],
            keySignature: _keys[i],
          ),
      ],
    );
  }
}
