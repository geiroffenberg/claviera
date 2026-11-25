import 'dart:convert';
import 'dart:ui';

import 'package:claviera/editor/score_editor.dart';
import 'package:claviera/models/score.dart';
import 'package:claviera/notation/beaming.dart';
import 'package:claviera/notation/musicxml_export.dart';
import 'package:claviera/storage/projects.dart';
import 'package:claviera/notation/score_painter.dart';
import 'package:claviera/notation/score_viewport.dart';
import 'package:claviera/ui/workspace_screen.dart';
import 'package:flutter/material.dart' show MaterialApp, ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

NotationEvent note(int start, int duration, {Tuplet? tuplet}) => NotationEvent(
  startTick: start,
  durationTicks: duration,
  voice: Voice.v1,
  staff: Staff.treble,
  pitches: const [Pitch(diatonicStep: 30, midiNote: 64)],
  tuplet: tuplet,
);

void main() {
  test('tuplet ticks are exact integers on the 960 grid', () {
    const triplet = Tuplet.triplet();
    const quintuplet = Tuplet.quintuplet();
    expect(triplet.scale(NoteValue.eighth.ticks), 320);
    expect(triplet.scale(NoteValue.quarter.ticks), 640);
    expect(quintuplet.scale(NoteValue.sixteenth.ticks), 192);
    expect(triplet.scale(1), isNull);
    expect(triplet.unscale(320), NoteValue.eighth.ticks);
    expect(triplet.unscale(321), isNull);
  });

  test('three triplet eighths fill exactly one quarter', () {
    expect(3 * const Tuplet.triplet().scale(NoteValue.eighth.ticks)!, 960);
    expect(
      5 * const Tuplet.quintuplet().scale(NoteValue.sixteenth.ticks)!,
      960,
    );
  });

  test('notation of a tuplet duration is its written value', () {
    expect(notationForDuration(320), isNull);
    final written = notationForDuration(320, tuplet: const Tuplet.triplet());
    expect(written?.value, NoteValue.eighth);
    expect(written?.dots, 0);
    expect(notationForDuration(480)?.value, NoteValue.eighth);
  });

  test('triplet eighths beam like eighths and form one group per beat', () {
    const t = Tuplet.triplet();
    expect(beamCount(320, tuplet: t), 1);
    expect(beamCount(160, tuplet: t), 2);
    final measure = Measure(
      events: [
        note(0, 320, tuplet: t),
        note(320, 320, tuplet: t),
        note(640, 320, tuplet: t),
        note(960, 960),
      ],
    );
    final groups = beamGroups(measure, numerator: 4, denominator: 4);
    expect(groups, hasLength(1));
    expect(groups.single, hasLength(3));
  });

  test('a beamed triplet needs no bracket, an unbeamed one does', () {
    const t = Tuplet.triplet(groupId: 1);
    final beamed = Measure(
      events: [
        note(0, 320, tuplet: t),
        note(320, 320, tuplet: t),
        note(640, 320, tuplet: t),
      ],
    );
    final beams = beamGroups(beamed, numerator: 4, denominator: 4);
    final spans = tupletSpans(beamed, beams);
    expect(spans.single.number, 3);
    expect(spans.single.events, hasLength(3));
    expect(spans.single.bracket, isFalse);

    const q = Tuplet.triplet(groupId: 2);
    final quarters = Measure(
      events: [
        note(0, 640, tuplet: q),
        note(640, 640, tuplet: q),
        note(1280, 640, tuplet: q),
      ],
    );
    final span = tupletSpans(
      quarters,
      beamGroups(quarters, numerator: 4, denominator: 4),
    ).single;
    expect(span.bracket, isTrue);
  });

  test('a measure with triplets paints without errors', () {
    const t = Tuplet.triplet(groupId: 1);
    final score = Score(
      title: '',
      beatsPerMeasure: 4,
      beatUnit: 4,
      measures: [
        Measure(
          events: [
            note(0, 320, tuplet: t),
            note(320, 320, tuplet: t),
            note(640, 320, tuplet: t),
            NotationEvent(
              startTick: 960,
              durationTicks: 640,
              voice: Voice.v1,
              staff: Staff.treble,
              tuplet: const Tuplet.triplet(groupId: 2),
            ),
            note(1600, 320, tuplet: const Tuplet.triplet(groupId: 2)),
          ],
        ),
      ],
    );
    final recorder = PictureRecorder();
    ScorePainter(score: score, selectedEvent: null, selectedPitch: 0).paint(
      Canvas(recorder),
      Size(ScorePainter.widthFor(score, 10), ScorePainter.heightFor(10)),
    );
    recorder.endRecording();
  });

  group('editor', () {
    ScoreEditor editor() => ScoreEditor(
      const Score(
        title: '',
        beatsPerMeasure: 4,
        beatUnit: 4,
        measures: [Measure(), Measure()],
      ),
    );
    const pitch = Pitch(diatonicStep: 30, midiNote: 64);
    int tuplet(ScoreEditor e, {NoteValue value = NoteValue.eighth, int? bar}) =>
        e.insertTuplet(
          voice: Voice.v1,
          staff: Staff.treble,
          tuplet: const Tuplet.triplet(),
          value: value,
          measure: bar,
        );

    test('inserts a group of placeholder rests that survive a round trip', () {
      final e = editor();
      tuplet(e);
      var events = e.score.measures[0].events;
      expect(events.map((x) => x.startTick), [0, 320, 640]);
      expect(events.map((x) => x.durationTicks), [320, 320, 320]);
      expect(events.every((x) => x.isRest && x.tuplet?.actual == 3), isTrue);
      expect(events.map((x) => x.tuplet!.groupId).toSet(), hasLength(1));
      events = ScoreEditor(e.score).score.measures[0].events;
      expect(events.map((x) => x.durationTicks), [320, 320, 320]);
    });

    test('notes fill slots without changing their length', () {
      final e = editor();
      final first = tuplet(e);
      final second = e.nextInTuplet(first)!;
      e.replaceRest(first, 960, pitch, Staff.treble);
      e.replaceRest(second.id, 60, pitch, Staff.treble);
      final events = e.score.measures[0].events;
      expect(events.map((x) => x.durationTicks), [320, 320, 320]);
      expect(events.map((x) => x.isRest), [false, false, true]);
      expect(e.nextInTuplet(events[2].eventId!), isNull);
      e.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 960,
        pitch: pitch,
        measure: 0,
      );
      expect(e.score.measures[0].events.last.startTick, 960);
    });

    test('a tuplet must fit in the bar and not overlap', () {
      final e = editor();
      e.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 2880,
        pitch: pitch,
        measure: 0,
      );
      expect(
        () => tuplet(e, value: NoteValue.quarter, bar: 0),
        throwsA(isA<EditException>()),
      );
      expect(e.score.measures[0].events, hasLength(1));
      tuplet(e, bar: 1);
      expect(e.score.measures[1].events, hasLength(3));
    });

    test('notes cannot be resized, deleting notes then rests removes it', () {
      final e = editor();
      final first = tuplet(e);
      e.replaceRest(first, 960, pitch, Staff.treble);
      expect(() => e.resize(first, 960), throwsA(isA<EditException>()));
      e.delete(first);
      var events = e.score.measures[0].events;
      expect(events.map((x) => x.durationTicks), [320, 320, 320]);
      expect(events.every((x) => x.isRest && x.tuplet != null), isTrue);
      e.delete(first);
      events = e.score.measures[0].events;
      expect(events.where((x) => x.tuplet != null), isEmpty);
    });

    test('tuplets survive saving and loading', () {
      final e = editor();
      final first = tuplet(e);
      e.replaceRest(first, 960, pitch, Staff.treble);
      final loaded = ProjectCodec.decode(
        ProjectCodec.encode(Project(name: 'x', tempo: 120, editor: e)),
      );
      final events = loaded.editor.score.measures[0].events;
      expect(events.map((x) => x.startTick), [0, 320, 640]);
      expect(events.map((x) => x.durationTicks), [320, 320, 320]);
      expect(events.map((x) => x.isRest), [false, true, true]);
      expect(events.every((x) => x.tuplet?.actual == 3), isTrue);
    });

    test('MusicXML writes time modification and tuplet brackets', () {
      final e = editor();
      final first = tuplet(e);
      e.replaceRest(first, 960, pitch, Staff.treble);
      final xml = XmlDocument.parse(
        utf8.decode(MusicXmlExport.encode(e, 120, 'T')),
      );
      final notes = xml.findAllElements('note').toList();
      expect(notes.first.getElement('duration')!.innerText, '320');
      expect(notes.first.getElement('type')!.innerText, 'eighth');
      for (final note in notes.take(3)) {
        final mod = note.getElement('time-modification')!;
        expect(mod.getElement('actual-notes')!.innerText, '3');
        expect(mod.getElement('normal-notes')!.innerText, '2');
      }
      final marks = xml
          .findAllElements('tuplet')
          .map((t) => t.getAttribute('type'));
      expect(marks, ['start', 'stop']);
    });

    test('undo removes the whole tuplet', () {
      final e = editor();
      tuplet(e);
      e.undo();
      expect(e.score.measures[0].events, isEmpty);
    });
  });

  testWidgets('the triplet button writes three notes in a row', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: WorkspaceScreen()));
    Score score() =>
        tester.widget<ScoreViewport>(find.byType(ScoreViewport)).score;
    await tester.tap(find.byTooltip('eighth note'));
    await tester.pump();
    await tester.tap(find.byTooltip('Tuplet'));
    await tester.pump();
    expect(score().measures.first.events, isEmpty);
    final canvas = find.byKey(const ValueKey('score-canvas'));
    for (var i = 0; i < 3; i++) {
      await tester.tapAt(tester.getTopLeft(canvas) + const Offset(160, 115));
      await tester.pump();
    }
    final events = score().measures.first.events;
    expect(events.map((e) => e.isRest), [false, false, false]);
    expect(events.map((e) => e.durationTicks), [320, 320, 320]);
    expect(events.every((e) => e.tuplet?.actual == 3), isTrue);
  });
}
