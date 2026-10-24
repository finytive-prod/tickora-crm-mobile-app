import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/blocs/leads_bloc.dart';
import 'package:crm_mobile/screens/auth/login_screen.dart';
import 'package:crm_mobile/screens/leads/lead_details_screen.dart';
import 'package:crm_mobile/screens/leads/quick_invite_screen.dart';

class NavigationService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static bool isAppReady = false;
  static String? _pendingQuickInvitePhone;
  static String? _pendingLeadDetailId;
  static DateTime? _lastNavigationTime;
  static String? _lastNavigatedTarget;

  static void markAppReady() {
    isAppReady = true;
    processPendingNavigation();
  }

  static void processPendingNavigation() {
    if (!isAppReady) return;
    if (_pendingLeadDetailId != null) {
      final id = _pendingLeadDetailId!;
      _pendingLeadDetailId = null;
      _pendingQuickInvitePhone = null;
      navigateToLeadDetails(id);
    } else if (_pendingQuickInvitePhone != null) {
      final phone = _pendingQuickInvitePhone!;
      _pendingQuickInvitePhone = null;
      _pendingLeadDetailId = null;
      navigateToQuickInvite(phone);
    }
  }

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

  static void navigateToLeadDetails(String leadId) {
    final cleanId = leadId.trim();
    if (cleanId.isEmpty) return;

    if (!isAppReady) {
      _pendingLeadDetailId = cleanId;
      return;
    }

    final now = DateTime.now();
    if (_lastNavigatedTarget == 'lead_$cleanId' &&
        _lastNavigationTime != null &&
        now.difference(_lastNavigationTime!).inMilliseconds < 1500) {
      return;
    }
    _lastNavigatedTarget = 'lead_$cleanId';
    _lastNavigationTime = now;

    void doNavigate() {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => LeadDetailsScreen(leadId: cleanId),
        ),
      );
    }

    if (navigatorKey.currentState != null) {
      doNavigate();
    } else {
      Future.delayed(const Duration(milliseconds: 300), doNavigate);
    }
  }

  static void navigateToQuickInvite(String phoneNumber) {
    final cleanPhone = phoneNumber.trim();
    if (cleanPhone.isEmpty) return;

    if (!isAppReady) {
      _pendingQuickInvitePhone = cleanPhone;
      return;
    }

    final now = DateTime.now();
    if (_lastNavigatedTarget == 'quick_$cleanPhone' &&
        _lastNavigationTime != null &&
        now.difference(_lastNavigationTime!).inMilliseconds < 1500) {
      return;
    }
    _lastNavigatedTarget = 'quick_$cleanPhone';
    _lastNavigationTime = now;

    void doNavigate() {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => BlocProvider<LeadsBloc>(
            create: (_) => sl<LeadsBloc>(),
            child: QuickInviteScreen(initialPhoneNumber: cleanPhone),
          ),
        ),
      );
    }

    if (navigatorKey.currentState != null) {
      doNavigate();
    } else {
      Future.delayed(const Duration(milliseconds: 300), doNavigate);
    }
  }
}
