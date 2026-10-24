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
import 'package:crm_mobile/screens/leads/widgets/lead_filter_side_sheet.dart';
import 'package:crm_mobile/widgets/expandable_fab.dart';
import 'package:crm_mobile/widgets/spinning_logo.dart';
import 'package:crm_mobile/models/lead.dart';
import 'package:crm_mobile/models/staff_user.dart';
import 'package:crm_mobile/models/lead_filter_params.dart';
import 'package:crm_mobile/core/utils/text_selection_utils.dart';
import 'package:crm_mobile/core/utils/phone_number_utils.dart';
import 'package:crm_mobile/core/services/auto_call_recording_uploader.dart';

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

class _LeadsScreenViewState extends State<LeadsScreenView>
    with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerAutoSync();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _triggerAutoSync();
    }
  }

  void _triggerAutoSync() {
    if (!mounted) return;
    final state = context.read<LeadsBloc>().state;
    final currentLeads = state is LeadsLoaded ? state.leads : null;
    AutoCallRecordingUploader.syncRecentCallsIfAvailable(
      knownLeads: currentLeads,
      onUploadSuccess: () {
        _refreshLeadsList();
      },
    );
  }

  void _refreshLeadsList() {
    if (!mounted) return;
    final bloc = context.read<LeadsBloc>();
    final state = bloc.state;
    if (state is LeadsLoaded) {
      bloc.add(
        FetchLeads(
          page: 0,
          size: 15,
          statusId: state.selectedStatusId,
          isActive: state.selectedIsActive ?? true,
          filterParams: state.filterParams,
          searchQuery: _searchController.text.isNotEmpty
              ? sanitizeLeadSearchQuery(_searchController.text)
              : null,
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll > 0 &&
        currentScroll > 0 &&
        (maxScroll - currentScroll <= 200)) {
      final bloc = context.read<LeadsBloc>();
      final state = bloc.state;
      if (state is LeadsLoaded && state.hasMoreLeads && !state.isLoadingMore) {
        final searchQuery = state.searchQuery;
        final filterParams = state.filterParams;
        bloc.add(
          FetchLeads(
            page: state.currentPage + 1,
            size: 15,
            statusId: state.selectedStatusId,
            isActive: state.selectedIsActive,
            isLoadMore: true,
            filterParams: filterParams,
            searchQuery: searchQuery,
          ),
        );
      }
    }
  }

  void _onSearchChanged(
    String input,
    String? selectedStatusId,
    bool? selectedIsActive,
    LeadFilterParams? filterParams,
  ) {
    final sanitized = sanitizeLeadSearchQuery(input);
    if (sanitized != input) {
      _searchController.value = TextEditingValue(
        text: sanitized,
        selection: TextSelection.collapsed(offset: sanitized.length),
      );
    }

    final query = sanitized.trim();
    context.read<LeadsBloc>().add(
      FetchLeads(
        page: 0,
        size: 15,
        statusId: selectedStatusId,
        isActive: selectedIsActive ?? true,
        filterParams: filterParams,
        searchQuery: query.isNotEmpty ? query : null,
      ),
    );
  }

  String _resolveAssigneeName(Lead lead, List<dynamic> owners) {
    if (lead.ownerUserName != null && lead.ownerUserName!.trim().isNotEmpty) {
      final name = lead.ownerUserName!.trim();
      final isUuid = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(name);
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
            final selectedStatusId = state is LeadsLoaded
                ? state.selectedStatusId
                : null;
            final selectedIsActive = state is LeadsLoaded
                ? state.selectedIsActive
                : null;
            final activeFilter = state is LeadsLoaded
                ? state.filterParams
                : null;

            return Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 12.0,
                  ),
                  child: Row(
                    children: [
                      Text(
                        selectedIsActive == false ? 'Inactive Leads' : 'Leads',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(
                          Icons.refresh,
                          color: AppColors.textPrimary,
                        ),
                        tooltip: 'Refresh Leads',
                        onPressed: () {
                          context.read<LeadsBloc>().add(
                            FetchLeads(
                              page: 0,
                              size: 15,
                              statusId: selectedStatusId,
                              isActive: selectedIsActive ?? true,
                              filterParams: activeFilter,
                              searchQuery: _searchController.text.isNotEmpty
                                  ? sanitizeLeadSearchQuery(
                                      _searchController.text,
                                    )
                                  : null,
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              color:
                                  (activeFilter != null &&
                                      activeFilter.hasActiveFilters)
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                            ),
                            if (activeFilter != null &&
                                activeFilter.hasActiveFilters)
                              Positioned(
                                right: -2,
                                top: -2,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 8,
                                    minHeight: 8,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        tooltip: 'Filter Leads',
                        onPressed: () async {
                          final currentFilter =
                              activeFilter ?? const LeadFilterParams();
                          final currentStatuses = state is LeadsLoaded
                              ? state.statuses
                              : <LeadStatus>[];
                          final currentSources = state is LeadsLoaded
                              ? state.sources
                              : <LeadSource>[];
                          final currentPriorities = state is LeadsLoaded
                              ? state.priorities
                              : <String>[];
                          final currentOwners = state is LeadsLoaded
                              ? state.owners
                              : <StaffUser>[];

                          final newFilter = await LeadFilterSideSheet.show(
                            context,
                            currentFilter: currentFilter,
                            statuses: currentStatuses,
                            sources: currentSources,
                            priorities: currentPriorities,
                            owners: currentOwners,
                          );

                          if (newFilter != null && context.mounted) {
                            context.read<LeadsBloc>().add(
                              FetchLeads(
                                page: 0,
                                size: 15,
                                statusId: selectedStatusId,
                                isActive: selectedIsActive ?? true,
                                filterParams: newFilter,
                                searchQuery: _searchController.text.isNotEmpty
                                    ? sanitizeLeadSearchQuery(
                                        _searchController.text,
                                      )
                                    : null,
                              ),
                            );
                          }
                        },
                      ),
                      PopupMenuButton<bool>(
                        icon: const Icon(
                          Icons.more_vert,
                          color: AppColors.textPrimary,
                        ),
                        onSelected: (bool showActive) {
                          context.read<LeadsBloc>().add(
                            FetchLeads(
                              page: 0,
                              size: 15,
                              statusId: selectedStatusId,
                              isActive: showActive,
                              filterParams: activeFilter,
                              searchQuery: _searchController.text.isNotEmpty
                                  ? sanitizeLeadSearchQuery(
                                      _searchController.text,
                                    )
                                  : null,
                            ),
                          );
                        },
                        itemBuilder: (BuildContext context) =>
                            <PopupMenuEntry<bool>>[
                              PopupMenuItem<bool>(
                                value: selectedIsActive == false ? true : false,
                                child: Row(
                                  children: [
                                    Icon(
                                      selectedIsActive == false
                                          ? Icons.check_circle_outline
                                          : Icons.pause_circle_outline,
                                      size: 20,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      selectedIsActive == false
                                          ? 'Active Leads'
                                          : 'Inactive Leads',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
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
                      onChanged: (query) => _onSearchChanged(
                        query,
                        selectedStatusId,
                        selectedIsActive,
                        activeFilter,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search Leads',
                        hintStyle: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: AppColors.textHint,
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                  Icons.clear,
                                  color: AppColors.textHint,
                                  size: 18,
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                  _onSearchChanged(
                                    '',
                                    selectedStatusId,
                                    selectedIsActive,
                                    activeFilter,
                                  );
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
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
                            context.read<LeadsBloc>().add(
                              FetchLeads(
                                page: 0,
                                size: 15,
                                isActive: selectedIsActive ?? true,
                              ),
                            );
                          },
                        ),
                        ...statuses.map(
                          (status) => _buildFilterChip(
                            status.statusName,
                            isSelected: selectedStatusId == status.id,
                            onTap: () {
                              context.read<LeadsBloc>().add(
                                FetchLeads(
                                  page: 0,
                                  size: 15,
                                  statusId: status.id,
                                  isActive: selectedIsActive ?? true,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                // Leads List
                Expanded(child: _buildLeadsContent(context, state)),
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
      if (state.message.contains('503') ||
          state.message.contains('Service Unavailable')) {
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
      final totalItemCount =
          state.leads.length +
          (showLoader ? 1 : 0) +
          1; // +1 for loader, +1 for FAB

      return ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        itemCount: totalItemCount,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index < state.leads.length) {
            final lead = state.leads[index];
            final fullName = '${lead.firstName} ${lead.lastName}'.trim();
            final displayName = fullName.isNotEmpty
                ? fullName
                : (lead.companyName.trim().isNotEmpty
                    ? lead.companyName.trim()
                    : (lead.phone.isNotEmpty ? lead.phone : 'Unnamed Lead'));
            final String initials =
                (lead.firstName.isNotEmpty ? lead.firstName[0] : (displayName.isNotEmpty ? displayName[0] : 'L')) +
                (lead.lastName.isNotEmpty ? lead.lastName[0] : '');
            final statusColor = lead.status?.color != null
                ? _hexToColor(lead.status!.color)
                : Colors.grey;

            Color priorityColor = Colors.grey;
            if (lead.priority == 'HIGH') priorityColor = Colors.red;
            if (lead.priority == 'MEDIUM') priorityColor = Colors.orange;
            if (lead.priority == 'LOW') priorityColor = Colors.green;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                final wasEdited = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => LeadDetailsScreen(
                      leadId: lead.id,
                      isActive: selectedIsActive ?? true,
                    ),
                  ),
                );
                if (wasEdited == true && context.mounted) {
                  final currentState = context.read<LeadsBloc>().state;
                  final currentStatusId = currentState is LeadsLoaded
                      ? currentState.selectedStatusId
                      : null;
                  final currentIsActive = currentState is LeadsLoaded
                      ? currentState.selectedIsActive
                      : null;
                  final searchQuery = currentState is LeadsLoaded
                      ? currentState.searchQuery
                      : null;

                  context.read<LeadsBloc>().add(
                    FetchLeads(
                      page: 0,
                      size: 15,
                      statusId: currentStatusId,
                      isActive: currentIsActive,
                      searchQuery: searchQuery,
                    ),
                  );
                }
              },
              child: LeadCard(
                leadId: lead.id,
                leadNumber: lead.leadNumber,
                initials: initials.toUpperCase(),
                avatarColor: const Color(0xFFFDE8E1),
                avatarTextColor: const Color(0xFFD97706),
                name: displayName,
                company: lead.companyName,
                email: lead.email,
                source: lead.source?.name,
                status: lead.status?.statusName ?? 'Unknown',
                statusBgColor: statusColor.withValues(alpha: 0.15),
                statusTextColor: statusColor,
                priority: lead.priority != null
                    ? '${lead.priority} Priority'
                    : 'No Priority',
                priorityColor: priorityColor,
                createdByName: lead.createdByName,
                createdAt: lead.createdAt,
                callStatus: lead.callStatus,
                assignee: _resolveAssigneeName(lead, state.owners),
                phone: lead.phone,
              ),
            );
          }

          if (showLoader && index == state.leads.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16.0),
              child: Center(child: SpinningLogo(size: 36)),
            );
          }

          return const SizedBox(height: 80); // Padding for FAB
        },
      );
    }
    return const SizedBox();
  }

  Widget _buildFilterChip(
    String label, {
    bool isSelected = false,
    required VoidCallback onTap,
  }) {
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
