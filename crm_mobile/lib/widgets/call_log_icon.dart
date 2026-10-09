import 'package:flutter/material.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';

class CallLogIcon extends StatelessWidget {
  final Color? color;
  final double size;

  const CallLogIcon({
    super.key,
    this.color,
    this.size = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? IconTheme.of(context).color ?? AppColors.textHint;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            left: 0,
            child: Icon(Icons.phone, size: size * 0.72, color: iconColor),
          ),
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              padding: const EdgeInsets.all(0.5),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.history, size: size * 0.58, color: iconColor),
            ),
          ),
        ],
      ),
    );
  }
}
