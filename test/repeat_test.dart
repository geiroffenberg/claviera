import 'dart:convert';

import 'package:claviera/audio/score_playback.dart';
import 'package:claviera/editor/score_editor.dart';
import 'package:claviera/main.dart';
import 'package:claviera/models/blank_score.dart';
import 'package:claviera/models/score.dart';
import 'package:claviera/notation/score_painter.dart';
import 'package:claviera/notation/score_viewport.dart';
import 'package:claviera/storage/projects.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ScoreEditor fixture() {
  final editor = ScoreEditor(blankScore);
  for (var i = 0; i < 4; i++) {
    editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 960,
      pitch: Pitch(diatonicStep: 28 + i, midiNote: 60 + i),
      measure: i,
    );
  }
  return editor;
}

void main() {
  test('repeat plays selected bars twice then continues', () {
    final editor = fixture();
    editor.setMeasureRepeats(1, start: true, end: false);
    editor.setMeasureRepeats(2, start: false, end: true);
    final plan = PlaybackPlan(editor, 120);
    expect(plan.notes.map((n) => (n.midi, n.startMs)), [
      (60, 0),
      (61, 2000),
      (62, 4000),
      (61, 6000),
      (62, 8000),
      (63, 10000),
    ]);
    expect(plan.durationMs, 10500);
  });

  test(
    'end repeat without start goes to beginning including empty bar tails',
    () {
      final editor = fixture();
      editor.setMeasureRepeats(1, start: false, end: true);
      final plan = PlaybackPlan(editor, 120);
      expect(plan.notes.map((n) => (n.midi, n.startMs)), [
        (60, 0),
        (61, 2000),
        (60, 4000),
        (61, 6000),
        (62, 8000),
        (63, 10000),
      ]);
    },
  );

  test('same-bar and consecutive repeats each repeat once', () {
    final editor = fixture();
    editor.setMeasureRepeats(0, start: true, end: true);
    editor.setMeasureRepeats(1, start: true, end: true);
    final plan = PlaybackPlan(editor, 120);
    expect(plan.notes.map((n) => n.midi), [60, 60, 61, 61, 62, 63]);
    expect(plan.durationMs, 10500);
  });

  test('meter and tempo changes are timed correctly on both passes', () {
    final editor = fixture();
    editor.setMeasureSignatures(1, time: const TimeSignature(3, 4));
    editor.setMeasureTempo(2, 60);
    editor.setMeasureRepeats(1, start: true, end: false);
    editor.setMeasureRepeats(2, start: false, end: true);
    final plan = PlaybackPlan(editor, 120);
    expect(plan.notes.map((n) => (n.midi, n.startMs, n.endMs)), [
      (60, 0, 500),
      (61, 2000, 2500),
      (62, 3500, 4500),
      (61, 6500, 7000),
      (62, 8000, 9000),
      (63, 11000, 12000),
    ]);
  });

  test('repeat boundary ties and nested starts show explicit errors', () {
    final editor = ScoreEditor(blankScore);
    editor.append(voice: Voice.v1, staff: Staff.treble, duration: 2880);
    editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 1920,
      pitch: const Pitch(diatonicStep: 28, midiNote: 60),
    );
    editor.setMeasureRepeats(0, start: false, end: true);
    expect(
      () => PlaybackPlan(editor, 120),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('tied note'),
        ),
      ),
    );
    final nested = fixture();
    nested.setMeasureRepeats(0, start: true, end: false);
    nested.setMeasureRepeats(1, start: true, end: true);
    expect(
      () => PlaybackPlan(nested, 120),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Nested'),
        ),
      ),
    );
  });

  test('repeat marks undo, redo, and survive project round-trip', () {
    final editor = fixture();
    editor.setMeasureSignatures(1, time: const TimeSignature(3, 4), key: 1);
    editor.setMeasureTempo(1, 80);
    editor.setMeasureRepeats(0, start: true, end: false);
    editor.setMeasureRepeats(2, start: false, end: true);
    editor.undo();
    expect(editor.repeatEnds, isEmpty);
    editor.redo();
    final encoded = ProjectCodec.encode(
      Project(name: 'Repeat', tempo: 120, editor: editor),
    );
    expect((jsonDecode(encoded) as Map)['version'], 4);
    final restored = ProjectCodec.decode(encoded);
    expect(ProjectCodec.encode(restored), encoded);
    expect(restored.editor.repeatStarts, {0});
    expect(restored.editor.repeatEnds, {2});
    expect(restored.editor.timeChanges[1], const TimeSignature(3, 4));
    expect(restored.editor.tempoChanges[1], 80);
    final invalid = jsonDecode(encoded) as Map<String, dynamic>;
    invalid['repeatEnds'] = [4];
    expect(
      () => ProjectCodec.decode(jsonEncode(invalid)),
      throwsFormatException,
    );
  });

  testWidgets(
    'repeat marks draw on both staves and leave room for signatures',
    (tester) async {
      final editor = ScoreEditor(blankScore);
      editor.setMeasureSignatures(1, time: const TimeSignature(3, 4), key: 1);
      final without = editor.score;
      editor.setMeasureRepeats(1, start: true, end: true);
      final score = editor.score;
      expect(
        ScorePainter.signatureSpace(score, 1),
        ScorePainter.signatureSpace(without, 1) + 2,
      );
      final canvas = TestRecordingCanvas();
      ScorePainter(score: score, selectedEvent: null, selectedPitch: 0).paint(
        canvas,
        Size(ScorePainter.widthFor(score, 10), ScorePainter.heightFor(10)),
      );
      expect(
        canvas.invocations.where(
          (call) => call.invocation.memberName == #drawCircle,
        ),
        hasLength(8),
      );
    },
  );

  testWidgets('bar settings can add and remove repeat signs on a phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    final canvas = find.byKey(const ValueKey('score-canvas'));
    Future<void> open() async {
      await tester.tapAt(tester.getTopLeft(canvas) + const Offset(410, 60));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Repeats'));
      await tester.pumpAndSettle();
    }

    await open();
    await tester.tap(find.text('Start repeat'));
    await tester.tap(find.text('End repeat'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    var bar = tester
        .widget<ScoreViewport>(find.byType(ScoreViewport))
        .score
        .measures[1];
    expect(bar.repeatStart, true);
    expect(bar.repeatEnd, true);
    await open();
    await tester.tap(find.text('Start repeat'));
    await tester.tap(find.text('End repeat'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    bar = tester
        .widget<ScoreViewport>(find.byType(ScoreViewport))
        .score
        .measures[1];
    expect(bar.repeatStart, false);
    expect(bar.repeatEnd, false);
  });
}
