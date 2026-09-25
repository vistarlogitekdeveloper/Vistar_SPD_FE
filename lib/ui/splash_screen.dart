import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import 'widgets/common.dart';

/// `#splash` — the orbit loader, wordmark and loading bar the prototype shows
/// for 2.2 s before the login screen fades in.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _r1 =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  late final AnimationController _r2 =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: false);
  late final AnimationController _breathe =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);
  late final AnimationController _bar =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) context.go('/login');
    });
  }

  @override
  void dispose() {
    _r1.dispose();
    _r2.dispose();
    _breathe.dispose();
    _bar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        // #splash — two radial washes over the page background.
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.16),
            radius: 1.1,
            colors: [Brand.purple.withValues(alpha: Brand.isLight ? 0.14 : 0.28), Colors.transparent],
            stops: const [0, 0.62],
          ),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 200,
              height: 200,
              child: Stack(alignment: Alignment.center, children: [
                // .ring.r1
                RotationTransition(
                  turns: _r1,
                  child: CustomPaint(
                    size: const Size(200, 200),
                    painter: _RingPainter(
                      top: Brand.pink.withValues(alpha: 0.65),
                      right: Brand.orange.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                // .ring.r2 — inset 22px, spins the other way
                RotationTransition(
                  turns: Tween(begin: 1.0, end: 0.0).animate(_r2),
                  child: CustomPaint(
                    size: const Size(156, 156),
                    painter: _RingPainter(
                      bottom: Brand.violet.withValues(alpha: 0.65),
                      left: Brand.amber.withValues(alpha: 0.45),
                    ),
                  ),
                ),
                ScaleTransition(
                  scale: Tween(begin: 0.92, end: 1.04)
                      .animate(CurvedAnimation(parent: _breathe, curve: Curves.easeInOut)),
                  child: const SMark(width: 96, height: 97),
                ),
              ]),
            ),
            const SizedBox(height: 26),
            const Wordmark(size: 36),
            const SizedBox(height: 26),
            Text('SPD · PRE-PACKING PROCESS AUTOMATION', style: eyebrow(size: 11, tracking: 3)),
            const SizedBox(height: 26),
            // .splash-bar
            SizedBox(
              width: 200,
              height: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(children: [
                  Positioned.fill(child: ColoredBox(color: Brand.track)),
                  AnimatedBuilder(
                    animation: _bar,
                    builder: (context, _) => Align(
                      alignment: Alignment(-1 + 2 * _bar.value * 1.4, 0),
                      child: Container(
                        width: 80,
                        decoration: BoxDecoration(gradient: Brand.ribbon, borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A circle with only two of its four arcs coloured, as the CSS ring borders do.
class _RingPainter extends CustomPainter {
  _RingPainter({this.top, this.right, this.bottom, this.left});

  final Color? top, right, bottom, left;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    const q = math.pi / 2;
    void arc(Color? c, double start) {
      if (c == null) return;
      canvas.drawArc(rect.deflate(1), start, q, false, p..color = c);
    }

    arc(top, -q - q / 2);
    arc(right, -q / 2);
    arc(bottom, q / 2);
    arc(left, q + q / 2);
  }

  @override
  bool shouldRepaint(_RingPainter old) => false;
}
