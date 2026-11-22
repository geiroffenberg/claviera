/// Timing is measured in ticks relative to the beginning of a measure.
const int ticksPerQuarter = 960;

enum Voice { v1, v2, v3, v4 }

enum Staff { treble, bass }

enum Accidental { none, sharp, flat, natural }

class TimeSignature {
  const TimeSignature(this.beats, this.unit)
    : assert(beats > 0),
      assert(unit == 1 || unit == 2 || unit == 4 || unit == 8 || unit == 16);

  final int beats;
  final int unit;

  int get ticks => beats * ticksPerQuarter * 4 ~/ unit;

  @override
  bool operator ==(Object other) =>
      other is TimeSignature && other.beats == beats && other.unit == unit;
  @override
  int get hashCode => Object.hash(beats, unit);
}

/// Number of sharps (positive) or flats (negative), in standard order.
int keyAlteration(int keySignature, int diatonicStep) {
  const sharps = [3, 0, 4, 1, 5, 2, 6];
  const flats = [6, 2, 5, 1, 4, 0, 3];
  final order = keySignature >= 0 ? sharps : flats;
  return order.take(keySignature.abs()).contains(diatonicStep % 7)
      ? keySignature.sign
      : 0;
}

int soundingMidi(int step, Accidental accidental, int keySignature) {
  const semitones = [0, 2, 4, 5, 7, 9, 11];
  final alteration = switch (accidental) {
    Accidental.none => keyAlteration(keySignature, step),
    Accidental.sharp => 1,
    Accidental.flat => -1,
    Accidental.natural => 0,
  };
  return 12 + step ~/ 7 * 12 + semitones[step % 7] + alteration;
}

enum NoteValue {
  whole(4 * ticksPerQuarter),
  half(2 * ticksPerQuarter),
  quarter(ticksPerQuarter),
  eighth(ticksPerQuarter ~/ 2),
  sixteenth(ticksPerQuarter ~/ 4),
  thirtySecond(ticksPerQuarter ~/ 8),
  sixtyFourth(ticksPerQuarter ~/ 16);

  const NoteValue(this.ticks);
  final int ticks;

  int duration({bool dotted = false}) {
    if (dotted && this == NoteValue.sixtyFourth) {
      throw ArgumentError('Dotted 64th notes are not supported.');
    }
    return dotted ? ticks * 3 ~/ 2 : ticks;
  }
}

/// C0 = 0, D0 = 1, ... C4 = 28. Accidentals do not change this position.
class Pitch {
  const Pitch({
    required this.diatonicStep,
    required this.midiNote,
    this.accidental = Accidental.none,
  }) : assert(midiNote >= 0 && midiNote <= 127);

  final int diatonicStep;
  final int midiNote;
  final Accidental accidental;
}

/// An event is either a chord (one or more pitches) or an explicit rest.
class NotationEvent {
  const NotationEvent({
    required this.startTick,
    required this.durationTicks,
    required this.voice,
    required this.staff,
    this.pitches = const [],
    this.eventId,
    this.tieFromPrevious = false,
    this.tieToNext = false,
  }) : assert(startTick >= 0),
       assert(durationTicks > 0);

  final int startTick;
  final int durationTicks;
  final Voice voice;
  final Staff staff;
  final List<Pitch> pitches;
  final int? eventId;
  final bool tieFromPrevious;
  final bool tieToNext;

  bool get isRest => pitches.isEmpty;
}

class Measure {
  const Measure({
    this.events = const [],
    this.tempo,
    this.timeSignature,
    this.keySignature,
    this.repeatStart = false,
    this.repeatEnd = false,
  });

  final List<NotationEvent> events;
  final int? tempo;
  final TimeSignature? timeSignature;
  final int? keySignature;
  final bool repeatStart;
  final bool repeatEnd;
}

class Score {
  const Score({
    required this.title,
    required this.beatsPerMeasure,
    required this.beatUnit,
    required this.measures,
    this.keySignature = 0,
  }) : assert(beatsPerMeasure > 0),
       assert(keySignature >= -7 && keySignature <= 7),
       assert(
         beatUnit == 1 ||
             beatUnit == 2 ||
             beatUnit == 4 ||
             beatUnit == 8 ||
             beatUnit == 16,
       );

  final String title;
  final int beatsPerMeasure;
  final int beatUnit;
  final int keySignature;
  final List<Measure> measures;

  int get ticksPerMeasure => beatsPerMeasure * ticksPerQuarter * 4 ~/ beatUnit;

  TimeSignature timeAt(int measure) {
    var time = TimeSignature(beatsPerMeasure, beatUnit);
    for (var i = 0; i <= measure && i < measures.length; i++) {
      time = measures[i].timeSignature ?? time;
    }
    return time;
  }

  int keyAt(int measure) {
    var key = keySignature;
    for (var i = 0; i <= measure && i < measures.length; i++) {
      key = measures[i].keySignature ?? key;
    }
    return key;
  }

  int measureStart(int measure) {
    var start = 0;
    var time = TimeSignature(beatsPerMeasure, beatUnit);
    for (var i = 0; i < measure; i++) {
      if (i < measures.length) time = measures[i].timeSignature ?? time;
      start += time.ticks;
    }
    return start;
  }

  int measureAtTick(int tick) {
    if (tick < 0) throw RangeError.value(tick, 'tick');
    var start = 0;
    var time = TimeSignature(beatsPerMeasure, beatUnit);
    for (var i = 0; i < measures.length; i++) {
      time = measures[i].timeSignature ?? time;
      if (tick < start + time.ticks) return i;
      start += time.ticks;
    }
    return measures.length + (tick - start) ~/ time.ticks;
  }
}
