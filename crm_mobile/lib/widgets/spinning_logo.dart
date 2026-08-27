import 'dart:math';
import 'package:flutter/material.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';

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
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildDot(int index) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Calculate offset for a wave effect
        final offset = sin((_controller.value * 2 * pi) - (index * 1.5)) * 6;
        return Transform.translate(
          offset: Offset(0, offset),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/logo.webp',
            width: widget.size,
            height: widget.size,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                Icons.image_not_supported_outlined,
                size: widget.size,
                color: AppColors.primary,
              );
            },
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (index) => _buildDot(index)),
          ),
          const SizedBox(height: 12),
         
        ],
      ),
    );
  }
}
