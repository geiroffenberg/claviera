import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../editor/score_editor.dart';
import '../models/score.dart';
import 'beaming.dart';

class MusicXmlExport {
  static Uint8List encode(ScoreEditor editor, int initialTempo, String title) {
    if (initialTempo < 30 || initialTempo > 240) {
      throw ArgumentError.value(initialTempo, 'initialTempo');
    }
    if (editor.pendingHairpin != null) {
      throw StateError('Finish or remove the unfinished hairpin first.');
    }
    final score = editor.score;
    final xml = XmlBuilder();

    void text(String name, Object value) =>
        xml.element(name, nest: value.toString());

    void repeat(String location, String direction) {
      xml.element(
        'barline',
        attributes: {'location': location},
        nest: () {
          xml.element('repeat', attributes: {'direction': direction});
        },
      );
    }

    void note(
      NotationEvent event,
      Pitch? pitch,
      bool chord,
      ArpeggioDirection? arpeggio,
    ) {
      final duration = event.durationTicks;
      final notation = notationForDuration(duration);
      if (notation == null) {
        throw StateError('Unsupported MusicXML note duration: $duration.');
      }
      final value = notation.value;
      xml.element(
        'note',
        nest: () {
          if (chord) xml.element('chord');
          if (pitch == null) {
            xml.element('rest');
          } else {
            final step = pitch.diatonicStep;
            final natural = soundingMidi(step, Accidental.natural, 0);
            final alter = pitch.midiNote - natural;
            xml.element(
              'pitch',
              nest: () {
                text(
                  'step',
                  const ['C', 'D', 'E', 'F', 'G', 'A', 'B'][step % 7],
                );
                if (alter != 0) text('alter', alter);
                text('octave', step ~/ 7);
              },
            );
          }
          text('duration', duration);
          if (event.tieFromPrevious) {
            xml.element('tie', attributes: {'type': 'stop'});
          }
          if (event.tieToNext) {
            xml.element('tie', attributes: {'type': 'start'});
          }
          text('voice', event.voice.index + 1);
          text('type', switch (value) {
            NoteValue.whole => 'whole',
            NoteValue.half => 'half',
            NoteValue.quarter => 'quarter',
            NoteValue.eighth => 'eighth',
            NoteValue.sixteenth => '16th',
            NoteValue.thirtySecond => '32nd',
            NoteValue.sixtyFourth => '64th',
          });
          for (var i = 0; i < notation.dots; i++) {
            xml.element('dot');
          }
          if (pitch != null &&
              pitch.accidental != Accidental.none &&
              !event.tieFromPrevious) {
            text('accidental', pitch.accidental.name);
          }
          if (pitch != null && value != NoteValue.whole) {
            text('stem', stemPointsUp(event.voice) ? 'up' : 'down');
          }
          text('staff', event.staff == Staff.treble ? 1 : 2);
          if (event.tieFromPrevious ||
              event.tieToNext ||
              (pitch != null && arpeggio != null) ||
              (pitch != null &&
                  event.articulations.any((mark) => mark.isOrnament)) ||
              (!chord && event.articulations.isNotEmpty)) {
            xml.element(
              'notations',
              nest: () {
                if (event.tieFromPrevious) {
                  xml.element('tied', attributes: {'type': 'stop'});
                }
                if (event.tieToNext) {
                  xml.element('tied', attributes: {'type': 'start'});
                }
                if (!chord &&
                    event.articulations.contains(Articulation.fermata)) {
                  xml.element('fermata');
                }
                if (pitch != null && arpeggio != null) {
                  xml.element(
                    'arpeggiate',
                    attributes: {'number': '1', 'direction': arpeggio.name},
                  );
                }
                if (pitch != null &&
                    event.articulations.any((mark) => mark.isOrnament)) {
                  xml.element(
                    'ornaments',
                    nest: () {
                      for (final mark in event.articulations.where(
                        (mark) => mark.isOrnament,
                      )) {
                        xml.element(
                          switch (mark) {
                            Articulation.trill => 'trill-mark',
                            Articulation.upperMordent => 'inverted-mordent',
                            Articulation.lowerMordent => 'mordent',
                            Articulation.turn => 'turn',
                            Articulation.invertedTurn => 'inverted-turn',
                            _ => throw StateError('Invalid ornament.'),
                          },
                          attributes: {
                            if (mark == Articulation.invertedTurn)
                              'start-note': 'below',
                          },
                        );
                      }
                    },
                  );
                }
                if (!chord &&
                    event.articulations.any(
                      (mark) =>
                          mark != Articulation.fermata && !mark.isOrnament,
                    )) {
                  xml.element(
                    'articulations',
                    nest: () {
                      for (final mark in Articulation.values) {
                        if (mark == Articulation.fermata ||
                            mark.isOrnament ||
                            !event.articulations.contains(mark)) {
                          continue;
                        }
                        if (mark == Articulation.marcato) {
                          final above = !stemPointsUp(event.voice);
                          xml.element(
                            'strong-accent',
                            attributes: {
                              'type': above ? 'up' : 'down',
                              'placement': above ? 'above' : 'below',
                            },
                          );
                        } else {
                          xml.element(mark.name);
                        }
                      }
                    },
                  );
                }
              },
            );
          }
        },
      );
    }

    xml.processing('xml', 'version="1.0" encoding="UTF-8"');
    xml.element(
      'score-partwise',
      attributes: {'version': '4.0'},
      nest: () {
        xml.element('work', nest: () => text('work-title', title));
        text('movement-title', title);
        xml.element(
          'part-list',
          nest: () => xml.element(
            'score-part',
            attributes: {'id': 'P1'},
            nest: () => text('part-name', 'Piano'),
          ),
        );
        xml.element(
          'part',
          attributes: {'id': 'P1'},
          nest: () {
            for (var index = 0; index < score.measures.length; index++) {
              final measure = score.measures[index];
              final time = score.timeAt(index);
              xml.element(
                'measure',
                attributes: {'number': '${index + 1}'},
                nest: () {
                  if (measure.repeatStart) repeat('left', 'forward');
                  if (index == 0 ||
                      measure.timeSignature != null ||
                      measure.keySignature != null) {
                    xml.element(
                      'attributes',
                      nest: () {
                        if (index == 0) text('divisions', ticksPerQuarter);
                        if (index == 0 || measure.keySignature != null) {
                          xml.element(
                            'key',
                            nest: () => text('fifths', score.keyAt(index)),
                          );
                        }
                        if (index == 0 || measure.timeSignature != null) {
                          xml.element(
                            'time',
                            nest: () {
                              text('beats', time.beats);
                              text('beat-type', time.unit);
                            },
                          );
                        }
                        if (index == 0) {
                          text('staves', 2);
                          for (final clef in [(1, 'G', 2), (2, 'F', 4)]) {
                            xml.element(
                              'clef',
                              attributes: {'number': '${clef.$1}'},
                              nest: () {
                                text('sign', clef.$2);
                                text('line', clef.$3);
                              },
                            );
                          }
                        }
                      },
                    );
                  }
                  final tempo =
                      measure.tempo ?? (index == 0 ? initialTempo : null);
                  if (tempo != null) {
                    xml.element(
                      'direction',
                      nest: () {
                        xml.element(
                          'direction-type',
                          nest: () => xml.element(
                            'metronome',
                            nest: () {
                              text('beat-unit', 'quarter');
                              text('per-minute', tempo);
                            },
                          ),
                        );
                        xml.element('sound', attributes: {'tempo': '$tempo'});
                      },
                    );
                  }
                  final dynamics = measure.dynamics.entries.toList()
                    ..sort((a, b) => a.key.compareTo(b.key));
                  for (final dynamicMark in dynamics) {
                    xml.element(
                      'direction',
                      attributes: {'placement': 'below'},
                      nest: () {
                        xml.element(
                          'direction-type',
                          nest: () => xml.element(
                            'dynamics',
                            nest: () => xml.element(dynamicMark.value.name),
                          ),
                        );
                        if (dynamicMark.key != 0) {
                          xml.element(
                            'offset',
                            attributes: {'sound': 'yes'},
                            nest: dynamicMark.key.toString(),
                          );
                        }
                        text('staff', 1);
                        xml.element(
                          'sound',
                          attributes: {
                            'dynamics':
                                '${dynamicMark.value.velocity * 100 / 90}',
                          },
                        );
                      },
                    );
                  }
                  final measureStart = score.measureStart(index);
                  final measureEnd = score.measureStart(index + 1);
                  final wedges =
                      <(int, String)>[
                        for (final h in score.hairpins) ...[
                          if (h.start >= measureStart && h.start < measureEnd)
                            (h.start - measureStart, h.kind.name),
                          if (h.end! >= measureStart && h.end! < measureEnd)
                            (h.end! - measureStart, 'stop'),
                        ],
                      ]..sort((a, b) {
                        final order = a.$1.compareTo(b.$1);
                        if (order != 0) return order;
                        return a.$2 == 'stop' ? -1 : 1;
                      });
                  for (final wedge in wedges) {
                    xml.element(
                      'direction',
                      attributes: {'placement': 'below'},
                      nest: () {
                        xml.element(
                          'direction-type',
                          nest: () => xml.element(
                            'wedge',
                            attributes: {'type': wedge.$2, 'number': '1'},
                          ),
                        );
                        if (wedge.$1 != 0) text('offset', wedge.$1);
                        text('staff', 1);
                      },
                    );
                  }
                  final voices = Voice.values.where(
                    (voice) =>
                        measure.events.any((event) => event.voice == voice),
                  );
                  var firstVoice = true;
                  for (final voice in voices) {
                    if (!firstVoice) {
                      xml.element(
                        'backup',
                        nest: () => text('duration', time.ticks),
                      );
                    }
                    firstVoice = false;
                    final events =
                        measure.events.where((e) => e.voice == voice).toList()
                          ..sort((a, b) => a.startTick.compareTo(b.startTick));
                    var cursor = 0;
                    for (final event in events) {
                      if (event.startTick > cursor) {
                        xml.element(
                          'forward',
                          nest: () =>
                              text('duration', event.startTick - cursor),
                        );
                      }
                      if (event.isRest) {
                        note(event, null, false, null);
                      } else {
                        final arpeggio = event.tieFromPrevious
                            ? null
                            : measure.arpeggios[event.startTick];
                        for (var i = 0; i < event.pitches.length; i++) {
                          note(event, event.pitches[i], i > 0, arpeggio);
                        }
                      }
                      cursor = event.startTick + event.durationTicks;
                    }
                    if (cursor < time.ticks) {
                      xml.element(
                        'forward',
                        nest: () => text('duration', time.ticks - cursor),
                      );
                    }
                  }
                  if (firstVoice) {
                    xml.element(
                      'note',
                      nest: () {
                        xml.element('rest', attributes: {'measure': 'yes'});
                        text('duration', time.ticks);
                        text('voice', 1);
                        text('staff', 1);
                      },
                    );
                  }
                  if (measure.repeatEnd) repeat('right', 'backward');
                },
              );
            }
          },
        );
      },
    );
    return Uint8List.fromList(utf8.encode(xml.buildDocument().toXmlString()));
  }
}
