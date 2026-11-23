import 'package:claviera/main.dart';
import 'package:claviera/models/score.dart';
import 'package:claviera/notation/beaming.dart';
import 'package:claviera/notation/score_painter.dart';
import 'package:claviera/notation/score_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mode toggles are grouped at the top of the left rail', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(568, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    final mode = find.byTooltip('Write mode');
    final input = find.byTooltip('Note');
    final divider = find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Divider),
        )
        .first;
    final dynamics = find.byTooltip('Dynamics');
    expect(tester.getCenter(mode).dy, lessThan(tester.getCenter(input).dy));
    expect(tester.getCenter(input).dy, lessThan(tester.getCenter(divider).dy));
    expect(
      tester.getCenter(divider).dy,
      lessThan(tester.getCenter(dynamics).dy),
    );
    await tester.tap(mode);
    await tester.tap(input);
    await tester.pump();
    expect(find.byTooltip('Edit mode'), findsOneWidget);
    expect(find.byTooltip('Rest'), findsOneWidget);
  });

  testWidgets('beaming updates after writing and undoing notes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    await tester.tap(find.byTooltip('eighth note'));
    await tester.pump();
    final origin = tester.getTopLeft(
      find.byKey(const ValueKey('score-canvas')),
    );
    await tester.tapAt(origin + const Offset(160, 115));
    await tester.tapAt(origin + const Offset(160, 110));
    await tester.pump();
    Score score() =>
        tester.widget<ScoreViewport>(find.byType(ScoreViewport)).score;
    expect(
      beamGroups(score().measures.first, numerator: 4, denominator: 4),
      hasLength(1),
    );
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(
      beamGroups(score().measures.first, numerator: 4, denominator: 4),
      isEmpty,
    );
  });

  testWidgets('startup score has no notes or rests in any voice', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    final viewport = tester.widget<ScoreViewport>(find.byType(ScoreViewport));
    expect(viewport.score.measures, hasLength(4));
    expect(
      viewport.score.measures.expand((measure) => measure.events),
      isEmpty,
    );
    expect(viewport.selectedEvent, isNull);
    expect(viewport.cursorTick, 0);
    expect(find.text('Untitled score'), findsOneWidget);
  });

  test('seconds offsets alternate in pitch order', () {
    const pitches = [
      Pitch(diatonicStep: 30, midiNote: 64),
      Pitch(diatonicStep: 28, midiNote: 60),
      Pitch(diatonicStep: 29, midiNote: 62),
    ];
    expect(secondOffsets(pitches), [false, false, true]);
  });

  testWidgets('write, select, chord stack, edit, undo and redo', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    ScoreViewport viewport() =>
        tester.widget<ScoreViewport>(find.byType(ScoreViewport));
    await tester.tap(find.text('V4'));
    await tester.pump();
    final canvas = find.byKey(const ValueKey('score-canvas'));
    final origin = tester.getTopLeft(canvas);
    await tester.tapAt(origin + const Offset(160, 115));
    await tester.pump();
    expect(viewport().selectedEvent!.voice, Voice.v4);
    expect(viewport().selectedEvent!.pitches.single.diatonicStep, 31);
    expect(viewport().cursorTick, 960);

    await tester.tap(find.byTooltip('Write mode'));
    await tester.pump();
    await tester.tapAt(origin + const Offset(160, 115));
    await tester.pump();
    await tester.tap(find.byTooltip('Edit mode'));
    await tester.pump();
    await tester.tap(find.byTooltip('Chord stack'));
    await tester.pump();
    await tester.tapAt(origin + const Offset(160, 105));
    await tester.pump();
    expect(viewport().selectedEvent!.pitches, hasLength(2));
    expect(viewport().cursorTick, 0);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(
      viewport().score.measures[0].events
          .singleWhere((e) => e.voice == Voice.v4)
          .pitches,
      hasLength(1),
    );
    await tester.scrollUntilVisible(
      find.byTooltip('Menu'),
      250,
      scrollable: find.descendant(
        of: find.byType(ListView).last,
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Redo'));
    await tester.pumpAndSettle();
    expect(
      viewport().score.measures[0].events
          .singleWhere((e) => e.voice == Voice.v4)
          .pitches,
      hasLength(2),
    );
  });

  testWidgets('two-finger pan cancels entry and scrolls score', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    await tester.tap(find.text('V4'));
    await tester.pump();
    final canvas = find.byKey(const ValueKey('score-canvas'));
    final origin = tester.getTopLeft(canvas);
    final one = await tester.createGesture(pointer: 1);
    final two = await tester.createGesture(pointer: 2);
    await one.down(origin + const Offset(300, 100));
    await two.down(origin + const Offset(350, 100));
    await one.moveBy(const Offset(-100, 0));
    await two.moveBy(const Offset(-100, 0));
    await one.up();
    await two.up();
    await tester.pump();
    final viewport = tester.widget<ScoreViewport>(find.byType(ScoreViewport));
    expect(
      viewport.score.measures
          .expand((m) => m.events)
          .where((e) => e.voice == Voice.v4),
      isEmpty,
    );
    expect(tester.getTopLeft(canvas).dx, lessThan(origin.dx));
  });

  testWidgets(
    'a newly entered rest advances time; an explicitly selected rest can be filled',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const ClavieraApp());
      await tester.tap(find.text('V4'));
      await tester.tap(find.byTooltip('Note'));
      await tester.pump();
      final origin = tester.getTopLeft(
        find.byKey(const ValueKey('score-canvas')),
      );
      await tester.tapAt(origin + const Offset(160, 115));
      await tester.pump();
      await tester.tap(find.byTooltip('Rest'));
      await tester.pump();
      await tester.tapAt(origin + const Offset(170, 115));
      await tester.pump();
      ScoreViewport viewport() =>
          tester.widget<ScoreViewport>(find.byType(ScoreViewport));
      List<NotationEvent> events() =>
          viewport().score.measures[0].events
              .where((e) => e.voice == Voice.v4)
              .toList()
            ..sort((a, b) => a.startTick.compareTo(b.startTick));
      expect(
        events().map((e) => (e.startTick, e.durationTicks, e.isRest)).toList(),
        [(0, 960, true), (960, 960, false)],
      );

      await tester.tap(find.byTooltip('Write mode'));
      await tester.pump();
      await tester.tapAt(origin + const Offset(160, 100));
      await tester.pump();
      await tester.tap(find.byTooltip('Edit mode'));
      await tester.pump();
      await tester.tap(find.byTooltip('half note'));
      await tester.pump();
      await tester.tapAt(origin + const Offset(160, 115));
      await tester.pump();
      expect(
        find.text('The note is longer than the selected rest.'),
        findsOneWidget,
      );
      expect(events().first.isRest, isTrue);
      await tester.tap(find.byTooltip('eighth note'));
      await tester.pump();
      await tester.tapAt(origin + const Offset(160, 115));
      await tester.pump();
      expect(
        events().map((e) => (e.startTick, e.durationTicks, e.isRest)).toList(),
        [(0, 480, false), (480, 480, true), (960, 960, false)],
      );
    },
  );

  testWidgets(
    'edit mode moves pitch and changes duration without shifting notes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const ClavieraApp());
      await tester.tap(find.text('V4'));
      await tester.pump();
      final canvas = find.byKey(const ValueKey('score-canvas'));
      final origin = tester.getTopLeft(canvas);
      await tester.tapAt(origin + const Offset(160, 115));
      await tester.tapAt(origin + const Offset(215, 115));
      await tester.pump();
      await tester.tap(find.byTooltip('Write mode'));
      await tester.pump();
      await tester.dragFrom(
        origin + const Offset(160, 115),
        const Offset(0, -10),
      );
      await tester.pump();
      ScoreViewport viewport() =>
          tester.widget<ScoreViewport>(find.byType(ScoreViewport));
      expect(viewport().selectedEvent!.pitches.single.diatonicStep, 33);
      await tester.tap(find.byTooltip('eighth note'));
      await tester.pump();
      final events =
          viewport().score.measures[0].events
              .where((e) => e.voice == Voice.v4)
              .toList()
            ..sort((a, b) => a.startTick.compareTo(b.startTick));
      expect(
        events.map((e) => (e.startTick, e.durationTicks, e.isRest)).toList(),
        [(0, 480, false), (480, 480, true), (960, 960, false)],
      );
    },
  );

  testWidgets('choose an earlier bar, clear it and write without a rest', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    await tester.tap(find.text('V4'));
    await tester.tap(find.byTooltip('Next bar'));
    await tester.pump();
    expect(find.text('Bar 2'), findsOneWidget);
    final canvas = find.byKey(const ValueKey('score-canvas'));
    Offset point(double x) => tester.getTopLeft(canvas) + Offset(x, 115);
    await tester.tapAt(point(440));
    await tester.pump();
    await tester.tap(find.byTooltip('Previous bar'));
    await tester.pump();
    await tester.tapAt(point(160));
    await tester.pump();
    await tester.tap(find.byTooltip('Write mode'));
    await tester.pump();
    await tester.tapAt(point(160));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byTooltip('Delete'),
      250,
      scrollable: find.descendant(
        of: find.byType(ListView).last,
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byTooltip('Delete'));
    await tester.pump();
    ScoreViewport viewport() =>
        tester.widget<ScoreViewport>(find.byType(ScoreViewport));
    expect(
      viewport().score.measures[0].events.where((e) => e.voice == Voice.v4),
      isEmpty,
    );
    expect(
      viewport().score.measures[1].events.where((e) => e.voice == Voice.v4),
      hasLength(1),
    );
    await tester.tap(find.byTooltip('Edit mode'));
    await tester.pump();
    expect(viewport().cursorTick, 0);
    await tester.tapAt(point(160));
    await tester.pump();
    expect(
      viewport().score.measures[0].events.where((e) => e.voice == Voice.v4),
      hasLength(1),
    );
    expect(
      viewport().score.measures[1].events.where((e) => e.voice == Voice.v4),
      hasLength(1),
    );
  });
}
