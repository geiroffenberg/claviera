import 'dart:convert';
import 'dart:io';

import 'package:claviera/editor/score_editor.dart';
import 'package:claviera/models/blank_score.dart';
import 'package:claviera/models/score.dart';
import 'package:claviera/storage/projects.dart';
import 'package:claviera/ui/workspace_screen.dart';
import 'package:claviera/notation/score_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const fSharp = Pitch(diatonicStep: 31, midiNote: 66);
const natural = Pitch(
  diatonicStep: 31,
  midiNote: 65,
  accidental: Accidental.natural,
);

class MemoryStore extends ProjectStore {
  final files = <String, String>{};
  RecoveryDraft? draft;

  @override
  Future<RecoveryDraft?> readRecovery() async => draft;

  @override
  Future<void> writeRecovery(RecoveryDraft value) async => draft = value;

  @override
  Future<void> clearRecovery() async => draft = null;

  @override
  Future<String> save(Project project, {String? id}) async {
    final key = id ?? '${files.length + 1}-1';
    files[key] = ProjectCodec.encode(project);
    return key;
  }

  @override
  Future<List<StoredProject>> list() async => [
    for (final entry in files.entries)
      StoredProject(
        entry.key,
        ProjectCodec.decode(entry.value).name,
        DateTime(2026),
      ),
  ];

  @override
  Future<Project> load(String id) async => ProjectCodec.decode(files[id]!);
}

class FailingStore extends MemoryStore {
  @override
  Future<String> save(Project project, {String? id}) async {
    throw const FileSystemException('Storage unavailable');
  }
}

class FailingRecoveryStore extends MemoryStore {
  @override
  Future<void> writeRecovery(RecoveryDraft value) async {
    throw const FileSystemException('Recovery storage unavailable');
  }
}

