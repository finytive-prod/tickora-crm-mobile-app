import 'package:flutter/material.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/screens/settings/lead_custom_form_screen.dart';
import 'package:crm_mobile/screens/settings/lead_statuses_screen.dart';
import 'package:crm_mobile/screens/settings/lead_sources_screen.dart';
import 'package:crm_mobile/screens/settings/roles_permissions_screen.dart';
import 'package:crm_mobile/core/services/privilege_service.dart';
import 'package:crm_mobile/injection/injection.dart';

class SettingsMenuScreen extends StatelessWidget {
  const SettingsMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondary,
      appBar: AppBar(
        backgroundColor: AppColors.secondary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Settings',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111827), // AppColors.textPrimary
                ),
              ),
              const SizedBox(height: 24),
              
              () {
                final priv = sl<PrivilegeService>();
                final items = <Widget>[];

                if (priv.hasPrivilege('LEAD_CUSTOM_FIELDS_READ') ||
                    priv.hasPrivilege('LEAD_CUSTOM_FORM_READ') ||
                    priv.hasPrivilege('CUSTOM_FIELDS_READ')) {
                  items.add(_buildMenuItem(
                    context: context,
                    icon: Icons.list_alt_rounded,
                    title: 'Lead Custom Form',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const LeadCustomFormScreen()),
                      );
                    },
                  ));
                }

                if (priv.hasPrivilege('LEAD_STATUS_READ') ||
                    priv.hasPrivilege('LEAD_STATUSES_READ')) {
                  items.add(_buildMenuItem(
                    context: context,
                    icon: Icons.settings_outlined,
                    title: 'Lead Status',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const LeadStatusesScreen()),
                      );
                    },
                  ));
                }

                if (priv.hasPrivilege('LEAD_SOURCES_READ') ||
                    priv.hasPrivilege('LEAD_SOURCE_READ')) {
                  items.add(_buildMenuItem(
                    context: context,
                    icon: Icons.people_alt_outlined,
                    title: 'Lead Sources',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const LeadSourcesScreen()),
                      );
                    },
                  ));
                }

                if (priv.hasPrivilege('PERMISSIONS_READ') ||
                    priv.hasPrivilege('PERMISSION_READ') ||
                    priv.hasPrivilege('ROLES_READ') ||
                    priv.hasPrivilege('ROLE_READ')) {
                  items.add(_buildMenuItem(
                    context: context,
                    icon: Icons.admin_panel_settings_outlined,
                    title: 'Roles & Permissions',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const RolesPermissionsScreen()),
                      );
                    },
                  ));
                }

                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 40.0),
                    child: Center(
                      child: Text(
                        'No settings available',
                        style: TextStyle(color: Color(0xFF6B7280), fontSize: 16),
                      ),
                    ),
                  );
                }

                final containerChildren = <Widget>[];
                for (int i = 0; i < items.length; i++) {
                  containerChildren.add(items[i]);
                  if (i < items.length - 1) {
                    containerChildren.add(_buildDivider());
                  }
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('CRM SETTINGS'),
                    _buildSectionContainer(children: containerChildren),
                  ],
                );
              }(),

            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSectionContainer({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderEnabled),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildMenuItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: const Color(0xFF374151), size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(
      height: 1,
      thickness: 1,
      color: AppColors.borderEnabled,
    );
  }
}
