import 'package:claviera/editor/score_editor.dart';
import 'package:claviera/models/blank_score.dart';
import 'package:claviera/models/score.dart';
import 'package:flutter_test/flutter_test.dart';

const c = Pitch(diatonicStep: 28, midiNote: 60);
const g = Pitch(diatonicStep: 32, midiNote: 67);

void main() {
  ScoreEditor editor() {
    final e = ScoreEditor(blankScore)..insertBars(1, 1, initialTempo: 120);
    e.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 960,
      pitch: g,
      measure: 0,
    );
    e.append(
      voice: Voice.v2,
      staff: Staff.treble,
      duration: 1920,
      pitch: c,
      measure: 0,
    );
    e.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 960,
      pitch: g,
      measure: 1,
    );
    return e;
  }

  List<int> midi(ScoreEditor e, Voice voice, int measure) => [
    for (final event in e.score.measures[measure].events)
      if (event.voice == voice && !event.isRest)
        for (final pitch in event.pitches) pitch.midiNote,
  ];

  test('swapping voices moves only the chosen bar and can be undone', () {
    final e = editor();
    e.swapVoices(0, Voice.v1, Voice.v2);
    expect(midi(e, Voice.v1, 0), [60]);
    expect(midi(e, Voice.v2, 0), [67]);
    expect(midi(e, Voice.v1, 1), [67]);
    e.undo();
    expect(midi(e, Voice.v1, 0), [67]);
    expect(midi(e, Voice.v2, 0), [60]);
  });

  test('swapping with an empty voice moves the notes there', () {
    final e = editor();
    e.swapVoices(0, Voice.v2, Voice.v3);
    expect(midi(e, Voice.v2, 0), isEmpty);
    expect(midi(e, Voice.v3, 0), [60]);
    expect(
      () => e.swapVoices(0, Voice.v1, Voice.v1),
      throwsA(isA<EditException>()),
    );
  });

  test('notes tied across the bar line cannot be switched', () {
    final e = ScoreEditor(blankScore)..insertBars(1, 1, initialTempo: 120);
    e.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 3840,
      pitch: c,
      measure: 0,
    );
    e.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 960,
      pitch: c,
      measure: 1,
    );
    e.toggleTieToPrevious(e.storedEventsFor(Voice.v1).last.id);
    expect(
      () => e.swapVoices(0, Voice.v1, Voice.v2),
      throwsA(isA<EditException>()),
    );
  });

  group('voice transpose', () {
    test('moves one voice in one bar by staff steps and octaves', () {
      final e = editor();
      e.transposeVoice(0, Voice.v1, 1);
      expect(midi(e, Voice.v1, 0), [69]);
      expect(midi(e, Voice.v2, 0), [60]);
      expect(midi(e, Voice.v1, 1), [67]);
      e.transposeVoice(0, Voice.v1, -7);
      expect(midi(e, Voice.v1, 0), [57]);
      e.undo();
      expect(midi(e, Voice.v1, 0), [69]);
    });

    test('accidentals follow the note and the range is protected', () {
      final e = ScoreEditor(blankScore);
      e.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 960,
        pitch: const Pitch(
          diatonicStep: 31,
          midiNote: 66,
          accidental: Accidental.sharp,
        ),
        measure: 0,
      );
      e.transposeVoice(0, Voice.v1, 1);
      final pitch = e.score.measures[0].events.first.pitches.single;
      expect((pitch.diatonicStep, pitch.midiNote), (32, 68));
      expect(pitch.accidental, Accidental.sharp);
      expect(
        () => e.transposeVoice(0, Voice.v1, 40),
        throwsA(isA<EditException>()),
      );
      expect(e.score.measures[0].events.first.pitches.single.midiNote, 68);
    });
  });

  group('transpose score', () {
    Pitch only(ScoreEditor e, int measure) =>
        e.score.measures[measure].events.first.pitches.single;

    test('C major up one semitone becomes D flat major', () {
      final e = editor();
      e.transposeScore(1);
      expect(e.score.keySignature, -5);
      expect(midi(e, Voice.v1, 0), [68]);
      expect(midi(e, Voice.v2, 0), [61]);
      expect(midi(e, Voice.v1, 1), [68]);
      // G becomes A flat and C becomes D flat, both from the key signature.
      expect(only(e, 0).diatonicStep, 33);
      expect(only(e, 0).accidental, Accidental.none);
      e.undo();
      expect(e.score.keySignature, 0);
      expect(midi(e, Voice.v1, 0), [67]);
    });

    test('octaves keep the key and chromatic notes are respelled', () {
      final e = ScoreEditor(blankScore);
      e.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 960,
        pitch: const Pitch(
          diatonicStep: 31,
          midiNote: 66,
          accidental: Accidental.sharp,
        ),
        measure: 0,
      );
      e.transposeScore(12);
      expect(e.score.keySignature, 0);
      expect(only(e, 0).midiNote, 78);
      expect(only(e, 0).accidental, Accidental.sharp);
      e.transposeScore(-1);
      expect(e.score.keySignature, 5);
      expect(only(e, 0).midiNote, 77);
      // F sharp in C is the raised fourth, so B major spells it E sharp.
      expect(only(e, 0).diatonicStep % 7, 2);
      expect(only(e, 0).accidental, Accidental.sharp);
      expect(() => e.transposeScore(40), throwsA(isA<EditException>()));
      expect(only(e, 0).midiNote, 77);
    });
  });
}
