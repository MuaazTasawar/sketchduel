import 'dart:ui' as ui;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class DrawingPoint {
  final Offset offset;
  final Paint paint;
  DrawingPoint(this.offset, this.paint);
}

class DrawingCanvas extends StatefulWidget {
  final Color strokeColor;
  final double strokeWidth;
  final GlobalKey canvasKey;
  final VoidCallback? onDrawingStarted;

  const DrawingCanvas({
    super.key,
    required this.canvasKey,
    this.strokeColor = Colors.white,
    this.strokeWidth = 4.0,
    this.onDrawingStarted,
  });

  @override
  State<DrawingCanvas> createState() => DrawingCanvasState();
}

class DrawingCanvasState extends State<DrawingCanvas> {
  final List<List<DrawingPoint>> _strokes = [];
  List<DrawingPoint> _currentStroke = [];

  void clear() => setState(() {
        _strokes.clear();
        _currentStroke = [];
      });

  Future<String> toBase64() async {
    final boundary = widget.canvasKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return '';
    final image = await boundary.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    return base64Encode(bytes);
  }

  Paint _makePaint() => Paint()
    ..color = widget.strokeColor
    ..strokeWidth = widget.strokeWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: widget.canvasKey,
      child: Container(
        color: const Color(0xFF1A1A2E),
        child: GestureDetector(
          onPanStart: (d) {
            widget.onDrawingStarted?.call();
            setState(() {
              _currentStroke = [DrawingPoint(d.localPosition, _makePaint())];
            });
          },
          onPanUpdate: (d) {
            setState(() {
              _currentStroke.add(DrawingPoint(d.localPosition, _makePaint()));
            });
          },
          onPanEnd: (_) {
            setState(() {
              _strokes.add(List.from(_currentStroke));
              _currentStroke = [];
            });
          },
          child: CustomPaint(
            painter: _CanvasPainter(_strokes, _currentStroke),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _CanvasPainter extends CustomPainter {
  final List<List<DrawingPoint>> strokes;
  final List<DrawingPoint> currentStroke;

  _CanvasPainter(this.strokes, this.currentStroke);

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in [...strokes, currentStroke]) {
      for (int i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(stroke[i].offset, stroke[i + 1].offset, stroke[i].paint);
      }
    }
  }

  @override
  bool shouldRepaint(_CanvasPainter old) => true;
}