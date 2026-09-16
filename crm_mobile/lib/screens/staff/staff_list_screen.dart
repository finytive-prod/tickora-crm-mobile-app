import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/blocs/staff_bloc.dart';
import 'package:crm_mobile/blocs/staff_event.dart';
import 'package:crm_mobile/blocs/staff_state.dart';
import 'package:crm_mobile/widgets/staff_card.dart';
import 'package:crm_mobile/widgets/spinning_logo.dart';
import 'package:crm_mobile/screens/staff/staff_detail_screen.dart';
import 'package:crm_mobile/screens/staff/add_staff_bottom_sheet.dart';
import 'package:crm_mobile/widgets/empty_state_widget.dart';
import 'package:crm_mobile/widgets/poor_internet_widget.dart';
import 'package:crm_mobile/widgets/server_error_503_widget.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';

class StaffListScreen extends StatelessWidget {
  const StaffListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<StaffBloc>()..add(const FetchStaffMembers()),
      child: const _StaffListView(),
    );
  }
}

class _StaffListView extends StatefulWidget {
  const _StaffListView();

  @override
  State<_StaffListView> createState() => _StaffListViewState();
}


class _StaffListViewState extends State<_StaffListView> {
  String _selectedStatus = 'ACTIVE';
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      context.read<StaffBloc>().add(FetchStaffMembers(status: _selectedStatus, searchQuery: query));
    });
  }

  void _onStatusChanged(String status) {
    setState(() => _selectedStatus = status);
    _searchController.clear();
    context.read<StaffBloc>().add(FetchStaffMembers(status: status));
  }

  Future<void> _navigateToDetail(staff) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StaffDetailScreen(staff: staff)),
    );
    if (result == true && mounted) {
      context.read<StaffBloc>().add(FetchStaffMembers(status: _selectedStatus));
    }
  }

  void _openAddStaffBottomSheet() async {
    final repo = sl<SettingsRepository>();
    final result = await AddStaffBottomSheet.show(context, (data) async {
      final res = await repo.createStaffMember(data);
      return res.fold(
        (failure) => failure.message,
        (member) => null,
      );
    });

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Staff member created successfully!')),
      );
      context.read<StaffBloc>().add(FetchStaffMembers(status: _selectedStatus));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondary,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _selectedStatus == 'ACTIVE' ? 'Staff' : 'Inactive Staff',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textPrimary, size: 22),
            tooltip: 'Refresh Staff',
            onPressed: () {
              context.read<StaffBloc>().add(FetchStaffMembers(status: _selectedStatus, searchQuery: _searchController.text.trim()));
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.textPrimary),
            onSelected: (String status) {
              _onStatusChanged(status);
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: _selectedStatus == 'ACTIVE' ? 'INACTIVE' : 'ACTIVE',
                child: Row(
                  children: [
                    Icon(
                      _selectedStatus == 'ACTIVE' ? Icons.person_off_outlined : Icons.person_outline,
                      size: 20,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _selectedStatus == 'ACTIVE' ? 'Inactive Staff' : 'Active Staff',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddStaffBottomSheet,
        backgroundColor: AppColors.primary,
        elevation: 4,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
      body: BlocListener<StaffBloc, StaffState>(
        listener: (context, state) {
          if (state is StaffCreateSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Staff member created successfully!')),
            );
            context.read<StaffBloc>().add(FetchStaffMembers(status: _selectedStatus));
          } else if (state is StaffCreateError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
        },
        child: Column(
          children: [
          // Summary Cards
          BlocBuilder<StaffBloc, StaffState>(
            builder: (context, state) {
              int activeCount = 0;
              int inactiveCount = 0;
              int totalCount = 0;

              if (state is StaffLoaded) {
                if (state.stats != null) {
                  activeCount = state.stats!.activeMembers;
                  inactiveCount = state.stats!.inactiveMembers;
                  totalCount = state.stats!.totalMembers;
                } else {
                  totalCount = state.staffMembers.length;
                  activeCount = state.staffMembers.where((s) => s.isActive).length;
                  inactiveCount = totalCount - activeCount;
                }
              }

              return Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.borderEnabled),
                ),
                child: Row(
                  children: [
                    _buildSummaryItem(
                      icon: Icons.people,
                      iconColor: AppColors.primary,
                      iconBg: AppColors.primary.withOpacity(0.1),
                      label: 'Active',
                      count: activeCount,
                    ),
                    _buildVerticalDivider(),
                    _buildSummaryItem(
                      icon: Icons.person_off,
                      iconColor: const Color(0xFFEF4444),
                      iconBg: const Color(0xFFEF4444).withOpacity(0.1),
                      label: 'Inactive',
                      count: inactiveCount,
                    ),
                    _buildVerticalDivider(),
                    _buildSummaryItem(
                      icon: Icons.groups,
                      iconColor: const Color(0xFF3B82F6),
                      iconBg: const Color(0xFF3B82F6).withOpacity(0.1),
                      label: 'Total',
                      count: totalCount,
                    ),
                  ],
                ),
              );
            },
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderEnabled),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: const InputDecoration(
                  hintText: 'Search by name...',
                  hintStyle: TextStyle(color: AppColors.textHint, fontSize: 14),
                  prefixIcon: Icon(Icons.search, color: AppColors.textHint),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Staff List
          Expanded(
            child: BlocBuilder<StaffBloc, StaffState>(
              buildWhen: (prev, curr) =>
                  curr is StaffLoading || curr is StaffLoaded || curr is StaffError,
              builder: (context, state) {
                if (state is StaffLoading) {
                  return const Center(child: SpinningLogo(size: 60));
                }
                if (state is StaffError) {
                  final err = state.message;
                  if (err.contains('503') || err.toLowerCase().contains('service unavailable')) {
                    return ServerError503Widget(
                      onRetry: () => context.read<StaffBloc>().add(
                        FetchStaffMembers(status: _selectedStatus),
                      ),
                    );
                  }
                  return PoorInternetWidget(
                    title: 'Connection Issue',
                    message: err.isEmpty ? 'Failed to load staff members. Please try again.' : err,
                    onRetry: () => context.read<StaffBloc>().add(
                      FetchStaffMembers(status: _selectedStatus),
                    ),
                  );
                }
                if (state is StaffLoaded) {
                  final query = state.searchQuery ?? '';
                  final staffMembers = state.staffMembers;

                  if (staffMembers.isEmpty) {
                    return EmptyStateWidget(
                      title: 'No Staff Members Found',
                      message: query.isNotEmpty
                          ? 'No staff members match your search "$query".'
                          : 'No ${_selectedStatus.toLowerCase()} staff members.',
                    );
                  }

                  final itemCount = staffMembers.length + (state.hasMore ? 1 : 0);

                  return RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: () async {
                      context.read<StaffBloc>().add(FetchStaffMembers(status: _selectedStatus, searchQuery: _searchController.text));
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: itemCount,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        if (index < staffMembers.length) {
                          return StaffCard(
                            staff: staffMembers[index],
                            onTap: () => _navigateToDetail(staffMembers[index]),
                          );
                        }

                        // Load more button
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: state.isLoadingMore
                                ? const SpinningLogo(size: 40)
                                : OutlinedButton.icon(
                                    onPressed: () {
                                      context.read<StaffBloc>().add(
                                        LoadMoreStaffMembers(
                                          page: state.currentPage + 1,
                                          status: _selectedStatus,
                                          searchQuery: state.searchQuery,
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.expand_more, color: AppColors.primary),
                                    label: const Text(
                                      'View More',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                        fontSize: 14,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: AppColors.primary, width: 1.5),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                    ),
                                  ),
                          ),
                        );
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

  Widget _buildSummaryItem({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String label,
    required int count,
  }) {
    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 6),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: iconColor,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      width: 1,
      height: 50,
      color: AppColors.borderEnabled,
    );
  }
}
