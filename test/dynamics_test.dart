import 'dart:convert';

import 'package:claviera/audio/midi_export.dart';
import 'package:claviera/audio/score_playback.dart';
import 'package:claviera/editor/score_editor.dart';
import 'package:claviera/models/blank_score.dart';
import 'package:claviera/models/score.dart';
import 'package:claviera/notation/musicxml_export.dart';
import 'package:claviera/notation/print_layout.dart';
import 'package:claviera/notation/score_painter.dart';
import 'package:claviera/notation/score_viewport.dart';
import 'package:claviera/storage/projects.dart';
import 'package:claviera/ui/workspace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import 'midi_export_test.dart' show parseMidi;

const c = Pitch(diatonicStep: 28, midiNote: 60);

void main() {
  test(
    'dynamic positions survive deletion, undo, meter changes and storage',
    () {
      final editor = ScoreEditor(blankScore);
      final id = editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 960,
        pitch: c,
        measure: 1,
      );
      editor.setDynamic(3840, DynamicMark.pp);
      editor.delete(id);
      expect(editor.dynamicChanges, {3840: DynamicMark.pp});
      editor.undo();
      editor.undo();
      expect(editor.dynamicChanges, isEmpty);
      editor.redo();
      expect(editor.dynamicChanges, {3840: DynamicMark.pp});
      editor.setScoreSettings(beats: 3, unit: 4, key: 0);
      expect(editor.dynamicChanges, {2880: DynamicMark.pp});
      final project = Project(name: 'Dynamics', tempo: 120, editor: editor);
      final encoded = ProjectCodec.encode(project);
      expect(jsonDecode(encoded)['version'], 5);
      expect(ProjectCodec.encode(ProjectCodec.decode(encoded)), encoded);
      expect(
        PrintLayout.systems(editor.score).first.score.measures[1].dynamics,
        {0: DynamicMark.pp},
      );
      final invalid = jsonDecode(encoded) as Map<String, dynamic>;
      invalid['dynamics'] = [
        {'tick': 2880, 'mark': 'pp'},
        {'tick': 2880, 'mark': 'ff'},
      ];
      expect(
        () => ProjectCodec.decode(jsonEncode(invalid)),
        throwsFormatException,
      );
    },
  );

  test('shorter bars cannot discard a dynamic without its note', () {
    final editor = ScoreEditor(blankScore);
    editor.setDynamic(2880, DynamicMark.f);
    expect(
      () => editor.setScoreSettings(beats: 3, unit: 4, key: 0),
      throwsA(isA<EditException>()),
    );
    expect(editor.dynamicChanges, {2880: DynamicMark.f});
    expect(editor.score.beatsPerMeasure, 4);
  });

  test('printed systems retain dynamics at the start of each system', () {
    final score = Score(
      title: 'Print',
      beatsPerMeasure: 4,
      beatUnit: 4,
      measures: List.generate(
        10,
        (_) => const Measure(dynamics: {0: DynamicMark.p}),
      ),
    );
    final systems = PrintLayout.systems(score);
    expect(systems.length, greaterThan(1));
    for (final system in systems) {
      expect(system.score.measures.first.dynamics, {0: DynamicMark.p});
    }
  });

  test('dynamics affect both staves, MIDI and playback across repeats', () {
    final editor = ScoreEditor(blankScore);
    for (final measure in [0, 1]) {
      for (final (voice, staff) in [
        (Voice.v1, Staff.treble),
        (Voice.v2, Staff.bass),
      ]) {
        editor.append(
          voice: voice,
          staff: staff,
          duration: 960,
          pitch: c,
          measure: measure,
        );
      }
    }
    editor.setDynamic(0, DynamicMark.pp);
    editor.setDynamic(3840, DynamicMark.ff);
    editor.setMeasureRepeats(0, start: true, end: false);
    editor.setMeasureRepeats(1, start: false, end: true);
    final plan = PlaybackPlan(editor, 120);
    expect(plan.notes.map((note) => note.volume), [
      42,
      42,
      110,
      110,
      42,
      42,
      110,
      110,
    ]);
    expect(plan.notes.first.toMap()['volume'], 42);
    final midi = parseMidi(MidiExport.encode(editor, 120));
    expect(midi.where((e) => e.status & 0xf0 == 0x90).map((e) => e.data[1]), [
      42,
      42,
      110,
      110,
      42,
      42,
      110,
      110,
    ]);
    editor.setDynamic(0, null);
    expect(PlaybackPlan(editor, 120).notes.first.volume, 80);
    editor.setDynamic(3840, null);
    expect(PlaybackPlan(editor, 120).notes.first.volume, 127);
  });

  test('MusicXML exports dynamics at their positions', () {
    final editor = ScoreEditor(blankScore);
    editor.setDynamic(0, DynamicMark.mf);
    editor.setDynamic(960, DynamicMark.ppp);
    final xml = XmlDocument.parse(
      utf8.decode(MusicXmlExport.encode(editor, 120, 'Dynamics')),
    );
    final directions = xml
        .findAllElements('direction')
        .where((e) => e.findAllElements('dynamics').isNotEmpty)
        .toList();
    expect(directions, hasLength(2));
    expect(directions[0].findAllElements('mf'), hasLength(1));
    expect(directions[0].getElement('offset'), isNull);
    expect(directions[1].findAllElements('ppp'), hasLength(1));
    expect(directions[1].getElement('offset')!.innerText, '960');
    expect(directions[1].getElement('offset')!.getAttribute('sound'), 'yes');
    expect(
      directions[1].getElement('sound')!.getAttribute('dynamics'),
      isNotNull,
    );
  });

  testWidgets('write, replace and remove a dynamic after deleting its note', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(568, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: WorkspaceScreen()));
    final canvas = find.byKey(const ValueKey('score-canvas'));
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(160, 115));
    await tester.pump();
    await tester.tap(find.byTooltip('Dynamics'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('pp'));
    await tester.pumpAndSettle();
    Score score() =>
        tester.widget<ScoreViewport>(find.byType(ScoreViewport)).score;
    expect(score().measures.first.dynamics, {0: DynamicMark.pp});
    await tester.tap(find.byTooltip('Dynamics'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ff'));
    await tester.pumpAndSettle();
    expect(score().measures.first.dynamics, {0: DynamicMark.ff});
    await tester.scrollUntilVisible(
      find.byTooltip('Write mode'),
      200,
      scrollable: find.descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byTooltip('Write mode'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byTooltip('Delete'),
      200,
      scrollable: find.descendant(
        of: find.byType(ListView).last,
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(score().measures.first.dynamics, {0: DynamicMark.ff});
    final bounds = ScorePainter.dynamicBounds(score(), 0, 0, 10);
    await tester.tapAt(tester.getTopLeft(canvas) + bounds.center);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(score().measures.first.dynamics, isEmpty);
  });
}
