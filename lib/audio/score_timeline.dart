import '../editor/score_editor.dart';
import '../models/score.dart';

class ScoreTimeline {
  ScoreTimeline(ScoreEditor editor) {
    events = [for (final voice in Voice.values) ...editor.eventsFor(voice)];
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
        if (events.any((event) =>
            !event.isRest && event.start < boundary && event.end > boundary)) {
          throw StateError(
            'A tied note crosses a repeat boundary. Edit the tie before playback or MIDI export.',
          );
        }
      }
    }
    final repeated = <int>{};
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
  }

  late final List<VoiceEvent> events;
  final List<(int, int)> spans = [];
}
