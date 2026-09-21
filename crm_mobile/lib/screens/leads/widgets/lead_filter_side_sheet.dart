import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/models/lead.dart';
import 'package:crm_mobile/models/staff_user.dart';
import 'package:crm_mobile/models/lead_filter_params.dart';

class LeadFilterSideSheet extends StatefulWidget {
  final LeadFilterParams currentFilter;
  final List<LeadStatus> statuses;
  final List<LeadSource> sources;
  final List<String> priorities;
  final List<StaffUser> owners;

  const LeadFilterSideSheet({
    super.key,
    required this.currentFilter,
    required this.statuses,
    required this.sources,
    required this.priorities,
    required this.owners,
  });

  static Future<LeadFilterParams?> show(
    BuildContext context, {
    required LeadFilterParams currentFilter,
    required List<LeadStatus> statuses,
    required List<LeadSource> sources,
    required List<String> priorities,
    required List<StaffUser> owners,
  }) {
    return showGeneralDialog<LeadFilterParams>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        final screenWidth = MediaQuery.of(context).size.width;
        final sheetWidth = screenWidth > 600 ? 460.0 : screenWidth * 0.88;

        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            elevation: 16,
            child: SizedBox(
              width: sheetWidth,
              height: double.infinity,
              child: LeadFilterSideSheet(
                currentFilter: currentFilter,
                statuses: statuses,
                sources: sources,
                priorities: priorities,
                owners: owners,
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut)),
          child: child,
        );
      },
    );
  }

  @override
  State<LeadFilterSideSheet> createState() => _LeadFilterSideSheetState();
}

class _LeadFilterSideSheetState extends State<LeadFilterSideSheet> {
  late List<String> _selectedStatusIds;
  late List<String> _selectedSourceIds;
  late List<String> _selectedPriorities;
  late List<String> _selectedOwnerIds;
  late List<String> _selectedCreatorIds;

  DateTime? _startDate;
  DateTime? _endDate;

  String _statusSearch = '';
  String _sourceSearch = '';
  String _ownerSearch = '';
  String _creatorSearch = '';

  final DateFormat _displayDateFormat = DateFormat('dd-MM-yyyy');
  final DateFormat _apiDateFormat = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _selectedStatusIds = List<String>.from(widget.currentFilter.statusIds);
    _selectedSourceIds = List<String>.from(widget.currentFilter.sourceIds);
    _selectedPriorities = List<String>.from(widget.currentFilter.priorities);
    _selectedOwnerIds = List<String>.from(widget.currentFilter.assignedToIds);
    _selectedCreatorIds = List<String>.from(widget.currentFilter.createdByIds);

