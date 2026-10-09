import 'package:crm_mobile/screens/dashboard/dashboard_screen.dart';
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
import 'package:crm_mobile/repositories/login_repository.dart';
import 'package:crm_mobile/screens/profile/profile_screen.dart';
import 'package:crm_mobile/widgets/call_log_icon.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  String _userName = 'User';
  String _userEmail = '';
  String _userRole = '';

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
      _userRole = prefs.getString('userRole') ?? '';
    });

    if (sl.isRegistered<LoginRepository>()) {
      sl<LoginRepository>().getProfile().then((res) {
        res.fold((_) {}, (profile) {
          if (mounted) {
            setState(() {
              _userName = profile.fullName.isNotEmpty
                  ? profile.fullName
                  : _userName;
              _userEmail = profile.email.isNotEmpty
                  ? profile.email
                  : _userEmail;
              if (profile.roles.isNotEmpty) {
                _userRole = profile.roles.join(', ');
              } else if (profile.designation != null &&
                  profile.designation!.isNotEmpty) {
                _userRole = profile.designation!;
              }
            });
          }
        });
      });
    }
  }

  void _handleLogout(BuildContext context) {
    FocusManager.instance.primaryFocus?.unfocus();
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.logout, color: Color(0xFFDB222A)),
              SizedBox(width: 8),
              Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'Are you sure you want to log out of the application?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDB222A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () async {
                Navigator.of(dialogContext).pop();

                // Call logout API endpoint with FCM token
                try {
                  if (sl.isRegistered<LoginRepository>()) {
                    await sl<LoginRepository>().logout();
                  }
                } catch (_) {}

                // Clear session & FCM token
                if (sl.isRegistered<SharedPreferences>()) {
                  await sl<SharedPreferences>().clear();
                }
                sl<PrivilegeService>().clearPrivileges();
                await FcmService.instance.deleteToken();

                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(),
                    ),
                    (Route<dynamic> route) => false,
                  );
                }
              },
              child: const Text(
                'Logout',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  void _openEditProfileModal() {
    final nameController = TextEditingController(text: _userName.trim());
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                top: 20,
                left: 20,
                right: 20,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Edit Profile',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: AppColors.textSecondary),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Name',
                        prefixIcon: const Icon(Icons.person_outline, color: AppColors.primary),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.primary, width: 2),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 2,
                        ),
                        onPressed: isSaving
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                setModalState(() => isSaving = true);

                                final repo = sl<LoginRepository>();
                                final result = await repo.updateProfile(
                                  nameController.text.trim(),
                                );

                                if (!context.mounted) return;
                                Navigator.pop(ctx);

                                result.fold(
                                  (failure) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(failure.message),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  },
                                  (updatedProfile) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Profile updated successfully!'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                    _loadUserData();
                                  },
                                );
                              },
                        child: isSaving
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                              )
                            : const Text(
                                'Save Changes',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
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
    final priv = sl<PrivilegeService>();
    final bool showAllByDefault = priv.privileges.isEmpty;

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
            padding: const EdgeInsets.only(
              top: 50,
              left: 20,
              right: 20,
              bottom: 24,
            ),
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
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.dashboard_customize_outlined,
                            color: Colors.white,
                            size: 24,
                          ),
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
                      onTap: _openEditProfileModal,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.edit_outlined,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Centered Profile Header
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: Colors.white,
                        child: Text(
                          _userName.isNotEmpty ? _userName[0].toUpperCase() : 'U',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: brandColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Centered User Name
                      Text(
                        _userName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),

                      // Role below the name
                      Text(
                        _userRole.isNotEmpty ? _userRole : 'USER',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Menu List Section
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                if (showAllByDefault || priv.hasPrivilege('DASHBOARD_READ'))
                  _buildMenuItem(
                    icon: Icons.grid_view_outlined,
                    title: 'Dashboard',
                    brandColor: brandColor,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const DashboardScreen(),
                        ),
                      );
                    },
                  ),
                if (showAllByDefault ||
                    priv.hasPrivilege('CALL_READ') ||
                    priv.hasPrivilege('DASHBOARD_READ'))
                  _buildMenuItem(
                    customIcon: const CallLogIcon(
                      color: AppColors.textPrimary,
                      size: 22,
                    ),
                    title: 'Call logs',
                    brandColor: brandColor,
                    onTap: () => _changeTab(context, 'Call logs'),
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
                        MaterialPageRoute(
                          builder: (context) => const LeadPipelineScreen(),
                        ),
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
                        MaterialPageRoute(
                          builder: (context) => const CustomerScreen(),
                        ),
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
                if (priv.hasPrivilege('STAFF_READ') ||
                    priv.hasPrivilege('USER_READ'))
                  _buildMenuItem(
                    icon: Icons.business_center_outlined,
                    title: 'Staff',
                    brandColor: brandColor,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const StaffListScreen(),
                        ),
                      );
                    },
                  ),
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
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Divider(
                    color: Color(0xFFF3F4F6),
                    thickness: 1,
                    height: 1,
                  ),
                ),

                if (priv.hasPrivilege('SETTINGS_READ'))
                  _buildMenuItem(
                    icon: Icons.settings_outlined,
                    title: 'Settings',
                    brandColor: brandColor,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SettingsMenuScreen(),
                        ),
                      );
                    },
                  ),
                _buildMenuItem(
                  icon: Icons.person_outline,
                  title: 'My Profile',
                  brandColor: brandColor,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProfileScreen(),
                      ),
                    );
                    _loadUserData();
                  },
                ),
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
    IconData? icon,
    Widget? customIcon,
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
        leading:
            customIcon ??
            (icon != null ? Icon(icon, color: color, size: 22) : null),
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
