import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/widgets/lead_card.dart';
import 'package:crm_mobile/widgets/empty_state_widget.dart';
import 'package:crm_mobile/widgets/poor_internet_widget.dart';
import 'package:crm_mobile/widgets/server_error_503_widget.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/blocs/leads_bloc.dart';
import 'package:crm_mobile/blocs/leads_event.dart';
import 'package:crm_mobile/blocs/leads_state.dart';
import 'package:crm_mobile/screens/leads/lead_details_screen.dart';
import 'package:crm_mobile/widgets/expandable_fab.dart';
import 'package:crm_mobile/widgets/spinning_logo.dart';
import 'package:crm_mobile/models/lead.dart';
import 'package:crm_mobile/models/staff_user.dart';
import 'package:crm_mobile/core/utils/text_selection_utils.dart';

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
        ..add(const FetchLeads(page: 0, size: 15, isActive: true)),
      child: const LeadsScreenView(),
    );
  }
}

class LeadsScreenView extends StatefulWidget {
  const LeadsScreenView({super.key});

  @override
  State<LeadsScreenView> createState() => _LeadsScreenViewState();
}

class _LeadsScreenViewState extends State<LeadsScreenView> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll - currentScroll <= 200) {
      final bloc = context.read<LeadsBloc>();
      final state = bloc.state;
      if (state is LeadsLoaded && state.hasMoreLeads && !state.isLoadingMore) {
        final searchQuery = state.searchQuery;
        if (searchQuery != null && searchQuery.isNotEmpty) {
          bloc.add(SearchLeads(
            query: searchQuery,
            page: state.currentPage + 1,
            size: 15,
            isLoadMore: true,
          ));
        } else {
          bloc.add(FetchLeads(
            page: state.currentPage + 1,
            size: 15,
            statusId: state.selectedStatusId,
            isActive: state.selectedIsActive,
            isLoadMore: true,
          ));
        }
      }
    }
  }

  String _sanitizeSearchQuery(String query) {
    String cleaned = query.trim();
    if (cleaned.isEmpty) return cleaned;

    // If query starts with '+' (e.g. +91 7878788787, +917878788787, +1-800-555)
    if (cleaned.startsWith('+')) {
      final countryCodeRegExp = RegExp(r'^\+\d{1,3}[\s\-]*');
      cleaned = cleaned.replaceFirst(countryCodeRegExp, '');
    } else {
      final digitsOnly = cleaned.replaceAll(RegExp(r'[^\d]'), '');
      // Handle 91XXXXXXXXXX (12 digits starting with 91)
      if (digitsOnly.length == 12 && digitsOnly.startsWith('91')) {
        cleaned = digitsOnly.substring(2);
      }
      // Handle 0XXXXXXXXXX (11 digits starting with 0)
      else if (digitsOnly.length == 11 && digitsOnly.startsWith('0')) {
        cleaned = digitsOnly.substring(1);
      }
    }

    // If after stripping prefix, query consists of digits and spaces/dashes (e.g., 98765 43210), format as clean digits
    final digits = cleaned.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length >= 7 && cleaned.replaceAll(RegExp(r'[\d\s\-]'), '').isEmpty) {
      cleaned = digits;
    }

    return cleaned;
  }

  void _onSearchChanged(String input, String? selectedStatusId, bool? selectedIsActive) {
    final sanitized = _sanitizeSearchQuery(input);
    if (sanitized != input) {
      _searchController.value = TextEditingValue(
        text: sanitized,
        selection: TextSelection.collapsed(offset: sanitized.length),
      );
    }

    if (sanitized.isEmpty) {
      context.read<LeadsBloc>().add(
        FetchLeads(
          page: 0,
          size: 15,
          statusId: selectedStatusId,
          isActive: selectedIsActive ?? true,
        ),
      );
    } else {
      context.read<LeadsBloc>().add(
        SearchLeads(query: sanitized, page: 0, size: 15),
      );
    }
  }

  String _resolveAssigneeName(Lead lead, List<dynamic> owners) {
    if (lead.ownerUserName != null && lead.ownerUserName!.trim().isNotEmpty) {
      final name = lead.ownerUserName!.trim();
      final isUuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(name);
      if (!isUuid) {
        return name;
      }
      for (final staff in owners) {
        if (staff is StaffUser && staff.userId == name) {
          return staff.name;
        }
      }
    }

    if (lead.ownerUserId != null && lead.ownerUserId!.trim().isNotEmpty) {
      final id = lead.ownerUserId!.trim();
      for (final staff in owners) {
        if (staff is StaffUser && staff.userId == id) {
          return staff.name;
        }
      }
    }

    final candidateIds = [
      if (lead.ownerUserId != null) lead.ownerUserId!.trim(),
      if (lead.ownerUserName != null) lead.ownerUserName!.trim(),
    ];

    for (final candidate in candidateIds) {
      if (candidate.isEmpty) continue;
      for (final staff in owners) {
        if (staff is StaffUser) {
          if (staff.userId.toLowerCase() == candidate.toLowerCase() ||
              staff.name.toLowerCase() == candidate.toLowerCase()) {
            return staff.name;
          }
        }
      }
    }

    return 'Unassigned';
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
                      Text(
                        selectedIsActive == false ? 'Inactive Leads' : 'Leads',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: AppColors.textPrimary),
                        tooltip: 'Refresh Leads',
                        onPressed: () {
                          context.read<LeadsBloc>().add(
                            FetchLeads(page: 0, size: 15, statusId: selectedStatusId, isActive: selectedIsActive ?? true),
                          );
                        },
                      ),
                      PopupMenuButton<bool>(
                        icon: const Icon(Icons.more_vert, color: AppColors.textPrimary),
                        onSelected: (bool showActive) {
                          context.read<LeadsBloc>().add(
                            FetchLeads(page: 0, size: 15, statusId: selectedStatusId, isActive: showActive),
                          );
                        },
                        itemBuilder: (BuildContext context) => <PopupMenuEntry<bool>>[
                          PopupMenuItem<bool>(
                            value: selectedIsActive == false ? true : false,
                            child: Row(
                              children: [
                                Icon(
                                  selectedIsActive == false ? Icons.check_circle_outline : Icons.pause_circle_outline,
                                  size: 20,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  selectedIsActive == false ? 'Active Leads' : 'Inactive Leads',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ],
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
                    child: TextField(
                      controller: _searchController,
                      enableInteractiveSelection: true,
                      selectionControls: MaterialTextSelectionControls(),
                      contextMenuBuilder: buildAdaptiveContextMenu,
                      onChanged: (query) => _onSearchChanged(query, selectedStatusId, selectedIsActive),
                      decoration: InputDecoration(
                        hintText: 'Search leads, assignees...',
                        hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 14),
                        prefixIcon: const Icon(Icons.search, color: AppColors.textHint),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: AppColors.textHint, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  _onSearchChanged('', selectedStatusId, selectedIsActive);
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
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
                            context.read<LeadsBloc>().add(FetchLeads(page: 0, size: 15, isActive: selectedIsActive ?? true));
                          },
                        ),
                        ...statuses.map((status) => _buildFilterChip(
                              status.statusName,
                              isSelected: selectedStatusId == status.id,
                              onTap: () {
                                context.read<LeadsBloc>().add(FetchLeads(page: 0, size: 15, statusId: status.id, isActive: selectedIsActive ?? true));
                              },
                            )),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                // Leads List
                Expanded(
                  child: _buildLeadsContent(context, state),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: const ExpandableFab(),
    );
  }

  Widget _buildLeadsContent(BuildContext context, LeadsState state) {
    if (state is LeadsLoading) {
      return const Center(child: SpinningLogo(size: 60));
    } else if (state is LeadsError) {
      if (state.message.contains('503') || state.message.contains('Service Unavailable')) {
        return ServerError503Widget(
          onRetry: () => context.read<LeadsBloc>().add(
            const FetchLeads(page: 0, size: 15),
          ),
        );
      } else if (state.message.toLowerCase().contains('internet') ||
          state.message.toLowerCase().contains('connection') ||
          state.message.toLowerCase().contains('timed out')) {
        return PoorInternetWidget(
          onRetry: () => context.read<LeadsBloc>().add(
            const FetchLeads(page: 0, size: 15),
          ),
        );
      }
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
        return EmptyStateWidget(
          title: 'No Leads Found',
          message: state.searchQuery != null && state.searchQuery!.isNotEmpty
              ? 'No leads match "${state.searchQuery}"'
              : 'There are no leads matching your filter.',
        );
      }
      final selectedIsActive = state.selectedIsActive;
      final bool showLoader = state.hasMoreLeads || state.isLoadingMore;
      final totalItemCount = state.leads.length + (showLoader ? 1 : 0) + 1; // +1 for loader, +1 for FAB

      return ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        itemCount: totalItemCount,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
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
              onTap: () async {
                final wasEdited = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => LeadDetailsScreen(leadId: lead.id, isActive: selectedIsActive ?? true),
                  ),
                );
                if (wasEdited == true && context.mounted) {
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
              },
              child: LeadCard(
                leadId: lead.id,
                initials: initials.toUpperCase(),
                avatarColor: statusColor.withValues(alpha: 0.2),
                avatarTextColor: statusColor,
                name: '${lead.firstName} ${lead.lastName}',
                company: lead.companyName,
                status: lead.status?.statusName ?? 'Unknown',
                statusBgColor: statusColor.withValues(alpha: 0.2),
                statusTextColor: statusColor,
                priority: lead.priority != null ? '${lead.priority} Priority' : 'No Priority',
                priorityColor: priorityColor,
                createdByName: lead.createdByName,
                assignee: _resolveAssigneeName(lead, state.owners),
                phone: lead.phone,
              ),
            );
          }

          if (showLoader && index == state.leads.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16.0),
              child: Center(
                child: SpinningLogo(size: 36),
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
