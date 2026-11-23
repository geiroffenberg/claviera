import 'dart:async';

import 'package:claviera/audio/piano_preview.dart';
import 'package:claviera/audio/score_playback.dart';
import 'package:claviera/editor/score_editor.dart';
import 'package:claviera/models/score.dart';
import 'package:claviera/notation/score_painter.dart';
import 'package:claviera/notation/score_viewport.dart';
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
  test('ornaments play the expected figures with key-aware neighbors', () {
    final editor = ScoreEditor(
      const Score(
        title: '',
        beatsPerMeasure: 4,
        beatUnit: 4,
        keySignature: 1,
        measures: [Measure()],
      ),
    );
    final id = editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 960,
      pitch: const Pitch(diatonicStep: 30, midiNote: 64),
    );
    for (final (mark, pitches) in [
      (Articulation.upperMordent, [64, 66, 64]),
      (Articulation.lowerMordent, [64, 62, 64]),
      (Articulation.turn, [66, 64, 62, 64]),
      (Articulation.invertedTurn, [62, 64, 66, 64]),
    ]) {
      editor.setArticulations(id, {mark});
      final plan = PlaybackPlan(editor, 120);
      expect(plan.notes.map((note) => note.midi), pitches);
      expect(plan.notes.first.startMs, 0);
      expect(plan.notes.last.endMs, 500);
      expect(plan.frameAt(300)!.playingPitches.values.single, {0});
    }
    editor.setArticulations(id, {Articulation.trill});
    final plan = PlaybackPlan(editor, 120);
    expect(plan.notes.map((note) => note.midi), [
      64,
      66,
      64,
      66,
      64,
      66,
      64,
      66,
      64,
    ]);
    expect(plan.notes.last.endMs, 500);
  });

  test('ornaments respect short notes and reject out-of-range neighbors', () {
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
      duration: 60,
      pitch: c,
    );
    editor.addPitch(id, sharp);
    editor.setArticulations(id, {
      Articulation.staccatissimo,
      Articulation.trill,
    });

    editor.setArpeggio(0, ArpeggioDirection.up);
    final plan = PlaybackPlan(editor, 120);
    expect(plan.notes.every((note) => note.startMs < note.endMs), isTrue);
    expect(() => PlaybackPlan(editor, 240), throwsStateError);
    final high = ScoreEditor(
      const Score(
        title: '',
        beatsPerMeasure: 4,
        beatUnit: 4,
        measures: [Measure()],
      ),
    );
    final highId = high.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 960,
      pitch: const Pitch(diatonicStep: 67, midiNote: 127),
    );
    high.setArticulations(highId, {Articulation.trill});
    expect(() => PlaybackPlan(high, 120), throwsStateError);
  });

  test('long trills remain rapid across tied bars', () {
    final editor = ScoreEditor(
      const Score(
        title: '',
        beatsPerMeasure: 4,
        beatUnit: 4,
        measures: [Measure()],
      ),
    );
    editor.insertBars(1, 15, initialTempo: 120);
    final id = editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 16 * 3840,
      pitch: c,
    );
    editor.setArticulations(id, {Articulation.trill});
    final plan = PlaybackPlan(editor, 120);
    expect(plan.notes.length, greaterThan(500));
    expect(plan.notes.every((note) => note.endMs - note.startMs < 70), isTrue);
    expect(plan.notes.last.endMs, 32000);
  });

  test(
    'arpeggio staggers pitches across voices and highlights each attack',
    () {
      final editor = ScoreEditor(
        const Score(
          title: '',
          beatsPerMeasure: 4,
          beatUnit: 4,
          measures: [Measure()],
        ),
      );
      final chord = editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 960,
        pitch: c,
      );
      editor.addPitch(chord, const Pitch(diatonicStep: 30, midiNote: 64));
      final bass = editor.append(
        voice: Voice.v2,
        staff: Staff.bass,
        duration: 960,
        pitch: const Pitch(diatonicStep: 21, midiNote: 48),
      );
      editor.setArpeggio(0, ArpeggioDirection.up);
      var plan = PlaybackPlan(editor, 120);
      expect(plan.notes.map((note) => (note.midi, note.startMs, note.endMs)), [
        (48, 0, 500),
        (60, 31, 500),
        (64, 63, 500),
      ]);
      final chordSegment = (measure: 0, startTick: 0, eventId: chord);
      final bassSegment = (measure: 0, startTick: 0, eventId: bass);
      expect(plan.frameAt(0)!.playingPitches, {
        bassSegment: {0},
      });
      expect(plan.frameAt(31)!.playingPitches[chordSegment], {0});
      expect(plan.frameAt(63)!.playingPitches[chordSegment], {0, 1});
      editor.setArpeggio(0, ArpeggioDirection.down);
      plan = PlaybackPlan(editor, 120);
      expect(plan.notes.map((note) => (note.midi, note.startMs)), [
        (64, 0),
        (60, 31),
        (48, 63),
      ]);
      editor.setArticulations(chord, {Articulation.fermata});
      editor.setMeasureRepeats(0, start: false, end: true);
      plan = PlaybackPlan(editor, 120);
      expect(plan.notes.map((note) => (note.midi, note.startMs, note.endMs)), [
        (64, 0, 750),
        (60, 31, 750),
        (48, 63, 750),
        (64, 2250, 3000),
        (60, 2281, 3000),
        (48, 2313, 3000),
      ]);
    },
  );

  test('arpeggio attacks fit inside short articulated notes', () {
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
      duration: 60,
      pitch: c,
    );
    editor.addPitch(id, sharp);
    editor.setArticulations(id, {Articulation.staccatissimo});
    editor.setArpeggio(0, ArpeggioDirection.up);
    final plan = PlaybackPlan(editor, 120);
    expect(plan.notes.last.startMs, lessThan(plan.notes.last.endMs));
    expect(plan.durationMs, 31);
  });

  test('a fermata on a rest holds a simultaneous note and delays the next', () {
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
                staff: Staff.treble,
                articulations: {Articulation.fermata},
              ),
              NotationEvent(
                startTick: 960,
                durationTicks: 960,
                voice: Voice.v1,
                staff: Staff.treble,
                pitches: [sharp],
              ),
              NotationEvent(
                startTick: 0,
                durationTicks: 1920,
                voice: Voice.v2,
                staff: Staff.bass,
                pitches: [c],
              ),
            ],
          ),
        ],
      ),
    );
    final plan = PlaybackPlan(editor, 120);
    expect(plan.notes.map((note) => (note.midi, note.startMs, note.endMs)), [
      (60, 0, 1250),
      (61, 750, 1250),
    ]);
  });

  test('fermatas pause all voices once, including a marked rest', () {
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
                staff: Staff.treble,
                pitches: [c],
                articulations: {Articulation.fermata},
              ),
              NotationEvent(
                startTick: 960,
                durationTicks: 960,
                voice: Voice.v1,
                staff: Staff.treble,
                pitches: [sharp],
              ),
              NotationEvent(
                startTick: 0,
                durationTicks: 1920,
                voice: Voice.v2,
                staff: Staff.bass,
                pitches: [c],
              ),
              NotationEvent(
                startTick: 0,
                durationTicks: 960,
                voice: Voice.v3,
                staff: Staff.treble,
                articulations: {Articulation.fermata},
              ),
            ],
          ),
        ],
      ),
    );
    final plan = PlaybackPlan(editor, 120);
    expect(plan.notes.map((note) => (note.startMs, note.endMs)), [
      (0, 750),
      (0, 1250),
      (750, 1250),
    ]);
    expect(plan.frameAt(749)!.segments, hasLength(2));
    expect(plan.frameAt(750)!.segments, hasLength(2));
    expect(plan.durationMs, 1250);
  });

  test(
    'fermatas repeat and keep bar-boundary tempo changes after the hold',
    () {
      final editor = ScoreEditor(
        const Score(
          title: '',
          beatsPerMeasure: 4,
          beatUnit: 4,
          measures: [Measure(), Measure()],
        ),
      );
      final id = editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 3840,
        pitch: c,
      );
      editor.setArticulations(id, {Articulation.fermata});
      editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 960,
        pitch: sharp,
      );
      editor.setMeasureRepeats(0, start: false, end: true);
      editor.setMeasureTempo(1, 60);
      final plan = PlaybackPlan(editor, 120);
      expect(plan.notes.map((note) => (note.startMs, note.endMs)), [
        (0, 3000),
        (3000, 6000),
        (6000, 7000),
      ]);
      expect(plan.frameAt(5999)!.measure, 0);
      expect(plan.frameAt(6000)!.measure, 1);
      expect(PlaybackPlan(editor, 120, startMeasure: 1).durationMs, 1000);
    },
  );

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

  test('double-dotted notes play for their exact duration', () {
    final editor = ScoreEditor(
      const Score(
        title: '',
        beatsPerMeasure: 4,
        beatUnit: 4,
        measures: [Measure()],
      ),
    );
    editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: NoteValue.quarter.duration(dots: 2),
      pitch: c,
    );
    final plan = PlaybackPlan(editor, 120);
    expect(plan.notes.single.endMs, 875);
    expect(plan.frameAt(874)!.segments, hasLength(1));
    expect(plan.frameAt(875), isNull);
  });

  test(
    'articulations change sounding duration, highlights and accent volume',
    () {
      final editor = ScoreEditor(fixture);
      final chord = editor.eventsFor(Voice.v1).first.id;
      for (final (marks, end) in [
        ({Articulation.staccato}, 250),
        ({Articulation.staccatissimo}, 125),
        ({Articulation.tenuto}, 500),
        ({Articulation.staccato, Articulation.tenuto}, 375),
      ]) {
        editor.setArticulations(chord, marks);
        final plan = PlaybackPlan(editor, 120);
        expect(plan.notes.take(2).map((n) => (n.endMs, n.volume)), [
          (end, 127),
          (end, 127),
        ]);
        expect(
          plan
              .frameAt(end)!
              .segments
              .any((segment) => segment.eventId == chord),
          isFalse,
        );
      }
      editor.setArticulations(chord, {
        Articulation.staccato,
        Articulation.accent,
      });
      var plan = PlaybackPlan(editor, 120);
      expect(plan.notes.take(2).map((n) => n.volume), [96, 96]);
      expect(plan.notes.last.volume, 80);
      editor.setDynamic(0, DynamicMark.pp);
      plan = PlaybackPlan(editor, 120);
      expect(plan.notes.first.volume, 58);
      editor.setArticulations(chord, {Articulation.marcato});
      expect(PlaybackPlan(editor, 120).notes.first.volume, 66);
    },
  );

  test('visual frames follow sounding voices and bar boundaries', () {
    final editor = ScoreEditor(fixture);
    final score = editor.score;
    PlaybackSegment segment(int measure, Voice voice, int tick) {
      final event = score.measures[measure].events.singleWhere(
        (e) => e.voice == voice && e.startTick == tick && !e.isRest,
      );
      return (measure: measure, startTick: tick, eventId: event.eventId!);
    }

    final chord = segment(0, Voice.v1, 0);
    final bass = segment(0, Voice.v2, 480);
    final last = segment(2, Voice.v1, 0);
    final plan = PlaybackPlan(editor, 120);
    expect(plan.frameAt(-1), isNull);
    expect(plan.frameAt(0)!.segments, {chord});
    expect(plan.frameAt(250)!.segments, {chord, bass});
    expect(plan.frameAt(500)!.segments, {bass});
    expect(plan.frameAt(1250)!.segments, isEmpty);
    expect(plan.frameAt(2000)!.measure, 1);
    expect(plan.frameAt(2000)!.segments, isEmpty);
    expect(plan.frameAt(4000)!.measure, 2);
    expect(plan.frameAt(4000)!.segments, {last});
    expect(plan.frameAt(4500), isNull);
  });

  test('starting at a later bar retains preceding tempo and dynamics', () {
    final editor = ScoreEditor(fixture);
    editor.setMeasureTempo(1, 60);
    editor.setDynamic(0, DynamicMark.pp);
    final plan = PlaybackPlan(editor, 120, startMeasure: 1);
    expect(plan.durationMs, 5000);
    expect(plan.notes.map((n) => (n.midi, n.startMs, n.endMs, n.volume)), [
      (60, 4000, 5000, 42),
    ]);
    expect(plan.frameAt(0)!.measure, 1);
    expect(plan.frameAt(0)!.segments, isEmpty);
    expect(plan.frameAt(4000)!.measure, 2);
    expect(plan.frameAt(4000)!.segments, hasLength(1));
    expect(() => PlaybackPlan(editor, 120, startMeasure: 3), throwsRangeError);
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
    editor.insertBars(1, 1, initialTempo: 120);
    editor.append(voice: Voice.v1, staff: Staff.treble, duration: 2880);
    editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 1920,
      pitch: c,
    );
    final plan = PlaybackPlan(editor, 120);
    expect(plan.notes.map((n) => (n.startMs, n.endMs)), [(1500, 2500)]);
    final first = plan.frameAt(1500)!;
    final second = plan.frameAt(2000)!;
    expect(first.measure, 0);
    expect(second.measure, 1);
    expect(first.segments.single.eventId, second.segments.single.eventId);
    expect(first.segments.single.startTick, 2880);
    expect(second.segments.single.startTick, 0);
  });

  test(
    'shortened tied notes do not highlight silent continuation segments',
    () {
      final editor = ScoreEditor(
        const Score(
          title: '',
          beatsPerMeasure: 4,
          beatUnit: 4,
          measures: [Measure()],
        ),
      );
      editor.insertBars(1, 1, initialTempo: 120);
      editor.append(voice: Voice.v1, staff: Staff.treble, duration: 2880);
      final id = editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 1920,
        pitch: c,
      );
      editor.setArticulations(id, {Articulation.staccato});
      final plan = PlaybackPlan(editor, 120);
      expect(plan.notes.single.endMs, 2000);
      expect(plan.frameAt(1999)!.segments, hasLength(1));
      expect(plan.frameAt(2000)!.segments, isEmpty);
    },
  );

  testWidgets('painter highlights every pitch of a playing chord', (
    tester,
  ) async {
    final score = ScoreEditor(fixture).score;
    final chord = score.measures[0].events.firstWhere(
      (event) => event.pitches.length == 2,
    );
    final canvas = TestRecordingCanvas();
    ScorePainter(
      score: score,
      selectedEvent: null,
      selectedPitch: 0,
      playingSegments: {
        (measure: 0, startTick: chord.startTick, eventId: chord.eventId!),
      },
    ).paint(canvas, Size(ScorePainter.widthFor(score, 10), 320));
    expect(
      canvas.invocations.where(
        (call) => call.invocation.memberName == #drawOval,
      ),
      hasLength(2),
    );
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
  Completer<bool>? preparing;
  setUp(() {
    calls.clear();
    errors.clear();
    loading = null;
    preparing = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'initialize' && loading != null) await loading!.future;
      if (call.method == 'prepareScore') {
        return preparing == null ? true : await preparing!.future;
      }
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
    expect(calls.map((call) => call.method), [
      'initialize',
      'prepareScore',
      'playScore',
    ]);
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

  testWidgets('score waits for audio preparation and can be stopped', (
    tester,
  ) async {
    preparing = Completer<bool>();
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
    expect(calls.map((call) => call.method), ['initialize', 'prepareScore']);
    piano.stopScore();
    preparing!.complete(false);
    await tester.pump();
    expect(await future, isFalse);
    expect(calls.map((call) => call.method), [
      'initialize',
      'prepareScore',
      'stopScore',
    ]);
    expect(errors, isEmpty);
    piano.dispose();
  });

  testWidgets('score starts only after audio preparation succeeds', (
    tester,
  ) async {
    preparing = Completer<bool>();
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
    expect(calls.map((call) => call.method), ['initialize', 'prepareScore']);
    preparing!.complete(true);
    await tester.pump();
    expect(await future, isTrue);
    expect(calls.last.method, 'playScore');
    piano.dispose();
    await tester.pump();
  });

  testWidgets('audio preparation failure is reported without playing', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'prepareScore') {
        throw PlatformException(
          code: 'play_failed',
          message: 'Unable to prepare piano playback.',
        );
      }
      return null;
    });
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
    expect(await future, isFalse);
    expect(errors, ['Unable to prepare piano playback.']);
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

  testWidgets('playback follows bars and restores editing state', (
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
    Future<void> addNote() async {
      await tester.tapAt(
        tester.getTopLeft(find.byType(ScoreViewport)) + const Offset(160, 115),
      );
      await tester.pump();
    }

    ScoreViewport viewport() =>
        tester.widget<ScoreViewport>(find.byType(ScoreViewport));
    double scrollOffset() => tester
        .widgetList<SingleChildScrollView>(
          find.descendant(
            of: find.byType(ScoreViewport),
            matching: find.byType(SingleChildScrollView),
          ),
        )
        .singleWhere((view) => view.scrollDirection == Axis.horizontal)
        .controller!
        .offset;
    await addNote();
    await tester.tap(find.byTooltip('Next bar'));
    await tester.pumpAndSettle();
    await addNote();
    await tester.tap(find.byTooltip('Previous bar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Write mode'));
    await tester.pump();
    final canvas = find.byKey(const ValueKey('score-canvas'));
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(160, 115));
    await tester.pump();
    final selectedId = viewport().selectedEvent!.eventId;
    final cursor = viewport().cursorTick;
    expect(viewport().selectedMeasure, 0);
    final barOneOffset = scrollOffset();

    Future<void> start() async {
      await tester.tap(find.byTooltip('Play score'));
      await tester.pump();
      await tester.pump();
      expect(viewport().selectedMeasure, 0);
      expect(viewport().selectedEvent, isNull);
      expect(viewport().cursorTick, isNull);
      expect(viewport().playingSegments, hasLength(1));
    }

    void restored() {
      expect(viewport().selectedMeasure, 0);
      expect(viewport().selectedEvent!.eventId, selectedId);
      expect(viewport().cursorTick, cursor);
      expect(viewport().playingSegments, isEmpty);
    }

    await start();
    await tester.pump(const Duration(milliseconds: 600));
    expect(viewport().playingSegments, isEmpty);
    await tester.pump(const Duration(milliseconds: 1400));
    expect(viewport().selectedMeasure, 1);
    expect(viewport().playingSegments, hasLength(1));
    expect(scrollOffset(), greaterThan(barOneOffset));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byTooltip('Play score'), findsOneWidget);
    restored();

    await start();
    await tester.tap(find.byTooltip('Stop playback'));
    await tester.pump();
    restored();

    await start();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    restored();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await start();
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        const MethodCall('playbackError', 'Unable to play a score note.'),
      ),
      null,
    );
    await tester.pump();
    expect(errors, ['Unable to play a score note.']);
    restored();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('play starts at selected bar and go to start resets it', (
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
    Future<void> addNote(double y) async {
      await tester.tapAt(
        tester.getTopLeft(find.byType(ScoreViewport)) + Offset(160, y),
      );
      await tester.pump();
    }

    await addNote(115);
    await tester.tap(find.byTooltip('Next bar'));
    await tester.pumpAndSettle();
    await addNote(105);
    await tester.tap(find.byTooltip('Play score'));
    await tester.pump();
    await tester.pump();
    final payload = calls.lastWhere((call) => call.method == 'playScore');
    final notes = (payload.arguments as Map)['notes'] as List;
    expect(notes, hasLength(1));
    expect((notes.single as Map)['startMs'], 0);
    expect(
      tester.widget<ScoreViewport>(find.byType(ScoreViewport)).selectedMeasure,
      1,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == 'Go to start',
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('Stop playback'));
    await tester.pump();
    await tester.tap(find.byTooltip('Go to start'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ScoreViewport>(find.byType(ScoreViewport)).selectedMeasure,
      0,
    );
    await tester.tap(find.byTooltip('Play score'));
    await tester.pump();
    final fromStart = calls.lastWhere((call) => call.method == 'playScore');
    expect(((fromStart.arguments as Map)['notes'] as List), hasLength(2));
    await tester.tap(find.byTooltip('Stop playback'));
    await tester.pump();
    await tester.tap(find.byTooltip('Next bar'));
    await tester.tap(find.byTooltip('Next bar'));
    await tester.pump();
    await tester.tap(find.byTooltip('Play score'));
    await tester.pump();
    expect(
      find.text('No notes or rests at or after this bar.'),
      findsOneWidget,
    );
    expect(find.byTooltip('Play score'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
