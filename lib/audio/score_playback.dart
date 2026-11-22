import '../editor/score_editor.dart';
import '../models/score.dart';

class PlaybackNote {
  const PlaybackNote(this.midi, this.startMs, this.endMs);
  final int midi;
  final int startMs;
  final int endMs;

  Map<String, int> toMap() => {
    'midi': midi,
    'startMs': startMs,
    'endMs': endMs,
  };
}

class PlaybackPlan {
  PlaybackPlan(ScoreEditor editor, int bpm) {
    if (bpm < 30 || bpm > 240) {
      throw ArgumentError.value(bpm, 'bpm', 'Must be between 30 and 240.');
    }
    final changes = editor.tempoChanges.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    int millis(int tick) {
      var previous = 0;
      var currentBpm = bpm;
      var elapsed = 0.0;
      for (final change in changes) {
        final at = editor.measureStart(change.key);
        if (at >= tick) break;
        elapsed += (at - previous) * 60000 / (currentBpm * ticksPerQuarter);
        currentBpm = change.value;
        previous = at;
      }
      return (elapsed +
              (tick - previous) * 60000 / (currentBpm * ticksPerQuarter))
          .round();
    }

    for (final voice in Voice.values) {
      for (final event in editor.eventsFor(voice)) {
        final end = millis(event.end);
        if (end > durationMs) durationMs = end;
        for (final pitch in event.pitches) {
          if (pitch.midiNote < 10 || pitch.midiNote > 127) {
            throw StateError(
              'MIDI note ${pitch.midiNote} is outside the sample playback range (10–127).',
            );
          }
          notes.add(PlaybackNote(pitch.midiNote, millis(event.start), end));
        }
      }
    }
    final edges =
        <(int, int)>[
          for (final note in notes) ...[(note.startMs, 1), (note.endMs, -1)],
        ]..sort((a, b) {
          final time = a.$1.compareTo(b.$1);
          return time != 0 ? time : a.$2.compareTo(b.$2);
        });
    var active = 0;
    for (final edge in edges) {
      active += edge.$2;
      if (active > 64) {
        throw StateError('Playback supports at most 64 simultaneous notes.');
      }
    }
    notes.sort((a, b) => a.startMs.compareTo(b.startMs));
  }

  final List<PlaybackNote> notes = [];
  int durationMs = 0;
}
