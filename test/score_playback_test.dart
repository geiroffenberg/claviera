import 'dart:async';

import 'package:claviera/audio/piano_preview.dart';
import 'package:claviera/audio/score_playback.dart';
import 'package:claviera/editor/score_editor.dart';
import 'package:claviera/models/score.dart';
import 'package:claviera/ui/workspace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const c = Pitch(diatonicStep: 28, midiNote: 60);
const sharp = Pitch(
  diatonicStep: 28,
  midiNote: 61,
  accidental: Accidental.sharp,
);
const fixture = Score(
  title: 'Playback',
  beatsPerMeasure: 4,
  beatUnit: 4,
  measures: [
    Measure(
      events: [
        NotationEvent(
          startTick: 0,
          durationTicks: 960,
          voice: Voice.v1,
          staff: Staff.treble,
          pitches: [c, sharp],
        ),
        NotationEvent(
          startTick: 960,
          durationTicks: 960,
          voice: Voice.v1,
          staff: Staff.treble,
        ),
        NotationEvent(
          startTick: 480,
          durationTicks: 1920,
          voice: Voice.v2,
          staff: Staff.bass,
          pitches: [c],
        ),
      ],
    ),
    Measure(),
    Measure(
      events: [
        NotationEvent(
          startTick: 0,
          durationTicks: 960,
          voice: Voice.v1,
          staff: Staff.treble,
          pitches: [c],
        ),
      ],
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('plans polyphony, silence and absolute timing at different tempos', () {
    final editor = ScoreEditor(fixture);
    final plan = PlaybackPlan(editor, 120);
    expect(plan.notes.map((n) => (n.midi, n.startMs, n.endMs)), [
      (60, 0, 500),
      (61, 0, 500),
      (60, 250, 1250),
      (60, 4000, 4500),
    ]);
    expect(plan.durationMs, 4500);
    expect(PlaybackPlan(editor, 60).durationMs, 9000);
    expect(() => PlaybackPlan(editor, 0), throwsArgumentError);
  });

  test('tied notes are scheduled once for their full duration', () {
    final editor = ScoreEditor(
      const Score(
        title: '',
        beatsPerMeasure: 4,
        beatUnit: 4,
        measures: [Measure()],
      ),
    );
    editor.append(voice: Voice.v1, staff: Staff.treble, duration: 2880);
    editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 1920,
      pitch: c,
    );
    final plan = PlaybackPlan(editor, 120);
    expect(plan.notes.map((n) => (n.startMs, n.endMs)), [(1500, 2500)]);
  });

  test('rejects exceeding soundpool polyphony', () {
    final editor = ScoreEditor(
      const Score(
        title: '',
        beatsPerMeasure: 4,
        beatUnit: 4,
        measures: [Measure()],
      ),
    );
    final id = editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 960,
      pitch: c,
    );
    for (var i = 0; i < 64; i++) {
      editor.addPitch(id, c);
    }
    expect(() => PlaybackPlan(editor, 120), throwsStateError);
  });

  test('rejects pitches outside the sample playback range', () {
    final editor = ScoreEditor(
      const Score(
        title: '',
        beatsPerMeasure: 4,
        beatUnit: 4,
        measures: [
          Measure(
            events: [
              NotationEvent(
                startTick: 0,
                durationTicks: 960,
                voice: Voice.v1,
                staff: Staff.bass,
                pitches: [Pitch(diatonicStep: 0, midiNote: 0)],
              ),
            ],
          ),
        ],
      ),
    );
    expect(() => PlaybackPlan(editor, 120), throwsStateError);
  });

  const channel = MethodChannel('claviera/score_playback_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  final errors = <String>[];
  Completer<void>? loading;
  setUp(() {
    calls.clear();
    errors.clear();
    loading = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'initialize' && loading != null) await loading!.future;
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('play and stop send whole score and cancel completion', (
    tester,
  ) async {
    final piano = PianoPreview(
      onError: errors.add,
      channel: channel,
      supported: true,
    );
    var finished = false;
    final plan = PlaybackPlan(ScoreEditor(fixture), 120);
    final future = piano.playScore(plan, onFinished: () => finished = true);
    await tester.pump();
    expect(await future, isTrue);
    expect(calls.map((call) => call.method), ['initialize', 'playScore']);
    final arguments = calls.last.arguments as Map;
    expect((arguments['notes'] as List), hasLength(4));
    await tester.pump(const Duration(milliseconds: 100));
    piano.stopScore();
    await tester.pump(const Duration(seconds: 5));
    expect(finished, isFalse);
    expect(piano.playingScore, isFalse);
    expect(calls.last.method, 'stopScore');
    expect(errors, isEmpty);
    piano.dispose();
  });

  testWidgets('stop during loading prevents playback from starting', (
    tester,
  ) async {
    loading = Completer<void>();
    final piano = PianoPreview(
      onError: errors.add,
      channel: channel,
      supported: true,
    );
    final future = piano.playScore(
      PlaybackPlan(ScoreEditor(fixture), 120),
      onFinished: () {},
    );
    await tester.pump();
    piano.stopScore();
    loading!.complete();
    await tester.pump();
    expect(await future, isFalse);
    expect(calls.where((call) => call.method == 'playScore'), isEmpty);
    piano.dispose();
  });

  testWidgets('transport, tempo and editing lock work in landscape', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(568, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final piano = PianoPreview(
      onError: errors.add,
      channel: channel,
      supported: true,
    );
    await tester.pumpWidget(
      MaterialApp(home: WorkspaceScreen(pianoPreview: piano)),
    );
    await tester.pump();
    await tester.tap(find.text('120 BPM'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '90');
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();
    expect(find.text('90 BPM'), findsOneWidget);
    final canvas = find.byKey(const ValueKey('score-canvas'));
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(160, 115));
    await tester.pump();
    await tester.tap(find.byTooltip('Play score'));
    await tester.pump();
    expect(find.byTooltip('Stop playback'), findsOneWidget);
    expect(calls.where((call) => call.method == 'playScore'), hasLength(1));
    final map = calls.last.arguments as Map;
    final notes = map['notes'] as List;
    expect((notes.single as Map)['endMs'], 667);
    await tester.tap(find.byTooltip('Stop playback'));
    await tester.pump();
    expect(find.byTooltip('Play score'), findsOneWidget);
    expect(calls.last.method, 'stopScore');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
