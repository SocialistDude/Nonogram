import 'package:flutter/material.dart';

class SolutionPainter extends CustomPainter {
  SolutionPainter({
    required this.grid,
    required this.color,
    required this.width,
    required this.height,
  });

  final List<List<bool>> grid;
  final Color color;
  final int width;
  final int height;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final cellW = canvasSize.width / width;
    final cellH = canvasSize.height / height;
    final paint = Paint()
      ..color = color
      ..isAntiAlias = false;

    for (int r = 0; r < height; r++) {
      for (int c = 0; c < width; c++) {
        if (grid[r][c]) {
          canvas.drawRect(
            Rect.fromLTWH(
              (c * cellW).roundToDouble(),
              (r * cellH).roundToDouble(),
              cellW.ceilToDouble(),
              cellH.ceilToDouble(),
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant SolutionPainter old) =>
      old.grid != grid ||
          old.color != color ||
          old.width != width ||
          old.height != height;
}