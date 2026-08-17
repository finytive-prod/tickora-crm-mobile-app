import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/screens/home_screen.dart';
import 'package:crm_mobile/screens/auth/login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2), // 2 seconds per full rotation for minute hand
    )..repeat();

    _navigateNext();
  }

  Future<void> _navigateNext() async {
    // Show splash screen for 3 seconds
    await Future.delayed(const Duration(seconds: 3));
    
    if (!mounted) return;

    final prefs = sl<SharedPreferences>();
    final token = prefs.getString('token');
    final isLoggedIn = token != null && token.isNotEmpty;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => isLoggedIn ? const HomeScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              size: const Size(150, 150),
              painter: ClockLogoPainter(animationValue: _controller.value),
            );
          },
        ),
      ),
    );
  }
}

class ClockLogoPainter extends CustomPainter {
  final double animationValue;

  ClockLogoPainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Draw Background Shape (Black Teardrop)
    // It's a rounded rectangle where all corners are fully rounded EXCEPT top right.
    final bgPaint = Paint()
      ..color = const Color(0xFF1E1E1E) // Very dark brown/black
      ..style = PaintingStyle.fill;
    
    final rRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(0, 0, size.width, size.height),
      topLeft: Radius.circular(radius),
      bottomLeft: Radius.circular(radius),
      bottomRight: Radius.circular(radius),
      topRight: const Radius.circular(5), // Slight rounding on the tip
    );
    canvas.drawRRect(rRect, bgPaint);

    // 2. Draw Inner Light Blue Face
    final innerFacePaint = Paint()
      ..color = const Color(0xFFCBE2DF) // Light blue tint
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.75, innerFacePaint);

    // Calculate rotation angles based on time
    // Let's make the minute hand rotate fully every 2 seconds.
    // The hour hand rotates 1/12th of that speed.
    final minuteAngle = animationValue * 2 * math.pi;
    final hourAngle = (animationValue * 2 * math.pi) / 12;

    // 3. Draw Hands
    final handPaint = Paint()
      ..color = const Color(0xFF1E1E1E)
      ..strokeWidth = radius * 0.15
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Hour Hand
    _drawHand(canvas, center, hourAngle, radius * 0.35, handPaint);
    
    // Minute Hand
    _drawHand(canvas, center, minuteAngle, radius * 0.55, handPaint);

    // 4. Draw Red Center Bubble
    final centerBubblePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFEF4444), // Light red (glare)
          const Color(0xFFB91C1C), // Base red
          const Color(0xFF7F1D1D), // Dark red shadow
        ],
        stops: const [0.1, 0.6, 1.0],
        center: const Alignment(-0.2, -0.4), // Offset for 3D light effect
        radius: 0.8,
      ).createShader(Rect.fromCircle(center: center, radius: radius * 0.35));
    
    canvas.drawCircle(center, radius * 0.3, centerBubblePaint);

    // 5. Draw Small white pivot dot in center
    final pivotPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, radius * 0.05, pivotPaint);
  }

  void _drawHand(Canvas canvas, Offset center, double angle, double length, Paint paint) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle - math.pi / 2); // Start pointing up (-90 deg)
    canvas.drawLine(const Offset(0, 0), Offset(length, 0), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ClockLogoPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
