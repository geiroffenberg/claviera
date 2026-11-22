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
    double millis(int tick) {
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
      return elapsed +
          (tick - previous) * 60000 / (currentBpm * ticksPerQuarter);
    }

    final starts = editor.repeatStarts;
    final ends = editor.repeatEnds;
    final destinations = <int, int>{};
    int? open;
    for (var measure = 0; measure < editor.measureCount; measure++) {
      if (starts.contains(measure)) {
        if (open != null) {
          throw StateError('Nested repeat starts are not supported yet.');
        }
        open = measure;
      }
      if (ends.contains(measure)) {
        destinations[measure] = open ?? 0;
        open = null;
      }
    }

    final events = [
      for (final voice in Voice.values) ...editor.eventsFor(voice),
    ];
    var lastTick = 0;
    for (final event in events) {
      if (event.end > lastTick) lastTick = event.end;
    }
    for (final end in ends) {
      final tick = editor.measureStart(end + 1);
      if (tick > lastTick) lastTick = tick;
    }
    for (final entry in destinations.entries) {
      for (final boundary in [
        editor.measureStart(entry.key + 1),
        editor.measureStart(entry.value),
      ]) {
        if (events.any(
          (event) =>
              !event.isRest && event.start < boundary && event.end > boundary,
        )) {
          throw StateError(
            'A tied note crosses a repeat boundary. Edit the tie before playback.',
          );
        }
      }
    }
    final repeated = <int>{};
    final spans = <(int, int)>[];
    var cursor = 0;
    while (cursor < lastTick) {
      int? nextEnd;
      for (final end in ends) {
        final boundary = editor.measureStart(end + 1);
        if (!repeated.contains(end) &&
            boundary > cursor &&
            boundary <= lastTick &&
            (nextEnd == null || end < nextEnd)) {
          nextEnd = end;
        }
      }
      if (nextEnd == null) {
        spans.add((cursor, lastTick));
        break;
      }
      final boundary = editor.measureStart(nextEnd + 1);
      spans.add((cursor, boundary));
      repeated.add(nextEnd);
      cursor = editor.measureStart(destinations[nextEnd]!);
    }

    var elapsed = 0.0;
    for (final span in spans) {
      final base = millis(span.$1);
      for (final event in events) {
        if (event.start < span.$1 || event.end > span.$2) continue;
        final start = (elapsed + millis(event.start) - base).round();
        final end = (elapsed + millis(event.end) - base).round();
        for (final pitch in event.pitches) {
          if (pitch.midiNote < 10 || pitch.midiNote > 127) {
            throw StateError(
              'MIDI note ${pitch.midiNote} is outside the sample playback range (10–127).',
            );
          }
          notes.add(PlaybackNote(pitch.midiNote, start, end));
        }
      }
      elapsed += millis(span.$2) - base;
    }
    durationMs = elapsed.round();
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
