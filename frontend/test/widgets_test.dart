import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:sketchduel_app/core/theme/app_theme.dart';
import 'package:sketchduel_app/features/game/widgets/ai_score_bar.dart';
import 'package:sketchduel_app/features/game/widgets/drawing_canvas.dart';
import 'package:sketchduel_app/features/game/widgets/prompt_card.dart';

/// Puts [child] on a 300 x 300 stage. A plain Material theme is used on purpose:
/// the app theme loads Google Fonts, which tries to download fonts and fails in tests.
Widget host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Center(child: SizedBox(width: 300, height: 300, child: child)),
  ),
);

void main() {
  group('DrawingController', () {
    test('starts empty', () {
      final controller = DrawingController();
      addTearDown(controller.dispose);
      expect(controller.hasInk, isFalse);
      expect(controller.strokeCount, 0);
    });

    test('a stroke counts as soon as it starts and is kept when it ends', () {
      final controller = DrawingController();
      addTearDown(controller.dispose);

      expect(controller.startStroke(1, const Offset(10, 10)), isTrue);
      expect(controller.hasInk, isTrue);
      controller.extendStroke(1, const Offset(20, 20));
      expect(controller.strokeCount, 1);

      controller.endStroke(1);
      expect(controller.strokeCount, 1);
      expect(controller.hasInk, isTrue);
    });

    test('only one finger draws at a time', () {
      final controller = DrawingController();
      addTearDown(controller.dispose);

      expect(controller.startStroke(1, const Offset(10, 10)), isTrue);
      expect(controller.startStroke(2, const Offset(50, 50)), isFalse);
      controller.extendStroke(2, const Offset(60, 60)); // ignored
      controller.endStroke(2); // ignored: finger 1 is still drawing
      controller.endStroke(1);

      expect(controller.strokeCount, 1);
      // Now that finger 1 is up, another finger may draw.
      expect(controller.startStroke(2, const Offset(5, 5)), isTrue);
    });

    test('clear removes everything and allows a fresh stroke', () {
      final controller = DrawingController();
      addTearDown(controller.dispose);

      controller.startStroke(1, const Offset(1, 1));
      controller.endStroke(1);
      controller.clear();

      expect(controller.hasInk, isFalse);
      expect(controller.strokeCount, 0);
      expect(controller.startStroke(7, const Offset(2, 2)), isTrue);
    });

    test('listeners are told about every change', () {
      final controller = DrawingController();
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.startStroke(1, const Offset(1, 1)); // 1
      controller.extendStroke(1, const Offset(2, 2)); // 2
      controller.endStroke(1); // 3
      controller.clear(); // 4

      expect(notifications, 4);
    });

    test(
      'exporting without a canvas on screen gives an empty string',
      () async {
        final controller = DrawingController();
        addTearDown(controller.dispose);
        expect(await controller.toBase64(), isEmpty);
      },
    );
  });

  group('DrawingCanvas', () {
    testWidgets(
      'dragging a finger records one stroke and reports the start once',
      (tester) async {
        final controller = DrawingController();
        addTearDown(controller.dispose);
        var started = 0;

        await tester.pumpWidget(
          host(
            DrawingCanvas(
              controller: controller,
              onDrawingStarted: () => started++,
            ),
          ),
        );

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(DrawingCanvas)),
        );
        await gesture.moveBy(const Offset(40, 10));
        await gesture.moveBy(const Offset(20, 20));
        await gesture.up();
        await tester.pump();

        expect(controller.hasInk, isTrue);
        expect(controller.strokeCount, 1);
        expect(started, 1);
      },
    );

    testWidgets('a tap without moving still leaves a dot', (tester) async {
      final controller = DrawingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(host(DrawingCanvas(controller: controller)));
      await tester.tapAt(tester.getCenter(find.byType(DrawingCanvas)));
      await tester.pump();

      expect(controller.hasInk, isTrue);
      expect(controller.strokeCount, 1);
    });

    testWidgets('a disabled canvas ignores touches', (tester) async {
      final controller = DrawingController();
      addTearDown(controller.dispose);
      var started = 0;

      await tester.pumpWidget(
        host(
          DrawingCanvas(
            controller: controller,
            enabled: false,
            onDrawingStarted: () => started++,
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(DrawingCanvas)),
      );
      await gesture.moveBy(const Offset(40, 10));
      await gesture.up();
      await tester.pump();

      expect(controller.hasInk, isFalse);
      expect(started, 0);
    });

    testWidgets('a second finger is ignored while the first is drawing', (
      tester,
    ) async {
      final controller = DrawingController();
      addTearDown(controller.dispose);
      var started = 0;

      await tester.pumpWidget(
        host(
          DrawingCanvas(
            controller: controller,
            onDrawingStarted: () => started++,
          ),
        ),
      );

      final center = tester.getCenter(find.byType(DrawingCanvas));
      final first = await tester.startGesture(center, pointer: 1);
      final second = await tester.startGesture(
        center + const Offset(60, 0),
        pointer: 2,
      );
      await first.moveBy(const Offset(10, 10));
      await second.moveBy(const Offset(10, 10));
      await first.up();
      await second.up();
      await tester.pump();

      expect(controller.strokeCount, 1);
      expect(started, 1);
    });

    testWidgets('exports the drawing as a PNG image', (tester) async {
      final controller = DrawingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(host(DrawingCanvas(controller: controller)));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(DrawingCanvas)),
      );
      await gesture.moveBy(const Offset(50, 0));
      await gesture.up();
      await tester.pump();

      // Rendering to an image needs real asynchrony, hence runAsync.
      final encoded = await tester.runAsync(() => controller.toBase64());

      expect(encoded, isNotNull);
      expect(encoded, isNotEmpty);
      final bytes = base64Decode(encoded!);
      // Every PNG file starts with these four bytes.
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });
  });

  group('PromptCard', () {
    Color timerColor(WidgetTester tester, int seconds) =>
        tester.widget<Text>(find.text('$seconds')).style!.color!;

    testWidgets('shows the prompt in capitals and the seconds left', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const PromptCard(
            prompt: 'ice cream',
            secondsLeft: 42,
            totalSeconds: 60,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ICE CREAM'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('Draw this:'), findsOneWidget);
    });

    testWidgets(
      'the timer turns from green to orange to pink as time runs out',
      (tester) async {
        Future<Color> colorFor(int seconds) async {
          await tester.pumpWidget(
            host(
              PromptCard(prompt: 'cat', secondsLeft: seconds, totalSeconds: 60),
            ),
          );
          await tester.pumpAndSettle();
          return timerColor(tester, seconds);
        }

        expect(await colorFor(45), AppTheme.accent);
        expect(await colorFor(20), Colors.orange);
        expect(await colorFor(5), AppTheme.secondary);
      },
    );
  });

  group('AiScoreBar', () {
    testWidgets('is invisible until it is told to show', (tester) async {
      await tester.pumpWidget(
        host(
          const AiScoreBar(
            confidence: 0.8,
            recognizedAs: 'cat',
            bluffDetected: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LinearPercentIndicator), findsNothing);
      expect(find.textContaining('AI sees'), findsNothing);
    });

    testWidgets('shows what the AI sees and how sure it is', (tester) async {
      await tester.pumpWidget(
        host(
          const AiScoreBar(
            confidence: 0.85,
            recognizedAs: 'cat',
            bluffDetected: false,
            isVisible: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('🤖 AI sees: cat'), findsOneWidget);
      expect(find.text('Confidence: 85.0%'), findsOneWidget);
      final bar = tester.widget<LinearPercentIndicator>(
        find.byType(LinearPercentIndicator),
      );
      expect(bar.percent, closeTo(0.85, 0.0001));
    });

    testWidgets('announces a bluff instead of the label', (tester) async {
      await tester.pumpWidget(
        host(
          const AiScoreBar(
            confidence: 0.9,
            recognizedAs: 'dog',
            bluffDetected: true,
            isVisible: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('🎭 Bluff detected!'), findsOneWidget);
      expect(find.textContaining('AI sees'), findsNothing);
    });
  });
}