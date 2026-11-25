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
}
