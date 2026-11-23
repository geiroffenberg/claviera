import 'dart:convert';
import 'dart:ui' as ui;

import 'package:claviera/audio/dynamics_timeline.dart';
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
    'hairpins save pending and completed states with undo and validation',
    () {
      final editor = ScoreEditor(blankScore);
      editor.startHairpin(3840, HairpinKind.diminuendo);
      editor.endHairpin(4800);
      editor.startHairpin(0, HairpinKind.crescendo);
      expect(
        () => editor.startHairpin(960, HairpinKind.crescendo),
        throwsA(isA<EditException>()),
      );
      expect(() => editor.endHairpin(0), throwsA(isA<EditException>()));
      expect(() => editor.endHairpin(4800), throwsA(isA<EditException>()));
      final project = Project(name: 'Hairpins', tempo: 120, editor: editor);
      final encoded = ProjectCodec.encode(project);
      expect(jsonDecode(encoded)['version'], 6);
      final reopened = ProjectCodec.decode(encoded).editor;
      expect(
        ProjectCodec.encode(
          Project(name: 'Hairpins', tempo: 120, editor: reopened),
        ),
        encoded,
      );
      expect(reopened.pendingHairpin!.start, 0);
      expect(reopened.hairpins.where((h) => h.end != null).single.end, 4800);
      expect(() => PlaybackPlan(reopened, 120), throwsStateError);
      expect(() => MidiExport.encode(reopened, 120), throwsStateError);
      expect(
        () => MusicXmlExport.encode(reopened, 120, 'Hairpins'),
        throwsStateError,
      );
      expect(() => PrintLayout.systems(reopened.score), throwsStateError);
      reopened.endHairpin(960);
      expect(reopened.pendingHairpin, isNull);
      reopened.undo();
      expect(reopened.pendingHairpin!.start, 0);
      reopened.redo();
      reopened.deleteHairpin(0);
      expect(reopened.hairpins, hasLength(1));
      reopened.undo();
      expect(reopened.hairpins, hasLength(2));
      final invalid = jsonDecode(encoded) as Map<String, dynamic>;
      invalid['hairpins'] = [
        {'start': 0, 'end': 1920, 'kind': 'crescendo'},
        {'start': 960, 'end': 2880, 'kind': 'diminuendo'},
      ];
      expect(
        () => ProjectCodec.decode(jsonEncode(invalid)),
        throwsFormatException,
      );
    },
  );

  test('meter changes preserve endpoints or reject a shortened bar', () {
    final editor = ScoreEditor(blankScore);
    editor.startHairpin(960, HairpinKind.crescendo);
    editor.endHairpin(4800);
    editor.setScoreSettings(beats: 3, unit: 4, key: 0);
    expect(
      (editor.hairpins.single.start, editor.hairpins.single.end),
      (960, 3840),
    );
    editor.undo();
    expect(
      (editor.hairpins.single.start, editor.hairpins.single.end),
      (960, 4800),
    );
    editor.deleteHairpin(960);
    editor.startHairpin(2880, HairpinKind.crescendo);
    expect(
      () => editor.setScoreSettings(beats: 3, unit: 4, key: 0),
      throwsA(isA<EditException>()),
    );
    expect(editor.pendingHairpin!.start, 2880);
  });

  test(
    'hairpins interpolate both staves, repeat and use explicit end marks',
    () {
      final editor = ScoreEditor(blankScore);
      for (final (voice, staff) in [
        (Voice.v1, Staff.treble),
        (Voice.v2, Staff.bass),
      ]) {
        for (var i = 0; i < 4; i++) {
          editor.append(voice: voice, staff: staff, duration: 960, pitch: c);
        }
      }
      editor.setDynamic(0, DynamicMark.p);
      editor.setDynamic(2880, DynamicMark.ff);
      editor.startHairpin(0, HairpinKind.crescendo);
      editor.endHairpin(2880);
      editor.setMeasureRepeats(0, start: false, end: true);
      final plan = PlaybackPlan(editor, 120);
      expect(plan.notes.map((n) => n.volume), [
        52,
        52,
        71,
        71,
        91,
        91,
        110,
        110,
        52,
        52,
        71,
        71,
        91,
        91,
        110,
        110,
      ]);
      final messages = parseMidi(MidiExport.encode(editor, 120));
      expect(
        messages.where((m) => m.status & 0xf0 == 0x90).map((m) => m.data[1]),
        plan.notes.map((n) => n.volume),
      );
    },
  );

  test(
    'fallback targets persist and intervening marks are interpolation anchors',
    () {
      final editor = ScoreEditor(blankScore);
      editor.startHairpin(0, HairpinKind.crescendo);
      editor.endHairpin(1920);
      editor.startHairpin(2880, HairpinKind.diminuendo);
      editor.endHairpin(3840);
      var dynamics = DynamicsTimeline(editor);
      expect([0, 960, 1920, 2880, 3840, 4800].map(dynamics.velocityAt), [
        80,
        88,
        96,
        96,
        80,
        80,
      ]);
      editor.setDynamic(960, DynamicMark.p);
      dynamics = DynamicsTimeline(editor);
      expect([0, 480, 960, 1440, 1920].map(dynamics.velocityAt), [
        80,
        66,
        52,
        74,
        96,
      ]);
    },
  );

  test('MusicXML and print preserve a hairpin across bars and systems', () {
    final editor = ScoreEditor(
      Score(
        title: 'Long',
        beatsPerMeasure: 4,
        beatUnit: 4,
        measures: List.generate(10, (_) => const Measure()),
      ),
    );
    editor.startHairpin(960, HairpinKind.crescendo);
    editor.endHairpin(5 * 3840 + 960);
    final document = XmlDocument.parse(
      utf8.decode(MusicXmlExport.encode(editor, 120, 'Long')),
    );
    final measures = document.findAllElements('measure').toList();
    expect(
      measures[0].findAllElements('wedge').single.getAttribute('type'),
      'crescendo',
    );
    expect(
      measures[0]
          .findAllElements('wedge')
          .single
          .parent!
          .parent!
          .getElement('offset')!
          .innerText,
      '960',
    );
    expect(
      measures[5].findAllElements('wedge').single.getAttribute('type'),
      'stop',
    );
    final systems = PrintLayout.systems(editor.score);
    expect(systems, hasLength(greaterThan(1)));
    expect(systems[0].score.hairpins.single.start, 960);
    expect(systems[1].score.hairpins.single.start, lessThan(0));
    expect(systems[1].score.hairpins.single.end, greaterThan(0));
  });

  testWidgets('unfinished hairpins are rendered red', (tester) async {
    final editor = ScoreEditor(blankScore);
    editor.startHairpin(0, HairpinKind.crescendo);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    ScorePainter(
      score: editor.score,
      selectedEvent: null,
      selectedPitch: 0,
    ).paint(canvas, const Size(1400, 320));
    final picture = recorder.endRecording();
    final image = await tester.runAsync(() => picture.toImage(1400, 320));
    expect(image, isNotNull);
    final data = await tester.runAsync(
      () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    expect(data, isNotNull);
    final bytes = data!.buffer.asUint8List();
    final bounds = ScorePainter.hairpinBounds(
      editor.score,
      editor.hairpins.single,
      10,
    );
    var redPixels = 0;
    for (var y = bounds.top.floor() - 2; y <= bounds.bottom.ceil() + 2; y++) {
      for (var x = bounds.left.floor() - 2; x <= bounds.right.ceil() + 2; x++) {
        final index = (y * 1400 + x) * 4;
        if (bytes[index] > 150 &&
            bytes[index + 1] < 100 &&
            bytes[index + 2] < 100 &&
            bytes[index + 3] > 100) {
          redPixels++;
        }
      }
    }
    image!.dispose();
    picture.dispose();
    expect(redPixels, greaterThan(0));
  });

  testWidgets('start, finish and delete a hairpin from the score', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(568, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: WorkspaceScreen()));
    final canvas = find.byKey(const ValueKey('score-canvas'));
    Future<void> addNote() async {
      await tester.tapAt(tester.getTopLeft(canvas) + const Offset(160, 115));
      await tester.pumpAndSettle();
    }

    Score score() =>
        tester.widget<ScoreViewport>(find.byType(ScoreViewport)).score;
    await addNote();
    await tester.tap(find.byTooltip('Dynamics'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Crescendo start'));
    await tester.tap(find.text('Crescendo start'));
    await tester.pumpAndSettle();
    expect(score().hairpins.single.end, isNull);
    var bounds = ScorePainter.hairpinBounds(
      score(),
      score().hairpins.single,
      10,
    );
    await tester.tapAt(tester.getTopLeft(canvas) + bounds.center);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(score().hairpins, isEmpty);
    await tester.tap(find.byTooltip('Dynamics'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Crescendo start'));
    await tester.tap(find.text('Crescendo start'));
    await tester.pumpAndSettle();
    await addNote();
    await tester.tap(find.byTooltip('Dynamics'));
    await tester.pumpAndSettle();
    expect(find.text('Set end'), findsOneWidget);
    await tester.tap(find.text('Set end'));
    await tester.pumpAndSettle();
    expect(
      (score().hairpins.single.start, score().hairpins.single.end),
      (0, 960),
    );
    bounds = ScorePainter.hairpinBounds(score(), score().hairpins.single, 10);
    await tester.tapAt(tester.getTopLeft(canvas) + bounds.center);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(score().hairpins, isEmpty);
  });
}
