import 'package:flutter/material.dart';

class WhatsAppIcon extends StatelessWidget {
  final double size;
  final Color? backgroundColor;
  final Color? iconColor;

  const WhatsAppIcon({
    super.key,
    this.size = 20.0,
    this.backgroundColor = const Color(0xFF25D366),
    this.iconColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _WhatsAppPainter(
        backgroundColor: backgroundColor ?? const Color(0xFF25D366),
        iconColor: iconColor ?? Colors.white,
      ),
    );
  }
}

class _WhatsAppPainter extends CustomPainter {
  final Color backgroundColor;
  final Color iconColor;

  _WhatsAppPainter({
    required this.backgroundColor,
    required this.iconColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    canvas.save();
    canvas.scale(scale, scale);

    // 1. WhatsApp Speech Bubble Background
    final bubblePath = Path();
    bubblePath.moveTo(12.04, 2.0);
    bubblePath.cubicTo(6.58, 2.0, 2.13, 6.45, 2.13, 11.91);
    bubblePath.cubicTo(2.13, 13.66, 2.59, 15.36, 3.45, 16.86);
    bubblePath.lineTo(2.05, 22.0);
    bubblePath.lineTo(7.3, 20.62);
    bubblePath.cubicTo(8.75, 21.41, 10.38, 21.83, 12.04, 21.83);
    bubblePath.cubicTo(17.5, 21.83, 21.95, 17.38, 21.95, 11.92);
    bubblePath.cubicTo(21.95, 9.27, 20.92, 6.78, 19.05, 4.91);
    bubblePath.cubicTo(17.18, 3.03, 14.69, 2.0, 12.04, 2.0);
    bubblePath.close();

    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(bubblePath, bgPaint);

    // 2. White Phone Handset Inside
    final handsetPath = Path();
    handsetPath.moveTo(8.53, 7.33);
    handsetPath.cubicTo(8.37, 7.33, 8.1, 7.39, 7.87, 7.64);
    handsetPath.cubicTo(7.65, 7.89, 7.02, 8.48, 7.02, 9.68);
    handsetPath.cubicTo(7.02, 10.88, 7.89, 12.04, 8.01, 12.2);
    handsetPath.cubicTo(8.13, 12.37, 9.71, 14.81, 12.13, 15.86);
    handsetPath.cubicTo(14.15, 16.73, 14.56, 16.55, 15.0, 16.51);
    handsetPath.cubicTo(15.45, 16.47, 16.43, 15.93, 16.64, 15.36);
    handsetPath.cubicTo(16.84, 14.78, 16.84, 14.29, 16.78, 14.19);
    handsetPath.cubicTo(16.72, 14.08, 16.56, 14.02, 16.32, 13.9);
    handsetPath.cubicTo(16.07, 13.78, 14.86, 13.18, 14.63, 13.1);
    handsetPath.cubicTo(14.41, 13.01, 14.24, 12.97, 14.08, 13.22);
    handsetPath.cubicTo(13.92, 13.47, 13.45, 14.02, 13.31, 14.19);
    handsetPath.cubicTo(13.17, 14.35, 13.03, 14.37, 12.78, 14.25);
    handsetPath.cubicTo(12.54, 14.13, 11.75, 13.87, 10.82, 13.04);
    handsetPath.cubicTo(10.09, 12.39, 9.6, 11.59, 9.46, 11.34);
    handsetPath.cubicTo(9.32, 11.1, 9.44, 10.96, 9.57, 10.84);
    handsetPath.cubicTo(9.68, 10.73, 9.81, 10.55, 9.94, 10.41);
    handsetPath.cubicTo(10.06, 10.26, 10.1, 10.16, 10.18, 10.0);
    handsetPath.cubicTo(10.26, 9.83, 10.22, 9.69, 10.16, 9.57);
    handsetPath.cubicTo(10.1, 9.44, 9.63, 8.28, 9.43, 7.81);
    handsetPath.cubicTo(9.24, 7.34, 9.04, 7.41, 8.89, 7.4);
    handsetPath.cubicTo(8.75, 7.4, 8.58, 7.39, 8.53, 7.33);
    handsetPath.close();

    final handsetPaint = Paint()
      ..color = iconColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(handsetPath, handsetPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WhatsAppPainter oldDelegate) {
    return oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.iconColor != iconColor;
  }
}
