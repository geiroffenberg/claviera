import 'package:claviera/audio/midi_export.dart';
import 'package:claviera/audio/score_playback.dart';
import 'package:claviera/editor/score_editor.dart';
import 'package:claviera/main.dart';
import 'package:claviera/models/blank_score.dart';
import 'package:claviera/models/score.dart';
import 'package:claviera/storage/projects.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

typedef MidiMessage = ({int tick, int status, List<int> data});

List<MidiMessage> parseMidi(Uint8List bytes) {
  expect(bytes.sublist(0, 4), 'MThd'.codeUnits);
  final header = ByteData.sublistView(bytes);
  expect(header.getUint32(4), 6);
  expect(header.getUint16(8), 0);
  expect(header.getUint16(10), 1);
  expect(header.getUint16(12), 960);
  expect(bytes.sublist(14, 18), 'MTrk'.codeUnits);
  expect(header.getUint32(18), bytes.length - 22);
  var index = 22;
  var tick = 0;
  int variable() {
    var value = 0;
    for (var count = 0; count < 4; count++) {
      final byte = bytes[index++];
      value = (value << 7) | (byte & 127);
      if (byte & 128 == 0) return value;
    }
    throw const FormatException('Invalid variable-length quantity');
  }

  final result = <MidiMessage>[];
  while (index < bytes.length) {
    tick += variable();
    final status = bytes[index++];
    if (status == 0xff) {
      final type = bytes[index++];
      final length = variable();
      final data = bytes.sublist(index, index + length);
      index += length;
      result.add((tick: tick, status: 0xff00 | type, data: data));
    } else {
      final length = status & 0xf0 == 0xc0 ? 1 : 2;
      final data = bytes.sublist(index, index + length);
      index += length;
      result.add((tick: tick, status: status, data: data));
    }
  }
  expect(result.last.status, 0xff2f);
  return result;
}