void main() {
  test('ornaments and arpeggios survive project round-trip', () {
    final editor = ScoreEditor(blankScore);
    final id = editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 960,
      pitch: fSharp,
    );
    editor.addPitch(id, natural);
    editor.setArticulations(id, {
      Articulation.lowerMordent,
      Articulation.accent,
    });
    final project = Project(name: 'Ornaments', tempo: 120, editor: editor);
    var encoded = ProjectCodec.encode(project);
    expect((jsonDecode(encoded) as Map<String, dynamic>)['version'], 9);
    expect(
      ProjectCodec.decode(
        encoded,
      ).editor.eventsFor(Voice.v1).first.articulations,
      {Articulation.lowerMordent, Articulation.accent},
    );
    editor.setArpeggio(0, ArpeggioDirection.up);
    encoded = ProjectCodec.encode(project);
    expect(ProjectCodec.decode(encoded).editor.arpeggios, {
      0: ArpeggioDirection.up,
    });
    final raw = jsonDecode(encoded) as Map<String, dynamic>;
    final event = (raw['events'] as List).first as Map<String, dynamic>;
    event['articulations'] = ['trill', 'turn'];
    expect(() => ProjectCodec.decode(jsonEncode(raw)), throwsFormatException);
  });

  test('arpeggios round-trip and malformed arpeggios are rejected', () {
    final editor = ScoreEditor(blankScore);
    final id = editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 960,
      pitch: fSharp,
    );
    editor.addPitch(id, natural);
    editor.setArpeggio(0, ArpeggioDirection.down);
    final encoded = ProjectCodec.encode(
      Project(name: 'Arpeggio', tempo: 120, editor: editor),
    );
    final document = jsonDecode(encoded) as Map<String, dynamic>;
    expect(document['version'], 8);
    expect(ProjectCodec.decode(encoded).editor.arpeggios, {
      0: ArpeggioDirection.down,
    });
    final marks = document['arpeggios'] as List;
    marks.add(marks.first);
    expect(
      () => ProjectCodec.decode(jsonEncode(document)),
      throwsFormatException,
    );
    marks.removeLast();
    (marks.first as Map<String, dynamic>)['tick'] = 960;
    expect(
      () => ProjectCodec.decode(jsonEncode(document)),
      throwsFormatException,
    );
  });

  test('fermatas on notes and rests survive saving', () {
    final editor = ScoreEditor(blankScore);
    final rest = editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 960,
    );
    final note = editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 960,
      pitch: fSharp,
    );
    editor.setArticulations(rest, {Articulation.fermata});
    editor.setArticulations(note, {Articulation.fermata, Articulation.accent});
    final saved = ProjectCodec.encode(
      Project(name: 'Fermata', tempo: 120, editor: editor),
    );
    final restored = ProjectCodec.decode(saved).editor.eventsFor(Voice.v1);
    expect(restored.first.articulations, {Articulation.fermata});
    expect(restored.last.articulations, {
      Articulation.fermata,
      Articulation.accent,
    });
  });

  test('double-dotted events survive project round-trip', () {
    final editor = ScoreEditor(blankScore);
    editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: NoteValue.quarter.duration(dots: 2),
      pitch: fSharp,
    );
    editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: NoteValue.sixteenth.duration(dots: 2),
    );
    final encoded = ProjectCodec.encode(
      Project(name: 'Dots', tempo: 120, editor: editor),
    );
    final restored = ProjectCodec.decode(encoded);
    expect(ProjectCodec.encode(restored), encoded);
    expect(
      restored.editor.score.measures.first.events.map(
        (event) => event.durationTicks,
      ),
      [1680, 420],
    );
  });

  test(
    'articulations round-trip with other project features and reject invalid marks',
    () {
      final editor = ScoreEditor(blankScore);
      final id = editor.append(
        voice: Voice.v1,
        staff: Staff.treble,
        duration: 960,
        pitch: fSharp,
      );
      editor.setArticulations(id, {Articulation.staccato, Articulation.accent});
      editor.setMeasureTempo(1, 80);
      editor.setMeasureSignatures(1, key: 1);
      editor.setMeasureRepeats(1, start: false, end: true);
      editor.setDynamic(0, DynamicMark.mf);
      editor.startHairpin(960, HairpinKind.crescendo);
      editor.endHairpin(1920);
      final encoded = ProjectCodec.encode(
        Project(name: 'Test', tempo: 120, editor: editor),
      );
      final document = jsonDecode(encoded) as Map<String, dynamic>;
      expect(document['version'], 7);
      final restored = ProjectCodec.decode(encoded);
      expect(ProjectCodec.encode(restored), encoded);
      expect(restored.editor.eventsFor(Voice.v1).first.articulations, {
        Articulation.staccato,
        Articulation.accent,
      });
      final event = (document['events'] as List).first as Map<String, dynamic>;
      event['articulations'] = ['staccato', 'staccato'];
      expect(
        () => ProjectCodec.decode(jsonEncode(document)),
        throwsFormatException,
      );
      event['articulations'] = ['staccatissimo', 'tenuto'];
      expect(
        () => ProjectCodec.decode(jsonEncode(document)),
        throwsFormatException,
      );
      event['articulations'] = ['unknown'];
      expect(
        () => ProjectCodec.decode(jsonEncode(document)),
        throwsFormatException,
      );
      event['articulations'] = ['accent'];
      event['pitches'] = [];
      expect(
        () => ProjectCodec.decode(jsonEncode(document)),
        throwsFormatException,
      );
    },
  );

  test('round trip preserves logical ties, voices, rests and settings', () {
    final editor = ScoreEditor(blankScore);
    editor.setScoreSettings(beats: 4, unit: 4, key: 1);
    editor.append(voice: Voice.v1, staff: Staff.treble, duration: 2880);
    final chord = editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 1920,
      pitch: fSharp,
    );
    editor.addPitch(chord, natural);
    editor.append(
      voice: Voice.v2,
      staff: Staff.bass,
      duration: 480,
      pitch: fSharp,
      measure: 2,
    );
    final original = Project(name: 'Sketch', tempo: 75, editor: editor);
    final encoded = ProjectCodec.encode(original);
    final decoded = ProjectCodec.decode(encoded);
    expect(ProjectCodec.encode(decoded), encoded);
    expect(decoded.tempo, 75);
    expect(decoded.editor.measureCount, 4);
    expect(
      decoded.editor
          .eventsFor(Voice.v1)
          .where((e) => !e.isRest)
          .single
          .duration,
      1920,
    );
    expect(
      decoded.editor.score.measures[0].events
          .where((e) => e.voice == Voice.v1 && !e.isRest)
          .last
          .tieToNext,
      true,
    );
    expect(
      decoded.editor.score.measures[1].events
          .where((e) => e.voice == Voice.v1 && !e.isRest)
          .first
          .tieFromPrevious,
      true,
    );
    expect(decoded.editor.eventsFor(Voice.v1).first.generatedRest, false);
    expect(decoded.editor.eventsFor(Voice.v2).single.start, 7680);
  });

  test('malformed, unsupported and overlapping projects are rejected', () {
    expect(() => ProjectCodec.decode('not json'), throwsFormatException);
    final document =
        jsonDecode(
              ProjectCodec.encode(
                Project(name: 'x', tempo: 120, editor: ScoreEditor(blankScore)),
              ),
            )
            as Map<String, dynamic>;
    document['version'] = 2;
    expect(
      () => ProjectCodec.decode(jsonEncode(document)),
      throwsFormatException,
    );
    document['version'] = 1;
    final event = {
      'start': 0,
      'duration': 960,
      'voice': 'v1',
      'staff': 'treble',
      'pitches': [],
    };
    document['events'] = [event, event];
    expect(
      () => ProjectCodec.decode(jsonEncode(document)),
      throwsFormatException,
    );
  });

  test('projects survive reopening and overwrite only their own ID', () async {
    final dir = await Directory.systemTemp.createTemp('claviera-project-test-');
    addTearDown(() => dir.delete(recursive: true));
    final store = ProjectStore(directory: () async => dir);
    final editor = ScoreEditor(blankScore);
    final id = await store.save(
      Project(name: 'First', tempo: 120, editor: editor),
    );
    final second = await store.save(
      Project(name: 'First', tempo: 60, editor: editor),
    );
    expect(id, isNot(second));
    await store.save(
      Project(name: 'Renamed', tempo: 90, editor: editor),
      id: id,
    );
    final reopened = ProjectStore(directory: () async => dir);
    expect((await reopened.list()).map((p) => p.name), ['First', 'Renamed']);
    expect((await reopened.load(id)).tempo, 90);
    expect((await reopened.load(second)).tempo, 60);
    expect(() => reopened.load('../bad'), throwsFormatException);
  });

  test('bundled Dream project installs once and remains loadable', () async {
    final source = ProjectCodec.decode(
      await rootBundle.loadString('assets/demo/Dream.claviera'),
    );
    expect(source.editor.measureCount, 7);
    expect(
      Voice.values.every(
        (voice) => source.editor
            .storedEventsFor(voice)
            .any((event) => !event.generatedRest),
      ),
      isTrue,
    );

    final dir = await Directory.systemTemp.createTemp('claviera-demo-test-');
    addTearDown(() => dir.delete(recursive: true));
    final store = ProjectStore(directory: () async => dir);
    final demo = Project(
      name: 'Dream',
      tempo: source.tempo,
      editor: source.editor,
    );

    await store.ensureDemoProject(demo);
    await store.ensureDemoProject(
      Project(name: 'Replacement', tempo: 120, editor: ScoreEditor(blankScore)),
    );

    expect((await store.list()).map((item) => item.name), ['Dream']);
    final loaded = await store.load(ProjectStore.demoProjectId);
    expect(ProjectCodec.encode(loaded), ProjectCodec.encode(demo));
  });

  test('recovery drafts persist separately from saved projects', () async {
    final dir = await Directory.systemTemp.createTemp(
      'claviera-recovery-test-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final store = ProjectStore(directory: () async => dir);
    final original = ProjectCodec.encode(
      Project(name: 'Sketch', tempo: 120, editor: ScoreEditor(blankScore)),
    );
    final edited = ProjectCodec.encode(
      Project(name: 'Sketch', tempo: 90, editor: ScoreEditor(blankScore)),
    );
    await store.writeRecovery(
      RecoveryDraft(contents: edited, savedState: original, projectId: '1-1'),
    );
    final recovered = await store.readRecovery();
    expect(recovered!.contents, edited);
    expect(recovered.savedState, original);
    expect(recovered.projectId, '1-1');
    expect(await store.list(), isEmpty);
    await store.clearRecovery();
    expect(await store.readRecovery(), isNull);
  });

  testWidgets('unsaved draft can be recovered without overwriting the save', (
    tester,
  ) async {
    final store = MemoryStore();
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: WorkspaceScreen(projectStore: store)),
    );
    await tester.pumpAndSettle();
    final canvas = find.byKey(const ValueKey('score-canvas'));
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(160, 115));
    await tester.pumpAndSettle();
    expect(store.draft, isNotNull);
    expect(store.files, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(home: WorkspaceScreen(projectStore: store)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Recover unsaved work?'), findsOneWidget);
    await tester.tap(find.text('Restore draft'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ScoreViewport>(find.byType(ScoreViewport))
          .score
          .measures
          .first
          .events,
      hasLength(1),
    );
    expect(store.files, isEmpty);
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
    await tester.tap(find.text('New score'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('backup contains the current unsaved score', (tester) async {
    final store = MemoryStore();
    Uint8List? bytes;
    String? name;
    const channel = MethodChannel('claviera/projects');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'backup') {
        bytes = call.arguments['bytes'] as Uint8List;
        name = call.arguments['name'] as String;
        return true;
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: WorkspaceScreen(projectStore: store)),
    );
    await tester.pumpAndSettle();
    final canvas = find.byKey(const ValueKey('score-canvas'));
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(160, 115));
    await tester.pumpAndSettle();
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
      find.text('Back up project'),
      200,
      scrollable: find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.text('Back up project'));
    await tester.pumpAndSettle();
    expect(name, 'Untitled score.claviera');
    expect(
      ProjectCodec.decode(utf8.decode(bytes!)).editor.eventsFor(Voice.v1),
      hasLength(1),
    );
    expect(store.files, isEmpty);
    expect(store.draft, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('discarding a recovery draft preserves the saved project', (
    tester,
  ) async {
    final store = MemoryStore();
    final original = Project(
      name: 'Saved score',
      tempo: 120,
      editor: ScoreEditor(blankScore),
    );
    final id = await store.save(original);
    final changed = Project(
      name: original.name,
      tempo: 90,
      editor: ScoreEditor(blankScore),
    );
    store.draft = RecoveryDraft(
      contents: ProjectCodec.encode(changed),
      savedState: ProjectCodec.encode(original),
      projectId: id,
    );
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: WorkspaceScreen(projectStore: store)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard draft'));
    await tester.pumpAndSettle();
    expect(store.draft, isNull);
    expect((await store.load(id)).tempo, 120);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('recovery write errors are visible without losing the edit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: WorkspaceScreen(projectStore: FailingRecoveryStore())),
    );
    await tester.pumpAndSettle();
    final canvas = find.byKey(const ValueKey('score-canvas'));
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(160, 115));
    await tester.pump();
    expect(find.textContaining('Recovery storage unavailable'), findsOneWidget);
    expect(
      tester
          .widget<ScoreViewport>(find.byType(ScoreViewport))
          .score
          .measures
          .first
          .events,
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('backup restore creates a copy and rejects invalid data', (
    tester,
  ) async {
    final store = MemoryStore();
    final contents = ProjectCodec.encode(
      Project(name: 'Backed up', tempo: 88, editor: ScoreEditor(blankScore)),
    );
    var file = Uint8List.fromList(utf8.encode(contents));
    final channel = const MethodChannel('claviera/projects');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'restore') return file;
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: WorkspaceScreen(projectStore: store)),
    );
    await tester.pumpAndSettle();
    Future<void> restore() async {
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
        find.text('Restore project backup'),
        200,
        scrollable: find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text('Restore project backup'));
      await tester.pumpAndSettle();
    }

    await restore();
    expect(store.files, hasLength(1));
    expect(find.text('Backed up'), findsOneWidget);
    file = Uint8List.fromList(utf8.encode('not a project'));
    await restore();
    expect(find.textContaining('Invalid project backup'), findsOneWidget);
    expect(store.files, hasLength(1));
    expect(find.text('Backed up'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('save, new, open and unsaved confirmation', (tester) async {
    final store = MemoryStore();
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: WorkspaceScreen(projectStore: store)),
    );
    await tester.pumpAndSettle();
    final canvas = find.byKey(const ValueKey('score-canvas'));
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(160, 115));
    await tester.pump();

    Future<void> menu(String name) async {
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
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }

    await menu('Save');
    await tester.enterText(find.byType(TextFormField), 'Sketch');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Sketch'), findsOneWidget);
    expect(await store.list(), hasLength(1));
    expect(store.draft, isNull);
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(160, 105));
    await tester.pumpAndSettle();
    expect(store.draft, isNotNull);
    await menu('New score');
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ScoreViewport>(find.byType(ScoreViewport))
          .score
          .measures
          .first
          .events,
      hasLength(2),
    );
    await menu('New score');
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(store.draft, isNull);
    expect(
      tester
          .widget<ScoreViewport>(find.byType(ScoreViewport))
          .score
          .measures
          .first
          .events,
      isEmpty,
    );
    await menu('Open project');
    await tester.tap(find.text('Sketch').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ScoreViewport>(find.byType(ScoreViewport))
          .score
          .measures
          .first
          .events,
      hasLength(1),
    );
    expect(find.text('Sketch'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('save as creates a copy and rename updates that copy', (
    tester,
  ) async {
    final store = MemoryStore();
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: WorkspaceScreen(projectStore: store)),
    );
    await tester.pumpAndSettle();
    Future<void> choose(String action, String name) async {
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
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), name);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    await choose('Save', 'Original');
    await choose('Save as', 'Copy');
    await choose('Rename', 'Renamed copy');
    expect(store.files, hasLength(2));
    expect((await store.list()).map((p) => p.name), [
      'Original',
      'Renamed copy',
    ]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('save errors are displayed and unsaved work is retained', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: WorkspaceScreen(projectStore: FailingStore())),
    );
    await tester.pumpAndSettle();
    final canvas = find.byKey(const ValueKey('score-canvas'));
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(160, 115));
    await tester.pump();
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
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Sketch');
    await tester.tap(find.text('OK'));
    await tester.pump();
    expect(find.textContaining('Storage unavailable'), findsOneWidget);
    expect(
      tester
          .widget<ScoreViewport>(find.byType(ScoreViewport))
          .score
          .measures
          .first
          .events,
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox());
  });
}
