import 'package:claviera/main.dart';
import 'package:claviera/models/score.dart';
import 'package:claviera/notation/beaming.dart';
import 'package:claviera/notation/score_painter.dart';
import 'package:claviera/notation/score_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('arpeggio can combine single notes in different voices', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    final canvas = find.byKey(const ValueKey('score-canvas'));
    final origin = tester.getTopLeft(canvas);
    await tester.tapAt(origin + const Offset(160, 115));
    await tester.pump();
    await tester.tap(find.text('V2'));
    await tester.pump();
    await tester.tapAt(origin + const Offset(160, 230));
    await tester.pump();
    await tester.tap(find.byTooltip('Articulations'));
    await tester.pumpAndSettle();
    final up = find.byWidgetPredicate(
      (widget) => widget is FilterChip && widget.label is Text &&
          (widget.label as Text).textSpan!.toPlainText() == 'Arpeggio up',
    );
    await tester.ensureVisible(up);
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(up).onSelected, isNotNull);
    await tester.tap(up);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    final score = tester.widget<ScoreViewport>(find.byType(ScoreViewport)).score;
    expect(score.measures.first.arpeggios, {0: ArpeggioDirection.up});
    expect(score.measures.first.events.where((event) => !event.isRest), hasLength(2));
  });

  testWidgets('arpeggio requires simultaneous notes and can change direction', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    final canvas = find.byKey(const ValueKey('score-canvas'));
    final origin = tester.getTopLeft(canvas);
    await tester.tapAt(origin + const Offset(160, 115));
    await tester.pump();
    Finder chip(String label) => find.byWidgetPredicate(
      (widget) =>
          widget is FilterChip &&
          widget.label is Text &&
          (widget.label as Text).textSpan!.toPlainText() == label,
    );
    await tester.tap(find.byTooltip('Articulations'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(chip('Arpeggio up'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(chip('Arpeggio up')).onSelected, isNull);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Chord stack'));
    await tester.tapAt(origin + const Offset(160, 105));
    await tester.pump();
    await tester.tap(find.byTooltip('Articulations'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(chip('Arpeggio up'));
    await tester.pumpAndSettle();
    await tester.tap(chip('Arpeggio up'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(chip('Arpeggio up')).selected, isTrue);
    await tester.tap(chip('Arpeggio down'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(chip('Arpeggio up')).selected, isFalse);
    expect(tester.widget<FilterChip>(chip('Arpeggio down')).selected, isTrue);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    final viewport = tester.widget<ScoreViewport>(find.byType(ScoreViewport));
    expect(viewport.score.measures.first.arpeggios, {
      0: ArpeggioDirection.down,
    });
  });

  testWidgets(
    'fermata can be toggled on a rest without offering note accents',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const ClavieraApp());
      await tester.tap(find.byTooltip('Note'));
      await tester.pump();
      final canvas = find.byKey(const ValueKey('score-canvas'));
      await tester.tapAt(tester.getTopLeft(canvas) + const Offset(160, 115));
      await tester.pump();
      await tester.tap(find.byTooltip('Articulations'));
      await tester.pumpAndSettle();
      final fermata = find.byWidgetPredicate(
        (widget) =>
            widget is FilterChip &&
            widget.label is Text &&
            (widget.label as Text).textSpan!.toPlainText().contains('Fermata'),
      );
      expect(fermata, findsOneWidget);
      expect(find.byType(FilterChip), findsOneWidget);
      await tester.tap(fermata);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(fermata).selected, isTrue);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ScoreViewport>(find.byType(ScoreViewport))
            .selectedEvent!
            .articulations,
        {Articulation.fermata},
      );
      await tester.tap(find.byTooltip('Articulations'));
      await tester.pumpAndSettle();
      await tester.tap(fermata);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(fermata).selected, isFalse);
    },
  );

  testWidgets('dot button cycles note values and respects short-note limits', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    final dot = find.byTooltip('Dot');
    final canvas = find.byKey(const ValueKey('score-canvas'));
    ScoreViewport viewport() =>
        tester.widget<ScoreViewport>(find.byType(ScoreViewport));
    await tester.tap(dot);
    await tester.tap(dot);
    await tester.pump();
    expect(find.text('\u2022 \u2022'), findsOneWidget);
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(160, 115));
    await tester.pump();
    expect(viewport().selectedEvent!.durationTicks, 1680);
    expect(viewport().cursorTick, 1680);
    await tester.tap(find.byTooltip('thirtySecond note'));
    await tester.pump();
    expect(find.text('\u2022 \u2022'), findsNothing);
    await tester.tap(find.byTooltip('sixtyFourth note'));
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(
            find.descendant(of: dot, matching: find.byType(TextButton)),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('Write mode'));
    await tester.pump();
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(160, 115));
    await tester.pump();
    expect(find.text('\u2022 \u2022'), findsOneWidget);
    await tester.tap(dot);
    await tester.pump();
    expect(viewport().selectedEvent!.durationTicks, 960);
    await tester.tap(dot);
    await tester.pump();
    expect(viewport().selectedEvent!.durationTicks, 1440);
    await tester.tap(dot);
    await tester.pump();
    expect(viewport().selectedEvent!.durationTicks, 1680);
  });

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

  testWidgets(
    'articulations are below chord stack and toggle compatible marks',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(568, 320));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const ClavieraApp());
      final canvas = find.byKey(const ValueKey('score-canvas'));
      await tester.tapAt(tester.getTopLeft(canvas) + const Offset(160, 115));
      await tester.pump();
      final leftScroll = find.descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.byTooltip('Articulations'),
        200,
        scrollable: leftScroll,
      );
      expect(
        tester.getCenter(find.byTooltip('Articulations')).dy,
        greaterThan(tester.getCenter(find.byTooltip('Chord stack')).dy),
      );
      await tester.tap(find.byTooltip('Articulations'));
      await tester.pumpAndSettle();
      Finder chip(String label) => find.byWidgetPredicate(
        (widget) =>
            widget is FilterChip &&
            widget.label is Text &&
            (widget.label as Text).textSpan!.toPlainText().contains(label),
      );
      for (final label in [
        'Staccato',
        'Staccatissimo',
        'Tenuto',
        'Portato',
        'Accent',
        'Marcato',
      ]) {
        expect(chip(label).hitTestable(), findsOneWidget);
      }
      Future<void> tapChip(String label) async {
        await tester.ensureVisible(chip(label));
        await tester.pumpAndSettle();
        await tester.tap(chip(label));
        await tester.pumpAndSettle();
      }

      await tapChip('Portato');
      expect(tester.widget<FilterChip>(chip('Portato')).selected, isTrue);
      await tapChip('Accent');
      await tapChip('Marcato');
      expect(tester.widget<FilterChip>(chip('Accent')).selected, isFalse);
      expect(tester.widget<FilterChip>(chip('Marcato')).selected, isTrue);
      await tapChip('Staccatissimo');
      expect(tester.widget<FilterChip>(chip('Portato')).selected, isFalse);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      final event = tester
          .widget<ScoreViewport>(find.byType(ScoreViewport))
          .selectedEvent!;
      expect(event.articulations, {
        Articulation.staccatissimo,
        Articulation.marcato,
      });
      await tester.scrollUntilVisible(
        find.byTooltip('Undo'),
        200,
        scrollable: find.descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(
        tester
            .widget<ScoreViewport>(find.byType(ScoreViewport))
            .score
            .measures[0]
            .events
            .firstWhere((event) => !event.isRest)
            .articulations,
        {Articulation.staccato, Articulation.tenuto, Articulation.marcato},
      );
    },
  );

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

  testWidgets('edit taps select a bar and select a note with its bar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    final canvas = find.byKey(const ValueKey('score-canvas'));
    Offset origin() => tester.getTopLeft(canvas);
    ScoreViewport viewport() =>
        tester.widget<ScoreViewport>(find.byType(ScoreViewport));
    await tester.tapAt(origin() + const Offset(160, 115));
    await tester.pump();
    await tester.tap(find.byTooltip('Next bar'));
    await tester.pumpAndSettle();
    await tester.tapAt(origin() + const Offset(160, 115));
    await tester.pump();
    final barTwoNote = viewport().selectedEvent!.eventId;
    await tester.tap(find.byTooltip('Write mode'));
    await tester.pump();
    await tester.tapAt(origin() + const Offset(250, 150));
    await tester.pump();
    expect(viewport().selectedMeasure, 0);
    expect(viewport().selectedEvent, isNull);
    await tester.tapAt(origin() + const Offset(440, 115));
    await tester.pump();
    expect(viewport().selectedMeasure, 1);
    expect(viewport().selectedEvent!.eventId, barTwoNote);
    expect(
      viewport().score.measures[0].events.where((e) => !e.isRest),
      hasLength(1),
    );
    expect(
      viewport().score.measures[1].events.where((e) => !e.isRest),
      hasLength(1),
    );
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
