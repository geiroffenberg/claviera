import 'dart:math' as math;

import '../editor/score_editor.dart';
import '../models/score.dart';
import 'articulation_playback.dart';

Map<(int, int), int> arpeggioOffsets(
  List<VoiceEvent> events,
  Map<int, ArpeggioDirection> arpeggios,
) {
  final offsets = <(int, int), int>{};
  for (final entry in arpeggios.entries) {
    final notes = <({VoiceEvent event, int index, int midi})>[
      for (final event in events)
        if (event.start == entry.key)
          for (var i = 0; i < event.pitches.length; i++)
            (event: event, index: i, midi: event.pitches[i].midiNote),
    ];
    if (notes.length < 2) continue;
    notes.sort((a, b) {
      final pitch = a.midi.compareTo(b.midi);
      if (pitch != 0) {
        return entry.value == ArpeggioDirection.up ? pitch : -pitch;
      }
      final id = a.event.id.compareTo(b.event.id);
      return id != 0 ? id : a.index.compareTo(b.index);
    });
    final shortest = notes
        .map((note) => articulatedEnd(note.event) - note.event.start)
        .reduce(math.min);
    final spread = math.min(60 * (notes.length - 1), shortest ~/ 2);
    for (var i = 0; i < notes.length; i++) {
      offsets[(notes[i].event.id, notes[i].index)] =
          spread * i ~/ (notes.length - 1);
    }
  }
  return offsets;
}
