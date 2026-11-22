import 'score.dart';

const demoScore = Score(
  title: 'A little sketch',
  beatsPerMeasure: 4,
  beatUnit: 4,
  measures: [
    Measure(
      events: [
        NotationEvent(
          startTick: 0,
          durationTicks: 960,
          voice: Voice.v1,
          staff: Staff.treble,
          pitches: [
            Pitch(diatonicStep: 28, midiNote: 60),
            Pitch(diatonicStep: 29, midiNote: 62),
            Pitch(diatonicStep: 32, midiNote: 67),
          ],
        ),
        NotationEvent(
          startTick: 960,
          durationTicks: 960,
          voice: Voice.v1,
          staff: Staff.treble,
          pitches: [Pitch(diatonicStep: 33, midiNote: 69)],
        ),
        NotationEvent(
          startTick: 1920,
          durationTicks: 480,
          voice: Voice.v1,
          staff: Staff.treble,
        ),
        NotationEvent(
          startTick: 2400,
          durationTicks: 480,
          voice: Voice.v1,
          staff: Staff.treble,
          pitches: [
            Pitch(diatonicStep: 34, midiNote: 70, accidental: Accidental.flat),
          ],
        ),
        NotationEvent(
          startTick: 2880,
          durationTicks: 960,
          voice: Voice.v1,
          staff: Staff.treble,
          pitches: [Pitch(diatonicStep: 35, midiNote: 72)],
        ),
        NotationEvent(
          startTick: 0,
          durationTicks: 1920,
          voice: Voice.v2,
          staff: Staff.bass,
          pitches: [
            Pitch(diatonicStep: 14, midiNote: 36),
            Pitch(diatonicStep: 18, midiNote: 43),
          ],
        ),
        NotationEvent(
          startTick: 1920,
          durationTicks: 1920,
          voice: Voice.v2,
          staff: Staff.bass,
          pitches: [Pitch(diatonicStep: 21, midiNote: 48)],
        ),
      ],
    ),
    Measure(
      events: [
        NotationEvent(
          startTick: 0,
          durationTicks: 1440,
          voice: Voice.v1,
          staff: Staff.treble,
          pitches: [Pitch(diatonicStep: 36, midiNote: 74)],
        ),
        NotationEvent(
          startTick: 1440,
          durationTicks: 480,
          voice: Voice.v1,
          staff: Staff.treble,
          pitches: [Pitch(diatonicStep: 35, midiNote: 72)],
        ),
        NotationEvent(
          startTick: 1920,
          durationTicks: 1920,
          voice: Voice.v1,
          staff: Staff.treble,
          pitches: [
            Pitch(
              diatonicStep: 32,
              midiNote: 67,
              accidental: Accidental.natural,
            ),
          ],
        ),
        NotationEvent(
          startTick: 0,
          durationTicks: 3840,
          voice: Voice.v2,
          staff: Staff.bass,
          pitches: [Pitch(diatonicStep: 17, midiNote: 41)],
        ),
      ],
    ),
    Measure(
      events: [
        NotationEvent(
          startTick: 0,
          durationTicks: 3840,
          voice: Voice.v1,
          staff: Staff.treble,
          pitches: [
            Pitch(diatonicStep: 28, midiNote: 61, accidental: Accidental.sharp),
            Pitch(diatonicStep: 32, midiNote: 67),
            Pitch(diatonicStep: 35, midiNote: 72),
          ],
        ),
        NotationEvent(
          startTick: 0,
          durationTicks: 3840,
          voice: Voice.v2,
          staff: Staff.bass,
          pitches: [Pitch(diatonicStep: 14, midiNote: 36)],
        ),
      ],
    ),
    Measure(),
  ],
);
