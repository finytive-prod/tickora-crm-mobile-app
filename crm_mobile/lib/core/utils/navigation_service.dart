import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/screens/auth/login_screen.dart';

class NavigationService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static Future<void> handleSessionExpired() async {
    if (sl.isRegistered<SharedPreferences>()) {
      final prefs = sl<SharedPreferences>();
      await prefs.remove('token');
    }

    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(sessionExpired: true),
      ),
      (route) => false,
    );
  }
}
