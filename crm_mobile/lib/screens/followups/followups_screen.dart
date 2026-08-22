import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/widgets/spinning_logo.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/blocs/followups_bloc.dart';
import 'package:crm_mobile/blocs/followups_event.dart';
import 'package:crm_mobile/blocs/followups_state.dart';
import 'package:crm_mobile/models/follow_up.dart';
import 'package:crm_mobile/core/services/privilege_service.dart';
import 'lead_followup_details_screen.dart';
import 'add_followup_screen.dart';

class FollowUpsScreen extends StatelessWidget {
  const FollowUpsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<FollowUpsBloc>()..add(const FetchFollowUps(category: 'ALL')),
      child: const FollowUpsScreenView(),
    );
  }
}

class FollowUpsScreenView extends StatefulWidget {
  const FollowUpsScreenView({super.key});

  @override
  State<FollowUpsScreenView> createState() => _FollowUpsScreenViewState();
}

class _FollowUpsScreenViewState extends State<FollowUpsScreenView> {
  String _selectedTab = 'All';

  int _allCount = 0;
  int _todayCount = 0;
  int _upcomingCount = 0;
  int _missedCount = 0;
  int _completedCount = 0;

  String _getApiCategory(String tab) {
    if (tab == 'Today') return 'TODAY';
    if (tab == 'Upcoming') return 'UPCOMING';
    if (tab == 'Missed') return 'MISSED';
    if (tab == 'Completed') return 'COMPLETED';
    return 'ALL';
  }

  void _onTabChanged(String tabName) {
    setState(() {
      _selectedTab = tabName;
    });
    context.read<FollowUpsBloc>().add(
      FetchFollowUps(category: _getApiCategory(tabName)),
    );
  }

  Color _hexToColor(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) {
      buffer.write('ff');
      buffer.write(hexString.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    }
    return Colors.grey;
  }

