import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/widgets/lead_card.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/blocs/leads_bloc.dart';
import 'package:crm_mobile/blocs/leads_event.dart';
import 'package:crm_mobile/blocs/leads_state.dart';
import 'package:crm_mobile/screens/leads/add_lead_screen.dart';
import 'package:crm_mobile/screens/leads/lead_details_screen.dart';
import 'package:crm_mobile/widgets/expandable_fab.dart';
import 'package:crm_mobile/widgets/spinning_logo.dart';
import 'package:crm_mobile/core/services/privilege_service.dart';

class LeadsScreen extends StatelessWidget {
  const LeadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<LeadsBloc>()
        ..add(FetchLeadStatuses())
        ..add(FetchLeadSources())
        ..add(FetchLeadPriorities())
        ..add(const FetchStaffUsers())
        ..add(const FetchLeads(page: 0, size: 15)),
      child: const LeadsScreenView(),
    );
  }
}

class LeadsScreenView extends StatelessWidget {
  const LeadsScreenView({super.key});

  Color _hexToColor(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) {
      buffer.write('ff');
      buffer.write(hexString.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    }
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondary,
      body: SafeArea(
        child: BlocBuilder<LeadsBloc, LeadsState>(
          buildWhen: (previous, current) =>
              current is LeadsLoaded ||
              current is LeadsLoading ||
              current is LeadsError,
          builder: (context, state) {
            final statuses = state is LeadsLoaded ? state.statuses : [];
            final selectedStatusId = state is LeadsLoaded ? state.selectedStatusId : null;
            final selectedIsActive = state is LeadsLoaded ? state.selectedIsActive : null;

            return Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Row(
                    children: [
                      const Text(
                        'Leads',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      const Spacer(),
                      // IconButton(
                      //   icon: const Icon(Icons.filter_alt_outlined, color: AppColors.textPrimary),
                      //   onPressed: () {},
                      // ),
                      // IconButton(
                      //   icon: const Icon(Icons.sort, color: AppColors.textPrimary),
                      //   onPressed: () {},
                      // ),
                    ],
                  ),
                ),
                // Search Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.borderEnabled),
                    ),
                    child: TextField(
                      onChanged: (query) {
                        final trimmed = query.trim();
                        if (trimmed.isEmpty) {
                          context.read<LeadsBloc>().add(const FetchLeads(page: 0, size: 15));
                        } else {
                          context.read<LeadsBloc>().add(SearchLeads(query: trimmed, page: 0, size: 15));
                        }
                      },
                      decoration: const InputDecoration(
                        hintText: 'Search leads, assignees...',
                        hintStyle: TextStyle(color: AppColors.textHint, fontSize: 14),
                        prefixIcon: Icon(Icons.search, color: AppColors.textHint),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Filter Chips
                if (statuses.isNotEmpty)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      children: [
                        _buildFilterChip(
                          'All Leads',
                          isSelected: selectedStatusId == null,
                          onTap: () {
                            context.read<LeadsBloc>().add(const FetchLeads(page: 0, size: 15));
                          },
                        ),
                        ...statuses.map((status) => _buildFilterChip(
                              status.statusName,
                              isSelected: selectedStatusId == status.id,
                              onTap: () {
                                context.read<LeadsBloc>().add(FetchLeads(page: 0, size: 15, statusId: status.id));
                              },
                            )),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                // Active/Inactive Toggle
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            context.read<LeadsBloc>().add(FetchLeads(page: 0, size: 15, statusId: selectedStatusId, isActive: true));
                          },
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: selectedIsActive == null || selectedIsActive == true ? AppColors.primary : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.primary),
                            ),
                            child: Text('Active', style: TextStyle(color: selectedIsActive == null || selectedIsActive == true ? Colors.white : AppColors.primary, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            context.read<LeadsBloc>().add(FetchLeads(page: 0, size: 15, statusId: selectedStatusId, isActive: false));
                          },
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: selectedIsActive == false ? AppColors.primary : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.primary),
                            ),
                            child: Text('Inactive', style: TextStyle(color: selectedIsActive == false ? Colors.white : AppColors.primary, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Leads List
                Expanded(
                  child: _buildLeadsContent(state),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: sl<PrivilegeService>().hasPrivilege('LEAD_CREATE') 
          ? const ExpandableFab() 
          : null,
    );
  }

  Widget _buildLeadsContent(LeadsState state) {
    if (state is LeadsLoading) {
      return const Center(child: SpinningLogo(size: 60));
    } else if (state is LeadsError) {
      return Center(
        child: Text(
          state.message,
          style: const TextStyle(color: AppColors.primary),
        ),
      );
    } else if (state is LeadsLoaded) {
      if (!state.isLeadsLoaded) {
        return const Center(child: SpinningLogo(size: 60));
      }
      if (state.leads.isEmpty) {
        return const Center(child: Text('No leads found.'));
      }
      final selectedIsActive = state.selectedIsActive;
      final totalItemCount = state.leads.length + (state.hasMoreLeads ? 1 : 0) + 1; // +1 for view more, +1 for FAB

      return ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        itemCount: totalItemCount,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index < state.leads.length) {
            final lead = state.leads[index];
            final String initials = (lead.firstName.isNotEmpty ? lead.firstName[0] : '') +
                                    (lead.lastName.isNotEmpty ? lead.lastName[0] : '');
            final statusColor = lead.status?.color != null 
                ? _hexToColor(lead.status!.color) 
                : Colors.grey;

            Color priorityColor = Colors.grey;
            if (lead.priority == 'HIGH') priorityColor = Colors.red;
            if (lead.priority == 'MEDIUM') priorityColor = Colors.orange;
            if (lead.priority == 'LOW') priorityColor = Colors.green;

            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => LeadDetailsScreen(leadId: lead.id, isActive: selectedIsActive ?? true),
                  ),
                ).then((wasEdited) {
                  if (wasEdited == true) {
                    final currentState = context.read<LeadsBloc>().state;
                    final currentStatusId = currentState is LeadsLoaded ? currentState.selectedStatusId : null;
                    final currentIsActive = currentState is LeadsLoaded ? currentState.selectedIsActive : null;
                    final searchQuery = currentState is LeadsLoaded ? currentState.searchQuery : null;
                    
                    if (searchQuery != null && searchQuery.isNotEmpty) {
                      context.read<LeadsBloc>().add(SearchLeads(query: searchQuery, page: 0, size: 15));
                    } else {
                      context.read<LeadsBloc>().add(FetchLeads(page: 0, size: 15, statusId: currentStatusId, isActive: currentIsActive));
                    }
                  }
                });
              },
              child: LeadCard(
                leadId: lead.id,
                initials: initials.toUpperCase(),
                avatarColor: statusColor.withOpacity(0.2),
                avatarTextColor: statusColor,
                name: '${lead.firstName} ${lead.lastName}',
                company: lead.companyName,
                status: lead.status?.statusName ?? 'Unknown',
                statusBgColor: statusColor.withOpacity(0.2),
                statusTextColor: statusColor,
                description: lead.source?.description ?? 'No description available.',
                priority: lead.priority != null ? '${lead.priority} Priority' : 'No Priority',
                priorityColor: priorityColor,
                assignee: (lead.ownerUserName != null && lead.ownerUserName!.isNotEmpty) 
                    ? lead.ownerUserName! 
                    : 'Unassigned',
                phone: lead.phone,
              ),
            );
          }

          if (index == state.leads.length && state.hasMoreLeads) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: Center(
                child: state.isLoadingMore
                    ? const SpinningLogo(size: 40)
                    : OutlinedButton.icon(
                        onPressed: () {
                          context.read<LeadsBloc>().add(
                            FetchLeads(
                              page: state.currentPage + 1,
                              size: 15,
                              statusId: state.selectedStatusId,
                              isActive: state.selectedIsActive,
                              isLoadMore: true,
                            ),
                          );
                        },
                        icon: const Icon(Icons.expand_more, color: AppColors.primary),
                        label: const Text(
                          'View More',
                          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 14),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.primary, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
              ),
            );
          }

          return const SizedBox(height: 80); // Padding for FAB
        },
      );
    }
    return const SizedBox();
  }

  Widget _buildFilterChip(String label, {bool isSelected = false, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.borderEnabled,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textLabel,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
