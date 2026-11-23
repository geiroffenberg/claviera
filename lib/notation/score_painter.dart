import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/score.dart';
import 'beaming.dart';

/// Alternates displaced heads in each run of adjacent diatonic steps.
List<bool> secondOffsets(List<Pitch> pitches, {bool stemUp = true}) {
  final result = List<bool>.filled(pitches.length, false);
  final order = List<int>.generate(pitches.length, (i) => i)
    ..sort(
      (a, b) => stemUp
          ? pitches[a].diatonicStep.compareTo(pitches[b].diatonicStep)
          : pitches[b].diatonicStep.compareTo(pitches[a].diatonicStep),
    );
  for (var i = 1; i < order.length; i++) {
    final previous = order[i - 1];
    final current = order[i];
    if ((pitches[current].diatonicStep - pitches[previous].diatonicStep)
            .abs() ==
        1) {
      result[current] = !result[previous];
    }
  }
  return result;
}

class ScorePainter extends CustomPainter {
  ScorePainter({
    required this.score,
    required this.selectedEvent,
    required this.selectedPitch,
    this.selectedMeasure,
    this.cursorTick,
    this.playingSegments = const {},
    this.previewPitch,
    this.previewStaff,
    this.previewDuration = 960,
    this.previewVoice = Voice.v1,
    this.staffSpace = 10,
    this.measureNumberOffset = 0,
  });

  final Score score;
  final NotationEvent? selectedEvent;
  final int selectedPitch;
  final int? selectedMeasure;
  final int? cursorTick;
  final Set<PlaybackSegment> playingSegments;
  final Pitch? previewPitch;
  final Staff? previewStaff;
  final int previewDuration;
  final Voice previewVoice;
  final double staffSpace;
  final int measureNumberOffset;

  double get _s => staffSpace;
  double get _trebleTop => 8 * _s;
  double get _bassTop => 20 * _s;

  static double signatureSpace(Score score, int measure) {
    if (measure == 0) return score.measures[0].repeatStart ? 2 : 0;
    final bar = score.measures[measure];
    var width = bar.repeatStart ? 2.0 : 0.0;
    if (bar.keySignature != null) {
      final previous = score.keyAt(measure - 1);
      final next = score.keyAt(measure);
      final cancellations = List.generate(7, (i) => i)
          .where(
            (i) =>
                keyAlteration(previous, i) != 0 &&
                keyAlteration(previous, i) != keyAlteration(next, i),
          )
          .length;
      width += (cancellations + next.abs()) * .8 + 1;
    }
    if (bar.timeSignature != null) width += 3.5;
    return width;
  }

  static double barX(Score score, int measure, double s) {
    var x = startFor(score, s);
    for (var i = 0; i < measure; i++) {
      x += (28 + signatureSpace(score, i)) * s;
    }
    return x;
  }

  static double eventXFor(Score score, int measure, int tick, double s) =>
      barX(score, measure, s) +
      (signatureSpace(score, measure) +
              3 +
              tick / score.timeAt(measure).ticks * 23) *
          s;

  static double startFor(Score score, double s) =>
      (13 + score.keySignature.abs() * .8) * s;
  static double widthFor(Score score, double s) =>
      barX(score, score.measures.length, s) + 2 * s;
  static double heightFor(double s) => 32 * s;

