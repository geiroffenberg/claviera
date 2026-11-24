import 'score.dart';

typedef _PhraseNote = ({int? step, int halfBeats});
typedef _Part = ({Voice voice, Staff staff, List<List<_PhraseNote>> phrases});

const _soprano = <List<_PhraseNote>>[
  [
    (step: 36, halfBeats: 2),
    (step: 35, halfBeats: 2),
    (step: 34, halfBeats: 2),
    (step: 33, halfBeats: 2),
  ],
  [
    (step: 34, halfBeats: 2),
    (step: 35, halfBeats: 2),
    (step: 36, halfBeats: 2),
    (step: 38, halfBeats: 2),
  ],
  [
    (step: 37, halfBeats: 3),
    (step: 36, halfBeats: 1),
    (step: 35, halfBeats: 2),
    (step: 33, halfBeats: 2),
  ],
  [
    (step: 32, halfBeats: 2),
    (step: 33, halfBeats: 2),
    (step: 35, halfBeats: 2),
    (step: 36, halfBeats: 2),
  ],
  [
    (step: 36, halfBeats: 4),
    (step: 35, halfBeats: 2),
    (step: 34, halfBeats: 2),
  ],
  [
    (step: 33, halfBeats: 3),
    (step: 36, halfBeats: 1),
    (step: 38, halfBeats: 2),
    (step: 37, halfBeats: 2),
  ],
  [
    (step: 35, halfBeats: 2),
    (step: 34, halfBeats: 2),
    (step: 33, halfBeats: 4),
  ],
  [
    (step: 35, halfBeats: 2),
    (step: 33, halfBeats: 2),
    (step: 36, halfBeats: 4),
  ],
];

const _alto = <List<_PhraseNote>>[
  [
    (step: null, halfBeats: 4),
    (step: 31, halfBeats: 2),
    (step: 33, halfBeats: 2),
  ],
  [
    (step: 31, halfBeats: 2),
    (step: 32, halfBeats: 2),
    (step: 33, halfBeats: 2),
    (step: 34, halfBeats: 2),
  ],
  [
    (step: 33, halfBeats: 4),
    (step: 32, halfBeats: 2),
    (step: 31, halfBeats: 2),
  ],
  [
    (step: 30, halfBeats: 2),
    (step: 32, halfBeats: 2),
    (step: 33, halfBeats: 4),
  ],
  [
    (step: 34, halfBeats: 2),
    (step: 33, halfBeats: 2),
    (step: 32, halfBeats: 4),
  ],
  [
    (step: 31, halfBeats: 4),
    (step: 33, halfBeats: 2),
    (step: 31, halfBeats: 2),
  ],
  [
    (step: 30, halfBeats: 2),
    (step: 32, halfBeats: 2),
    (step: 33, halfBeats: 4),
  ],
  [
    (step: 31, halfBeats: 2),
    (step: 30, halfBeats: 2),
    (step: 29, halfBeats: 4),
  ],
];

const _tenor = <List<_PhraseNote>>[
  [
    (step: null, halfBeats: 4),
    (step: 22, halfBeats: 2),
    (step: 26, halfBeats: 2),
  ],
  [
    (step: 22, halfBeats: 4),
    (step: 24, halfBeats: 2),
    (step: 25, halfBeats: 2),
  ],
  [
    (step: 21, halfBeats: 4),
    (step: 24, halfBeats: 2),
    (step: 26, halfBeats: 2),
  ],
  [
    (step: 21, halfBeats: 4),
    (step: 23, halfBeats: 2),
    (step: 25, halfBeats: 2),
  ],
  [
    (step: 22, halfBeats: 2),
    (step: 24, halfBeats: 2),
    (step: 25, halfBeats: 4),
  ],
  [
    (step: 19, halfBeats: 4),
    (step: 22, halfBeats: 2),
    (step: 24, halfBeats: 2),
  ],
  [
    (step: 21, halfBeats: 2),
    (step: 23, halfBeats: 2),
    (step: 19, halfBeats: 4),
  ],
  [
    (step: 19, halfBeats: 2),
    (step: 21, halfBeats: 2),
    (step: 22, halfBeats: 4),
  ],
];

const _bass = <List<_PhraseNote>>[
  [(step: 15, halfBeats: 4), (step: 12, halfBeats: 4)],
  [(step: 13, halfBeats: 4), (step: 17, halfBeats: 4)],
  [(step: 17, halfBeats: 4), (step: 14, halfBeats: 4)],
  [(step: 14, halfBeats: 4), (step: 11, halfBeats: 4)],
  [(step: 11, halfBeats: 4), (step: 15, halfBeats: 4)],
  [(step: 17, halfBeats: 4), (step: 12, halfBeats: 4)],
  [(step: 12, halfBeats: 4), (step: 16, halfBeats: 4)],
  [(step: 15, halfBeats: 8)],
];

const _parts = <_Part>[
  (voice: Voice.v1, staff: Staff.treble, phrases: _soprano),
  (voice: Voice.v2, staff: Staff.treble, phrases: _alto),
  (voice: Voice.v3, staff: Staff.bass, phrases: _tenor),
  (voice: Voice.v4, staff: Staff.bass, phrases: _bass),
];

List<NotationEvent> _phraseEvents(
  Voice voice,
  Staff staff,
  List<_PhraseNote> phrase,
) {
  var startTick = 0;
  final events = <NotationEvent>[];
  for (final note in phrase) {
    final duration = note.halfBeats * (ticksPerQuarter ~/ 2);
    final step = note.step;
    if (step != null) {
      events.add(
        NotationEvent(
          startTick: startTick,
          durationTicks: duration,
          voice: voice,
          staff: staff,
          pitches: [
            Pitch(
              diatonicStep: step,
              midiNote: soundingMidi(step, Accidental.none, -1),
            ),
          ],
        ),
      );
    }
    startTick += duration;
  }
  if (startTick != 4 * ticksPerQuarter) {
    throw StateError('A demo phrase must fill one 4/4 measure.');
  }
  return events;
}

Score _buildDemoScore() => Score(
  title: 'A Little Invention in D Minor',
  beatsPerMeasure: 4,
  beatUnit: 4,
  keySignature: -1,
  measures: [
    for (var measure = 0; measure < 8; measure++)
      Measure(
        events: [
          for (final part in _parts)
            ..._phraseEvents(part.voice, part.staff, part.phrases[measure]),
        ],
        dynamics: {
          if (measure == 0) 0: DynamicMark.p,
          if (measure == 2) 0: DynamicMark.mp,
          if (measure == 4) 0: DynamicMark.f,
          if (measure == 6) 0: DynamicMark.mp,
        },
      ),
  ],
  hairpins: const [
    Hairpin(start: 3840, end: 7680, kind: HairpinKind.crescendo),
    Hairpin(start: 11520, end: 15360, kind: HairpinKind.crescendo),
    Hairpin(start: 19200, end: 23040, kind: HairpinKind.diminuendo),
  ],
);

final demoScore = _buildDemoScore();
