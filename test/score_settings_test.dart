import 'package:claviera/audio/piano_preview.dart';
import 'package:claviera/audio/score_playback.dart';
import 'package:claviera/editor/score_editor.dart';
import 'package:claviera/main.dart';
import 'package:claviera/models/score.dart';
import 'package:claviera/notation/score_painter.dart';
import 'package:claviera/notation/score_viewport.dart';
import 'package:claviera/ui/workspace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const f = Pitch(diatonicStep: 31, midiNote: 65);
const naturalF = Pitch(
  diatonicStep: 31,
  midiNote: 65,
  accidental: Accidental.natural,
);
const blank = Score(
  title: 'Test',
  beatsPerMeasure: 4,
  beatUnit: 4,
  measures: [Measure(), Measure()],
);

void main() {
  test('key signature alteration order is correct for every major key', () {
    const sharpOrder = [3, 0, 4, 1, 5, 2, 6];
    const flatOrder = [6, 2, 5, 1, 4, 0, 3];
    for (var count = 0; count <= 7; count++) {
      for (var step = 0; step < 7; step++) {
        expect(
          keyAlteration(count, step),
          sharpOrder.take(count).contains(step) ? 1 : 0,
        );
        expect(
          keyAlteration(-count, step),
          flatOrder.take(count).contains(step) ? -1 : 0,
        );
      }
    }
  });

  testWidgets('each key accidental is drawn on both staves', (tester) async {
    int paragraphs(int signature) {
      final score = Score(
        title: '',
        beatsPerMeasure: 4,
        beatUnit: 4,
        keySignature: signature,
        measures: const [Measure()],
      );
      final canvas = TestRecordingCanvas();
      ScorePainter(score: score, selectedEvent: null, selectedPitch: 0).paint(
        canvas,
        Size(ScorePainter.widthFor(score, 10), ScorePainter.heightFor(10)),
      );
      return canvas.invocations
          .where((call) => call.invocation.memberName == #drawParagraph)
          .length;
    }

    for (var key = -7; key <= 7; key++) {
      expect(paragraphs(key) - paragraphs(0), key.abs() * 2);
    }
  });

  test('key updates existing and chord pitches, playback and undo', () {
    final editor = ScoreEditor(blank);
    final id = editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 960,
      pitch: f,
    );
    editor.addPitch(id, naturalF);
    editor.setScoreSettings(beats: 4, unit: 4, key: 1);
    expect(editor.score.keySignature, 1);
    expect(editor.eventById(id)!.pitches.map((p) => p.midiNote), [66, 65]);
    expect(PlaybackPlan(editor, 120).notes.map((n) => n.midi), [66, 65]);
    editor.undo();
    expect(editor.score.keySignature, 0);
    expect(editor.eventById(id)!.pitches.map((p) => p.midiNote), [65, 65]);
    editor.redo();
    expect(editor.eventById(id)!.pitches.first.midiNote, 66);
    editor.setScoreSettings(beats: 4, unit: 4, key: -7);
    expect(editor.eventById(id)!.pitches.map((p) => p.midiNote), [64, 65]);
  });

  test(
    'meter preserves notes in their bars and blocks overflow atomically',
    () {
      final editor = ScoreEditor(blank);
      final first = editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 960,
        pitch: f,
      );
      final later = editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 960,
        pitch: f,
        measure: 1,
      );
      editor.setScoreSettings(beats: 3, unit: 4, key: 0);
      expect(editor.eventById(first)!.start, 0);
      expect(editor.eventById(later)!.start, 2880);
      expect(editor.score.measures[1].events.single.startTick, 0);
      editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 1920,
        pitch: f,
        measure: 1,
      );
      expect(
        () => editor.setScoreSettings(beats: 2, unit: 4, key: 1),
        throwsA(isA<EditException>()),
      );
      expect(editor.score.beatsPerMeasure, 3);
      expect(editor.score.keySignature, 0);
      expect(editor.eventById(later)!.start, 2880);
    },
  );

  test('meter change blocks existing bar-spanning ties', () {
    final editor = ScoreEditor(blank);
    editor.append(voice: Voice.v1, staff: Staff.treble, duration: 2880);
    editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 1920,
      pitch: f,
    );
    expect(
      () => editor.setScoreSettings(beats: 3, unit: 4, key: 0),
      throwsA(isA<EditException>()),
    );
    expect(editor.score.beatsPerMeasure, 4);
  });

  testWidgets('pre-bar settings change key and apply to newly entered notes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    final canvas = find.byKey(const ValueKey('score-canvas'));
    var origin = tester.getTopLeft(canvas);
    await tester.tapAt(origin + const Offset(50, 100));
    await tester.pumpAndSettle();
    expect(find.text('Score settings'), findsOneWidget);
    expect(
      tester
          .widget<ScoreViewport>(find.byType(ScoreViewport))
          .score
          .measures
          .expand((m) => m.events),
      isEmpty,
    );
    await tester.tap(find.text('C major / A minor (no sharps or flats)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('G major / E minor (1 sharp)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    final score = tester
        .widget<ScoreViewport>(find.byType(ScoreViewport))
        .score;
    expect(score.keySignature, 1);
    origin = tester.getTopLeft(canvas);
    await tester.tapAt(
      origin + Offset(ScorePainter.startFor(score, 10) + 30, 115),
    );
    await tester.pump();
    expect(
      tester
          .widget<ScoreViewport>(find.byType(ScoreViewport))
          .selectedEvent!
          .pitches
          .single
          .midiNote,
      66,
    );
  });

  testWidgets('shorter meter shows an error without changing the score', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    final canvas = find.byKey(const ValueKey('score-canvas'));
    final origin = tester.getTopLeft(canvas);
    for (var i = 0; i < 4; i++) {
      await tester.tapAt(origin + const Offset(160, 115));
      await tester.pump();
    }
    await tester.tapAt(origin + const Offset(50, 100));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('score-beats-per-bar')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.textContaining('do not fit'), findsOneWidget);
    final score = tester
        .widget<ScoreViewport>(find.byType(ScoreViewport))
        .score;
    expect(score.beatsPerMeasure, 4);
    expect(score.measures.first.events, hasLength(4));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('entry preview uses the chosen key signature', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const channel = MethodChannel('claviera/settings_preview_test');
    final calls = <MethodCall>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final piano = PianoPreview(
      onError: (message) => fail(message),
      channel: channel,
      supported: true,
    );
    await tester.pumpWidget(
      MaterialApp(home: WorkspaceScreen(pianoPreview: piano)),
    );
    await tester.pump();
    final canvas = find.byKey(const ValueKey('score-canvas'));
    final origin = tester.getTopLeft(canvas);
    await tester.tapAt(origin + const Offset(50, 100));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('score-key-signature')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('G major / E minor (1 sharp)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(origin + const Offset(170, 115));
    await tester.pump();
    expect(calls.where((call) => call.method == 'play').last.arguments, {
      'midi': 66,
    });
    await gesture.up();
    await tester.pumpWidget(const SizedBox());
  });
}
