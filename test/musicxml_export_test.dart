import 'dart:convert';

import 'package:claviera/editor/score_editor.dart';
import 'package:claviera/main.dart';
import 'package:claviera/models/blank_score.dart';
import 'package:claviera/models/score.dart';
import 'package:claviera/notation/musicxml_export.dart';
import 'package:claviera/storage/projects.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

void main() {
  test(
    'exports one linked arpeggio across voices and only on tied attacks',
    () {
      final editor = ScoreEditor(blankScore);
      final chord = editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 4800,
        pitch: const Pitch(diatonicStep: 28, midiNote: 60),
      );
      editor.addPitch(chord, const Pitch(diatonicStep: 30, midiNote: 64));
      editor.append(
        voice: Voice.v2,
        staff: Staff.bass,
        duration: 960,
        pitch: const Pitch(diatonicStep: 21, midiNote: 48),
      );
      editor.setArpeggio(0, ArpeggioDirection.down);
      final xml = XmlDocument.parse(
        utf8.decode(MusicXmlExport.encode(editor, 120, 'Arpeggio')),
      );
      final marks = xml.findAllElements('arpeggiate').toList();
      expect(marks, hasLength(3));
      expect(
        marks.map((mark) => mark.getAttribute('direction')),
        everyElement('down'),
      );
      expect(
        marks.map((mark) => mark.getAttribute('number')),
        everyElement('1'),
      );
      expect(
        xml
            .findAllElements('measure')
            .toList()[1]
            .findAllElements('arpeggiate'),
        isEmpty,
      );
    },
  );

  test('exports fermatas on rests and the last segment of a tied chord', () {
    final editor = ScoreEditor(blankScore);
    final rest = editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 2880,
    );
    final chord = editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 1920,
      pitch: const Pitch(diatonicStep: 28, midiNote: 60),
    );
    editor.addPitch(chord, const Pitch(diatonicStep: 30, midiNote: 64));
    editor.setArticulations(rest, {Articulation.fermata});
    editor.setArticulations(chord, {Articulation.fermata, Articulation.accent});
    final xml = XmlDocument.parse(
      utf8.decode(MusicXmlExport.encode(editor, 120, 'Fermata')),
    );
    final fermatas = xml.findAllElements('fermata').toList();
    expect(fermatas, hasLength(2));
    expect(
      fermatas.first.parentElement!.parentElement!.getElement('rest'),
      isNotNull,
    );
    expect(
      fermatas.last.parentElement!.parentElement!.getElement('chord'),
      isNull,
    );
    expect(
      fermatas.last.parentElement!.getElement('tied')!.getAttribute('type'),
      'stop',
    );
    expect(
      xml.findAllElements('articulations').single.getElement('accent'),
      isNotNull,
    );
  });

  test('exports both dots and exact durations for notes and rests', () {
    final editor = ScoreEditor(blankScore);
    editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: NoteValue.quarter.duration(dots: 2),
      pitch: const Pitch(diatonicStep: 28, midiNote: 60),
    );
    editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: NoteValue.sixteenth.duration(dots: 2),
    );
    final xml = XmlDocument.parse(
      utf8.decode(MusicXmlExport.encode(editor, 120, 'Dots')),
    );
    final notes = xml
        .findAllElements('measure')
        .first
        .findElements('note')
        .toList();
    expect(notes.map((note) => note.getElement('duration')!.innerText), [
      '1680',
      '420',
    ]);
    expect(notes.map((note) => note.getElement('type')!.innerText), [
      'quarter',
      '16th',
    ]);
    expect(notes.map((note) => note.findElements('dot').length), [2, 2]);
    expect(notes.last.getElement('rest'), isNotNull);
  });

  test('exports articulations once on a chord attack alongside ties', () {
    final editor = ScoreEditor(blankScore);
    editor.append(voice: Voice.v1, staff: Staff.treble, duration: 2880);
    final id = editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 1920,
      pitch: const Pitch(diatonicStep: 28, midiNote: 60),
    );
    editor.addPitch(id, const Pitch(diatonicStep: 30, midiNote: 64));
    editor.setArticulations(id, {
      Articulation.staccato,
      Articulation.tenuto,
      Articulation.marcato,
    });
    final xml = XmlDocument.parse(
      utf8.decode(MusicXmlExport.encode(editor, 120, 'Marks')),
    );
    final marks = xml.findAllElements('articulations').single;
    expect(marks.childElements.map((e) => e.name.local), [
      'staccato',
      'tenuto',
      'strong-accent',
    ]);
    expect(marks.getElement('strong-accent')!.getAttribute('type'), 'down');
    expect(
      marks.getElement('strong-accent')!.getAttribute('placement'),
      'below',
    );
    final notations = marks.parentElement!;
    expect(notations.findElements('tied').single.getAttribute('type'), 'start');
    expect(xml.findAllElements('tied'), hasLength(4));
  });

  test('exports score structure, voices, ties, signatures and repeats', () {
    final editor = ScoreEditor(
      Score(
        title: 'Source',
        beatsPerMeasure: 4,
        beatUnit: 4,
        measures: [
          const Measure(
            repeatStart: true,
            events: [
              NotationEvent(
                startTick: 0,
                durationTicks: 1440,
                voice: Voice.v1,
                staff: Staff.treble,
                pitches: [Pitch(diatonicStep: 28, midiNote: 60)],
              ),
              NotationEvent(
                startTick: 2880,
                durationTicks: 1920,
                voice: Voice.v1,
                staff: Staff.treble,
                pitches: [
                  Pitch(
                    diatonicStep: 28,
                    midiNote: 61,
                    accidental: Accidental.sharp,
                  ),
                  Pitch(diatonicStep: 30, midiNote: 64),
                ],
              ),
              NotationEvent(
                startTick: 960,
                durationTicks: 960,
                voice: Voice.v2,
                staff: Staff.bass,
                pitches: [Pitch(diatonicStep: 21, midiNote: 48)],
              ),
            ],
          ),
          const Measure(
            timeSignature: TimeSignature(3, 4),
            keySignature: -2,
            tempo: 90,
            repeatEnd: true,
          ),
          const Measure(),
        ],
      ),
    );
    final project = Project(name: 'A & B <score>', tempo: 120, editor: editor);
    final before = ProjectCodec.encode(project);
    final xml = XmlDocument.parse(
      utf8.decode(MusicXmlExport.encode(editor, project.tempo, project.name)),
    );
    expect(ProjectCodec.encode(project), before);
    expect(xml.rootElement.name.local, 'score-partwise');
    expect(xml.rootElement.getAttribute('version'), '4.0');
    expect(xml.findAllElements('work-title').single.innerText, project.name);
    expect(xml.findAllElements('divisions').single.innerText, '960');
    expect(xml.findAllElements('staves').single.innerText, '2');
    expect(xml.findAllElements('clef').map((e) => e.innerText), ['G2', 'F4']);

    final measures = xml.findAllElements('measure').toList();
    expect(measures, hasLength(3));
    expect(measures[0].findAllElements('fifths').single.innerText, '0');
    expect(measures[1].findAllElements('fifths').single.innerText, '-2');
    expect(measures[1].findAllElements('beats').single.innerText, '3');
    expect(measures[1].findAllElements('beat-type').single.innerText, '4');
    expect(xml.findAllElements('sound').map((e) => e.getAttribute('tempo')), [
      '120',
      '90',
    ]);
    expect(
      xml.findAllElements('repeat').map((e) => e.getAttribute('direction')),
      ['forward', 'backward'],
    );

    final firstNotes = measures[0].findElements('note').toList();
    expect(firstNotes.first.getElement('type')!.innerText, 'quarter');
    expect(firstNotes.first.getElement('dot'), isNotNull);
    expect(firstNotes.any((note) => note.getElement('rest') != null), isTrue);
    final sharp = firstNotes.singleWhere(
      (note) => note.getElement('accidental')?.innerText == 'sharp',
    );
    expect(sharp.getElement('pitch')!.getElement('alter')!.innerText, '1');
    expect(sharp.findElements('tie').single.getAttribute('type'), 'start');
    final chord = firstNotes.singleWhere(
      (note) => note.getElement('chord') != null,
    );
    expect(chord.findElements('tie').single.getAttribute('type'), 'start');
    expect(measures[0].findElements('backup').single.innerText, '3840');
    expect(firstNotes.last.getElement('staff')!.innerText, '2');
    final continuations = measures[1].findElements('note').toList();
    expect(continuations, hasLength(2));
    expect(
      continuations.every(
        (n) => n.findElements('tie').single.getAttribute('type') == 'stop',
      ),
      isTrue,
    );
    expect(
      continuations.first.getElement('pitch')!.getElement('alter')!.innerText,
      '1',
    );
    expect(continuations.first.getElement('accidental'), isNull);
    expect(
      measures[2]
          .findElements('note')
          .single
          .getElement('rest')!
          .getAttribute('measure'),
      'yes',
    );
    expect(
      measures[2].findElements('note').single.getElement('duration')!.innerText,
      '2880',
    );
  });

  test('exports an empty score and rejects invalid tempo', () {
    final editor = ScoreEditor(blankScore);
    final xml = XmlDocument.parse(
      utf8.decode(MusicXmlExport.encode(editor, 120, 'Empty')),
    );
    expect(xml.findAllElements('measure'), hasLength(4));
    expect(xml.findAllElements('rest'), hasLength(4));
    expect(
      () => MusicXmlExport.encode(editor, 0, 'Empty'),
      throwsArgumentError,
    );
  });

  test('preserves sounding alterations and omits stems on whole notes', () {
    final editor = ScoreEditor(
      const Score(
        title: 'Key',
        beatsPerMeasure: 6,
        beatUnit: 4,
        keySignature: 1,
        measures: [
          Measure(
            events: [
              NotationEvent(
                startTick: 0,
                durationTicks: 5760,
                voice: Voice.v1,
                staff: Staff.treble,
                pitches: [Pitch(diatonicStep: 31, midiNote: 66)],
              ),
            ],
          ),
          Measure(
            events: [
              NotationEvent(
                startTick: 0,
                durationTicks: 960,
                voice: Voice.v1,
                staff: Staff.treble,
                pitches: [
                  Pitch(
                    diatonicStep: 31,
                    midiNote: 65,
                    accidental: Accidental.natural,
                  ),
                ],
              ),
              NotationEvent(
                startTick: 960,
                durationTicks: 960,
                voice: Voice.v1,
                staff: Staff.treble,
                pitches: [Pitch(diatonicStep: 31, midiNote: 66)],
              ),
            ],
          ),
        ],
      ),
    );
    final xml = XmlDocument.parse(
      utf8.decode(MusicXmlExport.encode(editor, 120, 'Key')),
    );
    final notes = xml.findAllElements('note').toList();
    expect(notes[0].getElement('type')!.innerText, 'whole');
    expect(notes[0].getElement('dot'), isNotNull);
    expect(notes[0].getElement('stem'), isNull);
    expect(notes[0].getElement('pitch')!.getElement('alter')!.innerText, '1');
    expect(notes[1].getElement('pitch')!.getElement('alter'), isNull);
    expect(notes[1].getElement('accidental')!.innerText, 'natural');
    expect(notes[2].getElement('pitch')!.getElement('alter')!.innerText, '1');
  });

  testWidgets('MusicXML menu saves, cancels and reports save errors', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const channel = MethodChannel('claviera/musicxml');
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
        find.text('Export MusicXML'),
        200,
        scrollable: find.descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text('Export MusicXML'));
      await tester.pumpAndSettle();
    }

    await export();
    expect(calls.single.arguments['name'], 'Untitled score.musicxml');
    final bytes = calls.single.arguments['bytes'] as Uint8List;
    expect(
      XmlDocument.parse(utf8.decode(bytes)).rootElement.name.local,
      'score-partwise',
    );
    expect(find.text('MusicXML saved.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    outcome = 1;
    await export();
    expect(find.text('MusicXML saved.'), findsNothing);
    outcome = 2;
    await export();
    expect(find.textContaining('Disk full'), findsOneWidget);
  });
}