  String _formatGroupDate(String dateStr) {
    if (dateStr.isEmpty) return 'NO FOLLOW UP DATE';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      final itemDate = DateTime(date.year, date.month, date.day);
      
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final monthStr = months[date.month - 1].toUpperCase();
      
      if (itemDate == today) {
        return 'TODAY, $monthStr ${date.day}';
      } else if (itemDate == tomorrow) {
        return 'TOMORROW, $monthStr ${date.day}';
      } else {
        return '$monthStr ${date.day}, ${date.year}';
      }
    } catch (_) {
      return dateStr.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondary,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title Header
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Text(
                'Follow-ups',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
            ),

            // Horizontal Tab Chips
            BlocListener<FollowUpsBloc, FollowUpsState>(
              listener: (context, state) {
                if (state is FollowUpsLoaded) {
                  setState(() {
                    _todayCount = state.response.summary.today;
                    _upcomingCount = state.response.summary.upcoming;
                    _missedCount = state.response.summary.missed;
                    _completedCount = state.response.summary.completed;
                    _allCount = _todayCount + _upcomingCount + _missedCount + _completedCount;
                  });
                }
              },
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: Row(
                  children: [
                    _buildTabChip('All', -1),
                    _buildTabChip('Today', _todayCount),
                    _buildTabChip('Upcoming', _upcomingCount),
                    _buildTabChip('Missed', _missedCount),
                    _buildTabChip('Completed', _completedCount),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Content List View
            Expanded(
              child: BlocBuilder<FollowUpsBloc, FollowUpsState>(
                builder: (context, state) {
                  if (state is FollowUpsLoading) {
                    return const Center(child: SpinningLogo(size: 60));
                  } else if (state is FollowUpsError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Text(
                          state.message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.primary, fontSize: 14),
                        ),
                      ),
                    );
                  } else if (state is FollowUpsLoaded) {
                    final followUps = state.response.followUps;
                    if (followUps.isEmpty) {
                      return Center(
                        child: Text(
                          'No $_selectedTab follow-ups.',
                          style: const TextStyle(color: AppColors.textHint, fontSize: 15),
                        ),
                      );
                    }

                    if (_selectedTab == 'Upcoming') {
                      // Group by date
                      final Map<String, List<FollowUp>> grouped = {};
                      for (var item in followUps) {
                        final formattedDate = _formatGroupDate(item.followUpDate);
                        if (!grouped.containsKey(formattedDate)) {
                          grouped[formattedDate] = [];
                        }
                        grouped[formattedDate]!.add(item);
                      }
                      
                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        itemCount: grouped.keys.length,
                        itemBuilder: (context, index) {
                          final dateHeader = grouped.keys.elementAt(index);
                          final groupItems = grouped[dateHeader]!;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                                child: Text(
                                  dateHeader,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textHint,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              ...groupItems.map((item) => _buildFollowUpCard(item)),
                            ],
                          );
                        },
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      itemCount: followUps.length,
                      itemBuilder: (context, index) => _buildFollowUpCard(followUps[index]),
                    );
                  }
                  return const SizedBox();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabChip(String tabName, int count) {
    final isSelected = _selectedTab == tabName;
    final activeBorderColor = const Color(0xFFEF4444);
    final activeTextColor = const Color(0xFFEF4444);
    final inactiveBorderColor = AppColors.borderEnabled;
    final inactiveTextColor = AppColors.textHint;
    
    return GestureDetector(
      onTap: () => _onTabChanged(tabName),
      child: Container(
        margin: const EdgeInsets.only(right: 8.0),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? activeBorderColor : inactiveBorderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tabName,
              style: TextStyle(
                color: isSelected ? activeTextColor : inactiveTextColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            if (count >= 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? activeBorderColor : const Color(0xFFE5E7EB),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFollowUpCard(FollowUp item) {
    final isMissed = _selectedTab == 'Missed';
    final isNoFollowUp = item.followUpStatus.toUpperCase().contains('NO FOLLOW UP');
    
    // Priority badge styling
    Color priorityBgColor = const Color(0xFFF3F4F6);
    Color priorityTextColor = const Color(0xFF4B5563);
    
    final priorityUpper = item.priority.toUpperCase();
    if (priorityUpper == 'HIGH') {
      priorityBgColor = const Color(0xFFFEE2E2);
      priorityTextColor = const Color(0xFFEF4444);
    } else if (priorityUpper == 'MEDIUM') {
      priorityBgColor = const Color(0xFFFEF3C7);
      priorityTextColor = const Color(0xFFD97706);
    } else if (priorityUpper == 'LOW') {
      priorityBgColor = const Color(0xFFD1FAE5);
      priorityTextColor = const Color(0xFF059669);
    }

    final String initials = item.leadName.trim().isNotEmpty
        ? item.leadName.trim().split(' ').map((e) => e[0]).take(2).join('').toUpperCase()
        : 'L';

    // Parse status color or default
    final statusColor = item.leadStatus?.color != null 
        ? _hexToColor(item.leadStatus!.color) 
        : Colors.grey;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LeadFollowUpDetailsScreen(leadId: item.leadId),
          ),
        );
      },
      child: Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isMissed ? Colors.red.withOpacity(0.4) : AppColors.borderEnabled,
            width: isMissed ? 1.2 : 1,
          ),
        ),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Initials Avatar (Status themed)
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: statusColor.withOpacity(0.15),
                    child: Text(
                      initials,
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  // Lead Name & Company Name
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.leadName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                        ),
                        Text(
                          item.companyName.isNotEmpty ? item.companyName : 'No Company',
                          style: const TextStyle(color: AppColors.textHint, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  
                  // Priority Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: priorityBgColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.priority,
                      style: TextStyle(color: priorityTextColor, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // Time / Assigned User row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        isMissed ? Icons.error_outline : Icons.access_time,
                        size: 16,
                        color: isMissed ? Colors.red : AppColors.textHint,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isMissed 
                            ? 'Overdue follow-up'
                            : (item.followUpTime.isNotEmpty ? item.followUpTime : (item.leadStatus?.statusName ?? 'No Date')),
                        style: TextStyle(
                          color: isMissed ? Colors.red : AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: isMissed ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_outline, size: 12, color: Colors.blue.shade700),
                        const SizedBox(width: 4),
                        Text(
                          item.assignedUser?.name ?? 'Unassigned',
                          style: TextStyle(color: Colors.blue.shade700, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Add Follow Up button if NO FOLLOW UP
              if (isNoFollowUp) ...[
                const SizedBox(height: 12),
                const Divider(height: 1, color: AppColors.borderEnabled),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final result = await AddFollowUpScreen.openFromRight(context, leadId: item.leadId);
                      if (result == true && mounted) {
                        context.read<FollowUpsBloc>().add(
                          FetchFollowUps(category: _getApiCategory(_selectedTab)),
                        );
                      }
                    },
                    icon: const Icon(Icons.add, size: 16, color: Colors.white),
                    label: const Text('Add Follow Up', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
              
              // Reschedule button if missed
              if (isMissed && sl<PrivilegeService>().hasPrivilege('FOLLOWUP_UPDATE')) ...[
                const SizedBox(height: 12),
                const Divider(height: 1, color: AppColors.borderEnabled),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Rescheduling is handled in lead details.')),
                      );
                    },
                    icon: const Icon(Icons.calendar_today, size: 16, color: AppColors.textPrimary),
                    label: const Text('Reschedule', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.borderEnabled),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
