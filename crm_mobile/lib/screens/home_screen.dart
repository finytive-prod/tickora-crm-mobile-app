import 'package:crm_mobile/injection/injection.dart';
import 'package:flutter/material.dart';
import 'package:crm_mobile/widgets/custom_bottom_nav_bar.dart';
import 'package:crm_mobile/screens/calls/calls_screen.dart';
import 'package:crm_mobile/screens/leads/leads_screen.dart';
import 'package:crm_mobile/screens/more/more_screen.dart';
import 'package:crm_mobile/screens/followups/followups_screen.dart';
import 'package:crm_mobile/screens/calendar/calendar_screen.dart';
import 'package:crm_mobile/core/services/privilege_service.dart';
import 'package:crm_mobile/core/services/call_recording_service.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/widgets/call_log_icon.dart';
import 'package:crm_mobile/core/utils/navigation_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 1;
  final List<Widget> _screens = [];
  final List<BottomNavigationBarItem> _navItems = [];
  bool _isCheckingPermissions = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _buildTabs();
    final leadsIndex = _navItems.indexWhere((item) => item.label == 'Leads');
    if (leadsIndex != -1) {
      _currentIndex = leadsIndex;
    }
    NavigationService.markAppReady();
    sl<PrivilegeService>().addListener(_onPrivilegesChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndRequestStartupPermissions();
    });
  }

  void _onPrivilegesChanged() {
    if (mounted) {
      setState(() {
        _buildTabs();
      });
    }
  }

  bool _isOverlayDialogShowing = false;
  bool _isScreeningDialogShowing = false;
  bool _hasPromptedScreeningThisSession = false;
  bool _isStorageDialogShowing = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) {
          _checkAndRequestStartupPermissions();
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    sl<PrivilegeService>().removeListener(_onPrivilegesChanged);
    super.dispose();
  }

  Future<void> _checkAndRequestStartupPermissions() async {
    if (!mounted || _isCheckingPermissions || _isOverlayDialogShowing || _isScreeningDialogShowing || _isStorageDialogShowing) return;
    _isCheckingPermissions = true;

    try {
      final service = CallRecordingService();

      // 1. Overlay Permission: If not granted, display the Overlay Permission dialog popup
      final hasOverlay = await service.hasOverlayPermission();
      if (!hasOverlay) {
        if (mounted && !_isOverlayDialogShowing) {
          await _showOverlayPermissionDialog(service);
        }
        return;
      }

      // 2. Caller ID / Call Screening Role: Prompt once per session to enable Caller ID
      final hasScreening = await service.hasCallScreeningRole();
      if (!hasScreening && !_hasPromptedScreeningThisSession) {
        _hasPromptedScreeningThisSession = true;
        if (mounted && !_isScreeningDialogShowing) {
          await _showCallScreeningDialog(service);
        }
      }

      // 3. Storage Permission: Check storage permission
      final hasStorage = await service.hasStoragePermission();
      if (!hasStorage) {
        if (mounted && !_isStorageDialogShowing) {
          await _showStoragePermissionDialog(service);
        }
        return;
      }
    } catch (e) {
      debugPrint('Error checking startup permissions: $e');
    } finally {
      _isCheckingPermissions = false;
    }
  }

  Future<void> _showOverlayPermissionDialog(CallRecordingService service) async {
    _isOverlayDialogShowing = true;
    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.layers_rounded, color: AppColors.primary, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Overlay Permission',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: const Text(
            'Tickora CRM requires "Display over other apps" permission to show caller details and call popup while receiving or making calls.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('NOT NOW', style: TextStyle(color: AppColors.textHint)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                await service.requestOverlayPermission();
              },
              child: const Text(
                'TURN ON PERMISSION',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    } finally {
      _isOverlayDialogShowing = false;
    }
  }

  Future<void> _showCallScreeningDialog(CallRecordingService service) async {
    _isScreeningDialogShowing = true;
    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.phone_in_talk_rounded, color: AppColors.primary, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Caller ID Permission',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: const Text(
            'Tickora CRM requires Caller ID permission to detect caller phone numbers in real time when you receive or make calls.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('NOT NOW', style: TextStyle(color: AppColors.textHint)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                await service.requestCallScreeningRole();
              },
              child: const Text(
                'ENABLE CALLER ID',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    } finally {
      _isScreeningDialogShowing = false;
    }
  }

  Future<void> _showStoragePermissionDialog(CallRecordingService service) async {
    _isStorageDialogShowing = true;
    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.folder_special_rounded, color: AppColors.primary, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Storage Permission',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: const Text(
            'Tickora CRM requires All Files Access and Call Log permissions on startup to automatically record, match, and sync customer call recordings.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('NOT NOW', style: TextStyle(color: AppColors.textHint)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                await service.openStoragePermissionSettings();
              },
              child: const Text('ALLOW PERMISSION', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } finally {
      _isStorageDialogShowing = false;
    }
  }

  void changeTabByLabel(String label) {
    final index = _navItems.indexWhere((item) =>
        item.label == label ||
        
        (label == 'Call Logs' && item.label == 'Call Logs'));
    if (index != -1) {
      setState(() {
        _currentIndex = index;
      });
    }
  }

  void _buildTabs() {
    _screens.clear();
    _navItems.clear();

    final priv = sl<PrivilegeService>();
    final bool showAllByDefault = priv.privileges.isEmpty;

    if (showAllByDefault ||
        priv.hasPrivilege('CALL_READ') ||
        priv.hasPrivilege('DASHBOARD_READ') ||
        priv.hasPrivilege('LEAD_READ')) {
      _screens.add(const CallsScreen());
      _navItems.add(const BottomNavigationBarItem(
        icon: CallLogIcon(color: AppColors.textHint),
        activeIcon: CallLogIcon(color: AppColors.primary),
        label: 'Call Logs',
      ));
    }

    if (showAllByDefault || priv.hasPrivilege('LEAD_READ')) {
      _screens.add(const LeadsScreen());
      _navItems.add(const BottomNavigationBarItem(
        icon: Icon(Icons.person_outline),
        activeIcon: Icon(Icons.person),
        label: 'Leads',
      ));
    }

    if (showAllByDefault || priv.hasPrivilege('FOLLOWUP_READ')) {
      _screens.add(const FollowUpsScreen());
      _navItems.add(const BottomNavigationBarItem(
        icon: Icon(Icons.reply_outlined),
        activeIcon: Icon(Icons.reply),
        label: 'Follow ups',
      ));
    }

    if (showAllByDefault || priv.hasPrivilege('CALENDAR_READ')) {
      _screens.add(const CalendarScreen());
      _navItems.add(const BottomNavigationBarItem(
        icon: Icon(Icons.calendar_today_outlined),
        activeIcon: Icon(Icons.calendar_today),
        label: 'Calendar',
      ));
    }

    // More tab is always available
    _screens.add(const MoreScreen());
    _navItems.add(const BottomNavigationBarItem(
      icon: Icon(Icons.menu),
      activeIcon: Icon(Icons.menu),
      label: 'More',
    ));

    if (_currentIndex < 0 || _currentIndex >= _screens.length) {
      final leadsIndex = _navItems.indexWhere((item) => item.label == 'Leads');
      _currentIndex = leadsIndex != -1 ? leadsIndex : 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_screens.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final safeIndex = _currentIndex.clamp(0, _screens.length - 1);

    return Scaffold(
      body: _screens[safeIndex],
      bottomNavigationBar: _navItems.length >= 2
          ? CustomBottomNavBar(
              currentIndex: safeIndex,
              items: _navItems,
              onTap: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
            )
          : null,
    );
  }
}
