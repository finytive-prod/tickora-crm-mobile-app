import 'package:flutter/material.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';

class CustomBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final List<BottomNavigationBarItem> items;

  const CustomBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    if (items.length < 2) {
      return const SizedBox.shrink();
    }

    final safeIndex = currentIndex.clamp(0, items.length - 1);

    return BottomNavigationBar(
      currentIndex: safeIndex,
      onTap: onTap,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textHint,
      backgroundColor: Colors.white,
      showUnselectedLabels: true,
      selectedFontSize: 12,
      unselectedFontSize: 12,
      elevation: 8,
      items: items,
    );
  }
}
