import 'package:claviera/models/score.dart';
import 'package:claviera/notation/beaming.dart';
import 'package:claviera/notation/score_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

NotationEvent event(
  int start,
  int duration, {
  Voice voice = Voice.v1,
  Staff staff = Staff.treble,
  bool rest = false,
  bool chord = false,
  bool tie = false,
}) => NotationEvent(
  startTick: start,
  durationTicks: duration,
  voice: voice,
  staff: staff,
  tieFromPrevious: tie,
  pitches: rest
      ? []
      : [
          const Pitch(diatonicStep: 30, midiNote: 64),
          if (chord) const Pitch(diatonicStep: 31, midiNote: 65),
        ],
);

void main() {
  test('stem directions and dotted beam counts', () {
    expect(Voice.values.map(stemPointsUp), [true, false, true, false]);
    expect([960, 720, 480, 360, 240, 180, 120, 60].map(beamCount), [
      0,
      1,
      1,
      2,
      2,
      3,
      3,
      4,
    ]);
    const chord = [
      Pitch(diatonicStep: 30, midiNote: 64),
      Pitch(diatonicStep: 31, midiNote: 65),
    ];
    expect(secondOffsets(chord), [false, true]);
    expect(secondOffsets(chord, stemUp: false), [true, false]);
  });

  testWidgets('double dots are drawn for both notes and rests', (tester) async {
    int paragraphs(int duration, {required bool rest}) {
      final score = Score(
        title: '',
        beatsPerMeasure: 4,
        beatUnit: 4,
        measures: [
          Measure(events: [event(0, duration, rest: rest)]),
        ],
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

    for (final rest in [false, true]) {
      final plain = paragraphs(960, rest: rest);
      expect(paragraphs(1440, rest: rest), plain + 1);
      expect(paragraphs(1680, rest: rest), plain + 2);
    }
    expect(beamCount(840), 1);
    expect(beamCount(420), 2);
  });

  test('4/4 groups consecutive events within each beat and voice', () {
    final events = [
      event(0, 480),
      event(480, 480),
      event(960, 480),
      event(1440, 480),
      event(0, 480, voice: Voice.v2),
      event(480, 480, voice: Voice.v2),
    ];
    final groups = beamGroups(
      Measure(events: events),
      numerator: 4,
      denominator: 4,
    );
    expect(groups, [
      [events[0], events[1]],
      [events[2], events[3]],
      [events[4], events[5]],
    ]);
  });

  test('rests, gaps, staff changes and beat crossings break groups', () {
    final events = [
      event(0, 240),
      event(240, 240, rest: true),
      event(480, 240),
      event(720, 240, staff: Staff.bass),
      event(960, 240),
      event(1320, 240),
      event(1560, 480),
      event(2040, 240),
    ];
    expect(
      beamGroups(Measure(events: events), numerator: 4, denominator: 4),
      isEmpty,
    );
  });

  test(
    'compound 6/8 uses dotted quarter beats; ties can join within a beat',
    () {
      final events = List.generate(6, (i) => event(i * 480, 480, tie: i == 1));
      final groups = beamGroups(
        Measure(events: events),
        numerator: 6,
        denominator: 8,
      );
      expect(groups.map((g) => g.map((e) => e.startTick).toList()), [
        [0, 480, 960],
        [1440, 1920, 2400],
      ]);
      expect(beamBeatTicks(3, 8), 480);
      expect(beamBeatTicks(4, 4), 960);
    },
  );

  test('mixed durations create full secondary beams and directed beamlets', () {
    final group = [
      event(0, 240),
      event(240, 240),
      event(480, 120),
      event(600, 60),
      event(660, 60),
      event(720, 240),
    ];
    final spans = beamSpans(group);
    expect(
      spans
          .map((s) => (s.level, s.first, s.last, s.isHook, s.hookRight))
          .toList(),
      [
        (1, 0, 5, false, false),
        (2, 0, 5, false, false),
        (3, 2, 4, false, false),
        (4, 3, 4, false, false),
      ],
    );
    final hooks = beamSpans([event(0, 240), event(240, 480), event(720, 240)]);
    expect(hooks.map((s) => (s.level, s.first, s.last, s.hookRight)).toList(), [
      (1, 0, 2, false),
      (2, 0, 0, true),
      (2, 2, 2, false),
    ]);
  });

  testWidgets('painter joins stems to beams and paints isolated down stems', (
    tester,
  ) async {
    final notes = [
      event(0, 240, voice: Voice.v2, chord: true),
      event(240, 480, voice: Voice.v2),
      event(720, 240, voice: Voice.v2),
    ];
    final score = Score(
      title: 'paint',
      beatsPerMeasure: 4,
      beatUnit: 4,
      measures: [Measure(events: notes)],
    );
    final canvas = TestRecordingCanvas();
    ScorePainter(
      score: score,
      selectedEvent: null,
      selectedPitch: 0,
    ).paint(canvas, const Size(500, 320));
    final beams = canvas.invocations
        .where((i) => i.invocation.memberName == #drawRect)
        .map((i) => i.invocation.positionalArguments.first as Rect)
        .toList();
    expect(beams, hasLength(3));
    expect(beams.first.height, 5);
    expect(beams[1].height, 5);
    expect(beams[2].height, 5);
    expect(beams[1].top, lessThan(beams.first.top));
    final lines = canvas.invocations
        .where((i) => i.invocation.memberName == #drawLine)
        .map((i) => i.invocation.positionalArguments)
        .toList();
    for (final note in notes) {
      final x = ScorePainter.eventX(
        0,
        note.startTick,
        score.ticksPerMeasure,
        10,
      );
      expect(
        lines.any((args) {
          final a = args[0] as Offset;
          final b = args[1] as Offset;
          return a.dx == x &&
              b.dx == x &&
              b.dy == beams.first.center.dy &&
              b.dy > a.dy;
        }),
        isTrue,
      );
    }

    final isolated = TestRecordingCanvas();
    ScorePainter(
      score: Score(
        title: 'isolated',
        beatsPerMeasure: 4,
        beatUnit: 4,
        measures: [
          Measure(events: [event(0, 480, voice: Voice.v4)]),
        ],
      ),
      selectedEvent: null,
      selectedPitch: 0,
    ).paint(isolated, const Size(500, 320));
    final stem = isolated.invocations
        .where((i) => i.invocation.memberName == #drawLine)
        .map((i) => i.invocation.positionalArguments)
        .where(
          (args) =>
              (args[0] as Offset).dx == 160 && (args[1] as Offset).dx == 160,
        )
        .single;
    expect((stem[1] as Offset).dy, greaterThan((stem[0] as Offset).dy));
    expect(
      isolated.invocations.where((i) => i.invocation.memberName == #drawRect),
      isEmpty,
    );
  });

  testWidgets('up stems connect to every level and bars remain independent', (
    tester,
  ) async {
    final first = [event(2880, 480), event(3360, 480)];
    final second = [
      event(0, 120),
      event(120, 120),
      event(240, 120),
      event(360, 120),
    ];
    final score = Score(
      title: 'bars',
      beatsPerMeasure: 4,
      beatUnit: 4,
      measures: [
        Measure(events: first),
        Measure(events: second),
      ],
    );
    final canvas = TestRecordingCanvas();
    ScorePainter(
      score: score,
      selectedEvent: null,
      selectedPitch: 0,
    ).paint(canvas, const Size(800, 320));
    final rectangles = canvas.invocations
        .where((i) => i.invocation.memberName == #drawRect)
        .map((i) => i.invocation.positionalArguments.first as Rect)
        .toList();
    expect(rectangles, hasLength(4));
    expect(rectangles.first.right, lessThan(410));
    expect(rectangles.skip(1).every((r) => r.left > 410), isTrue);
    expect(rectangles[2].top, greaterThan(rectangles[1].top));
    expect(rectangles[3].top, greaterThan(rectangles[2].top));
    final lines = canvas.invocations
        .where((i) => i.invocation.memberName == #drawLine)
        .map((i) => i.invocation.positionalArguments);
    for (final note in second) {
      final x =
          ScorePainter.eventX(1, note.startTick, score.ticksPerMeasure, 10) +
          11.5;
      expect(
        lines.any((args) {
          final a = args[0] as Offset;
          final b = args[1] as Offset;
          return a.dx == x &&
              b.dx == x &&
              b.dy == rectangles[1].center.dy &&
              b.dy < a.dy;
        }),
        isTrue,
      );
    }
  });
}
