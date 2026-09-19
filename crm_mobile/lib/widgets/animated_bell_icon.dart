import 'package:flutter/material.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';

class AnimatedBellIcon extends StatefulWidget {
  final int unreadCount;
  final VoidCallback onTap;

  const AnimatedBellIcon({
    super.key,
    required this.unreadCount,
    required this.onTap,
  });

  @override
  State<AnimatedBellIcon> createState() => _AnimatedBellIconState();
}

class _AnimatedBellIconState extends State<AnimatedBellIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    // Zoom in / zoom out scale pulse (1.0 to 1.25)
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.25).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.25, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50,
      ),
    ]).animate(_controller);

    // Bell swinging vibration angle (-0.25 rad to +0.25 rad, approx -15 to +15 degrees)
    _rotationAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: -0.25).chain(CurveTween(curve: Curves.easeOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -0.25, end: 0.25).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.25, end: -0.12).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -0.12, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 20,
      ),
    ]).animate(_controller);

    // Expanding vibration wave pulse
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    if (widget.unreadCount > 0) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(AnimatedBellIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.unreadCount > 0) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    } else {
      if (_controller.isAnimating) {
        _controller.stop();
        _controller.reset();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = widget.unreadCount > 0;

    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(6.0),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 1. Continuous expanding vibration wave pulse ring (only when unread)
            if (hasUnread)
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  final size = 28.0 + (22.0 * _pulseAnimation.value);
                  final opacity = (1.0 - _pulseAnimation.value).clamp(0.0, 1.0) * 0.45;
                  return Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withValues(alpha: opacity),
                    ),
                  );
                },
              ),

            // 2. Bell icon: swinging animation when unread, static when no unread
            if (hasUnread)
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Transform.rotate(
                      angle: _rotationAnimation.value,
                      child: const Icon(
                        Icons.notifications_active_rounded,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                  );
                },
              )
            else
              const Icon(
                Icons.notifications_none_rounded,
                color: AppColors.textPrimary,
                size: 24,
              ),

            // 3. Unread count badge
            if (hasUnread)
              Positioned(
                top: 0,
                right: 0,
                child: AnimatedBuilder(
                  animation: _scaleAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _scaleAnimation.value,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.5),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          widget.unreadCount > 9 ? '9+' : widget.unreadCount.toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
