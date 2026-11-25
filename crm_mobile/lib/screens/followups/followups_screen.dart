import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/widgets/spinning_logo.dart';
import 'package:crm_mobile/widgets/empty_state_widget.dart';
import 'package:crm_mobile/widgets/poor_internet_widget.dart';
import 'package:crm_mobile/widgets/server_error_503_widget.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/blocs/followups_bloc.dart';
import 'package:crm_mobile/blocs/followups_event.dart';
import 'package:crm_mobile/blocs/followups_state.dart';
import 'package:crm_mobile/models/follow_up.dart';
import 'package:crm_mobile/core/services/privilege_service.dart';
import 'package:crm_mobile/core/utils/text_selection_utils.dart';
import 'package:crm_mobile/widgets/call_number_picker_sheet.dart';
import 'lead_followup_details_screen.dart';
import 'add_followup_screen.dart';

class FollowUpsScreen extends StatelessWidget {
  const FollowUpsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<FollowUpsBloc>()..add(const FetchFollowUps(category: 'TODAY')),
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
  String _selectedTab = 'Today';
  final TextEditingController _searchController = TextEditingController();

  int _todayCount = 0;
  int _upcomingCount = 0;
  int _missedCount = 0;
  int _completedCount = 0;

  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    if (currentScroll >= maxScroll - 200) {
      final state = context.read<FollowUpsBloc>().state;
      if (state is FollowUpsLoaded && !state.isLoadingMore && !state.response.last) {
        context.read<FollowUpsBloc>().add(
          FetchFollowUps(
            category: _getApiCategory(_selectedTab),
            page: state.response.number + 1,
            isLoadMore: true,
            searchQuery: _searchController.text.trim(),
          ),
        );
      }
    }
  }

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
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    context.read<FollowUpsBloc>().add(
      FetchFollowUps(
        category: _getApiCategory(tabName),
        page: 0,
        searchQuery: _searchController.text.trim(),
      ),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Follow-ups',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: AppColors.textPrimary),
                    tooltip: 'Refresh Follow-ups',
                    onPressed: () {
                      context.read<FollowUpsBloc>().add(
                        FetchFollowUps(
                          category: _getApiCategory(_selectedTab),
                          page: 0,
                          searchQuery: _searchController.text.trim(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderEnabled),
                ),
                child: TextField(
                  controller: _searchController,
                  enableInteractiveSelection: true,
                  selectionControls: MaterialTextSelectionControls(),
                  contextMenuBuilder: buildAdaptiveContextMenu,
                  onChanged: (query) {
                    setState(() {});
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
                      if (!mounted) return;
                      context.read<FollowUpsBloc>().add(
                        FetchFollowUps(
                          category: _getApiCategory(_selectedTab),
                          page: 0,
                          searchQuery: query.trim(),
                        ),
                      );
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search follow-ups...',
                    hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 14),
                    prefixIcon: const Icon(Icons.search, color: AppColors.textHint),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: AppColors.textHint, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                              context.read<FollowUpsBloc>().add(
                                FetchFollowUps(
                                  category: _getApiCategory(_selectedTab),
                                  page: 0,
                                  searchQuery: '',
                                ),
                              );
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Horizontal Tab Chips
            BlocListener<FollowUpsBloc, FollowUpsState>(
              listener: (context, state) {
                if (state is FollowUpsLoaded) {
                  setState(() {
                    if (_searchController.text.trim().isEmpty) {
                      final summary = state.response.summary;
                      final total = state.response.totalElements;

                      if (_selectedTab == 'Today') {
                        _todayCount = total;
                      } else if (summary.today > 0 || _todayCount == 0) {
                        _todayCount = summary.today;
                      }

                      if (_selectedTab == 'Upcoming') {
                        _upcomingCount = total;
                      } else if (summary.upcoming > 0 || _upcomingCount == 0) {
                        _upcomingCount = summary.upcoming;
                      }

                      if (_selectedTab == 'Missed') {
                        _missedCount = total;
                      } else if (summary.missed > 0 || _missedCount == 0) {
                        _missedCount = summary.missed;
                      }

                      if (_selectedTab == 'Completed') {
                        _completedCount = total;
                      } else if (summary.completed > 0 || _completedCount == 0) {
                        _completedCount = summary.completed;
                      }
                    }
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
                    if (state.message.contains('503') || state.message.contains('Service Unavailable')) {
                      return ServerError503Widget(
                        onRetry: () => context.read<FollowUpsBloc>().add(
                          FetchFollowUps(category: _getApiCategory(_selectedTab), page: 0, isRefresh: true),
                        ),
                      );
                    } else if (state.message.toLowerCase().contains('internet') ||
                        state.message.toLowerCase().contains('connection') ||
                        state.message.toLowerCase().contains('timed out')) {
                      return PoorInternetWidget(
                        onRetry: () => context.read<FollowUpsBloc>().add(
                          FetchFollowUps(category: _getApiCategory(_selectedTab), page: 0, isRefresh: true),
                        ),
                      );
                    }
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
                      return RefreshIndicator(
                        onRefresh: () async {
                          context.read<FollowUpsBloc>().add(
                            FetchFollowUps(
                              category: _getApiCategory(_selectedTab),
                              page: 0,
                              isRefresh: true,
                              searchQuery: _searchController.text.trim(),
                            ),
                          );
                        },
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(height: MediaQuery.of(context).size.height * 0.1),
                            EmptyStateWidget(
                              title: 'No $_selectedTab Follow-ups',
                              message: _searchController.text.isNotEmpty
                                  ? 'No follow-ups match "${_searchController.text}"'
                                  : 'There are no $_selectedTab follow-ups at the moment.',
                            ),
                          ],
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
                      
                      return RefreshIndicator(
                        onRefresh: () async {
                          context.read<FollowUpsBloc>().add(
                            FetchFollowUps(
                              category: _getApiCategory(_selectedTab),
                              page: 0,
                              isRefresh: true,
                              searchQuery: _searchController.text.trim(),
                            ),
                          );
                        },
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          itemCount: grouped.keys.length + (state.isLoadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= grouped.keys.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16.0),
                                child: Center(child: SpinningLogo(size: 36)),
                              );
                            }
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
                        ),
                      );
                    }

                    return RefreshIndicator(
                      onRefresh: () async {
                        context.read<FollowUpsBloc>().add(
                          FetchFollowUps(
                            category: _getApiCategory(_selectedTab),
                            page: 0,
                            isRefresh: true,
                            searchQuery: _searchController.text.trim(),
                          ),
                        );
                      },
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        itemCount: followUps.length + (state.isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= followUps.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16.0),
                              child: Center(child: SpinningLogo(size: 36)),
                            );
                          }
                          return _buildFollowUpCard(followUps[index]);
                        },
                      ),
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

  String _formatBadgeCount(int count) {
    if (count < 0) return '';
    if (count > 999) return '999+';
    return '$count';
  }

  Widget _buildTabChip(String tabName, int count) {
    final isSelected = _selectedTab == tabName;
    final activeBorderColor = AppColors.primary;
    final activeTextColor = AppColors.primary;
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
                constraints: const BoxConstraints(minWidth: 18),
                decoration: BoxDecoration(
                  color: isSelected ? activeBorderColor : const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  _formatBadgeCount(count),
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
      priorityBgColor = AppColors.secondary;
      priorityTextColor = AppColors.primary;
    } else if (priorityUpper == 'MEDIUM') {
      priorityBgColor = const Color(0xFFFEF3C7);
      priorityTextColor = const Color(0xFFD97706);
    } else if (priorityUpper == 'LOW') {
      priorityBgColor = const Color(0xFFD1FAE5);
      priorityTextColor = const Color(0xFF059669);
    }

    final parts = item.leadName.trim().split(' ').where((e) => e.trim().isNotEmpty).toList();
    final String initials = parts.isNotEmpty
        ? parts.map((e) => e[0]).take(2).join('').toUpperCase()
        : 'L';

    // Parse status color or default
    final statusColor = item.leadStatus?.color != null 
        ? _hexToColor(item.leadStatus!.color) 
        : Colors.grey;

    final rawPrimaryPhone = (item.phoneNumber ?? '').trim();
    final rawAltPhone = (item.alternatePhone ?? '').trim();
    final phoneStr = rawPrimaryPhone.isNotEmpty && rawPrimaryPhone != '-'
        ? rawPrimaryPhone
        : rawAltPhone;
    final hasPhone = phoneStr.isNotEmpty && phoneStr != '-';

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
            color: isMissed ? AppColors.primary.withOpacity(0.4) : AppColors.borderEnabled,
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
                crossAxisAlignment: CrossAxisAlignment.center,
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
                          item.leadName.isNotEmpty ? item.leadName : 'Unnamed Lead',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (item.companyName.trim().isNotEmpty)
                          Text(
                            item.companyName,
                            style: const TextStyle(color: AppColors.textHint, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  
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
              const Divider(height: 1, color: AppColors.borderEnabled),
              const SizedBox(height: 10),

              // Phone Number Row (Below line with copy option and call button)
              if (hasPhone) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: phoneStr));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                                const SizedBox(width: 8),
                                Text('Phone number copied ($phoneStr)'),
                              ],
                            ),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.phone_iphone, size: 16, color: AppColors.textSecondary),
                            const SizedBox(width: 6),
                            Text(
                              phoneStr,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.copy_rounded, size: 14, color: AppColors.textHint),
                          ],
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () async {
                        await LeadCallHelper.initiateLeadCall(
                          context: context,
                          leadId: item.leadId,
                          primaryPhone: rawPrimaryPhone,
                          alternatePhone: item.alternatePhone,
                          leadName: item.leadName,
                        );
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.phone,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              
              // Time / Assigned User row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        isMissed ? Icons.error_outline : Icons.access_time,
                        size: 16,
                        color: isMissed ? AppColors.primary : AppColors.textHint,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isMissed 
                            ? 'Overdue follow-up'
                            : (item.followUpTime.isNotEmpty ? item.followUpTime : (item.leadStatus?.statusName ?? 'No Date')),
                        style: TextStyle(
                          color: isMissed ? AppColors.primary : AppColors.textPrimary,
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
