import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/lead_card.dart';
import '../../injection/injection.dart';
import '../../features/leads/presentation/bloc/leads_bloc.dart';
import '../../features/leads/presentation/bloc/leads_event.dart';
import '../../features/leads/presentation/bloc/leads_state.dart';

class LeadsScreen extends StatelessWidget {
  const LeadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<LeadsBloc>()
        ..add(FetchLeadStatuses())
        ..add(const FetchLeads()),
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
          builder: (context, state) {
            final statuses = state is LeadsLoaded ? state.statuses : [];
            final selectedStatusId = state is LeadsLoaded ? state.selectedStatusId : null;

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
                      IconButton(
                        icon: const Icon(Icons.filter_alt_outlined, color: AppColors.textPrimary),
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: const Icon(Icons.sort, color: AppColors.textPrimary),
                        onPressed: () {},
                      ),
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
                    child: const TextField(
                      decoration: InputDecoration(
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
                            context.read<LeadsBloc>().add(const FetchLeads());
                          },
                        ),
                        ...statuses.map((status) => _buildFilterChip(
                              status.statusName,
                              isSelected: selectedStatusId == status.id,
                              onTap: () {
                                context.read<LeadsBloc>().add(FetchLeads(statusId: status.id));
                              },
                            )),
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
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        shape: const CircleBorder(),
        onPressed: () {},
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buildLeadsContent(LeadsState state) {
    if (state is LeadsLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    } else if (state is LeadsError) {
      return Center(
        child: Text(
          state.message,
          style: const TextStyle(color: AppColors.primary),
        ),
      );
    } else if (state is LeadsLoaded) {
      if (state.leads.isEmpty) {
        return const Center(child: Text('No leads found.'));
      }
      return ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        itemCount: state.leads.length + 1, // +1 for the FAB padding
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == state.leads.length) {
            return const SizedBox(height: 80); // Padding for FAB
          }
          
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

          return LeadCard(
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
          );
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
