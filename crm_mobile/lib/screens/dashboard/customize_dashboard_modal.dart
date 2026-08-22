import 'package:flutter/material.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/repositories/dashboard_repository.dart';

class CustomizeDashboardModal extends StatefulWidget {
  final List<String> currentWidgets;

  const CustomizeDashboardModal({super.key, required this.currentWidgets});

  static Future<List<String>?> show(BuildContext context, List<String> currentWidgets) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CustomizeDashboardModal(currentWidgets: currentWidgets),
    );
  }

  @override
  State<CustomizeDashboardModal> createState() => _CustomizeDashboardModalState();
}

class _CustomizeDashboardModalState extends State<CustomizeDashboardModal> {
  late Set<String> _selectedKeys;

  @override
  void initState() {
    super.initState();
    _selectedKeys = Set<String>.from(widget.currentWidgets);
  }

  void _toggleKey(String key) {
    setState(() {
      if (_selectedKeys.contains(key)) {
        _selectedKeys.remove(key);
      } else {
        _selectedKeys.add(key);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedKeys = Set<String>.from(DashboardWidgetKeys.allKeys);
    });
  }

  void _deselectAll() {
    setState(() {
      _selectedKeys.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.tune_rounded, color: AppColors.primary, size: 22),
                const SizedBox(width: 10),
                const Text(
                  'Customize Dashboard',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textHint),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.borderEnabled),

          // Select All / Deselect All Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_selectedKeys.length} of ${DashboardWidgetKeys.allKeys.length} visible',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: _selectAll,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(60, 30)),
                      child: const Text('Select All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _deselectAll,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(60, 30)),
                      child: const Text('Clear All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textHint)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.borderEnabled),

          // Scrollable Checkbox List Grouped
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _buildSectionHeader('KPI Metric Cards'),
                _buildWidgetTile(DashboardWidgetKeys.totalLeads, Icons.people_alt_outlined),
                _buildWidgetTile(DashboardWidgetKeys.newLeadsToday, Icons.person_add_alt_1_outlined),
                _buildWidgetTile(DashboardWidgetKeys.qualifiedLeads, Icons.verified_user_outlined),
                _buildWidgetTile(DashboardWidgetKeys.lostLeads, Icons.cancel_outlined),
                _buildWidgetTile(DashboardWidgetKeys.todaysFollowups, Icons.access_time_outlined),
                _buildWidgetTile(DashboardWidgetKeys.overdueFollowups, Icons.warning_amber_rounded),
                _buildWidgetTile(DashboardWidgetKeys.revenueThisMonth, Icons.currency_rupee),
                _buildWidgetTile(DashboardWidgetKeys.conversionRate, Icons.trending_up),

                const SizedBox(height: 16),
                _buildSectionHeader('Analytics & Charts'),
                _buildWidgetTile(DashboardWidgetKeys.leadTrendAnalysis, Icons.show_chart),
                _buildWidgetTile(DashboardWidgetKeys.salesPipeline, Icons.filter_alt_outlined),
                _buildWidgetTile(DashboardWidgetKeys.leadStatusDistribution, Icons.pie_chart_outline),
                _buildWidgetTile(DashboardWidgetKeys.leadSourceDistribution, Icons.share_outlined),
                _buildWidgetTile(DashboardWidgetKeys.monthlyRevenueTarget, Icons.account_balance_wallet_outlined),

                const SizedBox(height: 16),
                _buildSectionHeader('Lists & Timelines'),
                _buildWidgetTile(DashboardWidgetKeys.upcomingFollowups, Icons.access_time_filled_outlined),
                _buildWidgetTile(DashboardWidgetKeys.recentActivities, Icons.history_outlined),
                _buildWidgetTile(DashboardWidgetKeys.recentLeads, Icons.person_add_outlined),
              ],
            ),
          ),

          // Bottom Action Buttons
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppColors.borderEnabled)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppColors.borderEnabled),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, _selectedKeys.toList()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text(
                      'Save Preferences',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 8, bottom: 6),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: AppColors.textHint,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildWidgetTile(String key, IconData icon) {
    final title = DashboardWidgetKeys.keyTitles[key] ?? key;
    final isChecked = _selectedKeys.contains(key);

    return CheckboxListTile(
      value: isChecked,
      onChanged: (_) => _toggleKey(key),
      activeColor: AppColors.primary,
      secondary: Icon(icon, size: 20, color: isChecked ? AppColors.primary : AppColors.textHint),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isChecked ? FontWeight.bold : FontWeight.normal,
          color: AppColors.textPrimary,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      dense: true,
      visualDensity: VisualDensity.compact,
    );
  }
}
