import 'dart:convert';
import 'dart:io';

import 'package:claviera/editor/score_editor.dart';
import 'package:claviera/models/blank_score.dart';
import 'package:claviera/models/score.dart';
import 'package:claviera/storage/projects.dart';
import 'package:claviera/ui/workspace_screen.dart';
import 'package:claviera/notation/score_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const fSharp = Pitch(diatonicStep: 31, midiNote: 66);
const natural = Pitch(
  diatonicStep: 31,
  midiNote: 65,
  accidental: Accidental.natural,
);

class MemoryStore extends ProjectStore {
  final files = <String, String>{};

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

void main() {
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

  testWidgets('save, new, open and unsaved confirmation', (tester) async {
    final store = MemoryStore();
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: WorkspaceScreen(projectStore: store)),
    );
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
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(160, 105));
    await tester.pump();
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
