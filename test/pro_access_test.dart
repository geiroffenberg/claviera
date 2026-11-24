import 'package:claviera/billing/pro_purchase_controller.dart';
import 'package:claviera/models/score.dart';
import 'package:claviera/notation/score_viewport.dart';
import 'package:claviera/ui/workspace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeProPurchaseController extends ProPurchaseController {
  bool unlocked = false;
  String? statusMessage;

  @override
  bool get isAndroid => true;

  @override
  bool get isPro => unlocked;

  @override
  bool get isAvailable => true;

  @override
  bool get isBusy => false;

  @override
  String? get localizedPrice => '\$4.99';

  @override
  String? get message => statusMessage;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> buyPro() async {
    unlocked = true;
    notifyListeners();
  }

  @override
  Future<void> restorePurchases() async {
    statusMessage = 'No Pro purchase was found for this Google account.';
    notifyListeners();
  }
}

void main() {
  testWidgets('locked articulations stay visible and offer a Pro upgrade', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final purchases = FakeProPurchaseController();
    addTearDown(purchases.dispose);

    await tester.pumpWidget(
      MaterialApp(home: WorkspaceScreen(proPurchaseController: purchases)),
    );
    final canvas = find.byKey(const ValueKey('score-canvas'));
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(160, 115));
    await tester.pump();
    await tester.tap(find.byTooltip('Articulations'));
    await tester.pumpAndSettle();

    final trill = find.byWidgetPredicate(
      (widget) =>
          widget is FilterChip &&
          widget.label is Text &&
          (widget.label as Text).textSpan!.toPlainText().contains('Trill'),
    );
    expect(trill, findsOneWidget);
    expect(find.text('Upgrade to Pro'), findsOneWidget);
    await tester.tap(trill);
    await tester.pumpAndSettle();
    expect(find.text('Claviera Pro'), findsOneWidget);
    expect(
      tester
          .widget<ScoreViewport>(find.byType(ScoreViewport))
          .selectedEvent!
          .articulations,
      isEmpty,
    );

    final unlockButton = find.widgetWithText(
      FilledButton,
      'Unlock Pro · \$4.99',
    );
    expect(tester.widget<FilledButton>(unlockButton).onPressed, isNotNull);
    await tester.tap(unlockButton);
    await tester.pumpAndSettle();
    expect(purchases.isPro, isTrue);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(trill);
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(trill).selected, isTrue);
    expect(
      tester
          .widget<ScoreViewport>(find.byType(ScoreViewport))
          .selectedEvent!
          .articulations,
      {Articulation.trill},
    );
  });

  testWidgets('free users can open dynamics and see locked choices', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final purchases = FakeProPurchaseController();
    addTearDown(purchases.dispose);

    await tester.pumpWidget(
      MaterialApp(home: WorkspaceScreen(proPurchaseController: purchases)),
    );
    final canvas = find.byKey(const ValueKey('score-canvas'));
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(160, 115));
    await tester.pump();
    await tester.tap(find.byTooltip('Dynamics'));
    await tester.pumpAndSettle();

    expect(find.text('Dynamics (both staves)'), findsOneWidget);
    expect(
      find.text('Dynamics and hairpins are included with Pro.'),
      findsOneWidget,
    );
    final loudDynamic = find.ancestor(
      of: find.text('ff'),
      matching: find.byType(ChoiceChip),
    );
    await tester.ensureVisible(loudDynamic);
    await tester.tap(loudDynamic);
    await tester.pumpAndSettle();
    expect(find.text('Claviera Pro'), findsOneWidget);
    expect(
      tester
          .widget<ScoreViewport>(find.byType(ScoreViewport))
          .score
          .measures
          .first
          .dynamics,
      isEmpty,
    );
  });

  testWidgets('export menu entries open the Pro upgrade instead of exporting', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final purchases = FakeProPurchaseController();
    addTearDown(purchases.dispose);

    await tester.pumpWidget(
      MaterialApp(home: WorkspaceScreen(proPurchaseController: purchases)),
    );
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Upgrade to Pro'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Back up project'),
      200,
      scrollable: find.descendant(
        of: find.byType(ListView).last,
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Back up project'), findsOneWidget);

    for (final export in ['Export PDF', 'Export MIDI', 'Export MusicXML']) {
      await tester.scrollUntilVisible(
        find.text(export),
        200,
        scrollable: find.descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text(export));
      await tester.pumpAndSettle();
      expect(find.text('Claviera Pro'), findsOneWidget);
      expect(find.text('Unlock Pro · \$4.99'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      if (export != 'Export MusicXML') {
        await tester.tap(find.byTooltip('Menu'));
        await tester.pumpAndSettle();
      }
    }
  });
}
