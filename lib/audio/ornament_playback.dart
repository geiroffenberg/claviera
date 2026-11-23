import 'dart:math' as math;

import '../editor/score_editor.dart';
import '../models/score.dart';
import 'articulation_playback.dart';

typedef OrnamentNote = ({int midi, int start, int end});

List<OrnamentNote> ornamentNotes(
  VoiceEvent event,
  Pitch pitch, {
  required int start,
  required int keySignature,
  int Function(int step)? neighborMidi,
}) {
  final end = articulatedEnd(event);
  final ornament = event.articulations
      .where((mark) => mark.isOrnament)
      .firstOrNull;
  if (ornament == null) {
    return [(midi: pitch.midiNote, start: start, end: end)];
  }
  int neighbor(int direction) {
    final step = pitch.diatonicStep + direction;
    if (neighborMidi != null && step >= 0 && step <= 67) {
      return neighborMidi(step);
    }
    const semitones = [0, 2, 4, 5, 7, 9, 11];
    return 12 +
        (step / 7).floor() * 12 +
        semitones[step % 7] +
        keyAlteration(keySignature, step);
  }

  final pattern = switch (ornament) {
    Articulation.trill => [pitch.midiNote, neighbor(1)],
    Articulation.upperMordent => [pitch.midiNote, neighbor(1), pitch.midiNote],
    Articulation.lowerMordent => [pitch.midiNote, neighbor(-1), pitch.midiNote],
    Articulation.turn => [
      neighbor(1),
      pitch.midiNote,
      neighbor(-1),
      pitch.midiNote,
    ],
    Articulation.invertedTurn => [
      neighbor(-1),
      pitch.midiNote,
      neighbor(1),
      pitch.midiNote,
    ],
    _ => throw StateError('Invalid ornament.'),
  };
  final length = end - start;
  if (ornament == Articulation.trill) {
    var count = math.max(3, (length + 119) ~/ 120);
    if (count.isEven) count++;
    if (count > 16383) {
      throw StateError('The trill is too long to play; split the note first.');
    }
    return [
      for (var i = 0; i < count; i++)
        (
          midi: pattern[i % 2],
          start: start + length * i ~/ count,
          end: start + length * (i + 1) ~/ count,
        ),
    ];
  }
  final step = math.min(120, math.max(1, length ~/ (2 * (pattern.length - 1))));
  return [
    for (var i = 0; i < pattern.length; i++)
      (
        midi: pattern[i],
        start: start + i * step,
        end: i == pattern.length - 1 ? end : start + (i + 1) * step,
      ),
  ];
}
