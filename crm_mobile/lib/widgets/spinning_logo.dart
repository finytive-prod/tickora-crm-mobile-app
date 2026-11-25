import 'dart:math' as math;
import 'package:flutter/material.dart';

class SpinningLogo extends StatefulWidget {
  final double size;
  const SpinningLogo({super.key, this.size = 50.0});

  @override
  State<SpinningLogo> createState() => _SpinningLogoState();
}

class _SpinningLogoState extends State<SpinningLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double logoSize = widget.size;
    final double orbitRadius = logoSize * 0.72;
    final double ballRadius = math.max(3.5, logoSize * 0.085);
    final double strokeWidth = math.max(1.5, logoSize * 0.025);
    final double totalSize = (orbitRadius + ballRadius + 4) * 2;

    return Center(
      child: SizedBox(
        width: totalSize,
        height: totalSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Orbit line track and 3 rotating balls
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _OrbitBallsPainter(
                      progress: _controller.value,
                      orbitRadius: orbitRadius,
                      ballRadius: ballRadius,
                      strokeWidth: strokeWidth,
                    ),
                  );
                },
              ),
            ),

            // Center App Logo
            ClipRRect(
              borderRadius: BorderRadius.circular(logoSize * 0.22),
              child: Container(
                width: logoSize,
                height: logoSize,
                color: const Color(0xFF021F77),
                child: Image.asset(
                  'assets/images/logo.png',
                  width: logoSize,
                  height: logoSize,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Image.asset(
                      'assets/images/logo.webp',
                      width: logoSize,
                      height: logoSize,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          Icons.business_center_rounded,
                          size: logoSize * 0.7,
                          color: Colors.white,
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrbitBallsPainter extends CustomPainter {
  final double progress;
  final double orbitRadius;
  final double ballRadius;
  final double strokeWidth;

  _OrbitBallsPainter({
    required this.progress,
    required this.orbitRadius,
    required this.ballRadius,
    required this.strokeWidth,
  });

  // 3 distinct colors matching the app theme & logo accents:
  // - Top: Vibrant blue (#147BD1)
  // - Bottom-Right: Cyan / turquoise (#00A9CF)
  // - Bottom-Left: Royal blue / indigo (#3B59D8)
  static const List<Color> _ballColors = [
    Color(0xFF147BD1),
    Color(0xFF00A9CF),
    Color(0xFF3B59D8),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // 1. Draw circular orbit line track
    final trackPaint = Paint()
      ..color = const Color(0xFFDCEAF9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true;
    canvas.drawCircle(center, orbitRadius, trackPaint);

    // 2. Draw 3 balls moving synchronously along the circular line
    final baseAngle = progress * 2 * math.pi;

    for (int i = 0; i < 3; i++) {
      // 120-degree separation (2 * pi / 3 radians)
      // -math.pi / 2 starts index 0 at the top (12 o'clock)
      final angle = baseAngle - (math.pi / 2) + (i * 2 * math.pi / 3);
      final x = center.dx + orbitRadius * math.cos(angle);
      final y = center.dy + orbitRadius * math.sin(angle);

      final ballPaint = Paint()
        ..color = _ballColors[i]
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;

      canvas.drawCircle(Offset(x, y), ballRadius, ballPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitBallsPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.orbitRadius != orbitRadius ||
        oldDelegate.ballRadius != ballRadius ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