  static TextPainter _dynamicText(DynamicMark mark, double s) => TextPainter(
    text: TextSpan(
      text: mark.name,
      style: TextStyle(
        fontFamily: 'serif',
        fontSize: 1.8 * s,
        fontWeight: FontWeight.bold,
        fontStyle: FontStyle.italic,
        color: const Color(0xff252c2a),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  static Rect dynamicBounds(Score score, int measure, int tick, double s) {
    final mark = score.measures[measure].dynamics[tick]!;
    final text = _dynamicText(mark, s);
    final x = eventXFor(score, measure, tick, s);
    return Rect.fromCenter(
      center: Offset(x, 16 * s),
      width: text.width,
      height: text.height,
    );
  }

  static Rect hairpinBounds(Score score, Hairpin hairpin, double s) {
    final total = score.measureStart(score.measures.length);
    double xAt(int tick) {
      if (tick >= total) return barX(score, score.measures.length, s) - .3 * s;
      final measure = score.measureAtTick(tick);
      return eventXFor(score, measure, tick - score.measureStart(measure), s);
    }

    final start = hairpin.start.clamp(0, total);
    final end = hairpin.end?.clamp(0, total);
    var left = xAt(start);
    var right = end == null ? left + 3 * s : xAt(end);
    if (hairpin.start >= 0 && start < total) {
      final measure = score.measureAtTick(start);
      final offset = start - score.measureStart(measure);
      if (score.measures[measure].dynamics.containsKey(offset)) {
        left += dynamicBounds(score, measure, offset, s).width / 2 + .3 * s;
      }
    }
    if (end != null && hairpin.end! < total) {
      final measure = score.measureAtTick(end);
      final offset = end - score.measureStart(measure);
      if (score.measures[measure].dynamics.containsKey(offset)) {
        right -= dynamicBounds(score, measure, offset, s).width / 2 + .3 * s;
      }
    }
    if (right < left + .6 * s) right = left + .6 * s;
    return Rect.fromLTRB(left, 17.3 * s, right, 18.7 * s);
  }

  static double eventX(
    int measure,
    int tick,
    int ticksPerMeasure,
    double s, {
    int keySignature = 0,
  }) =>
      (13 +
          keySignature.abs() * .8 +
          measure * 28 +
          3 +
          tick / ticksPerMeasure * 23) *
      s;

  static Staff staffAt(double y, double s) =>
      y < 16 * s ? Staff.treble : Staff.bass;

  static Pitch pitchAt(double y, Staff staff, double s) {
    final top = (staff == Staff.treble ? 8 : 20) * s;
    final bottom = staff == Staff.treble ? 30 : 18;
    final step = (bottom + ((top + 4 * s - y) / (s / 2)).round()).clamp(0, 67);
    const semitones = [0, 2, 4, 5, 7, 9, 11];
    return Pitch(
      diatonicStep: step,
      midiNote: 12 + (step ~/ 7) * 12 + semitones[step % 7],
    );
  }

  static List<String> articulationGlyphs(
    Set<Articulation> marks, {
    required bool above,
  }) {
    final below = above ? 0 : 1;
    final codes = <int>[];
    if (marks.contains(Articulation.staccato) &&
        marks.contains(Articulation.tenuto)) {
      codes.add(0xE4B2 + below);
    } else {
      if (marks.contains(Articulation.staccato)) codes.add(0xE4A2 + below);
      if (marks.contains(Articulation.tenuto)) codes.add(0xE4A4 + below);
    }
    if (marks.contains(Articulation.staccatissimo)) codes.add(0xE4A6 + below);
    if (marks.contains(Articulation.accent)) codes.add(0xE4A0 + below);
    if (marks.contains(Articulation.marcato)) codes.add(0xE4AC + below);
    return codes.map(String.fromCharCode).toList();
  }

  static double pitchY(Pitch pitch, Staff staff, double s) {
    final bottomStep = staff == Staff.treble ? 30 : 18;
    final top = (staff == Staff.treble ? 8 : 20) * s;
    return top + 4 * s - (pitch.diatonicStep - bottomStep) * s / 2;
  }

  void _glyph(
    Canvas canvas,
    String glyph,
    double x,
    double baseline, {
    Color color = const Color(0xff252c2a),
    double? size,
  }) {
    final text = TextPainter(
      text: TextSpan(
        text: glyph,
        style: TextStyle(
          fontFamily: 'Bravura',
          fontSize: size ?? 4 * _s,
          color: color,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(
      canvas,
      Offset(
        x,
        baseline -
            text.computeDistanceToActualBaseline(TextBaseline.alphabetic),
      ),
    );
  }

  void _timeNumber(Canvas canvas, int number, double x, double baseline) {
    for (final digit in number.toString().codeUnits) {
      _glyph(canvas, String.fromCharCode(0xE080 + digit - 0x30), x, baseline);
      x += 1.2 * _s;
    }
  }

  double _pitchY(Pitch pitch, Staff staff) {
    return pitchY(pitch, staff, _s);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..color = const Color(0xff333c39)
      ..strokeWidth = 1;
    final left = 2 * _s;
    final right = barX(score, score.measures.length, _s);
    if (selectedMeasure != null && selectedMeasure! < score.measures.length) {
      canvas.drawRect(
        Rect.fromLTWH(
          barX(score, selectedMeasure!, _s),
          _trebleTop - 3 * _s,
          (28 + signatureSpace(score, selectedMeasure!)) * _s,
          _bassTop - _trebleTop + 10 * _s,
        ),
        Paint()..color = const Color(0x0f1a8171),
      );
    }
    for (final top in [_trebleTop, _bassTop]) {
      for (var line = 0; line < 5; line++) {
        canvas.drawLine(
          Offset(left, top + line * _s),
          Offset(right, top + line * _s),
          ink,
        );
      }
    }
    canvas.drawLine(
      Offset(left, _trebleTop),
      Offset(left, _bassTop + 4 * _s),
      ink..strokeWidth = 2,
    );
    ink.strokeWidth = 1;
    _glyph(canvas, '\uE050', 3 * _s, _trebleTop + 3 * _s);
    _glyph(canvas, '\uE062', 3 * _s, _bassTop + _s);
    final signature = score.keySignature;
    const sharpTreble = [0.0, 1.5, -.5, 1.0, 2.5, .5, 2.0];
    const flatTreble = [2.0, .5, 2.5, 1.0, 3.0, 1.5, 3.5];
    const sharpBass = [1.0, 2.5, .5, 2.0, 3.5, 1.5, 3.0];
    const flatBass = [3.0, 1.5, 3.5, 2.0, 4.0, 2.5, 1.0];
    for (var i = 0; i < signature.abs(); i++) {
      final x = (7 + i * .8) * _s;
      final glyph = signature > 0 ? '\uE262' : '\uE260';
      _glyph(
        canvas,
        glyph,
        x,
        _trebleTop + (signature > 0 ? sharpTreble[i] : flatTreble[i]) * _s,
      );
      _glyph(
        canvas,
        glyph,
        x,
        _bassTop + (signature > 0 ? sharpBass[i] : flatBass[i]) * _s,
      );
    }
    for (final top in [_trebleTop, _bassTop]) {
      final x = (8 + signature.abs() * .8) * _s;
      _timeNumber(canvas, score.beatsPerMeasure, x, top + 2 * _s);
      _timeNumber(canvas, score.beatUnit, x, top + 4 * _s);
    }
    for (var m = 0; m <= score.measures.length; m++) {
      final x = barX(score, m, _s);
      canvas.drawLine(Offset(x, _trebleTop), Offset(x, _bassTop + 4 * _s), ink);
      final startRepeat =
          m < score.measures.length && score.measures[m].repeatStart;
      final endRepeat = m > 0 && score.measures[m - 1].repeatEnd;
      final repeatInk = Paint()..color = const Color(0xff333c39);
      if (startRepeat || endRepeat) {
        repeatInk.strokeWidth = 3;
        if (startRepeat) {
          canvas.drawLine(
            Offset(x + .4 * _s, _trebleTop),
            Offset(x + .4 * _s, _bassTop + 4 * _s),
            repeatInk,
          );
        }
        if (endRepeat) {
          canvas.drawLine(
            Offset(x - .4 * _s, _trebleTop),
            Offset(x - .4 * _s, _bassTop + 4 * _s),
            repeatInk,
          );
        }
        for (final top in [_trebleTop, _bassTop]) {
          for (final offset in [1.5, 2.5]) {
            if (startRepeat) {
              canvas.drawCircle(
                Offset(x + 1.15 * _s, top + offset * _s),
                .18 * _s,
                repeatInk,
              );
            }
            if (endRepeat) {
              canvas.drawCircle(
                Offset(x - 1.15 * _s, top + offset * _s),
                .18 * _s,
                repeatInk,
              );
            }
          }
        }
      }
      if (m < score.measures.length) {
        final number = TextPainter(
          text: TextSpan(
            text: '${m + 1 + measureNumberOffset}',
            style: TextStyle(
              color: const Color(0xff333c39),
              fontSize: 1.2 * _s,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        number.paint(
          canvas,
          Offset(x - number.width / 2, _trebleTop - 2.5 * _s),
        );
        final bpm = score.measures[m].tempo;
        if (bpm != null) {
          final marking = TextPainter(
            text: TextSpan(
              text: '♩ = $bpm',
              style: TextStyle(
                color: const Color(0xff333c39),
                fontSize: 1.2 * _s,
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          marking.paint(canvas, Offset(x + _s, _trebleTop - 4.5 * _s));
        }
      }
    }
    for (var m = 0; m < score.measures.length; m++) {
      if (m > 0) {
        final bar = score.measures[m];
        var x = barX(score, m, _s) + (bar.repeatStart ? 2.5 : .5) * _s;
        if (bar.keySignature != null) {
          final previous = score.keyAt(m - 1);
          final next = score.keyAt(m);
          final oldPositions = previous >= 0 ? sharpTreble : flatTreble;
          final oldBass = previous >= 0 ? sharpBass : flatBass;
          const sharps = [3, 0, 4, 1, 5, 2, 6];
          const flats = [6, 2, 5, 1, 4, 0, 3];
          final order = previous >= 0 ? sharps : flats;
          for (var i = 0; i < previous.abs(); i++) {
            if (keyAlteration(previous, order[i]) !=
                keyAlteration(next, order[i])) {
              _glyph(canvas, '\uE261', x, _trebleTop + oldPositions[i] * _s);
              _glyph(canvas, '\uE261', x, _bassTop + oldBass[i] * _s);
              x += .8 * _s;
            }
          }
          for (var i = 0; i < next.abs(); i++) {
            _glyph(
              canvas,
              next > 0 ? '\uE262' : '\uE260',
              x,
              _trebleTop + (next > 0 ? sharpTreble[i] : flatTreble[i]) * _s,
            );
            _glyph(
              canvas,
              next > 0 ? '\uE262' : '\uE260',
              x,
              _bassTop + (next > 0 ? sharpBass[i] : flatBass[i]) * _s,
            );
            x += .8 * _s;
          }
          x += _s;
        }
        if (bar.timeSignature != null) {
          for (final top in [_trebleTop, _bassTop]) {
            _timeNumber(canvas, bar.timeSignature!.beats, x, top + 2 * _s);
            _timeNumber(canvas, bar.timeSignature!.unit, x, top + 4 * _s);
          }
        }
      }
      final time = score.timeAt(m);
      final groups = beamGroups(
        score.measures[m],
        numerator: time.beats,
        denominator: time.unit,
      );
      final beamed = <NotationEvent, double>{};
      for (final group in groups) {
        final up = stemPointsUp(group.first.voice);
        final highestLevel = group
            .map((e) => beamCount(e.durationTicks))
            .reduce(math.max);
        final extension = (3.5 + .75 * (highestLevel - 1)) * _s;
        final pitches = group.expand(
          (event) => event.pitches.map((p) => _pitchY(p, event.staff)),
        );
        final y = up
            ? pitches.reduce(math.min) - extension
            : pitches.reduce(math.max) + extension;
        for (final event in group) {
          beamed[event] = y;
        }
      }
      for (final event in score.measures[m].events) {
        final x = eventXFor(score, m, event.startTick, _s);
        final playing = event.eventId != null &&
            playingSegments.contains((
              measure: m,
              startTick: event.startTick,
              eventId: event.eventId!,
            ));
        _drawEvent(canvas, event, x, ink, beamY: beamed[event], playing: playing);
        if (event.tieToNext) {
          final end = event.startTick + event.durationTicks;
          final nextX = end == time.ticks
              ? barX(score, m + 1, _s) - .3 * _s
              : eventXFor(score, m, end, _s);
          for (final pitch in event.pitches) {
            final y = _pitchY(pitch, event.staff) + 1.1 * _s;
            final path = Path()
              ..moveTo(x + 1.2 * _s, y)
              ..quadraticBezierTo((x + nextX) / 2, y + 1.4 * _s, nextX, y);
            canvas.drawPath(
              path,
              Paint()
                ..color = const Color(0xff333c39)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.2,
            );
          }
        }
        if (event.tieFromPrevious && event.startTick == 0) {
          for (final pitch in event.pitches) {
            final y = _pitchY(pitch, event.staff) + 1.1 * _s;
            final start = barX(score, m, _s) + .3 * _s;
            final path = Path()
              ..moveTo(start, y)
              ..quadraticBezierTo((start + x) / 2, y + 1.4 * _s, x, y);
            canvas.drawPath(
              path,
              Paint()
                ..color = const Color(0xff333c39)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.2,
            );
          }
        }
      }
      for (final group in groups) {
        _drawBeams(canvas, m, group, beamed[group.first]!);
      }
      for (final entry in score.measures[m].dynamics.entries) {
        final text = _dynamicText(entry.value, _s);
        final bounds = dynamicBounds(score, m, entry.key, _s);
        text.paint(canvas, bounds.topLeft);
      }
    }
    final totalTicks = score.measureStart(score.measures.length);
    for (final hairpin in score.hairpins) {
      if (hairpin.start >= totalTicks ||
          (hairpin.end != null && hairpin.end! <= 0)) {
        continue;
      }
      final bounds = hairpinBounds(score, hairpin, _s);
      final paint = Paint()
        ..color = hairpin.end == null
            ? const Color(0xffc63838)
            : const Color(0xff252c2a)
        ..strokeWidth = 1.2;
      final startProgress = hairpin.end == null
          ? 0.0
          : ((0 - hairpin.start) / (hairpin.end! - hairpin.start)).clamp(
              0.0,
              1.0,
            );
      final endProgress = hairpin.end == null
          ? 1.0
          : ((totalTicks - hairpin.start) / (hairpin.end! - hairpin.start))
                .clamp(0.0, 1.0);
      final leftOpen = hairpin.kind == HairpinKind.crescendo
          ? startProgress
          : 1 - startProgress;
      final rightOpen = hairpin.kind == HairpinKind.crescendo
          ? endProgress
          : 1 - endProgress;
      final y = bounds.center.dy;
      for (final sign in [-1, 1]) {
        canvas.drawLine(
          Offset(bounds.left, y + sign * .7 * _s * leftOpen),
          Offset(bounds.right, y + sign * .7 * _s * rightOpen),
          paint,
        );
      }
    }
    if (cursorTick != null) {
      final measure = score.measureAtTick(cursorTick!);
      final tick = cursorTick! - score.measureStart(measure);
      final x = measure >= score.measures.length
          ? barX(score, score.measures.length, _s)
          : eventXFor(score, measure, tick, _s);
      canvas.drawLine(
        Offset(x, _trebleTop - 2 * _s),
        Offset(x, _bassTop + 6 * _s),
        Paint()
          ..color = const Color(0x8870a899)
          ..strokeWidth = 1.5,
      );
      if (previewPitch != null && previewStaff != null) {
        _drawEvent(
          canvas,
          NotationEvent(
            startTick: tick,
            durationTicks: previewDuration,
            voice: previewVoice,
            staff: previewStaff!,
            pitches: [previewPitch!],
          ),
          x,
          ink,
          preview: true,
        );
      }
    }
  }

  void _drawBeams(
    Canvas canvas,
    int measure,
    List<NotationEvent> group,
    double y,
  ) {
    final up = stemPointsUp(group.first.voice);
    final xs = group
        .map(
          (event) =>
              eventXFor(score, measure, event.startTick, _s) +
              (up ? 1.15 * _s : 0.0),
        )
        .toList();
    final paint = Paint()..color = const Color(0xff252c2a);
    for (final span in beamSpans(group)) {
      var left = xs[span.first];
      var right = xs[span.last];
      if (span.isHook) {
        if (span.hookRight) {
          right += math.min(1.2 * _s, (xs[span.first + 1] - left) / 2);
        } else {
          left -= math.min(1.2 * _s, (right - xs[span.first - 1]) / 2);
        }
      }
      final levelY = y + (up ? 1 : -1) * (span.level - 1) * .75 * _s;
      canvas.drawRect(
        Rect.fromLTRB(
          left - .65,
          levelY - .25 * _s,
          right + .65,
          levelY + .25 * _s,
        ),
        paint,
      );
    }
  }

  void _drawEvent(
    Canvas canvas,
    NotationEvent event,
    double x,
    Paint ink, {
    bool preview = false,
    bool playing = false,
    double? beamY,
  }) {
    final top = event.staff == Staff.treble ? _trebleTop : _bassTop;
    final selected =
        event.eventId != null && event.eventId == selectedEvent?.eventId;
    final color = preview
        ? const Color(0x991a8171)
        : playing
        ? const Color(0xff2856ad)
        : selected
        ? const Color(0xff1a8171)
        : const Color(0xff252c2a);
    final duration = event.durationTicks;
    final base = baseDuration(duration);
    final dots = notationForDuration(duration)?.dots ?? 0;
    if (event.isRest) {
      final glyph = switch (base) {
        >= 3840 => '\uE4E3',
        >= 1920 => '\uE4E4',
        >= 960 => '\uE4E5',
        >= 480 => '\uE4E6',
        >= 240 => '\uE4E7',
        >= 120 => '\uE4E8',
        _ => '\uE4E9',
      };
      _glyph(canvas, glyph, x, top + 2 * _s, color: color);
      for (var i = 0; i < dots; i++) {
        _glyph(
          canvas,
          '\uE1E7',
          x + (1.6 + i * .6) * _s,
          top + 2 * _s,
          color: color,
        );
      }
      return;
    }
    final up = stemPointsUp(event.voice);
    final offsets = secondOffsets(event.pitches, stemUp: up);
    final ys = event.pitches.map((p) => _pitchY(p, event.staff)).toList();
    final head = base >= 3840
        ? '\uE0A2'
        : base >= 1920
        ? '\uE0A3'
        : '\uE0A4';
    for (var i = 0; i < event.pitches.length; i++) {
      final pitch = event.pitches[i];
      final headX = x + (offsets[i] ? (up ? 1.15 : -1.15) * _s : 0);
      final y = ys[i];
      // Draw ledger lines on staff-line positions, including middle C.
      for (var ledger = top - _s; ledger >= y - 0.1; ledger -= _s) {
        canvas.drawLine(
          Offset(headX - .35 * _s, ledger),
          Offset(headX + 1.6 * _s, ledger),
          ink,
        );
      }
      for (var ledger = top + 5 * _s; ledger <= y + 0.1; ledger += _s) {
        canvas.drawLine(
          Offset(headX - .35 * _s, ledger),
          Offset(headX + 1.6 * _s, ledger),
          ink,
        );
      }
      if (playing || (selected && i == selectedPitch)) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(headX + .6 * _s, y),
            width: 2.2 * _s,
            height: 1.6 * _s,
          ),
          Paint()..color = playing
              ? const Color(0x443f73d7)
              : const Color(0x331a8171),
        );
      }
      _glyph(canvas, head, headX, y, color: color);
      final accidental = switch (pitch.accidental) {
        Accidental.none => null,
        Accidental.sharp => '\uE262',
        Accidental.flat => '\uE260',
        Accidental.natural => '\uE261',
      };
      if (accidental != null) {
        _glyph(canvas, accidental, headX - 1.5 * _s, y, color: color);
      }
      for (var dot = 0; dot < dots; dot++) {
        _glyph(
          canvas,
          '\uE1E7',
          headX + (1.6 + dot * .6) * _s,
          y - .5 * _s,
          color: color,
        );
      }
    }
    final glyphs = articulationGlyphs(event.articulations, above: !up);
    final markY = up
        ? ys.reduce(math.max) + 1.5 * _s
        : ys.reduce(math.min) - 1.5 * _s;
    for (var i = 0; i < glyphs.length; i++) {
      _glyph(
        canvas,
        glyphs[i],
        x + .2 * _s,
        markY + (up ? 1 : -1) * i * _s,
        color: color,
      );
    }
    if (base < 3840) {
      final stemX = x + (up ? 1.15 * _s : 0);
      final stemEnd =
          beamY ??
          (up
              ? ys.reduce(math.min) - 3.5 * _s
              : ys.reduce(math.max) + 3.5 * _s);
      canvas.drawLine(
        Offset(stemX, up ? ys.reduce(math.max) : ys.reduce(math.min)),
        Offset(stemX, stemEnd),
        Paint()
          ..color = color
          ..strokeWidth = 1.3,
      );
      if (base <= 480 && beamY == null) {
        _glyph(
          canvas,
          base <= 60
              ? (up ? '\uE246' : '\uE247')
              : base <= 120
              ? (up ? '\uE244' : '\uE245')
              : base <= 240
              ? (up ? '\uE242' : '\uE243')
              : (up ? '\uE240' : '\uE241'),
          stemX,
          stemEnd,
          color: color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant ScorePainter oldDelegate) =>
      score != oldDelegate.score ||
      selectedEvent != oldDelegate.selectedEvent ||
      selectedPitch != oldDelegate.selectedPitch ||
      selectedMeasure != oldDelegate.selectedMeasure ||
      cursorTick != oldDelegate.cursorTick ||
      playingSegments != oldDelegate.playingSegments ||
      previewPitch != oldDelegate.previewPitch ||
      previewStaff != oldDelegate.previewStaff ||
      previewDuration != oldDelegate.previewDuration ||
      previewVoice != oldDelegate.previewVoice ||
      measureNumberOffset != oldDelegate.measureNumberOffset ||
      staffSpace != oldDelegate.staffSpace;
}
