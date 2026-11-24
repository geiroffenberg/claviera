import 'package:claviera/editor/score_editor.dart';
import 'package:claviera/models/score.dart';
import 'package:flutter_test/flutter_test.dart';

const emptyScore = Score(
  title: 'Test',
  beatsPerMeasure: 4,
  beatUnit: 4,
  measures: [Measure()],
);
const c = Pitch(diatonicStep: 28, midiNote: 60);
const d = Pitch(diatonicStep: 29, midiNote: 62);

void main() {
  test('ornaments are mutually exclusive and remain on tied attacks', () {
    final editor = ScoreEditor(emptyScore);
    editor.insertBars(1, 1, initialTempo: 120);
    editor.append(voice: Voice.v1, staff: Staff.treble, duration: 2880);
    final id = editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 1920,
      pitch: c,
    );
    editor.setArticulations(id, {Articulation.trill, Articulation.accent});
    expect(
      () =>
          editor.setArticulations(id, {Articulation.trill, Articulation.turn}),
      throwsA(isA<EditException>()),
    );
    final segments = editor.score.measures
        .expand((m) => m.events)
        .where((event) => event.eventId == id)
        .toList();
    expect(segments.first.articulations, {
      Articulation.trill,
      Articulation.accent,
    });
    expect(segments.last.articulations, isEmpty);
    editor.undo();
    expect(editor.eventById(id)!.articulations, isEmpty);
    editor.redo();
    expect(editor.eventById(id)!.articulations, contains(Articulation.trill));
  });

  test('arpeggios combine voices, follow meter changes and undo deletion', () {
    final editor = ScoreEditor(
      const Score(
        title: '',
        beatsPerMeasure: 4,
        beatUnit: 4,
        measures: [Measure(), Measure()],
      ),
    );
    final first = editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 960,
      pitch: c,
      measure: 1,
    );
    expect(
      () => editor.setArpeggio(3840, ArpeggioDirection.up),
      throwsA(isA<EditException>()),
    );
    final second = editor.append(
      voice: Voice.v2,
      staff: Staff.bass,
      duration: 960,
      pitch: d,
      measure: 1,
    );
    editor.setArpeggio(3840, ArpeggioDirection.down);
    expect(editor.score.measures[1].arpeggios, {0: ArpeggioDirection.down});
    editor.setScoreSettings(beats: 3, unit: 4, key: 0);
    expect(editor.arpeggios, {2880: ArpeggioDirection.down});
    editor.delete(second);
    expect(editor.arpeggios, isEmpty);
    editor.undo();
    expect(editor.arpeggios, {2880: ArpeggioDirection.down});
    expect(editor.eventById(first)!.start, 2880);
    editor.undo();
    expect(editor.arpeggios, {3840: ArpeggioDirection.down});
  });

  test('a fermata on a generated rest survives normalization and undo', () {
    final editor = ScoreEditor(
      const Score(
        title: '',
        beatsPerMeasure: 4,
        beatUnit: 4,
        measures: [
          Measure(
            events: [
              NotationEvent(
                startTick: 960,
                durationTicks: 960,
                voice: Voice.v1,
                staff: Staff.treble,
                pitches: [c],
              ),
            ],
          ),
        ],
      ),
    );
    final rest = editor.eventsFor(Voice.v1).first;
    expect(rest.generatedRest, isTrue);
    editor.setArticulations(rest.id, {Articulation.fermata});
    expect(editor.eventById(rest.id)!.articulations, {Articulation.fermata});
    editor.undo();
    expect(editor.eventById(rest.id)!.generatedRest, isTrue);
    editor.redo();
    expect(editor.eventById(rest.id)!.articulations, {Articulation.fermata});
  });

  test('fermatas work on rests and the last segment of tied notes', () {
    final editor = ScoreEditor(emptyScore);
    editor.insertBars(1, 1, initialTempo: 120);
    final rest = editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 2880,
    );
    editor.setArticulations(rest, {Articulation.fermata});
    final note = editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 1920,
      pitch: c,
    );
    editor.setArticulations(note, {Articulation.accent, Articulation.fermata});
    final segments = editor.score.measures
        .expand((measure) => measure.events)
        .where((event) => event.eventId == note)
        .toList();
    expect(segments.first.articulations, {Articulation.accent});
    expect(segments.last.articulations, {Articulation.fermata});
    expect(editor.eventById(rest)!.articulations, {Articulation.fermata});
    editor.undo();
    expect(editor.eventById(note)!.articulations, isEmpty);
    editor.redo();
    expect(
      editor.eventById(note)!.articulations,
      contains(Articulation.fermata),
    );
  });

  test(
    'double-dotted values keep exact timing and split correctly at barlines',
    () {
      expect(
        [
          NoteValue.whole,
          NoteValue.half,
          NoteValue.quarter,
          NoteValue.eighth,
          NoteValue.sixteenth,
        ].map((value) => value.duration(dots: 2)),
        [6720, 3360, 1680, 840, 420],
      );
      expect(
        () => NoteValue.thirtySecond.duration(dots: 2),
        throwsArgumentError,
      );
      final editor = ScoreEditor(emptyScore);
      editor.insertBars(1, 1, initialTempo: 120);
      editor.append(voice: Voice.v1, staff: Staff.treble, duration: 2880);
      final id = editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: NoteValue.quarter.duration(dots: 2),
        pitch: c,
      );
      final segments = editor.score.measures
          .expand((measure) => measure.events)
          .where((event) => event.eventId == id)
          .toList();
      expect(segments.map((event) => event.durationTicks), [960, 720]);
      expect(segments.first.tieToNext, isTrue);
      expect(segments.last.tieFromPrevious, isTrue);
      expect(editor.eventById(id)!.duration, 1680);
    },
  );

  test(
    'articulations belong to the chord attack and survive edits and undo',
    () {
      final editor = ScoreEditor(emptyScore);
      editor.insertBars(1, 1, initialTempo: 120);
      editor.append(voice: Voice.v1, staff: Staff.treble, duration: 2880);
      final restId = editor.eventsFor(Voice.v1).first.id;
      expect(
        () => editor.setArticulations(restId, {Articulation.accent}),
        throwsA(isA<EditException>()),
      );
      final id = editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 1920,
        pitch: c,
      );
      editor.addPitch(id, d);
      final marks = {
        Articulation.staccato,
        Articulation.tenuto,
        Articulation.accent,
      };
      editor.setArticulations(id, marks);
      marks.clear();
      expect(editor.eventById(id)!.articulations, {
        Articulation.staccato,
        Articulation.tenuto,
        Articulation.accent,
      });
      final segments = editor.score.measures
          .expand((m) => m.events)
          .where((e) => e.eventId == id)
          .toList();
      expect(segments.first.articulations, editor.eventById(id)!.articulations);
      expect(segments.last.articulations, isEmpty);
      editor.undo();
      expect(editor.eventById(id)!.articulations, isEmpty);
      editor.redo();
      editor.delete(id, pitchIndex: 1);
      expect(editor.eventById(id)!.articulations, isNotEmpty);
      editor.delete(id);
      expect(editor.eventById(id)?.articulations ?? {}, isEmpty);
      editor.undo();
      expect(editor.eventById(id)!.articulations, isNotEmpty);
      expect(
        () => editor.setArticulations(id, {
          Articulation.staccatissimo,
          Articulation.tenuto,
        }),
        throwsA(isA<EditException>()),
      );
    },
  );

  test('voices append independently with 32nd and 64th durations', () {
    final editor = ScoreEditor(emptyScore);
    final first = editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 120,
      pitch: c,
    );
    editor.append(voice: Voice.v1, staff: Staff.treble, duration: 60);
    editor.append(voice: Voice.v2, staff: Staff.bass, duration: 960, pitch: d);
    expect(editor.eventById(first)!.start, 0);
    expect(editor.nextTick(Voice.v1), 180);
    expect(editor.eventsFor(Voice.v1).last.isRest, isTrue);
    expect(editor.eventsFor(Voice.v2).single.start, 0);
    expect(() => NoteValue.sixtyFourth.duration(dots: 1), throwsArgumentError);
  });

  test(
    'chords share timing and allow duplicate pitches; deleting a pitch preserves event',
    () {
      final editor = ScoreEditor(emptyScore);
      final id = editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 960,
        pitch: c,
      );
      editor.addPitch(id, c);
      editor.addPitch(id, d);
      expect(editor.eventsFor(Voice.v1), hasLength(1));
      expect(editor.eventById(id)!.pitches, [c, c, d]);
      editor.delete(id, pitchIndex: 1);
      expect(editor.eventById(id)!.pitches, [c, d]);
      expect(editor.nextTick(Voice.v1), 960);
      editor.undo();
      expect(editor.eventById(id)!.pitches, [c, c, d]);
      editor.redo();
      expect(editor.eventById(id)!.pitches, [c, d]);
    },
  );

  test(
    'shorten creates rests, expand consumes them but never moves later notes',
    () {
      final editor = ScoreEditor(emptyScore);
      final id = editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 1920,
        pitch: c,
      );
      final next = editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 960,
        pitch: d,
      );
      editor.resize(id, 960);
      expect(
        editor
            .eventsFor(Voice.v1)
            .map((e) => (e.start, e.duration, e.isRest))
            .toList(),
        [(0, 960, false), (960, 960, true), (1920, 960, false)],
      );
      editor.resize(id, 1440);
      expect(
        editor
            .eventsFor(Voice.v1)
            .map((e) => (e.start, e.duration, e.isRest))
            .toList(),
        [(0, 1440, false), (1440, 480, true), (1920, 960, false)],
      );
      expect(() => editor.resize(id, 1980), throwsA(isA<EditException>()));
      expect(editor.eventById(next)!.start, 1920);
      expect(editor.eventById(id)!.duration, 1440);
      editor.undo();
      expect(editor.eventById(id)!.duration, 960);
      editor.redo();
      expect(editor.eventById(id)!.duration, 1440);
    },
  );

  test(
    'deleting internal notes leaves rests; deleting last notes does not pad the tail',
    () {
      final editor = ScoreEditor(emptyScore);
      final first = editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 960,
        pitch: c,
      );
      final last = editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 960,
        pitch: d,
      );
      editor.delete(first);
      expect(editor.eventById(first)!.isRest, isTrue);
      expect(editor.eventById(last)!.start, 960);
      editor.delete(last);
      expect(editor.eventsFor(Voice.v1), isEmpty);
      editor.undo();
      expect(editor.eventById(last), isNotNull);
      expect(editor.eventById(first)!.isRest, isTrue);
    },
  );

  test('replace a selected rest, split remainder, reject longer notes', () {
    final editor = ScoreEditor(emptyScore);
    final rest = editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 180,
    );
    editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 960,
      pitch: d,
    );
    expect(
      () => editor.replaceRest(rest, 240, c, Staff.treble),
      throwsA(isA<EditException>()),
    );
    editor.replaceRest(rest, 120, c, Staff.treble);
    expect(
      editor
          .eventsFor(Voice.v1)
          .map((e) => (e.start, e.duration, e.isRest))
          .toList(),
      [(0, 120, false), (120, 60, true), (180, 960, false)],
    );
    editor.undo();
    expect(editor.eventById(rest)!.isRest, isTrue);
  });

  test(
    'a note can cross an explicitly added bar and both actions are undoable',
    () {
      final editor = ScoreEditor(emptyScore);
      editor.append(voice: Voice.v1, staff: Staff.treble, duration: 2880);
      editor.insertBars(1, 1, initialTempo: 120);
      final id = editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 1920,
        pitch: c,
      );
      final score = editor.score;
      expect(score.measures, hasLength(2));
      final first = score.measures[0].events.singleWhere(
        (e) => e.eventId == id,
      );
      final second = score.measures[1].events.singleWhere(
        (e) => e.eventId == id,
      );
      expect(
        (
          first.startTick,
          first.durationTicks,
          first.tieFromPrevious,
          first.tieToNext,
        ),
        (2880, 960, false, true),
      );
      expect(
        (
          second.startTick,
          second.durationTicks,
          second.tieFromPrevious,
          second.tieToNext,
        ),
        (0, 960, true, false),
      );
      editor.undo();
      expect(editor.score.measures, hasLength(2));
      editor.undo();
      expect(editor.score.measures, hasLength(1));
      editor.redo();
      editor.redo();
      expect(editor.score.measures, hasLength(2));
    },
  );

  test('a trailing rest can be resized, but cannot override a later event', () {
    final editor = ScoreEditor(emptyScore);
    final rest = editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 960,
    );
    editor.resize(rest, 1920);
    expect(editor.nextTick(Voice.v1), 1920);
    editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 960,
      pitch: c,
    );
    expect(() => editor.resize(rest, 2880), throwsA(isA<EditException>()));
    expect(editor.nextTick(Voice.v1), 2880);
  });

  test(
    'clearing an earlier bar leaves it empty and allows direct re-entry',
    () {
      const score = Score(
        title: 'bars',
        beatsPerMeasure: 4,
        beatUnit: 4,
        measures: [
          Measure(
            events: [
              NotationEvent(
                startTick: 0,
                durationTicks: 960,
                voice: Voice.v1,
                staff: Staff.treble,
                pitches: [c],
              ),
              NotationEvent(
                startTick: 960,
                durationTicks: 960,
                voice: Voice.v1,
                staff: Staff.treble,
                pitches: [d],
              ),
              NotationEvent(
                startTick: 0,
                durationTicks: 960,
                voice: Voice.v2,
                staff: Staff.bass,
                pitches: [c],
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
                pitches: [d],
              ),
            ],
          ),
        ],
      );
      final editor = ScoreEditor(score);
      final earlier = editor
          .eventsFor(Voice.v1)
          .where((e) => e.start < 3840)
          .toList();
      final later = editor.eventsFor(Voice.v1).last;
      editor.delete(earlier[1].id);
      expect(editor.nextTick(Voice.v1, measure: 0), 960);
      editor.delete(earlier[0].id);
      expect(editor.nextTick(Voice.v1, measure: 0), 0);
      expect(
        editor.score.measures[0].events.where((e) => e.voice == Voice.v1),
        isEmpty,
      );
      expect(
        editor.score.measures[0].events.where((e) => e.voice == Voice.v2),
        hasLength(1),
      );
      expect(editor.eventById(later.id)!.start, 3840);
      editor.undo();
      expect(editor.nextTick(Voice.v1, measure: 0), 960);
      editor.redo();
      final newId = editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 480,
        pitch: c,
        measure: 0,
      );
      expect(editor.eventById(newId)!.start, 0);
      expect(editor.eventById(later.id)!.start, 3840);
      expect(editor.nextTick(Voice.v1, measure: 0), 480);
    },
  );

  test(
    'internal gaps get rests but trailing generated rests are removed per bar',
    () {
      const score = Score(
        title: 'bars',
        beatsPerMeasure: 4,
        beatUnit: 4,
        measures: [
          Measure(
            events: [
              NotationEvent(
                startTick: 0,
                durationTicks: 960,
                voice: Voice.v1,
                staff: Staff.treble,
                pitches: [c],
              ),
              NotationEvent(
                startTick: 960,
                durationTicks: 960,
                voice: Voice.v1,
                staff: Staff.treble,
                pitches: [d],
              ),
              NotationEvent(
                startTick: 1920,
                durationTicks: 960,
                voice: Voice.v1,
                staff: Staff.treble,
                pitches: [c],
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
                pitches: [d],
              ),
            ],
          ),
        ],
      );
      final editor = ScoreEditor(score);
      final events = editor.eventsFor(Voice.v1);
      editor.delete(events[1].id);
      expect(
        editor.eventsFor(Voice.v1).map((e) => (e.start, e.isRest)).toList(),
        [(0, false), (960, true), (1920, false), (3840, false)],
      );
      editor.delete(events[2].id);
      expect(
        editor.eventsFor(Voice.v1).map((e) => (e.start, e.isRest)).toList(),
        [(0, false), (3840, false)],
      );
      expect(editor.nextTick(Voice.v1, measure: 0), 960);
      editor.resize(events[0].id, 480);
      expect(editor.nextTick(Voice.v1, measure: 0), 480);
      expect(editor.eventById(events[3].id)!.start, 3840);
    },
  );

  test('explicit trailing rests remain and later bars can start empty', () {
    const score = Score(
      title: 'bars',
      beatsPerMeasure: 4,
      beatUnit: 4,
      measures: [
        Measure(
          events: [
            NotationEvent(
              startTick: 0,
              durationTicks: 960,
              voice: Voice.v1,
              staff: Staff.treble,
            ),
            NotationEvent(
              startTick: 960,
              durationTicks: 960,
              voice: Voice.v1,
              staff: Staff.treble,
              pitches: [c],
            ),
          ],
        ),
        Measure(),
        Measure(
          events: [
            NotationEvent(
              startTick: 0,
              durationTicks: 960,
              voice: Voice.v1,
              staff: Staff.treble,
              pitches: [d],
            ),
          ],
        ),
      ],
    );
    final editor = ScoreEditor(score);
    final note = editor.eventsFor(Voice.v1)[1];
    editor.delete(note.id);
    expect(editor.eventsFor(Voice.v1).first.isRest, isTrue);
    expect(editor.eventsFor(Voice.v1).first.generatedRest, isFalse);
    expect(editor.nextTick(Voice.v1, measure: 0), 960);
    expect(editor.nextTick(Voice.v1, measure: 1), 3840);
    expect(editor.score.measures[1].events, isEmpty);
    final inserted = editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 960,
      pitch: c,
      measure: 1,
    );
    expect(editor.eventById(inserted)!.start, 3840);
    expect(editor.score.measures[2].events.single.startTick, 0);
  });

  test('tied events occupy both bars and cannot overwrite later events', () {
    const score = Score(
      title: 'bars',
      beatsPerMeasure: 4,
      beatUnit: 4,
      measures: [Measure(), Measure(), Measure()],
    );
    final editor = ScoreEditor(score);
    editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 2880,
      measure: 0,
    );
    final tie = editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 1920,
      pitch: c,
      measure: 0,
    );
    final later = editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 960,
      pitch: d,
      measure: 1,
    );
    expect(editor.nextTick(Voice.v1, measure: 0), 3840);
    expect(editor.eventById(later)!.start, 4800);
    expect(
      () => editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 960,
        pitch: c,
        measure: 0,
      ),
      throwsA(isA<EditException>()),
    );
    editor.delete(tie);
    expect(editor.nextTick(Voice.v1, measure: 0), 2880);
    expect(editor.eventById(later)!.start, 4800);
    expect(
      editor.score.measures[1].events
          .where((e) => e.isRest)
          .single
          .durationTicks,
      960,
    );
    editor.undo();
    final segments = editor.score.measures
        .expand((m) => m.events)
        .where((e) => e.eventId == tie)
        .toList();
    expect(segments, hasLength(2));
    expect(segments.first.tieToNext, isTrue);
    expect(segments.last.tieFromPrevious, isTrue);
  });

  test('separately entered matching notes can be tied and untied', () {
    final editor = ScoreEditor(emptyScore);
    editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 960,
      pitch: c,
    );
    final next = editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 960,
      pitch: c,
    );

    editor.toggleTieToPrevious(next);
    var notes = editor.score.measures.single.events
        .where((event) => !event.isRest)
        .toList();
    expect(notes, hasLength(2));
    expect(notes.first.tieToNext, isTrue);
    expect(notes.last.tieFromPrevious, isTrue);

    editor.undo();
    notes = editor.score.measures.single.events
        .where((event) => !event.isRest)
        .toList();
    expect(notes.first.tieToNext, isFalse);
    expect(notes.last.tieFromPrevious, isFalse);

    editor.redo();
    notes = editor.score.measures.single.events
        .where((event) => !event.isRest)
        .toList();
    expect(notes.first.tieToNext, isTrue);
    expect(notes.last.tieFromPrevious, isTrue);

    editor.toggleTieToPrevious(next);
    notes = editor.score.measures.single.events
        .where((event) => !event.isRest)
        .toList();
    expect(notes.first.tieToNext, isFalse);
    expect(notes.last.tieFromPrevious, isFalse);
  });

  test('write tie rejects a different pitch without inserting it', () {
    final editor = ScoreEditor(emptyScore);
    editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 960,
      pitch: c,
    );

    expect(
      () => editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 960,
        pitch: d,
        tieToPrevious: true,
      ),
      throwsA(isA<EditException>()),
    );
    expect(
      editor.eventsFor(Voice.v1).where((event) => !event.isRest),
      hasLength(1),
    );
    expect(editor.nextTick(Voice.v1), 960);
  });

  test(
    'a tied note can consume generated rest in the next bar without moving later notes',
    () {
      const score = Score(
        title: 'bars',
        beatsPerMeasure: 4,
        beatUnit: 4,
        measures: [
          Measure(
            events: [
              NotationEvent(
                startTick: 0,
                durationTicks: 2880,
                voice: Voice.v1,
                staff: Staff.treble,
              ),
            ],
          ),
          Measure(
            events: [
              NotationEvent(
                startTick: 1920,
                durationTicks: 960,
                voice: Voice.v1,
                staff: Staff.treble,
                pitches: [d],
              ),
            ],
          ),
        ],
      );
      final editor = ScoreEditor(score);
      final later = editor.eventsFor(Voice.v1).last;
      final id = editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 1920,
        pitch: c,
        measure: 0,
      );
      expect(editor.eventById(id)!.start, 2880);
      expect(editor.eventById(later.id)!.start, 5760);
      expect(
        editor.score.measures[1].events
            .where((e) => e.voice == Voice.v1 && e.isRest)
            .single
            .startTick,
        960,
      );
      editor.undo();
      expect(
        editor.score.measures[1].events
            .where((e) => e.voice == Voice.v1 && e.isRest)
            .single
            .durationTicks,
        1920,
      );
    },
  );
}
