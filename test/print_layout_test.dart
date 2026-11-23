import 'package:claviera/editor/score_editor.dart';
import 'package:claviera/main.dart';
import 'package:claviera/models/blank_score.dart';
import 'package:claviera/models/score.dart';
import 'package:claviera/notation/print_layout.dart';
import 'package:claviera/notation/score_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('arpeggios survive PDF system slicing', () {
    final editor = ScoreEditor(
      Score(
        title: '',
        beatsPerMeasure: 4,
        beatUnit: 4,
        measures: List.generate(8, (_) => const Measure()),
      ),
    );
    final id = editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 960,
      pitch: const Pitch(diatonicStep: 28, midiNote: 60),
      measure: 4,
    );
    editor.addPitch(id, const Pitch(diatonicStep: 30, midiNote: 64));
    editor.setArpeggio(editor.measureStart(4), ArpeggioDirection.up);
    final systems = PrintLayout.systems(editor.score);
    expect(
      systems
          .expand((system) => system.score.measures)
          .where((measure) => measure.arpeggios.isNotEmpty)
          .single
          .arpeggios,
      {0: ArpeggioDirection.up},
    );
  });

  testWidgets('prints an articulation once on a tied chord attack', (
    tester,
  ) async {
    final editor = ScoreEditor(blankScore);
    editor.append(voice: Voice.v1, staff: Staff.treble, duration: 2880);
    final id = editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 1920,
      pitch: const Pitch(diatonicStep: 28, midiNote: 60),
    );
    editor.addPitch(id, const Pitch(diatonicStep: 30, midiNote: 64));
    int paragraphs(Score score) {
      final canvas = TestRecordingCanvas();
      ScorePainter(score: score, selectedEvent: null, selectedPitch: 0).paint(
        canvas,
        Size(ScorePainter.widthFor(score, 10), ScorePainter.heightFor(10)),
      );
      return canvas.invocations
          .where((call) => call.invocation.memberName == #drawParagraph)
          .length;
    }

    final before = editor.score;
    editor.setArticulations(id, {Articulation.staccato});
    final score = editor.score;
    expect(paragraphs(score), paragraphs(before) + 1);
    final printed = PrintLayout.systems(score)
        .expand((system) => system.score.measures)
        .expand((measure) => measure.events)
        .where((event) => event.eventId == id)
        .toList();
    expect(printed.first.articulations, {Articulation.staccato});
    expect(printed.last.articulations, isEmpty);
  });

  test('systems retain all bars and inherit key and time at each line', () {
    final score = Score(
      title: 'Print',
      beatsPerMeasure: 4,
      beatUnit: 4,
      measures: [
        const Measure(),
        const Measure(timeSignature: TimeSignature(3, 4), keySignature: 2),
        for (var i = 0; i < 10; i++) const Measure(),
      ],
    );
    final systems = PrintLayout.systems(score);
    expect(systems.length, greaterThan(1));
    expect(systems.expand((s) => s.score.measures), hasLength(12));
    for (final system in systems) {
      expect(system.score.keySignature, score.keyAt(system.firstMeasure));
      expect(
        TimeSignature(system.score.beatsPerMeasure, system.score.beatUnit),
        score.timeAt(system.firstMeasure),
      );
      expect(
        ScorePainter.widthFor(system.score, PrintLayout.staffSpace),
        lessThanOrEqualTo(PrintLayout.pageWidth - 2 * PrintLayout.margin),
      );
    }
  });

  testWidgets('renders multiple full-size pages', (tester) async {
    final score = Score(
      title: 'Long',
      beatsPerMeasure: 4,
      beatUnit: 4,
      measures: List.generate(40, (_) => const Measure()),
    );
    final pages = await tester.runAsync(
      () => PrintLayout.render(score, score.title),
    );
    expect(pages, isNotNull);
    expect(pages!.length, greaterThan(1));
    for (final page in pages) {
      expect(page.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    }
  });

  testWidgets('PDF menu sends printable pages to Android and reports errors', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const channel = MethodChannel('claviera/pdf');
    final calls = <MethodCall>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const ClavieraApp());
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
      find.text('Export PDF'),
      200,
      scrollable: find.descendant(
        of: find.byType(ListView).last,
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.text('Export PDF'));
    await tester.runAsync(() async {
      for (var i = 0; i < 50 && calls.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    expect(calls.single.arguments['name'], 'Untitled score.pdf');
    expect((calls.single.arguments['pages'] as List).single, isA<Uint8List>());
    expect(find.text('PDF saved.'), findsOneWidget);
  });

  test('systems retain tied segments on either side of a line break', () {
    final editor = ScoreEditor(blankScore);
    editor.insertBars(4, 1, initialTempo: 120);
    editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 2880,
      measure: 3,
    );
    editor.append(
      voice: Voice.v1,
      staff: Staff.treble,
      duration: 1920,
      pitch: const Pitch(diatonicStep: 28, midiNote: 60),
      measure: 3,
    );
    final systems = PrintLayout.systems(editor.score);
    expect(systems, hasLength(2));
    expect(
      systems.first.score.measures.last.events
          .where((e) => !e.isRest)
          .last
          .tieToNext,
      true,
    );
    expect(
      systems.last.score.measures.first.events
          .where((e) => !e.isRest)
          .first
          .tieFromPrevious,
      true,
    );
  });
}
