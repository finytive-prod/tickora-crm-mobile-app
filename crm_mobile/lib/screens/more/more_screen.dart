import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/core/services/privilege_service.dart';
import 'package:crm_mobile/core/services/fcm_service.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/screens/auth/login_screen.dart';
import 'package:crm_mobile/screens/home_screen.dart';
import 'package:crm_mobile/screens/settings/settings_menu_screen.dart';
import 'package:crm_mobile/screens/staff/staff_list_screen.dart';
import 'package:crm_mobile/screens/customers/customers_screen.dart';
import 'package:crm_mobile/screens/reports/reports_screen.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/blocs/leads_bloc.dart';
import 'package:crm_mobile/blocs/leads_event.dart';
import 'package:crm_mobile/screens/pipeline/lead_pipeline_screen.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  String _userName = 'User';
  String _userEmail = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _checkAndRefreshPrivileges();
  }

  void _checkAndRefreshPrivileges() async {
    final priv = sl<PrivilegeService>();
    if (priv.privileges.isEmpty) {
      await priv.fetchPrivileges();
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _loadUserData() async {
    final prefs = sl<SharedPreferences>();
    setState(() {
      _userName = prefs.getString('userName') ?? 'User';
      _userEmail = prefs.getString('userEmail') ?? '';
    });
  }

  void _handleLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.logout, color: Color(0xFFDB222A)),
              SizedBox(width: 8),
              Text(
                'Logout',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const Text('Are you sure you want to log out of the application?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDB222A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                
                final prefs = sl<SharedPreferences>();
                await prefs.clear(); // Complete session wipe
                sl<PrivilegeService>().clearPrivileges();
                
                // Delete FCM token so this device stops receiving notifications
                await FcmService.instance.deleteToken();
                
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                    (Route<dynamic> route) => false,
                  );
                }
              },
              child: const Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _changeTab(BuildContext context, String label) {
    final homeState = context.findAncestorStateOfType<HomeScreenState>();
    if (homeState != null) {
      homeState.changeTabByLabel(label);
    }
  }

  @override
  Widget build(BuildContext context) {
    const brandColor = Color(0xFFDB222A);
    final activeTabColor = const Color(0xFFFEE2E2);
    final priv = sl<PrivilegeService>();

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Red Header Section
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: brandColor,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            padding: const EdgeInsets.only(top: 50, left: 20, right: 20, bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo & Close row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Image.asset(
                          'assets/images/logo.webp',
                          width: 28,
                          height: 28,
                          errorBuilder: (_, __, ___) => const Icon(Icons.dashboard_customize_outlined, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'TICKORA CRM',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () => _changeTab(context, priv.hasPrivilege('LEAD_READ') ? 'Leads' : 'Dashboard'),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Profile row
                Row(
                  children: [
                    // Avatar
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.white,
                        child: Icon(Icons.person, color: brandColor, size: 32),
                      ),
                    ),
                    const SizedBox(width: 14),

                    // User name & email
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _userName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _userEmail,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Menu List Section
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                if (priv.hasPrivilege('DASHBOARD_READ'))
                  _buildMenuItem(
                    icon: Icons.grid_view_outlined,
                    title: 'Dashboard',
                    isSelected: true,
                    activeTabColor: activeTabColor,
                    brandColor: brandColor,
                    onTap: () => _changeTab(context, 'Dashboard'),
                  ),
                if (priv.hasPrivilege('LEAD_READ')) ...[
                  _buildMenuItem(
                    icon: Icons.person_add_alt_1_outlined,
                    title: 'Leads',
                    brandColor: brandColor,
                    onTap: () => _changeTab(context, 'Leads'),
                  ),
                  _buildMenuItem(
                    icon: Icons.auto_awesome_mosaic_outlined,
                    title: 'Pipelines',
                    brandColor: brandColor,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const LeadPipelineScreen()),
                      );
                    },
                  ),
                ],
                if (priv.hasPrivilege('CUSTOMER_READ'))
                  _buildMenuItem(
                    icon: Icons.people_outline,
                    title: 'Customers',
                    brandColor: brandColor,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const CustomerScreen()),
                      );
                    },
                  ),
                if (priv.hasPrivilege('FOLLOWUP_READ'))
                  _buildMenuItem(
                    icon: Icons.phone_in_talk_outlined,
                    title: 'Follow-ups',
                    brandColor: brandColor,
                    onTap: () => _changeTab(context, 'Follow ups'),
                  ),
                if (priv.hasPrivilege('STAFF_READ') || priv.hasPrivilege('USER_READ'))
                  _buildMenuItem(
                    icon: Icons.business_center_outlined,
                    title: 'Staff',
                    brandColor: brandColor,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const StaffListScreen()),
                      );
                    },
                  ),
                // _buildMenuItem(
                //   icon: Icons.check_box_outlined,
                //   title: 'Tasks',
                //   brandColor: brandColor,
                //   onTap: () => _showComingSoon('Tasks'),
                // ),
                if (priv.hasPrivilege('CALENDAR_READ'))
                  _buildMenuItem(
                    icon: Icons.calendar_today_outlined,
                    title: 'Calendar',
                    brandColor: brandColor,
                    onTap: () => _changeTab(context, 'Calendar'),
                  ),
                if (priv.hasPrivilege('REPORT_READ'))
                  _buildMenuItem(
                    icon: Icons.bar_chart_outlined,
                    title: 'Reports',
                    brandColor: brandColor,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => BlocProvider<LeadsBloc>(
                            create: (_) => sl<LeadsBloc>()
                              ..add(FetchLeadStatuses())
                              ..add(FetchLeadSources())
                              ..add(const FetchStaffUsers()),
                            child: const ReportsScreen(),
                          ),
                        ),
                      );
                    },
                  ),
                
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Divider(color: Color(0xFFF3F4F6), thickness: 1, height: 1),
                ),

                if (priv.hasPrivilege('SETTINGS_READ'))
                  _buildMenuItem(
                    icon: Icons.settings_outlined,
                    title: 'Settings',
                    brandColor: brandColor,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const SettingsMenuScreen()),
                      );
                    },
                  ),
                // _buildMenuItem(
                //   icon: Icons.person_outline,
                //   title: 'Profile',
                //   brandColor: brandColor,
                //   onTap: () => _showComingSoon('Profile'),
                // ),
                _buildMenuItem(
                  icon: Icons.logout,
                  title: 'Logout',
                  brandColor: brandColor,
                  isDestructive: true,
                  onTap: () => _handleLogout(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required Color brandColor,
    required VoidCallback onTap,
    bool isSelected = false,
    Color? activeTabColor,
    bool isDestructive = false,
  }) {
    final color = isDestructive 
        ? brandColor 
        : (isSelected ? brandColor : AppColors.textPrimary);
        
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? activeTabColor : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(icon, color: color, size: 22),
        title: Text(
          title,
          style: TextStyle(
            color: color,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 15,
          ),
        ),
        trailing: isSelected 
            ? Icon(Icons.chevron_right, color: color, size: 20) 
            : null,
        onTap: onTap,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
    );
  }

  
}
