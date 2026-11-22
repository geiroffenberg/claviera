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

const f = Pitch(diatonicStep: 31, midiNote: 65);
const naturalF = Pitch(
  diatonicStep: 31,
  midiNote: 65,
  accidental: Accidental.natural,
);

void main() {
  test(
    'changing a bar preserves event positions within bars and tempo playback',
    () {
      final editor = ScoreEditor(blankScore);
      final first = editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 960,
        pitch: f,
        measure: 0,
      );
      final second = editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 960,
        pitch: f,
        measure: 1,
      );
      final third = editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 960,
        pitch: f,
        measure: 2,
      );
      editor.addPitch(second, naturalF);
      editor.setMeasureTempo(2, 60);
      editor.setMeasureSignatures(1, time: const TimeSignature(3, 4), key: 1);
      expect(
        [
          editor.measureStart(0),
          editor.measureStart(1),
          editor.measureStart(2),
          editor.measureStart(3),
        ],
        [0, 3840, 6720, 9600],
      );
      expect(editor.eventById(first)!.pitches.single.midiNote, 65);
      expect(editor.eventById(second)!.pitches.map((p) => p.midiNote), [
        66,
        65,
      ]);
      expect(editor.eventById(third)!.start, 6720);
      expect(editor.eventById(third)!.pitches.single.midiNote, 66);
      final plan = PlaybackPlan(editor, 120);
      expect(plan.notes.where((n) => n.startMs == 3500).single.endMs, 4500);
      editor.setMeasureSignatures(2, time: const TimeSignature(6, 8), key: -1);
      expect(editor.keyAt(3), -1);
      expect(editor.eventById(third)!.pitches.single.midiNote, 65);
      editor.undo();
      expect(editor.keyAt(3), 1);
      editor.redo();
      expect(editor.keyAt(3), -1);
      editor.setMeasureSignatures(2);
      expect(editor.keyAt(3), 1);
      expect(editor.timeAt(3), const TimeSignature(3, 4));
    },
  );

  test(
    'short bars and ties are blocked without altering notes or settings',
    () {
      final editor = ScoreEditor(blankScore);
      editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 3840,
        pitch: f,
        measure: 1,
      );
      expect(
        () => editor.setMeasureSignatures(
          1,
          time: const TimeSignature(3, 4),
          key: 1,
        ),
        throwsA(isA<EditException>()),
      );
      expect(editor.timeChanges, isEmpty);
      expect(editor.keyChanges, isEmpty);
      final tied = ScoreEditor(blankScore);
      tied.append(voice: Voice.v1, staff: Staff.treble, duration: 2880);
      tied.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 1920,
        pitch: f,
      );
      expect(
        () => tied.setMeasureSignatures(1, time: const TimeSignature(3, 4)),
        throwsA(isA<EditException>()),
      );
      expect(tied.score.measures[1].events.first.tieFromPrevious, true);
    },
  );

  test('saved projects preserve changes, ties and effective values', () {
    final editor = ScoreEditor(blankScore);
    editor.setMeasureSignatures(1, time: const TimeSignature(3, 4), key: 1);
    editor.setMeasureSignatures(3, time: const TimeSignature(5, 8), key: -2);
    editor.setMeasureTempo(2, 100);
    editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 1920,
      pitch: const Pitch(diatonicStep: 31, midiNote: 66),
      measure: 1,
    );
    editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 1920,
      pitch: const Pitch(diatonicStep: 31, midiNote: 66),
      measure: 1,
    );
    final project = Project(name: 'bars', tempo: 120, editor: editor);
    final json = ProjectCodec.encode(project);
    expect((jsonDecode(json) as Map)['version'], 3);
    final decoded = ProjectCodec.decode(json);
    expect(ProjectCodec.encode(decoded), json);
    expect(decoded.editor.timeAt(2), const TimeSignature(3, 4));
    expect(decoded.editor.keyAt(3), -2);
    expect(decoded.editor.tempoChanges, {2: 100});
    expect(
      decoded.editor.score.measures[2].events.any((e) => e.tieFromPrevious),
      true,
    );
    final malformed = jsonDecode(json) as Map<String, dynamic>;
    malformed['timeChanges'] = [
      {'measure': 1, 'beats': 3, 'unit': 3},
    ];
    expect(
      () => ProjectCodec.decode(jsonEncode(malformed)),
      throwsFormatException,
    );
  });

  testWidgets('bar dialog sets signature and entry uses the new key', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    final canvas = find.byKey(const ValueKey('score-canvas'));
    var origin = tester.getTopLeft(canvas);
    await tester.tapAt(origin + const Offset(410, 60));
    await tester.pumpAndSettle();
    expect(find.text('Bar 2 settings'), findsOneWidget);
    await tester.tap(find.text('Key and time signature'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change key at this bar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('score-key-signature')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('G major / E minor (1 sharp)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change time at this bar'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('score-beats-per-bar')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('score-beats-per-bar')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    var score = tester.widget<ScoreViewport>(find.byType(ScoreViewport)).score;
    expect(score.keyAt(1), 1);
    expect(score.timeAt(1), const TimeSignature(3, 4));
    await tester.tap(find.byTooltip('Next bar'));
    await tester.pumpAndSettle();
    origin = tester.getTopLeft(canvas);
    await tester.tapAt(
      origin + Offset(ScorePainter.eventXFor(score, 1, 0, 10), 115),
    );
    await tester.pump();
    score = tester.widget<ScoreViewport>(find.byType(ScoreViewport)).score;
    expect(score.measures[1].events.single.pitches.single.midiNote, 66);
  });

  testWidgets('first bar offers initial key and time settings', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    final canvas = find.byKey(const ValueKey('score-canvas'));
    final origin = tester.getTopLeft(canvas);
    await tester.tapAt(origin + const Offset(130, 60));
    await tester.pumpAndSettle();
    expect(find.text('Bar 1 settings'), findsOneWidget);
    expect(find.text('Tempo'), findsOneWidget);
    await tester.tap(find.text('Key and time signature'));
    await tester.pumpAndSettle();
    expect(find.text('Score settings'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ScoreViewport>(find.byType(ScoreViewport))
          .score
          .measures
          .expand((measure) => measure.events),
      isEmpty,
    );
  });
}
