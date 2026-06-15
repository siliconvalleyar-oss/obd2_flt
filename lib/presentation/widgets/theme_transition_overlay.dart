import 'dart:math' as math;
import 'package:flutter/material.dart';

class ThemeTransitionOverlay extends StatefulWidget {
  final Color backgroundColor;
  final Offset origin;
  final VoidCallback onComplete;

  const ThemeTransitionOverlay({
    super.key,
    required this.backgroundColor,
    required this.origin,
    required this.onComplete,
  });

  @override
  State<ThemeTransitionOverlay> createState() => _ThemeTransitionOverlayState();
}

class _ThemeTransitionOverlayState extends State<ThemeTransitionOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onComplete();
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final maxRadius = math.sqrt(size.width * size.width + size.height * size.height);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ClipPath(
          clipper: _RadialRevealClipper(
            progress: _controller.value,
            origin: widget.origin,
            maxRadius: maxRadius,
          ),
          child: child!,
        );
      },
      child: Container(color: widget.backgroundColor),
    );
  }
}

class _RadialRevealClipper extends CustomClipper<Path> {
  final double progress;
  final Offset origin;
  final double maxRadius;

  const _RadialRevealClipper({
    required this.progress,
    required this.origin,
    required this.maxRadius,
  });

  @override
  Path getClip(Size size) {
    final holeRadius = progress * maxRadius;
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);
    return Path.combine(
      PathOperation.difference,
      Path()..addRect(fullRect),
      Path()..addOval(Rect.fromCircle(center: origin, radius: holeRadius)),
    );
  }

  @override
  bool shouldReclip(_RadialRevealClipper oldClipper) =>
      progress != oldClipper.progress;
}