    if (widget.currentFilter.startDate != null && widget.currentFilter.startDate!.isNotEmpty) {
      _startDate = DateTime.tryParse(widget.currentFilter.startDate!);
    }
    if (widget.currentFilter.endDate != null && widget.currentFilter.endDate!.isNotEmpty) {
      _endDate = DateTime.tryParse(widget.currentFilter.endDate!);
    }
  }

  void _applyCurrentYearPreset() {
    final now = DateTime.now();
    setState(() {
      _startDate = DateTime(now.year, 1, 1);
      _endDate = DateTime(now.year, 12, 31);
    });
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final initial = isStart ? (_startDate ?? DateTime.now()) : (_endDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: AppColors.primary),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate != null && _startDate!.isAfter(_endDate!)) {
            _endDate = null;
          }
        } else {
          _endDate = picked;
        }
      });
    }
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

  void _resetAll() {
    setState(() {
      _selectedStatusIds.clear();
      _selectedSourceIds.clear();
      _selectedPriorities.clear();
      _selectedOwnerIds.clear();
      _selectedCreatorIds.clear();
      _startDate = null;
      _endDate = null;
      _statusSearch = '';
      _sourceSearch = '';
      _ownerSearch = '';
      _creatorSearch = '';
    });
  }

  void _applyFilters() {
    final filter = LeadFilterParams(
      sourceIds: _selectedSourceIds,
      statusIds: _selectedStatusIds,
      priorities: _selectedPriorities,
      createdByIds: _selectedCreatorIds,
      assignedToIds: _selectedOwnerIds,
      startDate: _startDate != null ? _apiDateFormat.format(_startDate!) : null,
      endDate: _endDate != null ? _apiDateFormat.format(_endDate!) : null,
    );
    Navigator.of(context).pop(filter);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.filter_alt_outlined, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Filter Leads',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Filter by date, status, source, priority & owner',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Filter Content List
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section 1: Created Date Range
                    _buildSectionHeader(
                      icon: Icons.calendar_today_rounded,
                      title: 'CREATED DATE RANGE',
                      action: InkWell(
                        onTap: _applyCurrentYearPreset,
                        child: const Text(
                          'Current Year',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDateField(
                            label: 'Start Date',
                            date: _startDate,
                            onTap: () => _selectDate(context, true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildDateField(
                            label: 'End Date',
                            date: _endDate,
                            onTap: () => _selectDate(context, false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Section 2: Statuses
                    _buildSectionHeader(
                      icon: Icons.local_offer_outlined,
                      title: 'STATUSES',
                    ),
                    const SizedBox(height: 8),
                    _buildSearchInput(
                      hint: 'Search statuses...',
                      onChanged: (val) => setState(() => _statusSearch = val.toLowerCase()),
                    ),
                    const SizedBox(height: 12),
                    _buildStatusesList(),
                    const SizedBox(height: 24),

                    // Section 3: Sources
                    _buildSectionHeader(
                      icon: Icons.share_outlined,
                      title: 'SOURCES',
                    ),
                    const SizedBox(height: 8),
                    _buildSearchInput(
                      hint: 'Search sources...',
                      onChanged: (val) => setState(() => _sourceSearch = val.toLowerCase()),
                    ),
                    const SizedBox(height: 12),
                    _buildSourcesList(),
                    const SizedBox(height: 24),

                    // Section 4: Priorities
                    _buildSectionHeader(
                      icon: Icons.flag_outlined,
                      title: 'PRIORITIES',
                    ),
                    const SizedBox(height: 12),
                    _buildPrioritiesList(),
                    const SizedBox(height: 24),

                    // Section 5: Assigned Owner
                    _buildSectionHeader(
                      icon: Icons.person_outline_rounded,
                      title: 'ASSIGNED OWNER',
                    ),
                    const SizedBox(height: 8),
                    _buildSearchInput(
                      hint: 'Search owners...',
                      onChanged: (val) => setState(() => _ownerSearch = val.toLowerCase()),
                    ),
                    const SizedBox(height: 12),
                    _buildOwnersList(isCreatorSection: false),
                    const SizedBox(height: 24),

                    // Section 6: Created By
                    _buildSectionHeader(
                      icon: Icons.person_add_alt_1_outlined,
                      title: 'CREATED BY',
                    ),
                    const SizedBox(height: 8),
                    _buildSearchInput(
                      hint: 'Search creators...',
                      onChanged: (val) => setState(() => _creatorSearch = val.toLowerCase()),
                    ),
                    const SizedBox(height: 12),
                    _buildOwnersList(isCreatorSection: true),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // Footer Actions
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _resetAll,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppColors.borderEnabled),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      child: const Text(
                        'Reset to Default',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _applyFilters,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      child: const Text(
                        'Apply Filters',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    Widget? action,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
            letterSpacing: 0.5,
          ),
        ),
        if (action != null) ...[
          const Spacer(),
          action,
        ],
      ],
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.borderEnabled),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  date != null ? _displayDateFormat.format(date) : 'DD-MM-YYYY',
                  style: TextStyle(
                    fontSize: 13,
                    color: date != null ? AppColors.textPrimary : AppColors.textHint,
                  ),
                ),
                const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchInput({
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderEnabled),
      ),
      child: TextField(
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 13),
          prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textHint),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  Widget _buildStatusesList() {
    final filtered = widget.statuses.where((s) {
      if (_statusSearch.isEmpty) return true;
      return s.statusName.toLowerCase().contains(_statusSearch);
    }).toList();

    if (filtered.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Text('No statuses found', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: filtered.map((status) {
        final isSelected = _selectedStatusIds.contains(status.id);
        final dotColor = _hexToColor(status.color);

        return InkWell(
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedStatusIds.remove(status.id);
              } else {
                _selectedStatusIds.add(status.id);
              }
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary.withValues(alpha: 0.05) : Colors.white,
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.borderEnabled,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: Checkbox(
                    value: isSelected,
                    activeColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedStatusIds.add(status.id);
                        } else {
                          _selectedStatusIds.remove(status.id);
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  status.statusName,
                  style: TextStyle(
                    fontSize: 13,
                    color: isSelected ? AppColors.primary : AppColors.textPrimary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSourcesList() {
    final filtered = widget.sources.where((s) {
      if (_sourceSearch.isEmpty) return true;
      return s.name.toLowerCase().contains(_sourceSearch);
    }).toList();

    if (filtered.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Text('No sources found', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: filtered.map((source) {
        final isSelected = _selectedSourceIds.contains(source.id);

        return InkWell(
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedSourceIds.remove(source.id);
              } else {
                _selectedSourceIds.add(source.id);
              }
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary.withValues(alpha: 0.05) : Colors.white,
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.borderEnabled,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: Checkbox(
                    value: isSelected,
                    activeColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedSourceIds.add(source.id);
                        } else {
                          _selectedSourceIds.remove(source.id);
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  source.name,
                  style: TextStyle(
                    fontSize: 13,
                    color: isSelected ? AppColors.primary : AppColors.textPrimary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPrioritiesList() {
    final list = widget.priorities.isNotEmpty ? widget.priorities : const ['LOW', 'MEDIUM', 'HIGH'];

    return Row(
      children: list.map((priority) {
        final isSelected = _selectedPriorities.contains(priority);

        return Expanded(
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _selectedPriorities.remove(priority);
                  } else {
                    _selectedPriorities.add(priority);
                  }
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary.withValues(alpha: 0.05) : Colors.white,
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.borderEnabled,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: Checkbox(
                        value: isSelected,
                        activeColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedPriorities.add(priority);
                            } else {
                              _selectedPriorities.remove(priority);
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      priority,
                      style: TextStyle(
                        fontSize: 13,
                        color: isSelected ? AppColors.primary : AppColors.textPrimary,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildOwnersList({required bool isCreatorSection}) {
    final search = isCreatorSection ? _creatorSearch : _ownerSearch;
    final selectedList = isCreatorSection ? _selectedCreatorIds : _selectedOwnerIds;

    final filtered = widget.owners.where((o) {
      if (search.isEmpty) return true;
      return o.name.toLowerCase().contains(search);
    }).toList();


    if (filtered.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Text('No users found', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: filtered.map((owner) {
        final isSelected = selectedList.contains(owner.userId);

        return InkWell(
          onTap: () {
            setState(() {
              if (isSelected) {
                selectedList.remove(owner.userId);
              } else {
                selectedList.add(owner.userId);
              }
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary.withValues(alpha: 0.05) : Colors.white,
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.borderEnabled,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: Checkbox(
                    value: isSelected,
                    activeColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          selectedList.add(owner.userId);
                        } else {
                          selectedList.remove(owner.userId);
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  owner.name,
                  style: TextStyle(
                    fontSize: 13,
                    color: isSelected ? AppColors.primary : AppColors.textPrimary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
