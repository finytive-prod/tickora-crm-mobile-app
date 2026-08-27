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
              
              if (sl<PrivilegeService>().hasPrivilege('SETTINGS_READ')) ...[
                _buildSectionTitle('CRM SETTINGS'),
                _buildSectionContainer(
                children: [
                  _buildMenuItem(
                    context: context,
                    icon: Icons.list_alt_rounded,
                    title: 'Lead Custom Form',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const LeadCustomFormScreen()),
                      );
                    },
                  ),
                  _buildDivider(),
                  _buildMenuItem(
                    context: context,
                    icon: Icons.settings_outlined,
                    title: 'Lead Status',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const LeadStatusesScreen()),
                      );
                    },
                  ),
                  _buildDivider(),
                  _buildMenuItem(
                    context: context,
                    icon: Icons.show_chart_outlined,
                    title: 'Pipeline Stages',
                    onTap: () => _showComingSoon(context, 'Pipeline Stages'),
                  ),
                  _buildDivider(),
                  _buildMenuItem(
                    context: context,
                    icon: Icons.people_alt_outlined,
                    title: 'Lead Sources',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const LeadSourcesScreen()),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ],

              if (sl<PrivilegeService>().hasPrivilege('ROLE_READ') || sl<PrivilegeService>().hasPrivilege('PERMISSION_READ')) ...[
                _buildSectionTitle('TEAM MANAGEMENT'),
                _buildSectionContainer(
                children: [
                 
                  _buildDivider(),
                  _buildMenuItem(
                    context: context,
                    icon: Icons.admin_panel_settings_outlined,
                    title: 'Roles & Permissions',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const RolesPermissionsScreen()),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ],
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

  void _showComingSoon(BuildContext context, String pageName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$pageName coming soon.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
