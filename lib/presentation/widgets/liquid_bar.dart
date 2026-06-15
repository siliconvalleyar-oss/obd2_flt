import 'dart:math';
import 'package:flutter/material.dart';

class LiquidBar extends StatefulWidget {
  final double progress;
  final double height;
  final List<Color> colors;
  final double animationSpeed;

  const LiquidBar({
    super.key,
    this.progress = 0.5,
    this.height = 6,
    this.colors = const [Color(0xFF6C63FF), Color(0xFFFF6584)],
    this.animationSpeed = 1.0,
  });

  @override
  State<LiquidBar> createState() => _LiquidBarState();
}

class _LiquidBarState extends State<LiquidBar> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _LiquidBarPainter(
            progress: widget.progress,
            phase: _controller.value * 2 * pi,
            colors: widget.colors,
          ),
          size: Size(double.infinity, widget.height),
        );
      },
    );
  }
}

class _LiquidBarPainter extends CustomPainter {
  final double progress;
  final double phase;
  final List<Color> colors;

  _LiquidBarPainter({required this.progress, required this.phase, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: colors,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path = Path();
    final waveHeight = size.height * 0.4;
    final filledWidth = size.width * progress;

    path.moveTo(0, size.height);
    for (double x = 0; x <= filledWidth; x += 1) {
      final y = size.height / 2 +
          sin((x / size.width) * 2 * pi * 2 + phase) * waveHeight +
          sin((x / size.width) * 4 * pi + phase * 1.5) * waveHeight * 0.3;
      path.lineTo(x, y);
    }
    path.lineTo(filledWidth, size.height);
    path.close();
    canvas.drawPath(path, paint);

    final glowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          colors.first.withValues(alpha: 0.3),
          colors.last.withValues(alpha: 0.1),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height + 10))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final glowPath = Path();
    glowPath.moveTo(0, size.height);
    for (double x = 0; x <= filledWidth; x += 2) {
      final y = size.height / 2 +
          sin((x / size.width) * 2 * pi * 2 + phase) * waveHeight +
          sin((x / size.width) * 4 * pi + phase * 1.5) * waveHeight * 0.3;
      glowPath.lineTo(x, y);
    }
    glowPath.lineTo(filledWidth, size.height);
    glowPath.close();
    canvas.drawPath(glowPath, glowPaint);
  }

  @override
  bool shouldRepaint(_LiquidBarPainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.progress != progress;
  }
}
