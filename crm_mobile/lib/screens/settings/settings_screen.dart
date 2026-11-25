import 'package:flutter/material.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/core/services/privilege_service.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'lead_custom_form_screen.dart';
import 'lead_statuses_screen.dart';
import 'lead_sources_screen.dart';
import 'roles_permissions_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondary,
      appBar: AppBar(
        backgroundColor: AppColors.secondary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                'Manage application settings and configurations',
                style: TextStyle(color: AppColors.textHint, fontSize: 14),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  if (sl<PrivilegeService>().hasPrivilege('LEAD_CUSTOM_FIELDS_READ') ||
                      sl<PrivilegeService>().hasPrivilege('LEAD_CUSTOM_FORM_READ') ||
                      sl<PrivilegeService>().hasPrivilege('CUSTOM_FIELDS_READ')) ...[
                    _buildSettingCard(
                      context: context,
                      icon: Icons.list_alt_rounded,
                      iconColor: Colors.deepPurple,
                      title: 'Lead Custom Form',
                      subtitle: 'Define and manage custom input fields for the Create Lead form.',
                      destination: const LeadCustomFormScreen(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (sl<PrivilegeService>().hasPrivilege('LEAD_STATUS_READ') ||
                      sl<PrivilegeService>().hasPrivilege('LEAD_STATUSES_READ')) ...[
                    _buildSettingCard(
                      context: context,
                      icon: Icons.playlist_add_check_rounded,
                      iconColor: Colors.teal,
                      title: 'Lead Statuses',
                      subtitle: 'Configure customer statuses with custom colors, orders, and linked rules.',
                      destination: const LeadStatusesScreen(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (sl<PrivilegeService>().hasPrivilege('LEAD_SOURCES_READ') ||
                      sl<PrivilegeService>().hasPrivilege('LEAD_SOURCE_READ')) ...[
                    _buildSettingCard(
                      context: context,
                      icon: Icons.hub_outlined,
                      iconColor: Colors.blue,
                      title: 'Lead Sources',
                      subtitle: 'Configure and track acquisition channels like Website, Referral, Ads, etc.',
                      destination: const LeadSourcesScreen(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (sl<PrivilegeService>().hasPrivilege('PERMISSIONS_READ') ||
                      sl<PrivilegeService>().hasPrivilege('PERMISSION_READ') ||
                      sl<PrivilegeService>().hasPrivilege('ROLES_READ') ||
                      sl<PrivilegeService>().hasPrivilege('ROLE_READ')) ...[
                    _buildSettingCard(
                      context: context,
                      icon: Icons.admin_panel_settings_outlined,
                      iconColor: AppColors.primary,
                      title: 'Roles & Permissions',
                      subtitle: 'Manage role-based access for modules such as Customer, Invoice, Payroll, and Items.',
                      destination: const RolesPermissionsScreen(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingCard({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget destination,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderEnabled),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.015),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => destination),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
