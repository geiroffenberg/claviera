import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/score.dart';
import 'score_painter.dart';

class PrintSystem {
  const PrintSystem(this.score, this.firstMeasure, this.top, this.height);
  final Score score;
  final int firstMeasure;
  final double top;
  final double height;
}

class PrintLayout {
  static const double pageWidth = 595;
  static const double pageHeight = 842;
  static const double margin = 36;
  static const double staffSpace = 4;

  static Score _slice(Score score, int first, int end) {
    final time = score.timeAt(first);
    final firstBar = score.measures[first];
    return Score(
      title: score.title,
      beatsPerMeasure: time.beats,
      beatUnit: time.unit,
      keySignature: score.keyAt(first),
      measures: [
        Measure(
          events: firstBar.events,
          tempo: firstBar.tempo,
          repeatStart: firstBar.repeatStart,
          repeatEnd: firstBar.repeatEnd,
        ),
        ...score.measures.skip(first + 1).take(end - first - 1),
      ],
    );
  }

  static List<PrintSystem> systems(Score score) {
    final systems = <PrintSystem>[];
    var first = 0;
    while (first < score.measures.length) {
      var end = first + 1;
      while (end < score.measures.length) {
        final candidate = _slice(score, first, end + 1);
        if (ScorePainter.widthFor(candidate, staffSpace) >
            pageWidth - 2 * margin) {
          break;
        }
        end++;
      }
      final system = _slice(score, first, end);
      if (ScorePainter.widthFor(system, staffSpace) > pageWidth - 2 * margin) {
        throw StateError('A bar is too wide to fit on a PDF page.');
      }
      var top = 0.0;
      var bottom = ScorePainter.heightFor(staffSpace);
      for (final measure in system.measures) {
        for (final event in measure.events) {
          for (final pitch in event.pitches) {
            final y = ScorePainter.pitchY(pitch, event.staff, staffSpace);
            top = math.min(top, y - 7 * staffSpace);
            bottom = math.max(bottom, y + 7 * staffSpace);
          }
        }
      }
      final height = bottom - top;
      if (height > pageHeight - 2 * margin - 30) {
        throw StateError('A system is too tall to fit on a PDF page.');
      }
      systems.add(PrintSystem(system, first, top, height));
      first = end;
    }
    return systems;
  }

  static Future<List<Uint8List>> render(
    Score score,
    String title, {
    int initialTempo = 120,
  }) async {
    final pages = <Uint8List>[];
    ui.PictureRecorder? recorder;
    Canvas? canvas;
    var y = 0.0;

    void startPage() {
      recorder = ui.PictureRecorder();
      canvas = Canvas(recorder!)..scale(2);
      canvas!.drawColor(Colors.white, BlendMode.src);
      y = margin;
      final text = TextPainter(
        text: TextSpan(
          text: pages.isEmpty ? title : '$title (continued)',
          style: const TextStyle(
            fontSize: 16,
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: pageWidth - 2 * margin);
      text.paint(canvas!, Offset(margin, y));
      y += 30;
      if (pages.isEmpty &&
          (score.measures.isEmpty || score.measures.first.tempo == null)) {
        final tempo = TextPainter(
          text: TextSpan(
            text: '♩ = $initialTempo',
            style: const TextStyle(fontSize: 11, color: Colors.black),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tempo.paint(canvas!, Offset(margin, y));
        y += 20;
      }
    }

    Future<void> finishPage() async {
      final picture = recorder!.endRecording();
      final image = await picture.toImage(
        (pageWidth * 2).toInt(),
        (pageHeight * 2).toInt(),
      );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      if (bytes == null) throw StateError('Could not render a PDF page.');
      pages.add(bytes.buffer.asUint8List());
    }

    startPage();
    for (final system in systems(score)) {
      if (y + system.height > pageHeight - margin) {
        await finishPage();
        startPage();
      }
      canvas!.save();
      canvas!.translate(margin, y - system.top);
      ScorePainter(
        score: system.score,
        selectedEvent: null,
        selectedPitch: 0,
        staffSpace: staffSpace,
        measureNumberOffset: system.firstMeasure,
      ).paint(
        canvas!,
        Size(ScorePainter.widthFor(system.score, staffSpace), system.height),
      );
      canvas!.restore();
      y += system.height + 16;
    }
    await finishPage();
    return pages;
  }
}
