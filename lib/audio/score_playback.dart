import 'dart:math' as math;

import '../editor/score_editor.dart';
import '../models/score.dart';
import 'arpeggio_playback.dart';
import 'articulation_playback.dart';
import 'dynamics_timeline.dart';
import 'ornament_playback.dart';
import 'score_timeline.dart';

class PlaybackFrame {
  const PlaybackFrame(
    this.startMs,
    this.measure,
    this.segments,
    this.playingPitches,
  );
  final int startMs;
  final int measure;
  final Set<PlaybackSegment> segments;
  final Map<PlaybackSegment, Set<int>> playingPitches;
}

class _FrameChanges {
  int? measure;
  final adds = <(PlaybackSegment, int)>{};
  final removes = <(PlaybackSegment, int)>{};
}

class PlaybackNote {
  const PlaybackNote(this.midi, this.startMs, this.endMs, {this.volume = 127});
  final int midi;
  final int startMs;
  final int endMs;
  final int volume;

  Map<String, int> toMap() => {
    'midi': midi,
    'startMs': startMs,
    'endMs': endMs,
    'volume': volume,
  };
}

class PlaybackPlan {
  PlaybackPlan(ScoreEditor editor, int bpm, {int startMeasure = 0}) {
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

    final timeline = ScoreTimeline(editor, startMeasure: startMeasure);
    final offsets = arpeggioOffsets(timeline.events, editor.arpeggios);
    final dynamics = DynamicsTimeline(editor);
    final hasAccents = timeline.events.any(
      (event) =>
          event.articulations.contains(Articulation.accent) ||
          event.articulations.contains(Articulation.marcato),
    );
    final score = editor.score;
    final changesByTime = <int, _FrameChanges>{};
    _FrameChanges at(int ms) =>
        changesByTime.putIfAbsent(ms, _FrameChanges.new);

    var elapsed = 0.0;
    for (final span in timeline.spans) {
      final base = millis(span.$1);
      final holds = FermataHolds(timeline.events, span);
      double heldMillis(int tick) {
        var result = 0.0;
        for (final hold in holds.holds) {
          if (hold.key > tick) break;
          var holdBpm = bpm;
          for (final change in changes) {
            if (editor.measureStart(change.key) >= hold.key) break;
            holdBpm = change.value;
          }
          result += hold.value * 60000 / (holdBpm * ticksPerQuarter);
        }
        return result;
      }

      final playableEvents = timeline.events
          .where((event) => event.start >= span.$1 && event.end <= span.$2)
          .toList();
      final playable = {for (final event in playableEvents) event.id: event};
      int outputTime(int tick) =>
          (elapsed + millis(tick) - base + heldMillis(tick)).round();
      var measure = editor.measureAtTick(span.$1);
      while (measure < score.measures.length) {
        final barStart = editor.measureStart(measure);
        if (barStart >= span.$2) break;
        final barEnd = editor.measureStart(measure + 1);
        final start = barStart < span.$1 ? span.$1 : barStart;
        at(outputTime(start)).measure = measure;
        for (final event in score.measures[measure].events) {
          final logical = playable[event.eventId];
          if (event.isRest || logical == null) continue;
          final eventStart = barStart + event.startTick;
          final soundingEnd = articulatedEnd(logical);
          if (eventStart >= soundingEnd) continue;
          final eventEnd = (eventStart + event.durationTicks).clamp(
            eventStart,
            soundingEnd,
          );
          if (eventStart < span.$1 || eventStart >= eventEnd) continue;
          final segment = (
            measure: measure,
            startTick: event.startTick,
            eventId: event.eventId!,
          );
          for (var i = 0; i < logical.pitches.length; i++) {
            final pitchStart = math.max(
              eventStart,
              logical.start + (offsets[(logical.id, i)] ?? 0),
            );
            if (pitchStart >= eventEnd) continue;
            at(outputTime(pitchStart)).adds.add((segment, i));
            at(outputTime(eventEnd)).removes.add((segment, i));
          }
        }
        if (barEnd >= span.$2) break;
        measure++;
      }
      for (final event in playableEvents) {
        for (var i = 0; i < event.pitches.length; i++) {
          final pitch = event.pitches[i];
          final start = event.start + (offsets[(event.id, i)] ?? 0);
          final key = editor.keyAt(editor.measureAtTick(event.start));
          for (final note in ornamentNotes(
            event,
            pitch,
            start: start,
            keySignature: key,
          )) {
            if (note.midi < 10 || note.midi > 127) {
              throw StateError(
                'MIDI note ${note.midi} is outside the sample playback range (10–127).',
              );
            }
            final startMs = outputTime(note.start);
            final endMs = outputTime(note.end);
            if (startMs >= endMs &&
                event.articulations.any((mark) => mark.isOrnament)) {
              throw StateError(
                'The ornament is too short to play at this tempo.',
              );
            }
            notes.add(
              PlaybackNote(
                note.midi,
                startMs,
                endMs,
                volume: articulatedVelocity(
                  event,
                  dynamics.hasExpression || hasAccents
                      ? dynamics.velocityAt(event.start)
                      : 127,
                ),
              ),
            );
          }
        }
      }
      elapsed += millis(span.$2) - base + heldMillis(span.$2);
    }
    durationMs = elapsed.round();
    final playing = <(PlaybackSegment, int)>{};
    var currentMeasure = 0;
    final times = changesByTime.keys.toList()..sort();
    for (final time in times) {
      final change = changesByTime[time]!;
      currentMeasure = change.measure ?? currentMeasure;
      playing.removeAll(change.removes);
      playing.addAll(change.adds);
      if (time < durationMs) {
        final pitches = <PlaybackSegment, Set<int>>{};
        for (final (segment, pitch) in playing) {
          pitches.putIfAbsent(segment, () => <int>{}).add(pitch);
        }
        _frames.add(
          PlaybackFrame(
            time,
            currentMeasure,
            Set.unmodifiable(pitches.keys),
            Map.unmodifiable({
              for (final entry in pitches.entries)
                entry.key: Set<int>.unmodifiable(entry.value),
            }),
          ),
        );
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
  final List<PlaybackFrame> _frames = [];
  int durationMs = 0;

  PlaybackFrame? frameAt(int elapsedMs) {
    if (elapsedMs < 0 || elapsedMs >= durationMs || _frames.isEmpty) {
      return null;
    }
    var low = 0;
    var high = _frames.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_frames[middle].startMs <= elapsedMs) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low == 0 ? null : _frames[low - 1];
  }
}
