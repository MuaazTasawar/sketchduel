import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Holds the strokes of one drawing and can turn the picture into a PNG for the server.
class DrawingController extends ChangeNotifier {
  /// Attached to the canvas' RepaintBoundary by [DrawingCanvas].
  final GlobalKey boundaryKey = GlobalKey();

  final List<List<Offset>> _strokes = [];
  List<Offset>? _current;
  int? _activePointer;

  /// True as soon as something has been drawn.
  bool get hasInk => _strokes.isNotEmpty || (_current?.isNotEmpty ?? false);

  int get strokeCount => _strokes.length + (_current == null ? 0 : 1);

  /// Starts a stroke for [pointer]. Returns false when another finger is already drawing.
  bool startStroke(int pointer, Offset position) {
    if (_activePointer != null) return false;
    _activePointer = pointer;
    _current = [position];
    notifyListeners();
    return true;
  }

  void extendStroke(int pointer, Offset position) {
    if (pointer != _activePointer || _current == null) return;
    _current!.add(position);
    notifyListeners();
  }

  void endStroke(int pointer) {
    if (pointer != _activePointer) return;
    final stroke = _current;
    _activePointer = null;
    _current = null;
    if (stroke != null && stroke.isNotEmpty) _strokes.add(stroke);
    notifyListeners();
  }

  void clear() {
    _strokes.clear();
    _current = null;
    _activePointer = null;
    notifyListeners();
  }

  Iterable<List<Offset>> get _allStrokes sync* {
    yield* _strokes;
    final current = _current;
    if (current != null) yield current;
  }

  /// The canvas as a base64 PNG (empty string if it is not on screen).
  Future<String> toBase64({double pixelRatio = 1.0}) async {
    final boundary =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return '';
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return '';
      return base64Encode(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }
}

/// A finger / mouse drawing surface.
///
/// It listens to raw pointer events, so a stroke starts exactly where the finger touched down
/// (no "slop" distance is lost), and it ignores a second finger while one is already drawing.
class DrawingCanvas extends StatelessWidget {
  const DrawingCanvas({
    super.key,
    required this.controller,
    this.enabled = true,
    this.strokeColor = Colors.white,
    this.strokeWidth = 4.0,
    this.backgroundColor = const Color(0xFF1A1A2E),
    this.onDrawingStarted,
  });

  final DrawingController controller;

  /// When false (time is up, or the drawing was handed in) touches are ignored.
  final bool enabled;
  final Color strokeColor;
  final double strokeWidth;
  final Color backgroundColor;
  final VoidCallback? onDrawingStarted;

  @override
  Widget build(BuildContext context) {
    // The background lives INSIDE the boundary, so the exported PNG is an opaque picture.
    return RepaintBoundary(
      key: controller.boundaryKey,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (!enabled) return;
          if (controller.startStroke(event.pointer, event.localPosition)) {
            onDrawingStarted?.call();
          }
        },
        onPointerMove: (event) {
          if (enabled) {
            controller.extendStroke(event.pointer, event.localPosition);
          }
        },
        onPointerUp: (event) => controller.endStroke(event.pointer),
        onPointerCancel: (event) => controller.endStroke(event.pointer),
        child: ClipRect(
          child: ColoredBox(
            color: backgroundColor,
            child: CustomPaint(
              painter: _CanvasPainter(
                controller: controller,
                color: strokeColor,
                strokeWidth: strokeWidth,
              ),
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }
}

class _CanvasPainter extends CustomPainter {
  _CanvasPainter({
    required this.controller,
    required this.color,
    required this.strokeWidth,
  }) : super(repaint: controller);

  final DrawingController controller;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final dot = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (final stroke in controller._allStrokes) {
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, strokeWidth / 2, dot);
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, line);
    }
  }

  @override
  bool shouldRepaint(_CanvasPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}