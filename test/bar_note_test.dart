import 'dart:convert';

import 'package:claviera/editor/score_editor.dart';
import 'package:claviera/models/blank_score.dart';
import 'package:claviera/notation/score_viewport.dart';
import 'package:claviera/main.dart';
import 'package:flutter/material.dart';
import 'package:claviera/storage/projects.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ScoreEditor editorWithBars() =>
      ScoreEditor(blankScore)..insertBars(1, 2, initialTempo: 120);

  test('bar notes are trimmed, limited, cleared and undoable', () {
    final editor = editorWithBars();
    editor.setBarNote(1, '  Am7  ');
    expect(editor.barNotes, {1: 'Am7'});
    expect(editor.score.measures[1].note, 'Am7');
    expect(
      () => editor.setBarNote(1, 'x' * (ScoreEditor.maxBarNoteLength + 1)),
      throwsA(isA<EditException>()),
    );
    editor.setBarNote(1, '');
    expect(editor.barNotes, isEmpty);
    editor.undo();
    expect(editor.barNotes, {1: 'Am7'});
  });

  test('bar notes follow their bar when bars are inserted or deleted', () {
    final editor = editorWithBars()..setBarNote(1, 'verse');
    editor.insertBars(0, 1, initialTempo: 120);
    expect(editor.barNotes, {2: 'verse'});
    final copy = editor.copyBars(2, 1, initialTempo: 120);
    editor.pasteBars(0, copy, initialTempo: 120);
    expect(editor.barNotes, {0: 'verse', 3: 'verse'});
    editor.deleteBars(0, 1, initialTempo: 120);
    expect(editor.barNotes, {2: 'verse'});
  });

  test('bar notes are saved and loaded', () {
    final editor = editorWithBars()..setBarNote(2, 'La la');
    final saved = ProjectCodec.encode(
      Project(name: 'x', tempo: 120, editor: editor),
    );
    expect(jsonDecode(saved)['version'], 12);
    expect(ProjectCodec.decode(saved).editor.barNotes, {2: 'La la'});
  });

  testWidgets('bar dialog sets a note under the bar', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    final canvas = find.byKey(const ValueKey('score-canvas'));
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(410, 60));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bar note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Dm chord');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    final score = tester
        .widget<ScoreViewport>(find.byType(ScoreViewport))
        .score;
    expect(score.measures[1].note, 'Dm chord');
    expect(find.byIcon(Icons.notes), findsNothing);
  });
}
