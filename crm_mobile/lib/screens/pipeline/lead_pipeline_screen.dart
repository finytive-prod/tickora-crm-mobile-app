import 'dart:async';
import 'package:flutter/material.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/repositories/leads_repository.dart';
import 'package:crm_mobile/models/pipeline_model.dart';
import 'package:crm_mobile/screens/pipeline/widgets/pipeline_column_widget.dart';
import 'package:crm_mobile/screens/pipeline/widgets/pipeline_lead_card.dart';
import 'package:crm_mobile/widgets/spinning_logo.dart';
import 'package:crm_mobile/core/utils/text_selection_utils.dart';

class LeadPipelineScreen extends StatefulWidget {
  const LeadPipelineScreen({super.key});

  @override
  State<LeadPipelineScreen> createState() => _LeadPipelineScreenState();
}

class _LeadPipelineScreenState extends State<LeadPipelineScreen> {
  late LeadsRepository _leadsRepository;
  bool _isLoading = true;
  String? _errorMessage;
  List<PipelineColumnData> _columns = [];
  bool _isKanbanView = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _kanbanScrollController = ScrollController();
  Timer? _autoScrollTimer;

  @override
  void initState() {
    super.initState();
    _leadsRepository = sl<LeadsRepository>();
    _fetchPipelineData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _kanbanScrollController.dispose();
    _stopAutoScroll();
    super.dispose();
  }