void main() {
  test('encodes voices, chords, gaps, ties and overlapping same pitches', () {
    final editor = ScoreEditor(
      Score(
        title: 'MIDI',
        beatsPerMeasure: 4,
        beatUnit: 4,
        measures: [
          Measure(
            events: [
              const NotationEvent(
                startTick: 0,
                durationTicks: 4800,
                voice: Voice.v1,
                staff: Staff.treble,
                pitches: [
                  Pitch(diatonicStep: 28, midiNote: 60),
                  Pitch(diatonicStep: 30, midiNote: 64),
                ],
              ),
              const NotationEvent(
                startTick: 960,
                durationTicks: 960,
                voice: Voice.v2,
                staff: Staff.bass,
                pitches: [
                  Pitch(diatonicStep: 28, midiNote: 60),
                  Pitch(diatonicStep: 28, midiNote: 60),
                ],
              ),
              const NotationEvent(
                startTick: 1920,
                durationTicks: 960,
                voice: Voice.v3,
                staff: Staff.treble,
                pitches: [Pitch(diatonicStep: 0, midiNote: 0)],
              ),
              const NotationEvent(
                startTick: 2880,
                durationTicks: 960,
                voice: Voice.v4,
                staff: Staff.bass,
                pitches: [Pitch(diatonicStep: 67, midiNote: 127)],
              ),
            ],
          ),
          const Measure(),
        ],
      ),
    );
    final messages = parseMidi(MidiExport.encode(editor, 120));
    final ons = messages.where((m) => m.status & 0xf0 == 0x90).toList();
    expect(ons.map((m) => (m.tick, m.data[0])), [
      (0, 60),
      (0, 64),
      (960, 60),
      (960, 60),
      (1920, 0),
      (2880, 127),
    ]);
    final overlapping = ons.where((m) => m.data[0] == 60).toList();
    expect(overlapping.map((m) => m.status & 15).toSet(), hasLength(3));
    expect(
      messages
          .where((m) => m.status & 0xf0 == 0x80 && m.data[0] == 64)
          .single
          .tick,
      4800,
    );
    expect(messages.last.tick, 4800);
    expect(() => PlaybackPlan(editor, 120), throwsStateError);
  });

  test('expands repeats and restores tempo, meter and key at jumps', () {
    final editor = ScoreEditor(blankScore);
    for (var i = 0; i < 4; i++) {
      editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 960,
        pitch: Pitch(diatonicStep: 28 + i, midiNote: 60 + i),
        measure: i,
      );
    }
    editor.setMeasureSignatures(1, time: const TimeSignature(3, 4), key: -2);
    editor.setMeasureSignatures(2, time: const TimeSignature(4, 4), key: 3);
    editor.setMeasureTempo(1, 100);
    editor.setMeasureTempo(2, 60);
    editor.setMeasureRepeats(1, start: true, end: false);
    editor.setMeasureRepeats(2, start: false, end: true);
    final events = parseMidi(MidiExport.encode(editor, 120));
    final notes = events.where((e) => e.status & 0xf0 == 0x90);
    expect(notes.map((e) => (e.tick, e.data[0])), [
      (0, 60),
      (3840, 62),
      (6720, 64),
      (10560, 62),
      (13440, 64),
      (17280, 66),
    ]);
    expect(
      events.where((e) => e.tick == 10560 && e.status == 0xff51).single.data,
      [0x09, 0x27, 0xc0],
    );
    expect(
      events.where((e) => e.tick == 10560 && e.status == 0xff58).single.data,
      [3, 2, 24, 8],
    );
    expect(
      events.where((e) => e.tick == 10560 && e.status == 0xff59).single.data,
      [254, 0],
    );
    expect(events.last.tick, 18240);
  });

  test('note-offs precede same-tick note-ons; repeat tail remains silent', () {
    final editor = ScoreEditor(blankScore);
    for (var i = 0; i < 2; i++) {
      editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 960,
        pitch: const Pitch(diatonicStep: 28, midiNote: 60),
        measure: 0,
      );
    }
    editor.setMeasureRepeats(0, start: false, end: true);
    final messages = parseMidi(MidiExport.encode(editor, 120));
    final atBoundary = messages
        .where((m) => m.tick == 960 && m.status < 0xff)
        .toList();
    expect(atBoundary.map((m) => m.status & 0xf0), [0x80, 0x90]);
    expect(messages.last.tick, 7680);
  });

  test('unsupported repeat boundary ties fail explicitly', () {
    final editor = ScoreEditor(blankScore);
    editor.append(voice: Voice.v1, staff: Staff.treble, duration: 2880);
    editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 1920,
      pitch: const Pitch(diatonicStep: 28, midiNote: 60),
    );
    editor.setMeasureRepeats(0, start: false, end: true);
    expect(() => MidiExport.encode(editor, 120), throwsStateError);
  });

  test('empty score is valid and export does not modify a project', () {
    final editor = ScoreEditor(blankScore);
    final project = Project(name: 'Test', tempo: 120, editor: editor);
    final before = ProjectCodec.encode(project);
    final messages = parseMidi(MidiExport.encode(editor, 120));
    expect(messages.last.tick, 0);
    expect(messages.where((e) => e.status == 0xff51).single.data,
        [0x07, 0xa1, 0x20]);
    expect(ProjectCodec.encode(project), before);
  });

  test('end repeat without a start returns to the beginning', () {
    final editor = ScoreEditor(blankScore);
    editor.append(
      voice: Voice.v1, staff: Staff.treble, duration: 960,
      pitch: const Pitch(diatonicStep: 28, midiNote: 60), measure: 0,
    );
    editor.setMeasureRepeats(1, start: false, end: true);
    final messages = parseMidi(MidiExport.encode(editor, 120));
    expect(
      messages.where((m) => m.status & 0xf0 == 0x90).map((m) => m.tick),
      [0, 7680],
    );
    expect(messages.last.tick, 15360);
  });

  test('nested repeats fail explicitly', () {
    final editor = ScoreEditor(blankScore);
    editor.setMeasureRepeats(0, start: true, end: false);
    editor.setMeasureRepeats(1, start: true, end: true);
    expect(() => MidiExport.encode(editor, 120), throwsStateError);
  });

  testWidgets('MIDI menu saves, cancels and reports save errors', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const channel = MethodChannel('claviera/midi');
    final calls = <MethodCall>[];
    var outcome = 0;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (outcome == 2) {
        throw PlatformException(code: 'save_failed', message: 'Disk full');
      }
      return outcome == 0;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const ClavieraApp());
    Future<void> export() async {
      await tester.scrollUntilVisible(
        find.byTooltip('Menu'),
        250,
        scrollable: find.descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Export MIDI'),
        200,
        scrollable: find.descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text('Export MIDI'));
      await tester.pumpAndSettle();
    }

    await export();
    expect(calls.single.arguments['name'], 'Untitled score.mid');
    parseMidi(calls.single.arguments['bytes'] as Uint8List);
    expect(find.text('MIDI saved.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    outcome = 1;
    await export();
    expect(find.text('MIDI saved.'), findsNothing);
    outcome = 2;
    await export();
    expect(find.textContaining('Disk full'), findsOneWidget);
  });
}
