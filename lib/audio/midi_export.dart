import 'dart:typed_data';

import '../editor/score_editor.dart';
import '../models/score.dart';
import 'articulation_playback.dart';
import 'dynamics_timeline.dart';
import 'score_timeline.dart';

class _MidiEvent {
  const _MidiEvent(this.tick, this.order, this.bytes);
  final int tick;
  final int order;
  final List<int> bytes;
}

class MidiExport {
  static Uint8List encode(ScoreEditor editor, int initialTempo) {
    if (initialTempo < 30 || initialTempo > 240) {
      throw ArgumentError.value(initialTempo, 'initialTempo');
    }
    final timeline = ScoreTimeline(editor);
    final dynamics = DynamicsTimeline(editor);
    final events = <_MidiEvent>[];
    final extraChannels = [
      for (var i = 4; i < 16; i++)
        if (i != 9) i,
    ];
    final usedChannels = <int>{};
    final notes = <(int, int, int, Voice, int)>[];
    var offset = 0;

    void metadata(int outputTick, int measure) {
      var tempo = initialTempo;
      var latest = -1;
      for (final change in editor.tempoChanges.entries) {
        if (change.key <= measure && change.key > latest) {
          tempo = change.value;
          latest = change.key;
        }
      }
      if (tempo < 30 || tempo > 240) {
        throw StateError('Invalid tempo for MIDI export: $tempo.');
      }
      final micros = (60000000 / tempo).round();
      final time = editor.timeAt(measure);
      if (time.beats > 255) {
        throw StateError('The time signature is too large for MIDI export.');
      }
      var denominator = time.unit;
      var power = 0;
      while (denominator > 1) {
        denominator ~/= 2;
        power++;
      }
      final key = editor.keyAt(measure);
      events.add(
        _MidiEvent(outputTick, 0, [
          0xff,
          0x51,
          3,
          micros >> 16,
          (micros >> 8) & 255,
          micros & 255,
        ]),
      );
      events.add(
        _MidiEvent(outputTick, 0, [0xff, 0x58, 4, time.beats, power, 24, 8]),
      );
      events.add(_MidiEvent(outputTick, 0, [0xff, 0x59, 2, key & 255, 0]));
    }

    if (timeline.spans.isEmpty) metadata(0, 0);
    for (final span in timeline.spans) {
      final first = editor.measureAtTick(span.$1);
      metadata(offset, first);
      for (var measure = first + 1; measure < editor.measureCount; measure++) {
        final tick = editor.measureStart(measure);
        if (tick >= span.$2) break;
        if (editor.tempoChanges.containsKey(measure) ||
            editor.timeChanges.containsKey(measure) ||
            editor.keyChanges.containsKey(measure)) {
          metadata(offset + tick - span.$1, measure);
        }
      }
      for (final event in timeline.events) {
        if (event.start < span.$1 || event.end > span.$2) continue;
        for (final pitch in event.pitches) {
          if (pitch.midiNote < 0 || pitch.midiNote > 127) {
            throw StateError('Invalid MIDI pitch: ${pitch.midiNote}.');
          }
          notes.add((
            offset + event.start - span.$1,
            offset + articulatedEnd(event) - span.$1,
            pitch.midiNote,
            event.voice,
            articulatedVelocity(event, dynamics.velocityAt(event.start)),
          ));
        }
      }
      offset += span.$2 - span.$1;
    }
    notes.sort((a, b) {
      final start = a.$1.compareTo(b.$1);
      if (start != 0) return start;
      final pitch = a.$3.compareTo(b.$3);
      if (pitch != 0) return pitch;
      final voice = a.$4.index.compareTo(b.$4.index);
      return voice != 0 ? voice : a.$2.compareTo(b.$2);
    });
    final active = <int, Map<int, int>>{};
    for (final note in notes) {
      final playing = active.putIfAbsent(note.$3, () => {});
      playing.removeWhere((channel, end) => end <= note.$1);
      final channel = [
        note.$4.index,
        ...extraChannels,
      ].where((c) => !playing.containsKey(c)).firstOrNull;
      if (channel == null) {
        throw StateError(
          'Too many overlapping notes of the same pitch for MIDI channels.',
        );
      }
      playing[channel] = note.$2;
      usedChannels.add(channel);
      events.add(_MidiEvent(note.$1, 2, [0x90 | channel, note.$3, note.$5]));
      events.add(_MidiEvent(note.$2, 1, [0x80 | channel, note.$3, 0]));
    }
    for (final channel in usedChannels) {
      events.add(_MidiEvent(0, 0, [0xc0 | channel, 0]));
    }
    events.sort((a, b) {
      final tick = a.tick.compareTo(b.tick);
      return tick != 0 ? tick : a.order.compareTo(b.order);
    });

    List<int> vlq(int value) {
      if (value < 0 || value > 0x0fffffff) {
        throw StateError('MIDI timing exceeds the supported range.');
      }
      final result = <int>[value & 0x7f];
      while ((value >>= 7) > 0) {
        result.insert(0, (value & 0x7f) | 0x80);
      }
      return result;
    }

    final track = <int>[];
    var last = 0;
    for (final event in events) {
      track.addAll(vlq(event.tick - last));
      track.addAll(event.bytes);
      last = event.tick;
    }
    track.addAll(vlq(offset - last));
    track.addAll([0xff, 0x2f, 0]);
    List<int> u32(int value) => [
      value >> 24 & 255,
      value >> 16 & 255,
      value >> 8 & 255,
      value & 255,
    ];
    return Uint8List.fromList([
      ...'MThd'.codeUnits,
      ...u32(6),
      0,
      0,
      0,
      1,
      ticksPerQuarter >> 8,
      ticksPerQuarter & 255,
      ...'MTrk'.codeUnits,
      ...u32(track.length),
      ...track,
    ]);
  }
}