  void _onDragUpdate(Offset globalPosition) {
    if (!mounted || !_kanbanScrollController.hasClients) return;
    final screenWidth = MediaQuery.of(context).size.width;
    const double edgeThreshold = 70.0;
    const double scrollSpeed = 16.0;

    if (globalPosition.dx > screenWidth - edgeThreshold) {
      // Auto-scroll right
      if (_autoScrollTimer == null || !_autoScrollTimer!.isActive) {
        _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
          if (_kanbanScrollController.hasClients) {
            final maxScroll = _kanbanScrollController.position.maxScrollExtent;
            final currentScroll = _kanbanScrollController.offset;
            final newScroll = (currentScroll + scrollSpeed).clamp(0.0, maxScroll);
            _kanbanScrollController.jumpTo(newScroll);
          }
        });
      }
    } else if (globalPosition.dx < edgeThreshold) {
      // Auto-scroll left
      if (_autoScrollTimer == null || !_autoScrollTimer!.isActive) {
        _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
          if (_kanbanScrollController.hasClients) {
            final currentScroll = _kanbanScrollController.offset;
            final newScroll = (currentScroll - scrollSpeed).clamp(0.0, double.infinity);
            _kanbanScrollController.jumpTo(newScroll);
          }
        });
      }
    } else {
      _stopAutoScroll();
    }
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  Future<void> _fetchPipelineData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _leadsRepository.getLeadPipeline(page: 0, size: 50);
    result.fold(
      (failure) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = failure.message;
          });
        }
      },
      (columns) {
        if (mounted) {
          setState(() {
            _columns = columns;
            _isLoading = false;
          });
        }
      },
    );
  }

  void _onLeadDropped(PipelineLeadItem lead, PipelineStatus targetStatus) async {
    _stopAutoScroll();

    // Find current column
    int sourceColIdx = -1;
    for (int i = 0; i < _columns.length; i++) {
      if (_columns[i].leads.any((l) => l.id == lead.id)) {
        sourceColIdx = i;
        break;
      }
    }

    // Find target column
    final targetColIdx = _columns.indexWhere((c) => c.status.id == targetStatus.id);
    if (targetColIdx == -1 || sourceColIdx == targetColIdx) return;

    final sourceCol = _columns[sourceColIdx];
    final targetCol = _columns[targetColIdx];

    // Optimistic UI update
    setState(() {
      final updatedSourceLeads = sourceCol.leads.where((l) => l.id != lead.id).toList();
      final updatedTargetLeads = List<PipelineLeadItem>.from(targetCol.leads)..insert(0, lead);

      _columns[sourceColIdx] = sourceCol.copyWith(
        leads: updatedSourceLeads,
        totalElements: (sourceCol.totalElements - 1).clamp(0, 99999),
      );

      _columns[targetColIdx] = targetCol.copyWith(
        leads: updatedTargetLeads,
        totalElements: targetCol.totalElements + 1,
      );
    });

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Moved ${lead.fullName} to ${targetStatus.statusName}'),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 2),
      ),
    );

    // Call API in background
    final res = await _leadsRepository.updateLeadStatusInPipeline(lead.id, targetStatus.id);
    res.fold(
      (failure) {
        if (mounted) {
          _fetchPipelineData();
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(failure.message),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      },
      (_) {},
    );
  }

  void _showStatusPickerModal(PipelineLeadItem lead, PipelineStatus currentStatus) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Move Status',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                        Text(
                          lead.fullName,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.textHint),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Select new status column:',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _columns.length,
                  itemBuilder: (context, index) {
                    final col = _columns[index];
                    final isCurrent = col.status.id == currentStatus.id;

                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isCurrent ? col.status.color : const Color(0xFFE5E7EB),
                          width: isCurrent ? 1.5 : 1.0,
                        ),
                      ),
                      color: isCurrent ? col.status.color.withValues(alpha: 0.05) : Colors.white,
                      child: ListTile(
                        onTap: () {
                          Navigator.of(ctx).pop();
                          if (!isCurrent) {
                            _onLeadDropped(lead, col.status);
                          }
                        },
                        leading: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(color: col.status.color, shape: BoxShape.circle),
                        ),
                        title: Text(
                          col.status.statusName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isCurrent ? col.status.color : AppColors.textPrimary,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${col.totalElements} leads',
                                style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                              ),
                            ),
                            if (isCurrent) ...[
                              const SizedBox(width: 8),
                              Icon(Icons.check_circle_rounded, color: col.status.color, size: 20),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  int get _totalLeadsCount {
    return _columns.fold(0, (sum, col) => sum + col.totalElements);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          'Leads Pipeline',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textPrimary),
            tooltip: 'Refresh Pipeline',
            onPressed: _fetchPipelineData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: SpinningLogo(size: 50))
          : _errorMessage != null
              ? _buildErrorView()
              : Column(
                  children: [
                    _buildSubHeader(),
                    _buildSearchBar(),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _fetchPipelineData,
                        child: _isKanbanView ? _buildKanbanView() : _buildListView(),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSubHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Welcome to your Tickora CRM view',
                    style: TextStyle(fontSize: 12, color: AppColors.textHint),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Text(
                        'Total Leads: ',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$_totalLeadsCount',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // View toggle buttons
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(3),
                child: Row(
                  children: [
                    _buildToggleBtn(
                      icon: Icons.space_dashboard_outlined,
                      label: 'Kanban',
                      isSelected: _isKanbanView,
                      onTap: () => setState(() => _isKanbanView = true),
                    ),
                    _buildToggleBtn(
                      icon: Icons.format_list_bulleted_rounded,
                      label: 'List',
                      isSelected: !_isKanbanView,
                      onTap: () => setState(() => _isKanbanView = false),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToggleBtn({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : AppColors.textHint),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : AppColors.textHint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: TextField(
        controller: _searchController,
        enableInteractiveSelection: true,
        selectionControls: MaterialTextSelectionControls(),
        contextMenuBuilder: buildAdaptiveContextMenu,
        onChanged: (val) {
          setState(() {
            _searchQuery = val.trim().toLowerCase();
          });
        },
        decoration: InputDecoration(
          hintText: 'Search pipeline leads...',
          hintStyle: const TextStyle(fontSize: 13, color: AppColors.textHint),
          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.textHint),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18, color: AppColors.textHint),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          fillColor: const Color(0xFFF9FAFB),
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary),
          ),
        ),
      ),
    );
  }

  Widget _buildKanbanView() {
    if (_columns.isEmpty) {
      return const Center(
        child: Text('No pipeline columns found.', style: TextStyle(color: AppColors.textHint)),
      );
    }

    final filteredColumns = _columns.map((col) {
      if (_searchQuery.isEmpty) return col;
      final filteredLeads = col.leads.where((l) {
        return l.fullName.toLowerCase().contains(_searchQuery) ||
            l.companyName.toLowerCase().contains(_searchQuery) ||
            l.phone.toLowerCase().contains(_searchQuery) ||
            l.email.toLowerCase().contains(_searchQuery);
      }).toList();
      return col.copyWith(leads: filteredLeads, totalElements: filteredLeads.length);
    }).toList();

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(Icons.swipe_rounded, size: 13, color: AppColors.textHint),
              SizedBox(width: 4),
              Text(
                'Drag card to edge or tap status to move',
                style: TextStyle(fontSize: 11, color: AppColors.textHint, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _kanbanScrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            physics: const BouncingScrollPhysics(),
            itemCount: filteredColumns.length,
            itemBuilder: (context, index) {
              final colData = filteredColumns[index];
              return PipelineColumnWidget(
                columnData: colData,
                onLeadDropped: _onLeadDropped,
                onDragUpdate: _onDragUpdate,
                onDragEnd: _stopAutoScroll,
                onStatusTap: (lead, currentStatus) => _showStatusPickerModal(lead, currentStatus),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildListView() {
    final filteredColumns = _columns.map((col) {
      if (_searchQuery.isEmpty) return col;
      final filteredLeads = col.leads.where((l) {
        return l.fullName.toLowerCase().contains(_searchQuery) ||
            l.companyName.toLowerCase().contains(_searchQuery) ||
            l.phone.toLowerCase().contains(_searchQuery) ||
            l.email.toLowerCase().contains(_searchQuery);
      }).toList();
      return col.copyWith(leads: filteredLeads, totalElements: filteredLeads.length);
    }).toList();

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: filteredColumns.length,
      itemBuilder: (context, index) {
        final col = filteredColumns[index];
        final status = col.status;
        final leads = col.leads;

        return Container(
          margin: const EdgeInsets.only(bottom: 16.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: true,
              leading: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: status.color, shape: BoxShape.circle),
              ),
              title: Text(
                status.statusName.toUpperCase(),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${col.totalElements}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: status.color),
                ),
              ),
              children: [
                if (leads.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('No leads in this status', style: TextStyle(color: AppColors.textHint, fontSize: 13)),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Column(
                      children: leads.map((lead) {
                        return PipelineLeadCard(
                          lead: lead,
                          status: status,
                          onStatusTap: () => _showStatusPickerModal(lead, status),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Failed to load pipeline data.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _fetchPipelineData,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
