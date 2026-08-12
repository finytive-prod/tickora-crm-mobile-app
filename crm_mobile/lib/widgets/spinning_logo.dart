import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

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
      duration: const Duration(seconds: 2),
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
    return Center(
      child: RotationTransition(
        turns: _controller,
        child: Image.asset(
          'assets/images/app_logo.png',
          width: widget.size,
          height: widget.size,
          errorBuilder: (context, error, stackTrace) {
            // Fallback to progress indicator if image fails to load
            return CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 3,
            );
          },
        ),
      ),
    );
  }
}
