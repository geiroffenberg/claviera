import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:claviera/main.dart';
import 'package:claviera/models/blank_score.dart';
import 'package:claviera/models/score.dart';
import 'package:claviera/notation/score_painter.dart';
import 'package:claviera/notation/score_viewport.dart';
import 'package:claviera/ui/workspace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

List<double> previewLedgerLines(ScorePainter painter) {
  final canvas = TestRecordingCanvas();
  painter.paint(canvas, const Size(1270, 320));
  return canvas.invocations
      .where((call) => call.invocation.memberName == #drawLine)
      .map((call) => call.invocation.positionalArguments)
      .where((args) {
        final start = args[0] as Offset;
        final end = args[1] as Offset;
        return start.dx == 156.5 && end.dx == 176 && start.dy == end.dy;
      })
      .map((args) => (args[0] as Offset).dy)
      .toList();
}

void main() {
  testWidgets('ledger lines occur only at the required positions', (
    tester,
  ) async {
    ScorePainter painter(int step) => ScorePainter(
      score: blankScore,
      selectedEvent: null,
      selectedPitch: 0,
      cursorTick: 0,
      previewStaff: Staff.treble,
      previewPitch: Pitch(diatonicStep: step, midiNote: 60),
    );

    expect(previewLedgerLines(painter(30)), isEmpty);
    expect(previewLedgerLines(painter(29)), isEmpty);
    expect(previewLedgerLines(painter(28)), [130]);
    expect(previewLedgerLines(painter(25)), [130, 140]);
    expect(previewLedgerLines(painter(39)), isEmpty);
    expect(previewLedgerLines(painter(40)), [70]);
  });

  testWidgets('writing preview removes ledger lines when dragged back', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    final canvas = find.byKey(const ValueKey('score-canvas'));
    final origin = tester.getTopLeft(canvas);
    final gesture = await tester.startGesture(origin + const Offset(160, 115));
    await gesture.moveTo(origin + const Offset(160, 315));
    await tester.pump();
    ScorePainter painter() =>
        tester
                .widget<CustomPaint>(
                  find
                      .descendant(
                        of: canvas,
                        matching: find.byType(CustomPaint),
                      )
                      .first,
                )
                .painter!
            as ScorePainter;
    expect(previewLedgerLines(painter()), isNotEmpty);
    expect(
      find.descendant(of: canvas, matching: find.byType(ClipRect)),
      findsOneWidget,
    );
    await gesture.moveTo(origin + const Offset(160, 115));
    await tester.pump();
    expect(previewLedgerLines(painter()), isEmpty);
    await gesture.up();
    await tester.pump();
    final viewport = tester.widget<ScoreViewport>(find.byType(ScoreViewport));
    expect(viewport.previewPitch, isNull);
    expect(viewport.selectedEvent!.pitches.single.diatonicStep, 31);
  });

  testWidgets('edit preview follows the finger back to its starting pitch', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    final origin = tester.getTopLeft(
      find.byKey(const ValueKey('score-canvas')),
    );
    await tester.tapAt(origin + const Offset(160, 115));
    await tester.pump();
    await tester.tap(find.byTooltip('Write mode'));
    await tester.pump();
    final gesture = await tester.startGesture(origin + const Offset(160, 115));
    await gesture.moveTo(origin + const Offset(160, 200));
    await tester.pump();
    ScoreViewport viewport() =>
        tester.widget<ScoreViewport>(find.byType(ScoreViewport));
    expect(viewport().previewPitch!.diatonicStep, lessThan(30));
    await gesture.moveTo(origin + const Offset(160, 115));
    await tester.pump();
    expect(viewport().previewPitch!.diatonicStep, 31);
    await gesture.up();
    await tester.pump();
    expect(viewport().selectedEvent!.pitches.single.diatonicStep, 31);
    expect(viewport().previewPitch, isNull);
  });

  testWidgets(
    'writing switches staff while dragging and removes old ledger lines',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const ClavieraApp());
      final canvas = find.byKey(const ValueKey('score-canvas'));
      final origin = tester.getTopLeft(canvas);
      ScoreViewport viewport() =>
          tester.widget<ScoreViewport>(find.byType(ScoreViewport));
      ScorePainter painter() =>
          tester
                  .widget<CustomPaint>(
                    find
                        .descendant(
                          of: canvas,
                          matching: find.byType(CustomPaint),
                        )
                        .first,
                  )
                  .painter!
              as ScorePainter;

      final gesture = await tester.startGesture(
        origin + const Offset(160, 115),
      );
      await gesture.moveTo(origin + const Offset(160, 130));
      await tester.pump();
      expect(viewport().previewStaff, Staff.treble);
      expect(previewLedgerLines(painter()), [130]);

      await gesture.moveTo(origin + const Offset(160, 215));
      await tester.pump();
      expect(viewport().previewStaff, Staff.bass);
      expect(previewLedgerLines(painter()), isEmpty);

      await gesture.moveTo(origin + const Offset(160, 270));
      await tester.pump();
      expect(previewLedgerLines(painter()), [250, 260, 270]);
      await gesture.moveTo(origin + const Offset(160, 105));
      await tester.pump();
      expect(viewport().previewStaff, Staff.treble);
      expect(previewLedgerLines(painter()), isEmpty);
      await gesture.moveTo(origin + const Offset(160, 215));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(viewport().selectedEvent!.staff, Staff.bass);
      expect(viewport().selectedEvent!.pitches.single.diatonicStep, 23);
      expect(previewLedgerLines(painter()), isEmpty);
    },
  );

  testWidgets('chord stack keeps the selected event on its original staff', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ClavieraApp());
    final origin = tester.getTopLeft(
      find.byKey(const ValueKey('score-canvas')),
    );
    await tester.tapAt(origin + const Offset(160, 115));
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
    final gesture = await tester.startGesture(origin + const Offset(160, 115));
    await gesture.moveTo(origin + const Offset(160, 215));
    await tester.pump();
    final viewport = tester.widget<ScoreViewport>(find.byType(ScoreViewport));
    expect(viewport.previewStaff, Staff.treble);
    await gesture.up();
    await tester.pump();
    final event = tester
        .widget<ScoreViewport>(find.byType(ScoreViewport))
        .selectedEvent!;
    expect(event.staff, Staff.treble);
    expect(event.pitches, hasLength(2));
  });

  testWidgets(
    'rendered drag leaves no ghost lines after returning or placing',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const boundaryKey = ValueKey('render-check');
      Widget app() => const MaterialApp(
        home: RepaintBoundary(key: boundaryKey, child: WorkspaceScreen()),
      );
      await tester.pumpWidget(app());
      await tester.pump();
      final origin = tester.getTopLeft(
        find.byKey(const ValueKey('score-canvas')),
      );

      Future<Uint8List> captureRegion() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(boundaryKey),
        );
        final boundaryOrigin = tester.getTopLeft(find.byKey(boundaryKey));
        final left = (origin.dx - boundaryOrigin.dx + 152).round();
        final top = (origin.dy - boundaryOrigin.dy + 125).round();
        return tester
            .runAsync(() async {
              final image = await boundary.toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              final pixels = data!.buffer.asUint8List();
              final region = BytesBuilder();
              for (var y = top; y < top + 60; y++) {
                final start = (y * image.width + left) * 4;
                region.add(pixels.sublist(start, start + 30 * 4));
              }
              image.dispose();
              return region.takeBytes();
            })
            .then((result) => result!);
      }

      final gesture = await tester.startGesture(
        origin + const Offset(160, 115),
      );
      await tester.pump();
      final before = await captureRegion();
      await gesture.moveTo(origin + const Offset(160, 150));
      await tester.pump();
      final outside = await captureRegion();
      expect(outside, isNot(before));
      await gesture.moveTo(origin + const Offset(160, 115));
      await tester.pump();
      expect(await captureRegion(), orderedEquals(before));
      await gesture.up();
      await tester.pump();
      final placed = await captureRegion();

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await tester.pump();
      await tester.tapAt(origin + const Offset(160, 115));
      await tester.pump();
      expect(await captureRegion(), orderedEquals(placed));
    },
  );
}
