import 'package:claviera/main.dart';
import 'package:claviera/models/score.dart';
import 'package:claviera/notation/beaming.dart';
import 'package:claviera/notation/score_painter.dart';
import 'package:claviera/notation/score_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('top menu shows the app icon in landscape', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in [const Size(568, 320), const Size(1000, 700)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(const ClavieraApp());
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName ==
                  'assets/icons/claviera_icon.png',
        ),
        findsOneWidget,
      );
      expect(find.text('CLAVIERA'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('app icon opens About and licenses in landscape', (tester) async {
    await tester.binding.setSurfaceSize(const Size(568, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    await tester.tap(find.byTooltip('About Claviera'));
    await tester.pumpAndSettle();
    expect(find.text('Claviera'), findsOneWidget);
    expect(
      find.text('A piano score sketchpad for writing and playing music.'),
      findsOneWidget,
    );
    await tester.tap(find.text('View licenses'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bar menu adds, copies and inserts bars', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    ScoreViewport viewport() =>
        tester.widget<ScoreViewport>(find.byType(ScoreViewport));
    Future<void> openBarEditor() async {
      await tester.tap(find.byTooltip('Bar menu'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Edit bars'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit bars'));
      await tester.pumpAndSettle();
    }

    await openBarEditor();
    await tester.enterText(find.byType(TextFormField), '2');
    await tester.tap(find.text('Add at end'));
    await tester.pumpAndSettle();
    expect(viewport().score.measures, hasLength(6));
    expect(find.text('Bar 5'), findsOneWidget);
    await openBarEditor();
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    await openBarEditor();
    await tester.tap(find.text('Paste before'));
    await tester.pumpAndSettle();
    expect(viewport().score.measures, hasLength(7));
    expect(find.text('Bar 5'), findsOneWidget);
  });

  testWidgets('bar editing fits on a phone and confirms deletion', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(568, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    await tester.tap(find.byTooltip('Bar menu'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Edit bars'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit bars'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete bars?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ScoreViewport>(find.byType(ScoreViewport)).score.measures,
      hasLength(4),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('getting started is accessible and scrollable in landscape', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(568, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    final canvas = find.byKey(const ValueKey('score-canvas'));
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(160, 115));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byTooltip('Menu'),
      200,
      scrollable: find.descendant(
        of: find.byType(ListView).last,
        matching: find.byType(Scrollable),
      ),
    );
    await tester.ensureVisible(find.byTooltip('Menu'));
    await tester.pump();
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    final upgrade = find.byTooltip('Upgrade to Pro');
    final gettingStarted = find.ancestor(
      of: find.text('Getting started'),
      matching: find.byType(TextButton),
    );
    expect(
      tester.getTopLeft(gettingStarted).dx - tester.getTopRight(upgrade).dx,
      greaterThanOrEqualTo(16),
    );
    await tester.tap(find.text('Getting started'));
    await tester.pumpAndSettle();
    expect(find.text('Write mode / Edit mode'), findsOneWidget);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(
      (await SharedPreferences.getInstance()).getBool(
        'claviera.gettingStarted.hidden',
      ),
      isTrue,
    );
    await tester.ensureVisible(find.text('Save and back up'));
    await tester.pumpAndSettle();
    expect(find.text('Save and back up'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ScoreViewport>(find.byType(ScoreViewport))
          .score
          .measures
          .first
          .events,
      hasLength(1),
    );
  });

  testWidgets('user manual opens from menu and scrolls on a phone', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(568, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    final canvas = find.byKey(const ValueKey('score-canvas'));
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(160, 115));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byTooltip('Menu'),
      200,
      scrollable: find.descendant(
        of: find.byType(ListView).last,
        matching: find.byType(Scrollable),
      ),
    );
    await tester.ensureVisible(find.byTooltip('Menu'));
    await tester.pump();
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('User manual'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(
      find.descendant(of: dialog, matching: find.text('Getting around')),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Articulation palette (Pro)'));
    await tester.pumpAndSettle();
    expect(find.text('Fermata'), findsOneWidget);
    await tester.ensureVisible(find.text('Export MusicXML (Pro)'));
    await tester.pumpAndSettle();
    expect(find.text('Lock'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      tester
          .widget<ScoreViewport>(find.byType(ScoreViewport))
          .score
          .measures
          .first
          .events,
      hasLength(1),
    );
  });

  testWidgets('ornaments are available on notes and replace each other', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(568, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    final canvas = find.byKey(const ValueKey('score-canvas'));
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(160, 115));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byTooltip('Articulations'),
      200,
      scrollable: find.descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byTooltip('Articulations'));
    await tester.pumpAndSettle();
    Finder chip(String label) => find.byWidgetPredicate(
      (widget) =>
          widget is FilterChip &&
          widget.label is Text &&
          (widget.label as Text).textSpan!.toPlainText().contains(' $label'),
    );
    for (final name in [
      'Trill',
      'Upper mordent',
      'Lower mordent',
      'Turn',
      'Inverted turn',
    ]) {
      expect(chip(name), findsOneWidget);
    }
    await tester.ensureVisible(chip('Trill'));
    await tester.pumpAndSettle();
    await tester.tap(chip('Trill'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(chip('Lower mordent'));
    await tester.pumpAndSettle();
    await tester.tap(chip('Lower mordent'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(chip('Trill')).selected, isFalse);
    expect(tester.widget<FilterChip>(chip('Lower mordent')).selected, isTrue);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ScoreViewport>(find.byType(ScoreViewport))
          .selectedEvent!
          .articulations,
      {Articulation.lowerMordent},
    );
  });

  testWidgets('arpeggio can combine single notes in different voices', (
    tester,
  ) async {
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
      (widget) =>
          widget is FilterChip &&
          widget.label is Text &&
          (widget.label as Text).textSpan!.toPlainText() == 'Arpeggio up',
    );
    await tester.ensureVisible(up);
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(up).onSelected, isNotNull);
    await tester.tap(up);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    final score = tester
        .widget<ScoreViewport>(find.byType(ScoreViewport))
        .score;
    expect(score.measures.first.arpeggios, {0: ArpeggioDirection.up});
    expect(
      score.measures.first.events.where((event) => !event.isRest),
      hasLength(2),
    );
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

  testWidgets('ties work from both Write and Edit modes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(568, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    final canvas = find.byKey(const ValueKey('score-canvas'));
    final leftScroll = find.descendant(
      of: find.byType(ListView).first,
      matching: find.byType(Scrollable),
    );
    List<NotationEvent> notes() => tester
        .widget<ScoreViewport>(find.byType(ScoreViewport))
        .score
        .measures
        .expand((measure) => measure.events)
        .where((event) => event.voice == Voice.v1 && !event.isRest)
        .toList();

    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(160, 115));
    await tester.pump();
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(160, 115));
    await tester.pump();
    expect(notes(), hasLength(2));
    expect(notes().first.tieToNext, isFalse);

    await tester.scrollUntilVisible(
      find.byTooltip('Write mode'),
      -200,
      scrollable: leftScroll,
    );
    await tester.tap(find.byTooltip('Write mode'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byTooltip('Tie to previous note'),
      200,
      scrollable: leftScroll,
    );
    await tester.tap(find.byTooltip('Tie to previous note'));
    await tester.pump();
    expect(notes().first.tieToNext, isTrue);
    expect(notes().last.tieFromPrevious, isTrue);

    await tester.scrollUntilVisible(
      find.byTooltip('Edit mode'),
      -200,
      scrollable: leftScroll,
    );
    await tester.tap(find.byTooltip('Edit mode'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byTooltip('Tie next note'),
      200,
      scrollable: leftScroll,
    );
    await tester.tap(find.byTooltip('Tie next note'));
    await tester.pump();
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(160, 115));
    await tester.pump();

    expect(notes(), hasLength(3));
    expect(notes()[1].tieToNext, isTrue);
    expect(notes()[2].tieFromPrevious, isTrue);
    expect(tester.takeException(), isNull);
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

  testWidgets('rest entry follows the voice and remains selectable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    ScoreViewport viewport() =>
        tester.widget<ScoreViewport>(find.byType(ScoreViewport));
    final origin = tester.getTopLeft(
      find.byKey(const ValueKey('score-canvas')),
    );
    await tester.tap(find.byTooltip('Note'));
    await tester.pump();
    for (final voice in Voice.values) {
      await tester.tap(find.text('V${voice.index + 1}'));
      await tester.pump();
      final y = voice.index < 2 ? 215.0 : 115.0;
      await tester.tapAt(origin + Offset(160, y));
      await tester.pump();
      final event = viewport().score.measures.first.events.singleWhere(
        (event) => event.voice == voice,
      );
      expect(event.isRest, isTrue);
      expect(event.staff, voice.index < 2 ? Staff.treble : Staff.bass);
    }

    await tester.tap(find.byTooltip('Write mode'));
    await tester.pump();
    await tester.tapAt(origin + const Offset(160, 258));
    await tester.pump();
    expect(viewport().selectedEvent?.voice, Voice.v4);
    expect(viewport().selectedEvent?.isRest, isTrue);
    await tester.tap(find.byTooltip('Edit mode'));
    await tester.tap(find.byTooltip('Rest'));
    await tester.pump();
    await tester.tapAt(origin + const Offset(160, 115));
    await tester.pump();
    final replacement = viewport().score.measures.first.events.singleWhere(
      (event) => event.voice == Voice.v4,
    );
    expect(replacement.isRest, isFalse);
    expect(replacement.staff, Staff.treble);
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
    await tester.scrollUntilVisible(
      find.byTooltip('Chord stack'),
      200,
      scrollable: find.descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      ),
    );
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
    await tester.ensureVisible(find.byTooltip('Menu'));
    await tester.pump();
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

  testWidgets('two-finger flings coast, stop on touch and respect edges', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    final scroll = tester
        .widgetList<SingleChildScrollView>(
          find.descendant(
            of: find.byType(ScoreViewport),
            matching: find.byType(SingleChildScrollView),
          ),
        )
        .singleWhere((view) => view.scrollDirection == Axis.horizontal)
        .controller!;
    final one = await tester.createGesture(pointer: 1);
    final two = await tester.createGesture(pointer: 2);
    Future<void> swipe(double delta, {bool pause = false}) async {
      final origin = tester.getTopLeft(find.byType(ScoreViewport));
      await one.down(origin + const Offset(450, 120));
      await two.down(
        origin + const Offset(500, 120),
        timeStamp: const Duration(milliseconds: 1),
      );
      for (var i = 0; i < 4; i++) {
        await one.moveBy(
          Offset(delta, 0),
          timeStamp: Duration(milliseconds: 10 + i * 20),
        );
        await two.moveBy(
          Offset(delta, 0),
          timeStamp: Duration(milliseconds: 10 + i * 20),
        );
      }
      await one.up(timeStamp: Duration(milliseconds: pause ? 300 : 82));
      await two.up(timeStamp: Duration(milliseconds: pause ? 302 : 84));
    }

    await swipe(-25);
    final released = scroll.offset;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(scroll.offset, greaterThan(released));
    final moving = scroll.offset;
    await tester.tapAt(tester.getCenter(find.byType(ScoreViewport)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(scroll.offset, closeTo(moving, 0.01));
    expect(
      tester
          .widget<ScoreViewport>(find.byType(ScoreViewport))
          .score
          .measures
          .expand((measure) => measure.events),
      isEmpty,
    );

    await swipe(25);
    final reverse = scroll.offset;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(scroll.offset, lessThan(reverse));
    await tester.tapAt(tester.getCenter(find.byType(ScoreViewport)));
    await tester.pump();
    await swipe(-25, pause: true);
    final stopped = scroll.offset;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(scroll.offset, stopped);

    final origin = tester.getTopLeft(find.byType(ScoreViewport));
    await one.down(origin + const Offset(450, 120));
    await two.down(
      origin + const Offset(500, 120),
      timeStamp: const Duration(milliseconds: 1),
    );
    await one.moveBy(
      const Offset(-30, 0),
      timeStamp: const Duration(milliseconds: 10),
    );
    await two.moveBy(
      const Offset(-30, 0),
      timeStamp: const Duration(milliseconds: 20),
    );
    await one.cancel(timeStamp: const Duration(milliseconds: 30));
    await two.up(timeStamp: const Duration(milliseconds: 40));
    final cancelled = scroll.offset;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(scroll.offset, cancelled);

    scroll.jumpTo(scroll.position.maxScrollExtent - 5);
    await swipe(-25);
    await tester.pumpAndSettle();
    expect(scroll.offset, scroll.position.maxScrollExtent);
    scroll.jumpTo(5);
    await swipe(25);
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
  });

  testWidgets('go to bar fits in compact landscape', (tester) async {
    await tester.binding.setSurfaceSize(const Size(568, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    await tester.tap(find.byTooltip('Bar menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go to bar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '4');
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ScoreViewport>(find.byType(ScoreViewport)).selectedMeasure,
      3,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('go to bar validates and reveals even the current bar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    ScoreViewport viewport() =>
        tester.widget<ScoreViewport>(find.byType(ScoreViewport));
    await tester.tap(find.byTooltip('Bar menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit bars'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '96');
    await tester.tap(find.text('Add at end'));
    await tester.pumpAndSettle();
    expect(viewport().score.measures, hasLength(100));

    Future<void> openGoToBar() async {
      await tester.tap(find.byTooltip('Bar menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go to bar'));
      await tester.pumpAndSettle();
    }

    await openGoToBar();
    for (final invalid in ['', '0', '101', 'abc']) {
      await tester.enterText(find.byType(TextFormField), invalid);
      await tester.tap(find.text('Go'));
      await tester.pump();
      expect(find.text('Enter a bar from 1 to 100.'), findsOneWidget);
      expect(viewport().selectedMeasure, 4);
    }
    await tester.enterText(find.byType(TextFormField), '98');
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(viewport().selectedMeasure, 97);
    final scroll = tester
        .widgetList<SingleChildScrollView>(
          find.descendant(
            of: find.byType(ScoreViewport),
            matching: find.byType(SingleChildScrollView),
          ),
        )
        .singleWhere((view) => view.scrollDirection == Axis.horizontal)
        .controller!;
    final barX = ScorePainter.barX(viewport().score, 97, 10);
    expect(barX, greaterThanOrEqualTo(scroll.offset));
    expect(
      barX + 280,
      lessThanOrEqualTo(scroll.offset + scroll.position.viewportDimension),
    );

    final canvas = find.byKey(const ValueKey('score-canvas'));
    await tester.tapAt(tester.getTopLeft(canvas) + Offset(barX + 30, 115));
    await tester.pump();
    expect(viewport().score.measures[97].events, hasLength(1));
    scroll.jumpTo(0);
    await tester.pump();
    await openGoToBar();
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(viewport().selectedMeasure, 97);
    expect(scroll.offset, greaterThan(0));
    expect(viewport().score.measures[97].events, hasLength(1));
    expect(viewport().selectedEvent, isNull);
    await openGoToBar();
    await tester.enterText(find.byType(TextFormField), '1');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(viewport().selectedMeasure, 97);
    await openGoToBar();
    await tester.enterText(find.byType(TextFormField), '100');
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(viewport().selectedMeasure, 99);
    expect(scroll.offset, scroll.position.maxScrollExtent);
    for (final width in [568.0, 680.0, 760.0, 900.0, 1000.0, 1060.0]) {
      await tester.binding.setSurfaceSize(Size(width, 320));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'Width $width');
      expect(find.byTooltip('Go to end'), findsOneWidget);
    }
    await openGoToBar();
    await tester.enterText(find.byType(TextFormField), '1');
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(viewport().selectedMeasure, 0);
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
      await tester.tapAt(origin + const Offset(160, 230));
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
