import '../models/score.dart';

bool stemPointsUp(Voice voice) => voice == Voice.v1 || voice == Voice.v3;

int baseDuration(int duration, {Tuplet? tuplet}) {
  return notationForDuration(duration, tuplet: tuplet)?.value.ticks ?? duration;
}

int beamCount(int duration, {Tuplet? tuplet}) {
  final base = baseDuration(duration, tuplet: tuplet);
  if (base > NoteValue.eighth.ticks) return 0;
  if (base > NoteValue.sixteenth.ticks) return 1;
  if (base > NoteValue.thirtySecond.ticks) return 2;
  if (base > NoteValue.sixtyFourth.ticks) return 3;
  return 4;
}

/// Simple meters use denominator beats; compound eighth-note meters use groups
/// of three eighths. Each measure is laid out independently.
int beamBeatTicks(int numerator, int denominator) {
  final unit = ticksPerQuarter * 4 ~/ denominator;
  return denominator == 8 && numerator > 3 && numerator % 3 == 0
      ? unit * 3
      : unit;
}

List<List<NotationEvent>> beamGroups(
  Measure measure, {
  required int numerator,
  required int denominator,
}) {
  final result = <List<NotationEvent>>[];
  final beat = beamBeatTicks(numerator, denominator);
  for (final voice in Voice.values) {
    final events = measure.events.where((e) => e.voice == voice).toList()
      ..sort((a, b) => a.startTick.compareTo(b.startTick));
    var group = <NotationEvent>[];
    void finish() {
      if (group.length > 1) result.add(group);
      group = [];
    }

    for (final event in events) {
      final end = event.startTick + event.durationTicks;
      final eligible =
          !event.isRest &&
          beamCount(event.durationTicks, tuplet: event.tuplet) > 0 &&
          event.startTick ~/ beat == (end - 1) ~/ beat;
      if (!eligible) {
        finish();
        continue;
      }
      if (group.isNotEmpty) {
        final previous = group.last;
        if (previous.startTick + previous.durationTicks != event.startTick ||
            previous.staff != event.staff ||
            previous.startTick ~/ beat != event.startTick ~/ beat) {
          finish();
        }
      }
      group.add(event);
    }
    finish();
  }
  return result;
}

/// Inclusive indices for full beams, or an isolated index for a beamlet.
class BeamSpan {
  const BeamSpan(this.level, this.first, this.last, {this.hookRight = false});

  final int level;
  final int first;
  final int last;
  final bool hookRight;
  bool get isHook => first == last;
}

List<BeamSpan> beamSpans(List<NotationEvent> group) {
  final counts = group
      .map((event) => beamCount(event.durationTicks, tuplet: event.tuplet))
      .toList();
  final spans = <BeamSpan>[];
  for (var level = 1; level <= 4; level++) {
    var i = 0;
    while (i < group.length) {
      if (counts[i] < level) {
        i++;
        continue;
      }
      final start = i;
      while (i + 1 < group.length && counts[i + 1] >= level) {
        i++;
      }
      final end = i;
      // Isolated secondary beams point toward the closest neighboring stem.
      final hookRight =
          start == end &&
          (start == 0 ||
              (start < group.length - 1 &&
                  group[start + 1].startTick - group[start].startTick <
                      group[start].startTick - group[start - 1].startTick));
      spans.add(BeamSpan(level, start, end, hookRight: hookRight));
      i++;
    }
  }
  return spans;
}

/// Events of one tuplet in one voice. A bracket line is only needed when the
/// events are not all joined by a single beam; the number is always drawn.
class TupletSpan {
  const TupletSpan(this.events, {required this.bracket});

  final List<NotationEvent> events;
  final bool bracket;
  int get number => events.first.tuplet!.actual;
}

List<TupletSpan> tupletSpans(Measure measure, List<List<NotationEvent>> beams) {
  final byKey = <(Voice, int), List<NotationEvent>>{};
  for (final event in measure.events) {
    final tuplet = event.tuplet;
    if (tuplet == null) continue;
    byKey.putIfAbsent((event.voice, tuplet.groupId), () => []).add(event);
  }
  return [
    for (final events in byKey.values)
      TupletSpan(
        events..sort((a, b) => a.startTick.compareTo(b.startTick)),
        bracket: !beams.any((beam) => events.every(beam.contains)),
      ),
  ];
}
