import 'dart:convert';

import 'package:claviera/audio/score_playback.dart';
import 'package:claviera/editor/score_editor.dart';
import 'package:claviera/main.dart';
import 'package:claviera/models/blank_score.dart';
import 'package:claviera/models/score.dart';
import 'package:claviera/notation/score_viewport.dart';
import 'package:claviera/storage/projects.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tempo changes affect tied notes and later events and support undo', () {
    final editor = ScoreEditor(blankScore);
    const c = Pitch(diatonicStep: 28, midiNote: 60);
    editor.append(voice: Voice.v1, staff: Staff.treble, duration: 2880);
    editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 1920,
      pitch: c,
    );
    editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 960,
      pitch: c,
      measure: 2,
    );
    editor.setMeasureTempo(1, 60);
    editor.setMeasureTempo(2, 240);
    final plan = PlaybackPlan(editor, 120);
    expect(plan.notes.map((n) => (n.startMs, n.endMs)), [
      (1500, 3000),
      (6000, 6250),
    ]);
    editor.undo();
    expect(editor.tempoChanges, {1: 60});
    editor.redo();
    expect(editor.tempoChanges, {1: 60, 2: 240});
    editor.setMeasureTempo(1, null);
    expect(editor.tempoChanges, {2: 240});
  });

  test('tempo changes round-trip and old projects remain readable', () {
    final editor = ScoreEditor(blankScore);
    final project = Project(name: 'Test', tempo: 120, editor: editor);
    final old = ProjectCodec.encode(project);
    expect(ProjectCodec.decode(old).editor.tempoChanges, isEmpty);
    editor.setMeasureTempo(1, 84);
    final encoded = ProjectCodec.encode(project);
    expect((jsonDecode(encoded) as Map)['version'], 2);
    expect(ProjectCodec.decode(encoded).editor.tempoChanges, {1: 84});
    final invalid = jsonDecode(encoded) as Map<String, dynamic>;
    invalid['tempoChanges'] = [
      {'measure': 1, 'bpm': 0},
    ];
    expect(
      () => ProjectCodec.decode(jsonEncode(invalid)),
      throwsFormatException,
    );
  });

  testWidgets('bar settings opens tempo without writing a note', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    final origin = tester.getTopLeft(
      find.byKey(const ValueKey('score-canvas')),
    );
    await tester.tapAt(origin + const Offset(410, 60));
    await tester.pumpAndSettle();
    expect(find.text('Bar 2 settings'), findsOneWidget);
    await tester.tap(find.text('Tempo'));
    await tester.pumpAndSettle();
    expect(find.text('Bar 2 tempo'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '90');
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();
    final score = tester
        .widget<ScoreViewport>(find.byType(ScoreViewport))
        .score;
    expect(score.measures[1].tempo, 90);
    expect(score.measures.expand((m) => m.events), isEmpty);
    await tester.tapAt(origin + const Offset(410, 60));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tempo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove change'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ScoreViewport>(find.byType(ScoreViewport))
          .score
          .measures[1]
          .tempo,
      isNull,
    );
  });
}
