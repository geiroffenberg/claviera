import 'package:claviera/models/score.dart';
import 'package:claviera/notation/score_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('only a final system draws a final barline', (tester) async {
    const score = Score(
      title: 'Bars',
      beatsPerMeasure: 4,
      beatUnit: 4,
      measures: [Measure()],
    );
    int lineCount(bool finalBar) {
      final canvas = TestRecordingCanvas();
      ScorePainter(
        score: score,
        selectedEvent: null,
        selectedPitch: 0,
        showFinalBarline: finalBar,
      ).paint(
        canvas,
        Size(ScorePainter.widthFor(score, 10), ScorePainter.heightFor(10)),
      );
      return canvas.invocations
          .where((call) => call.invocation.memberName == #drawLine)
          .length;
    }

    expect(lineCount(true), lineCount(false) + 1);
  });

  testWidgets('a number is painted above every starting barline', (
    tester,
  ) async {
    final score = Score(
      title: 'Bars',
      beatsPerMeasure: 4,
      beatUnit: 4,
      measures: List.generate(12, (_) => const Measure()),
    );
    final canvas = TestRecordingCanvas();
    ScorePainter(score: score, selectedEvent: null, selectedPitch: 0).paint(
      canvas,
      Size(ScorePainter.widthFor(score, 10), ScorePainter.heightFor(10)),
    );
    final offsets = canvas.invocations
        .where((call) => call.invocation.memberName == #drawParagraph)
        .map((call) => call.invocation.positionalArguments[1] as Offset)
        .where((offset) => offset.dy == 55)
        .toList();
    expect(offsets, hasLength(12));
    for (var measure = 0; measure < offsets.length; measure++) {
      final barlineX = (13 + measure * 28) * 10.0;
      expect(offsets[measure].dx, inInclusiveRange(barlineX - 20, barlineX));
    }
  });
}
