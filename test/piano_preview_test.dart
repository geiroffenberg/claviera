import 'dart:async';

import 'package:claviera/audio/piano_preview.dart';
import 'package:claviera/notation/score_viewport.dart';
import 'package:claviera/ui/workspace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('claviera/piano_preview_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  final errors = <String>[];
  Completer<void>? loading;

  setUp(() {
    calls.clear();
    errors.clear();
    loading = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'initialize' && loading != null) {
        await loading!.future;
      }
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('plays changed pitches only and stops on release or mute', () async {
    final piano = PianoPreview(
      onError: errors.add,
      channel: channel,
      supported: true,
    );
    piano.warmUp();
    await Future<void>.delayed(Duration.zero);
    piano.play(60);
    await Future<void>.delayed(Duration.zero);
    piano.play(60);
    piano.play(61);
    await Future<void>.delayed(Duration.zero);
    piano.setEnabled(false);
    await Future<void>.delayed(Duration.zero);
    piano.play(62);
    expect(calls.map((call) => call.method), [
      'initialize',
      'play',
      'play',
      'stop',
    ]);
    expect(
      calls
          .where((call) => call.method == 'play')
          .map((call) => call.arguments),
      [
        {'midi': 60},
        {'midi': 61},
      ],
    );
    expect(errors, isEmpty);
    piano.dispose();
  });

  test('late loading only plays the latest held pitch', () async {
    loading = Completer<void>();
    final piano = PianoPreview(
      onError: errors.add,
      channel: channel,
      supported: true,
    );
    piano.play(60);
    piano.play(62);
    await Future<void>.delayed(Duration.zero);
    loading!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(calls.map((call) => call.method), ['initialize', 'play']);
    expect(calls.last.arguments, {'midi': 62});
    piano.dispose();
  });

  test('release before loading finishes cannot start a stale note', () async {
    loading = Completer<void>();
    final piano = PianoPreview(
      onError: errors.add,
      channel: channel,
      supported: true,
    );
    piano.play(60);
    piano.stop();
    loading!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(calls.where((call) => call.method == 'play'), isEmpty);
    piano.dispose();
  });

  test('sample load errors are reported once and do not play', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      throw PlatformException(
        code: 'sample_load_failed',
        message: 'Sample unavailable',
      );
    });
    final piano = PianoPreview(
      onError: errors.add,
      channel: channel,
      supported: true,
    );
    piano.warmUp();
    piano.play(60);
    await Future<void>.delayed(Duration.zero);
    piano.play(61);
    expect(errors, ['Sample unavailable']);
    expect(calls.map((call) => call.method), ['initialize']);
    piano.dispose();
  });

  testWidgets(
    'write and edit preview sounds follow pitch, accidentals and mute',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final piano = PianoPreview(
        onError: errors.add,
        channel: channel,
        supported: true,
      );
      await tester.pumpWidget(
        MaterialApp(home: WorkspaceScreen(pianoPreview: piano)),
      );
      await tester.pump();
      final origin = tester.getTopLeft(
        find.byKey(const ValueKey('score-canvas')),
      );
      final gesture = await tester.startGesture(
        origin + const Offset(160, 115),
      );
      await tester.pump();
      await gesture.moveTo(origin + const Offset(160, 116));
      await tester.pump();
      expect(
        calls
            .where((call) => call.method == 'play')
            .map((call) => call.arguments),
        [
          {'midi': 65},
        ],
      );
      await gesture.moveTo(origin + const Offset(160, 105));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(
        calls
            .where((call) => call.method == 'play')
            .map((call) => call.arguments),
        [
          {'midi': 65},
          {'midi': 69},
        ],
      );
      expect(calls.last.method, 'stop');

      await tester.tap(find.byTooltip('Write mode'));
      await tester.pump();
      await tester.tapAt(origin + const Offset(160, 105));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byTooltip('♯ accidental'),
        200,
        scrollable: find.descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.byTooltip('♯ accidental'));
      await tester.pump();
      final drag = await tester.startGesture(origin + const Offset(160, 105));
      await drag.moveTo(origin + const Offset(160, 95));
      await tester.pump();
      expect(calls.last.method, 'play');
      expect(calls.last.arguments, {'midi': 73});
      await drag.up();
      await tester.pump();
      await tester.tap(find.byTooltip('Mute piano preview'));
      await tester.pump();
      expect(find.byTooltip('Enable piano preview'), findsOneWidget);
      final count = calls.where((call) => call.method == 'play').length;
      await tester.dragFrom(
        origin + const Offset(160, 95),
        const Offset(0, 10),
      );
      await tester.pump();
      expect(calls.where((call) => call.method == 'play').length, count);
      expect(errors, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('write preview follows an earlier accidental in the bar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final piano = PianoPreview(
      onError: errors.add,
      channel: channel,
      supported: true,
    );
    await tester.pumpWidget(
      MaterialApp(home: WorkspaceScreen(pianoPreview: piano)),
    );
    await tester.pump();
    final origin = tester.getTopLeft(
      find.byKey(const ValueKey('score-canvas')),
    );
    await tester.tapAt(origin + const Offset(160, 115));
    await tester.pump();
    await tester.tap(find.byTooltip('Write mode'));
    await tester.pump();
    await tester.tapAt(origin + const Offset(160, 115));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byTooltip('♯ accidental'),
      200,
      scrollable: find.descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byTooltip('♯ accidental'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byTooltip('Edit mode'),
      -200,
      scrollable: find.descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byTooltip('Edit mode'));
    await tester.pump();
    final gesture = await tester.startGesture(origin + const Offset(160, 115));
    await tester.pump();
    expect(calls.where((call) => call.method == 'play').last.arguments, {
      'midi': 66,
    });
    await gesture.up();
    await tester.pump();
    final score = tester
        .widget<ScoreViewport>(find.byType(ScoreViewport))
        .score;
    expect(
      score.measures.first.events.map((event) => event.pitches.single.midiNote),
      [66, 66],
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('compact landscape header fits with the mute control', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(568, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: WorkspaceScreen()));
    await tester.pump();
    expect(find.byTooltip('Mute piano preview'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
