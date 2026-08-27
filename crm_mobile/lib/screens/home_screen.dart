import 'package:flutter/material.dart';
import 'package:crm_mobile/widgets/custom_bottom_nav_bar.dart';
import 'package:crm_mobile/screens/dashboard/dashboard_screen.dart';
import 'package:crm_mobile/screens/leads/leads_screen.dart';
import 'package:crm_mobile/screens/more/more_screen.dart';
import 'package:crm_mobile/screens/followups/followups_screen.dart';
import 'package:crm_mobile/screens/calendar/calendar_screen.dart';
import 'package:crm_mobile/core/services/privilege_service.dart';
import 'package:crm_mobile/core/services/call_recording_service.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/injection/injection.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  List<Widget> _screens = [];
  List<BottomNavigationBarItem> _navItems = [];

  @override
  void initState() {
    super.initState();
    _buildTabs();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndRequestStartupPermissions();
    });
  }

  Future<void> _checkAndRequestStartupPermissions() async {
    final service = CallRecordingService();
    final hasPerm = await service.hasStoragePermission();
    if (!hasPerm && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.folder_special_rounded, color: AppColors.primary, size: 28),
              SizedBox(width: 10),
              Text('Storage Permission', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
    }
  }

  void changeTabByLabel(String label) {
    final index = _navItems.indexWhere((item) => item.label == label);
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

    // If privileges service has privileges defined, check them. Otherwise show default set.
    final bool showAllByDefault = priv.privileges.isEmpty;

    if (showAllByDefault || priv.hasPrivilege('DASHBOARD_READ')) {
      _screens.add(const DashboardScreen());
      _navItems.add(const BottomNavigationBarItem(
        icon: Icon(Icons.home_outlined),
        activeIcon: Icon(Icons.home),
        label: 'Dashboard',
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

    // Set default tab to Leads if it exists, otherwise 0
    final leadsIndex = _navItems.indexWhere((item) => item.label == 'Leads');
    _currentIndex = leadsIndex != -1 ? leadsIndex : 0;
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
