import 'package:claviera/audio/score_playback.dart';
import 'package:claviera/editor/score_editor.dart';
import 'package:claviera/models/blank_score.dart';
import 'package:claviera/models/score.dart';
import 'package:claviera/storage/projects.dart';
import 'package:flutter_test/flutter_test.dart';

const c = Pitch(diatonicStep: 28, midiNote: 60);
const d = Pitch(diatonicStep: 29, midiNote: 62);

void main() {
  test('bars are added manually and can be undone', () {
    final editor = ScoreEditor(blankScore);
    editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 3840,
      pitch: c,
      measure: 3,
    );
    expect(editor.measureCount, 4);
    expect(
      () => editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 960,
        pitch: d,
        measure: 3,
      ),
      throwsA(isA<EditException>()),
    );
    editor.insertBars(4, 2, initialTempo: 120);
    expect(editor.measureCount, 6);
    editor.undo();
    expect(editor.measureCount, 4);
    editor.redo();
    expect(editor.measureCount, 6);
  });

  test('copy and insert preserve bar contents and surrounding settings', () {
    final editor = ScoreEditor(blankScore);
    editor.setMeasureSignatures(1, time: const TimeSignature(3, 4), key: -1);
    editor.setMeasureSignatures(2, time: const TimeSignature(4, 4), key: 1);
    editor.setMeasureTempo(1, 90);
    editor.setMeasureRepeats(1, start: true, end: true);
    final first = editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 960,
      pitch: c,
      measure: 1,
    );
    editor.addPitch(first, d);
    editor.setArpeggio(editor.measureStart(1), ArpeggioDirection.up);
    editor.setDynamic(editor.measureStart(1), DynamicMark.p);
    editor.startHairpin(editor.measureStart(1), HairpinKind.crescendo);
    editor.endHairpin(editor.measureStart(1) + 960);
    final original = editor.append(
      voice: Voice.v2,
      staff: Staff.bass,
      duration: 960,
      pitch: c,
      measure: 2,
    );
    final clip = editor.copyBars(1, 1, initialTempo: 120);
    editor.pasteBars(0, clip, initialTempo: 120);
    expect(editor.measureCount, 5);
    expect(editor.timeAt(0), const TimeSignature(3, 4));
    expect(editor.keyAt(0), -1);
    expect(editor.timeAt(1), const TimeSignature(4, 4));
    expect(editor.keyAt(1), 0);
    expect(editor.timeAt(3), const TimeSignature(4, 4));
    expect(editor.keyAt(3), 1);
    expect(editor.repeatStarts, containsAll([0, 2]));
    expect(editor.repeatEnds, containsAll([0, 2]));
    expect(
      editor.dynamicChanges.keys,
      containsAll([0, editor.measureStart(2)]),
    );
    expect(
      editor.hairpins.map((h) => h.start),
      unorderedEquals([0, editor.measureStart(2)]),
    );
    expect(editor.arpeggios.keys, containsAll([0, editor.measureStart(2)]));
    expect(editor.eventById(original)!.start, editor.measureStart(3));
    final encoded = ProjectCodec.encode(
      Project(name: 'Bars', tempo: 120, editor: editor),
    );
    expect(ProjectCodec.encode(ProjectCodec.decode(encoded)), encoded);
    expect(PlaybackPlan(editor, 120).notes, isNotEmpty);
    editor.undo();
    expect(editor.measureCount, 4);
    expect(editor.eventById(original)!.start, editor.measureStart(2));
    editor.redo();
    expect(editor.measureCount, 5);
  });

  test('delete and paste keep copied bars independent and undoable', () {
    final editor = ScoreEditor(blankScore);
    final first = editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 960,
      pitch: c,
      measure: 1,
    );
    editor.append(
      voice: Voice.v2,
      staff: Staff.bass,
      duration: 960,
      pitch: d,
      measure: 2,
    );
    final clip = editor.copyBars(1, 2, initialTempo: 120);
    editor.deleteBars(1, 2, initialTempo: 120);
    expect(editor.measureCount, 2);
    expect(editor.eventById(first), isNull);
    editor.pasteBars(1, clip, initialTempo: 120);
    expect(editor.measureCount, 4);
    expect(editor.score.measures[1].events.single.pitches.single.midiNote, 60);
    expect(editor.score.measures[2].events.single.pitches.single.midiNote, 62);
    editor.undo();
    expect(editor.measureCount, 2);
    editor.undo();
    expect(editor.eventById(first), isNotNull);
    expect(
      () => editor.deleteBars(0, 4, initialTempo: 120),
      throwsA(isA<EditException>()),
    );
  });

  test(
    'deleting the first bar preserves the following key, meter and tempo',
    () {
      final editor = ScoreEditor(blankScore);
      editor.setMeasureSignatures(1, time: const TimeSignature(3, 4), key: -2);
      editor.setMeasureTempo(1, 80);
      editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 960,
        pitch: c,
        measure: 1,
      );
      editor.deleteBars(0, 1, initialTempo: 120);
      expect(editor.score.beatsPerMeasure, 3);
      expect(editor.score.keySignature, -2);
      expect(editor.tempoChanges[0], 80);
      final encoded = ProjectCodec.encode(
        Project(name: 'First bar', tempo: 120, editor: editor),
      );
      expect(ProjectCodec.encode(ProjectCodec.decode(encoded)), encoded);
      editor.undo();
      expect(editor.score.beatsPerMeasure, 4);
      expect(editor.score.keySignature, 0);
      expect(editor.tempoChanges[1], 80);
    },
  );

  test('operations reject boundaries crossing ties or hairpins', () {
    final editor = ScoreEditor(blankScore);
    editor.append(voice: Voice.v1, staff: Staff.treble, duration: 2880);
    editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 1920,
      pitch: c,
    );
    expect(
      () => editor.copyBars(0, 1, initialTempo: 120),
      throwsA(isA<EditException>()),
    );
    expect(
      () => editor.insertBars(1, 1, initialTempo: 120),
      throwsA(isA<EditException>()),
    );
    expect(editor.measureCount, 4);
    final hairpin = ScoreEditor(blankScore);
    hairpin.startHairpin(960, HairpinKind.crescendo);
    hairpin.endHairpin(3840);
    expect(
      () => hairpin.deleteBars(1, 1, initialTempo: 120),
      throwsA(isA<EditException>()),
    );
    final pending = ScoreEditor(blankScore);
    pending.startHairpin(960, HairpinKind.crescendo);
    pending.insertBars(4, 1, initialTempo: 120);
    pending.endHairpin(pending.measureStart(4));
    expect(pending.hairpins.single.end, pending.measureStart(4));
  });
}
